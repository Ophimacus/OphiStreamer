using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace OphiStreamer.Core;

/// <summary>
/// Optional "show the game only on my phone": when Apollo's virtual display appears (the phone is streaming),
/// switch Windows to that display only, like Win+P "Second screen only"; when it goes away, put the laptop
/// screen back the way it was. Off by default. Never leaves the laptop dark: it restores on exit, when the
/// setting is turned off, and on the next start after a crash.
/// </summary>
public sealed class ScreenSwitch : IDisposable
{
    private static readonly TimeSpan Tick = TimeSpan.FromSeconds(2);

    private readonly AppSettings _settings;
    private readonly Func<int?> _activeStreams;
    private readonly Timer _timer;
    private readonly object _lock = new();
    private int _seenTicks;
    private bool _handledThisStream;
    private bool _disposed;

    public event Action? Changed;

    /// <summary>Short text for the Stream page.</summary>
    public string Status { get; private set; } = "Off";
    public bool Switched => _settings.ScreenSwitched;
    public bool VirtualDisplayActive { get; private set; }

    public ScreenSwitch(AppSettings settings, Func<int?>? activeStreams = null)
    {
        _settings = settings;
        _activeStreams = activeStreams ?? (() => null);
        // Recover from a crash or power loss while the laptop screen was off.
        if (_settings.ScreenSwitched && !Displays.AnyVirtualActive(out _))
        {
            Restore("left off after the app closed");
        }
        _timer = new Timer(_ => OnTick(), null, TimeSpan.FromSeconds(1), Tick);
    }

    private void OnTick()
    {
        lock (_lock)
        {
            if (_disposed) return;
            bool virt = Displays.AnyVirtualActive(out var names);
            if (virt != VirtualDisplayActive)
            {
                EventLog.Write(virt ? "virtual_display_on" : "virtual_display_off", names);
            }
            VirtualDisplayActive = virt;
            // Apollo may retain its virtual desktop after one client leaves. Use its actual
            // session count, never the first phone's Wi-Fi presence, to decide when to restore.
            int? activeStreams = _activeStreams();
            bool sessionsEnded = activeStreams == 0;

            if (!virt || sessionsEnded)
            {
                _seenTicks = 0;
                _handledThisStream = false;
                if (_settings.ScreenSwitched) Restore(!virt ? "virtual display removed" : "last stream disconnected");
            }
            else if (_settings.PhoneOnlyScreen && !_handledThisStream)
            {
                // Wait a moment so the stream has settled before switching screens.
                if (++_seenTicks >= 2)
                {
                    _handledThisStream = true; // once per stream: if you press Win+P yourself, that wins
                    SwitchToPhone();
                }
            }

            Status = !_settings.PhoneOnlyScreen && !_settings.ScreenSwitched ? "Off"
                : _settings.ScreenSwitched ? "Laptop screen off while streaming"
                : virt ? "Streaming, laptop screen on"
                : "Waiting for the phone to stream";
        }
        Changed?.Invoke();
    }

    private void SwitchToPhone()
    {
        int before = Displays.CurrentTopology();
        int err = Displays.Apply(Displays.TopologyExternal);
        if (err != 0)
        {
            EventLog.Write("screen_switch_failed", $"error {err}");
            return;
        }
        // Remember how it was. "Second screen only" before is not a useful thing to go back to.
        _settings.ScreenRestoreTopology = before is Displays.TopologyExternal or 0 ? Displays.TopologyInternal : before;
        _settings.ScreenSwitched = true;
        _settings.Save();
        EventLog.Write("screen_phone_only", "laptop screen off");
    }

    private void Restore(string why)
    {
        int topo = _settings.ScreenRestoreTopology == 0 ? Displays.TopologyInternal : _settings.ScreenRestoreTopology;
        int err = Displays.Apply(topo);
        // If the remembered layout can't be applied (a monitor was unplugged), the laptop screen alone always can.
        if (err != 0 && topo != Displays.TopologyInternal) err = Displays.Apply(Displays.TopologyInternal);
        // Keep recovery armed if Windows failed; the next tick/start must retry.
        if (err == 0) _settings.ScreenSwitched = false;
        _settings.Save();
        EventLog.Write("screen_restored", err == 0 ? why : $"{why}, error {err}");
    }

    /// <summary>Called when the user turns the setting off: bring the laptop screen back now.</summary>
    public void SettingChanged()
    {
        lock (_lock)
        {
            if (!_settings.PhoneOnlyScreen && _settings.ScreenSwitched) Restore("setting turned off");
            _handledThisStream = false;
            _seenTicks = 0;
        }
    }

    public void Dispose()
    {
        _timer.Dispose();
        lock (_lock)
        {
            _disposed = true;
            if (_settings.ScreenSwitched) Restore("app closed");
        }
    }
}

/// <summary>Windows display topology (the same switch as Win+P) and detection of virtual displays.</summary>
internal static class Displays
{
    public const int TopologyInternal = 0x1, TopologyClone = 0x2, TopologyExtend = 0x4, TopologyExternal = 0x8;

