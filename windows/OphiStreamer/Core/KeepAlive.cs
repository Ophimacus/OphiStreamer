using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.NetworkInformation;
using System.Threading;

namespace OphiStreamer.Core;

public sealed record LatencyStats(double AvgMs, double MaxMs, int Spikes, int Lost, int Samples)
{
    public static readonly LatencyStats Empty = new(0, 0, 0, 0, 0);
}

/// <summary>
/// Pings the phone 10 times a second while Gaming mode is on. Keeps the phone hotspot's radio from
/// dozing (which adds lag on wake) and gives live latency, spike and loss numbers for the window.
/// </summary>
public sealed class KeepAlive : IDisposable
{
    public const int SpikeMs = 50;
    private const int IntervalMs = 100;
    private static readonly TimeSpan Window = TimeSpan.FromSeconds(60);

    private readonly object _lock = new();
    private readonly Queue<(DateTime At, double? Ms)> _samples = new();
    private Thread? _thread;
    private volatile bool _running;
    private volatile string? _target;

    public string? Target
    {
        get => _target;
        set => _target = value;
    }

    public void Start(string? target)
    {
        _target = target;
        if (_running) return;
        _running = true;
        _thread = new Thread(Loop) { IsBackground = true, Name = "OphiStreamer keep-alive" };
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        _thread = null;
        lock (_lock) _samples.Clear();
    }

    /// <summary>Stats over the last minute.</summary>
    public LatencyStats Snapshot()
    {
        lock (_lock)
        {
            if (_samples.Count == 0) return LatencyStats.Empty;
            var ok = _samples.Where(s => s.Ms.HasValue).Select(s => s.Ms!.Value).ToList();
            return new LatencyStats(
                ok.Count > 0 ? ok.Average() : 0,
                ok.Count > 0 ? ok.Max() : 0,
                ok.Count(v => v >= SpikeMs),
                _samples.Count(s => !s.Ms.HasValue),
                _samples.Count);
        }
    }

    private void Loop()
    {
        using var ping = new Ping();
        while (_running)
        {
            var target = _target;
            if (target != null)
            {
                double? ms = null;
                try
                {
                    var reply = ping.Send(target, 500);
                    if (reply.Status == IPStatus.Success) ms = reply.RoundtripTime;
                }
                catch
                {
                    // counted as lost
                }
                lock (_lock)
                {
                    var now = DateTime.UtcNow;
                    _samples.Enqueue((now, ms));
                    while (_samples.Count > 0 && now - _samples.Peek().At > Window) _samples.Dequeue();
                }
            }
            Thread.Sleep(IntervalMs);
        }
    }

    public void Dispose() => Stop();
}
