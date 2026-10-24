using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace OphiStreamer.Core;

/// <summary>
/// The phone app's link to this PC: a small HTTP/JSON service on TCP 47900.
///
/// Security: changes (pair, unpair, repair, gaming mode) are accepted only from the laptop's current
/// Wi-Fi gateway - which, on the phone hotspot, is the phone itself - or from this PC. Other devices
/// on the network can read status and run a speed test, nothing else.
/// </summary>
public sealed class PhoneLink : IDisposable
{
    public const int Port = 47900;
    private const int MaxBody = 16 * 1024;

    private readonly SessionController _session;
    private readonly ApolloClient _apollo;
    private readonly CancellationTokenSource _cts = new();
    private TcpListener? _listener;

    /// <summary>Raised for things worth a tray notification (e.g. "Honor X7d paired").</summary>
    public event Action<string>? Notice;
    public string? StartError { get; private set; }

    public PhoneLink(SessionController session, ApolloClient apollo)
    {
        _session = session;
        _apollo = apollo;
    }

    public void Start()
    {
        try
        {
            _listener = new TcpListener(IPAddress.Any, Port);
            _listener.Start();
            _ = AcceptLoop(_cts.Token);
        }
        catch (Exception e)
        {
            StartError = e.Message;
        }
    }

    private async Task AcceptLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await _listener!.AcceptTcpClientAsync(ct); }
            catch { break; }
            _ = Task.Run(() => Handle(client), ct);
        }
    }

    private async Task Handle(TcpClient client)
    {
        using (client)
        {
            client.ReceiveTimeout = 5000;
            client.SendTimeout = 5000;
            var remote = (client.Client.RemoteEndPoint as IPEndPoint)?.Address;
            using var stream = client.GetStream();
            // Socket timeouts don't apply to async reads; this does. Speed tests use their own connection.
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            int status = 200;
            object body;
            try
            {
                var (method, path, payload) = await ReadRequest(stream, timeout.Token);
                (status, body) = await Route(method, path, payload, remote);
            }
            catch (Exception e)
            {
                status = 400;
                body = new { error = e.Message };
            }
            var json = JsonSerializer.Serialize(body);
            var bytes = Encoding.UTF8.GetBytes(json);
            var head = $"HTTP/1.1 {status} {(status == 200 ? "OK" : "Error")}\r\nContent-Type: application/json\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
            try
            {
                await stream.WriteAsync(Encoding.ASCII.GetBytes(head), timeout.Token);
                await stream.WriteAsync(bytes, timeout.Token);
            }
            catch (OperationCanceledException) { }
        }
    }

    private async Task<(int, object)> Route(string method, string path, JsonElement? body, IPAddress? remote)
    {
        bool trusted = IsTrusted(remote);
        switch (method, path)
        {
            case ("GET", "/status"):
                return (200, Status(trusted));

            case ("POST", "/calibrate"):
            {
                if (remote == null || !IsLocalNetwork(remote)) return Forbidden();
                int port = Int(body, "port", 0);
                int mbps = Math.Clamp(Int(body, "mbps", 10), 1, 100);
                int ms = Math.Clamp(Int(body, "ms", 2000), 200, 5000);
                if (port <= 0) return (400, new { error = "port missing" });
                var sent = await Task.Run(() => SendBurst(new IPEndPoint(remote, port), mbps, ms));
                return (200, new { sent, mbps, ms });
            }
        }

        if (!trusted) return Forbidden();

        switch (method, path)
        {
            case ("POST", "/gaming"):
                if (Bool(body, "on")) _session.TurnOn(); else _session.TurnOff();
                return (200, new { ok = true, gaming = _session.Active });

            case ("POST", "/pair"):
            {
                var pin = Str(body, "pin");
                var name = Str(body, "name") ?? "Phone";
                if (pin == null || pin.Length is < 4 or > 8) return (400, new { error = "pin missing" });
                // Give the phone's pairing request a moment to reach Apollo first.
                await Task.Delay(800);
                var err = await _apollo.SubmitPinAsync(pin, name);
                if (err == null) Notice?.Invoke($"{name} paired");
                EventLog.Write("pair", err ?? $"{name} paired", _session.Link);
                return err == null ? (200, new { ok = true }) : (502, new { error = err });
            }

            case ("POST", "/repair"):
            {
                var err = await _apollo.RestartAsync();
                EventLog.Write("repair", err ?? "Apollo restarted", _session.Link);
                return err == null ? (200, new { ok = true, step = "Apollo restarted" }) : (502, new { error = err });
            }

            case ("POST", "/unpair-all"):
            {
                var err = await _apollo.UnpairAllAsync();
                EventLog.Write("unpair_all", err ?? "all devices unpaired", _session.Link);
                return err == null ? (200, new { ok = true }) : (502, new { error = err });
            }
        }
        return (404, new { error = "unknown request" });
    }

    private object Status(bool trusted)
    {
        var link = _session.Link;
        var lat = _session.Latency;
        return new
        {
            app = "OphiStreamer",
            version = typeof(PhoneLink).Assembly.GetName().Version?.ToString(3),
            trusted,
            gaming = _session.Active,
            lagFix = _session.LagFixOn,
            drops = _session.DropsThisSession,
            apolloLogin = _apollo.HasCredentials,
            host = SystemChecks.Host().Status,
            link = new { ssid = link.Ssid, band = link.Is5GHz ? "5 GHz" : "2.4 GHz", channel = link.Channel, signal = link.SignalPercent, dfs = link.IsDfs },
            latency = new { avgMs = Math.Round(lat.AvgMs, 1), maxMs = lat.MaxMs, spikes = lat.Spikes, lost = lat.Lost, samples = lat.Samples },
        };
    }

    /// <summary>The phone (hotspot gateway) or this PC.</summary>
    private bool IsTrusted(IPAddress? remote)
    {
        if (remote == null) return false;
        if (remote.IsIPv4MappedToIPv6) remote = remote.MapToIPv4();
        if (IPAddress.IsLoopback(remote)) return true;
        var gw = _session.Link.Gateway;
        return gw != null && remote.ToString() == gw;
    }

    /// <summary>Same /24 as the laptop's Wi-Fi address.</summary>
    private bool IsLocalNetwork(IPAddress remote)
    {
        if (remote.IsIPv4MappedToIPv6) remote = remote.MapToIPv4();
        if (IPAddress.IsLoopback(remote)) return true;
        var mine = _session.Link.LaptopIp;
        if (mine == null) return false;
        var a = IPAddress.Parse(mine).GetAddressBytes();
        var b = remote.GetAddressBytes();
        return b.Length == 4 && a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
    }

    /// <summary>
    /// Speed test in the same direction as video (PC to phone): paced UDP packets of 1200 bytes,
    /// each carrying a sequence number and the total, so the phone can count loss and jitter.
    /// </summary>
    private static int SendBurst(IPEndPoint target, int mbps, int ms)
    {
        const int size = 1200;
        long bytesPerSec = mbps * 1_000_000L / 8;
        long total = bytesPerSec * ms / 1000 / size;
        var packet = new byte[size];
        using var udp = new UdpClient();
        var sw = Stopwatch.StartNew();
        int seq = 0;
        while (seq < total)
        {
            long due = (long)(sw.Elapsed.TotalSeconds * bytesPerSec / size);
            while (seq < total && seq <= due)
            {
                BitConverter.TryWriteBytes(packet.AsSpan(0, 4), IPAddress.HostToNetworkOrder(seq));
                BitConverter.TryWriteBytes(packet.AsSpan(4, 4), IPAddress.HostToNetworkOrder((int)total));
                udp.Send(packet, size, target);
                seq++;
            }
            Thread.Sleep(1);
        }
        return seq;
    }

    private static async Task<(string, string, JsonElement?)> ReadRequest(Stream stream, CancellationToken ct)
    {
        var buffer = new byte[MaxBody + 4096];
        int read = 0, headerEnd = -1;
        while (headerEnd < 0)
        {
            int n = await stream.ReadAsync(buffer.AsMemory(read, buffer.Length - read), ct);
            if (n == 0) throw new IOException("closed");
            read += n;
            headerEnd = IndexOf(buffer, read, "\r\n\r\n"u8);
            if (read >= buffer.Length && headerEnd < 0) throw new IOException("request too large");
        }
        var head = Encoding.ASCII.GetString(buffer, 0, headerEnd);
        var lines = head.Split("\r\n");
        var first = lines[0].Split(' ');
        if (first.Length < 2) throw new IOException("bad request");
        var path = first[1].Split('?')[0];
        int length = 0;
        foreach (var l in lines)
            if (l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)) int.TryParse(l[15..].Trim(), out length);
        if (length > MaxBody) throw new IOException("body too large");
        int bodyStart = headerEnd + 4;
        while (read - bodyStart < length)
        {
            int n = await stream.ReadAsync(buffer.AsMemory(read, buffer.Length - read), ct);
            if (n == 0) break;
            read += n;
        }
        JsonElement? json = null;
        if (length > 0)
        {
            using var doc = JsonDocument.Parse(buffer.AsMemory(bodyStart, length));
            json = doc.RootElement.Clone();
        }
        return (first[0].ToUpperInvariant(), path, json);
    }

    private static int IndexOf(byte[] data, int count, ReadOnlySpan<byte> needle) => data.AsSpan(0, count).IndexOf(needle);

    private static (int, object) Forbidden() => (403, new { error = "Only your phone (the hotspot) can do this" });

    private static string? Str(JsonElement? b, string name) =>
        b is { ValueKind: JsonValueKind.Object } o && o.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int Int(JsonElement? b, string name, int fallback) =>
        b is { ValueKind: JsonValueKind.Object } o && o.TryGetProperty(name, out var v) && v.TryGetInt32(out var i) ? i : fallback;

    private static bool Bool(JsonElement? b, string name) =>
        b is { ValueKind: JsonValueKind.Object } o && o.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    public void Dispose()
    {
        _cts.Cancel();
        try { _listener?.Stop(); } catch { }
    }
}