    private const uint QdcOnlyActivePaths = 0x2, QdcDatabaseCurrent = 0x4;
    private const uint SdcApply = 0x80;
    private const int DeviceInfoGetTargetName = 2;

    // DISPLAYCONFIG_OUTPUT_TECHNOLOGY values that mean "built into the laptop".
    private static readonly HashSet<uint> InternalTech = new() { 0x80000000, 6 /*LVDS*/, 11 /*DP embedded*/, 13 /*UDI embedded*/ };
    // Indirect (IddCx) displays: how virtual display drivers like Apollo's SudoVDA usually report.
    private static readonly HashSet<uint> IndirectTech = new() { 16, 17 };

    public static int Apply(int topology) => SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, SdcApply | (uint)topology);

    public static int CurrentTopology()
    {
        if (GetDisplayConfigBufferSizes(QdcDatabaseCurrent, out uint np, out uint nm) != 0) return 0;
        var paths = new PathInfo[np];
        var modes = new ModeInfo[nm];
        return QueryDisplayConfigTopology(QdcDatabaseCurrent, ref np, paths, ref nm, modes, out int topo) == 0 ? topo : 0;
    }

    /// <summary>True when an active display is a virtual one (Apollo's). <paramref name="names"/> lists all active displays for the log.</summary>
    public static bool AnyVirtualActive(out string names)
    {
        names = "";
        if (GetDisplayConfigBufferSizes(QdcOnlyActivePaths, out uint np, out uint nm) != 0) return false;
        var paths = new PathInfo[np];
        var modes = new ModeInfo[nm];
        if (QueryDisplayConfig(QdcOnlyActivePaths, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return false;

        bool any = false;
        var list = new List<string>();
        for (int i = 0; i < np; i++)
        {
            var t = paths[i].Target;
            var name = new TargetName
            {
                Header = new DeviceInfoHeader
                {
                    Type = DeviceInfoGetTargetName,
                    Size = (uint)Marshal.SizeOf<TargetName>(),
                    AdapterId = t.AdapterId,
                    Id = t.Id,
                },
            };
            string friendly = "", path = "";
            if (DisplayConfigGetDeviceInfo(ref name) == 0)
            {
                friendly = name.FriendlyName ?? "";
                path = name.DevicePath ?? "";
            }
            bool virt = IndirectTech.Contains(t.OutputTechnology) || LooksVirtual(friendly) || LooksVirtual(path);
            if (InternalTech.Contains(t.OutputTechnology)) virt = false;
            any |= virt;
            list.Add($"{(friendly.Length > 0 ? friendly : "display")} [tech {t.OutputTechnology}{(virt ? ", virtual" : "")}]");
        }
        names = string.Join("; ", list);
        return any;
    }

    private static bool LooksVirtual(string s) =>
        s.Contains("Sudo", StringComparison.OrdinalIgnoreCase)
        || s.Contains("Virtual", StringComparison.OrdinalIgnoreCase)
        || s.Contains("Apollo", StringComparison.OrdinalIgnoreCase);

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public uint Low; public int High; }

    [StructLayout(LayoutKind.Sequential)]
    private struct SourceInfo { public Luid AdapterId; public uint Id; public uint ModeInfoIdx; public uint StatusFlags; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rational { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    private struct TargetInfo
    {
        public Luid AdapterId;
        public uint Id;
        public uint ModeInfoIdx;
        public uint OutputTechnology;
        public uint Rotation;
        public uint Scaling;
        public Rational RefreshRate;
        public uint ScanLineOrdering;
        public int TargetAvailable;
        public uint StatusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo { public SourceInfo Source; public TargetInfo Target; public uint Flags; }

    // DISPLAYCONFIG_MODE_INFO: only passed through, so the 48-byte union is kept as raw bytes.
    [StructLayout(LayoutKind.Sequential, Size = 64)]
    private struct ModeInfo { public uint InfoType; public uint Id; public Luid AdapterId; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInfoHeader { public int Type; public uint Size; public Luid AdapterId; public uint Id; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct TargetName
    {
        public DeviceInfoHeader Header;
        public uint Flags;
        public uint OutputTechnology;
        public ushort EdidManufactureId;
        public ushort EdidProductCodeId;
        public uint ConnectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string FriendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DevicePath;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PathInfo[] paths,
        ref uint numModes, [Out] ModeInfo[] modes, IntPtr topologyId);

    [DllImport("user32.dll", EntryPoint = "QueryDisplayConfig")]
    private static extern int QueryDisplayConfigTopology(uint flags, ref uint numPaths, [Out] PathInfo[] paths,
        ref uint numModes, [Out] ModeInfo[] modes, out int topologyId);

    [DllImport("user32.dll")]
    private static extern int SetDisplayConfig(uint numPaths, IntPtr paths, uint numModes, IntPtr modes, uint flags);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref TargetName request);
}
