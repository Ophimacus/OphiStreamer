using System;
using System.Threading;

namespace OphiStreamer.Core;

/// <summary>
/// Gaming mode: lag fix + keep-alive while the laptop is on the phone hotspot, a watchdog that
/// reconnects right away after a drop, and automatic restore when the phone goes away, the laptop
/// sleeps or the app exits. All state changes are logged.
/// </summary>
public sealed class SessionController : IDisposable
{
    private static readonly TimeSpan Tick = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan ReapplyEvery = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan PhoneGoneAfter = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan ReconnectEvery = TimeSpan.FromSeconds(3);

    private readonly AppSettings _settings;
    private readonly LagFix _lagFix = new();
    private readonly KeepAlive _keepAlive = new();
    private readonly Timer _timer;
    private readonly object _lock = new();

    private DateTime _lastApply = DateTime.MinValue;
    private DateTime? _disconnectedSince;
    private DateTime _lastReconnect = DateTime.MinValue;
    private string? _sessionProfile;
    private bool _userTurnedOff;
    private int _drops;
    private int _busy;
    private bool _disposed;

    public event Action? Changed;

    public bool Active { get; private set; }
    public bool StartedAutomatically { get; private set; }
    public WifiState Link { get; private set; } = WifiState.None;
    public string Status { get; private set; } = "Starting...";
    public int DropsThisSession => _drops;
    public bool LagFixOn => _lagFix.Active;
    public string? LagFixError => _lagFix.LastError;
    public LatencyStats Latency => _keepAlive.Snapshot();

    public SessionController(AppSettings settings)
    {
        _settings = settings;
        _timer = new Timer(_ => OnTick(), null, TimeSpan.Zero, Tick);
    }

    public bool OnPhoneHotspot =>
        Link.Connected && _settings.PhoneSsid != null && string.Equals(Link.Ssid, _settings.PhoneSsid, StringComparison.Ordinal);

    public void TurnOn()
    {
        lock (_lock)
        {
            _userTurnedOff = false;
            Enable(automatic: false);
        }
        Changed?.Invoke();
    }

    public void TurnOff()
    {
        lock (_lock)
        {
            _userTurnedOff = true;
            Disable("turned off");
        }
        Changed?.Invoke();
    }

    /// <summary>Laptop going to sleep: restore normal Wi-Fi behaviour first.</summary>
    public void OnSuspend()
    {
        lock (_lock) Disable("laptop sleeping");
        Changed?.Invoke();
    }

    private void Enable(bool automatic)
    {
        if (Active) return;
        Link = WifiLink.Read();
        _lagFix.Apply();
        _keepAlive.Start(Link.Gateway);
        _sessionProfile = Link.Profile;
        _drops = 0;
        _disconnectedSince = null;
        _lastApply = DateTime.UtcNow;
        Active = true;
        StartedAutomatically = automatic;
        EventLog.Write("gaming_on", automatic ? "phone hotspot joined" : "turned on", Link);
    }

    private void Disable(string why)
    {
        if (!Active) return;
        _lagFix.Release();
        _keepAlive.Stop();
        Active = false;
        EventLog.Write("gaming_off", why, Link);
    }

    private void OnTick()
    {
        // Timer callbacks can overlap if netsh is slow; skip a tick instead.
        if (Interlocked.Exchange(ref _busy, 1) == 1) return;
        try
        {
            var link = WifiLink.Read();
            lock (_lock)
            {
                if (_disposed) return;
                var was = Link;
                Link = link;

                // Leaving the phone network resets "turned off by user" so next time it auto-starts again.
                if (!OnPhoneHotspot) _userTurnedOff = false;

                if (!Active && _settings.AutoGamingMode && OnPhoneHotspot && !_userTurnedOff) Enable(automatic: true);

                if (Active)
                {
                    if (link.Connected)
                    {
                        if (_disconnectedSince != null)
                        {
                            EventLog.Write("reconnected", $"after {(DateTime.UtcNow - _disconnectedSince.Value).TotalSeconds:0} s", link);
                            _disconnectedSince = null;
                            _lastApply = DateTime.MinValue; // re-apply right away
                        }
                        if (DateTime.UtcNow - _lastApply > ReapplyEvery)
                        {
                            _lagFix.Apply();
                            _lastApply = DateTime.UtcNow;
                        }
                        _keepAlive.Target = link.Gateway;

                        // Joined a different network (e.g. home Wi-Fi): an automatic session ends.
                        if (StartedAutomatically && !OnPhoneHotspot && _settings.PhoneSsid != null && link.Ssid != null)
                            Disable("left the phone hotspot");
                    }
                    else
                    {
                        if (_disconnectedSince == null)
                        {
                            _disconnectedSince = DateTime.UtcNow;
                            _drops++;
                            EventLog.Write("drop", "Wi-Fi disconnected", was);
                        }
                        // Watchdog: ask Windows to reconnect now instead of waiting.
                        if (_sessionProfile != null && DateTime.UtcNow - _lastReconnect > ReconnectEvery)
                        {
                            _lastReconnect = DateTime.UtcNow;
                            WifiLink.Connect(_sessionProfile);
                        }
                        if (DateTime.UtcNow - _disconnectedSince.Value > PhoneGoneAfter) Disable("phone gone for 2 minutes");
                    }
                }

                Status = Describe();
            }
        }
        catch (Exception e)
        {
            Status = "Error: " + e.Message;
        }
        finally
        {
            Interlocked.Exchange(ref _busy, 0);
        }
        Changed?.Invoke();
    }

    private string Describe()
    {
        if (!Link.HasAdapter) return "No Wi-Fi adapter found";
        if (Active && !Link.Connected) return "Reconnecting to the phone...";
        if (Active) return $"{Link.Ssid ?? "Phone"} connected";
        if (!Link.Connected) return "Turn on your phone hotspot";
        if (Link.NameHidden) return "Allow location access to see the Wi-Fi name";
        if (_settings.PhoneSsid == null) return $"On {Link.Ssid}. Set it as your phone hotspot?";
        return OnPhoneHotspot ? "Phone hotspot connected" : $"On {Link.Ssid}, not the phone hotspot";
    }

    public void Dispose()
    {
        _timer.Dispose();
        lock (_lock)
        {
            _disposed = true;
            Disable("app closed");
        }
        _lagFix.Dispose();
        _keepAlive.Dispose();
    }
}
