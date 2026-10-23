using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace OphiStreamer.Core;

/// <summary>Snapshot of the laptop's Wi-Fi connection.</summary>
public sealed record WifiState(
    bool HasAdapter,
    bool Connected,
    string? Ssid,
    string? Profile,
    string? Band,
    int Channel,
    int SignalPercent,
    double RxMbps,
    double TxMbps,
    string? Gateway,
    string? LaptopIp,
    bool NameHidden)
{
    public static readonly WifiState None = new(false, false, null, null, null, 0, 0, 0, 0, null, null, false);

    public bool Is5GHz => (Band?.StartsWith("5") ?? false) || (Channel >= 32 && Channel <= 177);

    /// <summary>Radar (DFS) channels can pause or move; 36-48 and 149-165 are safer.</summary>
    public bool IsDfs => Channel >= 52 && Channel <= 144;
}

public static class WifiLink
{
    /// <summary>Reads the Wi-Fi link from "netsh wlan show interfaces" plus the adapter's IP settings.</summary>
    public static WifiState Read()
    {
        var info = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in Netsh("wlan show interfaces"))
        {
            int colon = line.IndexOf(':');
            if (colon <= 0) continue;
            var key = line[..colon].Trim();
            if (key.Length > 0 && !info.ContainsKey(key)) info[key] = line[(colon + 1)..].Trim();
        }

        var nic = NetworkInterface.GetAllNetworkInterfaces()
            .FirstOrDefault(n => n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211 && n.OperationalStatus == OperationalStatus.Up)
            ?? NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n => n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211);
        if (nic == null && info.Count == 0) return WifiState.None;

        string? gateway = null, ip = null;
        if (nic != null)
        {
            var props = nic.GetIPProperties();
            gateway = props.GatewayAddresses.Select(g => g.Address).FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork)?.ToString();
            ip = props.UnicastAddresses.Select(u => u.Address).FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork)?.ToString();
        }

        bool connected = info.TryGetValue("State", out var state) && state.Equals("connected", StringComparison.OrdinalIgnoreCase);
        info.TryGetValue("SSID", out var ssid);
        return new WifiState(
            HasAdapter: true,
            Connected: connected,
            Ssid: string.IsNullOrWhiteSpace(ssid) ? null : ssid,
            Profile: info.GetValueOrDefault("Profile"),
            Band: info.GetValueOrDefault("Band"),
            Channel: ParseInt(info.GetValueOrDefault("Channel")),
            SignalPercent: ParseInt(info.GetValueOrDefault("Signal")),
            RxMbps: ParseDouble(info.GetValueOrDefault("Receive rate (Mbps)")),
            TxMbps: ParseDouble(info.GetValueOrDefault("Transmit rate (Mbps)")),
            Gateway: gateway,
            LaptopIp: ip,
            // Windows 11 24H2+ hides the network name from apps unless location access is on.
            NameHidden: connected && string.IsNullOrWhiteSpace(ssid));
    }

    /// <summary>Asks Windows to (re)connect to a saved Wi-Fi profile right away.</summary>
    public static void Connect(string profile) => Netsh($"wlan connect name=\"{profile}\"");

    /// <summary>
    /// Pins the phone network: connect automatically, never auto-switch to another network mid-game,
    /// and mark it metered so Windows Update stays off it. Needs one admin prompt; false if declined.
    /// </summary>
    public static bool PinProfile(string profile)
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo("netsh", $"wlan set profileparameter name=\"{profile}\" connectionmode=auto autoswitch=No cost=Fixed")
            {
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden,
            });
            p?.WaitForExit(10000);
            return p?.ExitCode == 0;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false; // admin prompt declined
        }
    }

    /// <summary>True when the driver has 802.11n/ac switched off (link capped at 54 Mbps).</summary>
    public static bool LegacyRadioOnly()
    {
        var line = Netsh("wlan show drivers").FirstOrDefault(l => l.Contains("Radio types supported", StringComparison.OrdinalIgnoreCase));
        return line != null && !line.Contains("802.11n") && !line.Contains("802.11ac") && !line.Contains("802.11ax");
    }

    internal static List<string> Netsh(string args)
    {
        try
        {
            var psi = new ProcessStartInfo("netsh", args)
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi)!;
            var lines = new List<string>();
            while (p.StandardOutput.ReadLine() is { } l) lines.Add(l);
            p.WaitForExit(5000);
            return lines;
        }
        catch
        {
            return new List<string>();
        }
    }

    private static int ParseInt(string? s)
    {
        if (s == null) return 0;
        var digits = new string(s.Where(char.IsDigit).ToArray());
        return int.TryParse(digits, out int v) ? v : 0;
    }

    private static double ParseDouble(string? s) =>
        double.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double v) ? v : 0;
}
