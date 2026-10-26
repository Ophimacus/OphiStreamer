using System;
using System.Net;
using System.Net.Http;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace OphiStreamer.Core;

/// <summary>
/// Talks to Apollo's local web API (https://localhost:47990), the same API its web panel uses.
/// Apollo authenticates with a session cookie from POST /api/login. Note: Apollo keeps one web
/// session at a time, so logging in here signs a browser out of the panel.
/// </summary>
public sealed class ApolloClient : IDisposable
{
    private const string BaseUrl = "https://127.0.0.1:47990";
    private readonly AppSettings _settings;
    private readonly HttpClient _http;
    private bool _loggedIn;
    private readonly SemaphoreSlim _requests = new(1, 1);
    private readonly SemaphoreSlim _coopApply = new(1, 1);
    private readonly Timer _clientPoll;
    private int _polling;
    private volatile ClientSnapshot? _clientSnapshot;
    private sealed record ClientSnapshot(IReadOnlyList<ApolloClientPresence> Clients, DateTimeOffset UpdatedAt);

    public bool CoopEnabled => _settings.CoopEnabled;
    /// <summary>Requested app capacity, not an Apollo-enforced limit.</summary>
    public int CoopCapacity => CoopEnabled ? 2 : 1;
    public bool CoopApplyPending => _settings.CoopApplyPending;
    public string? CoopGuestUuid => _settings.CoopGuestUuid;
    private bool ShouldPoll => CoopEnabled || _settings.PhoneOnlyScreen;
    private ClientSnapshot? FreshSnapshot
    {
        get
        {
            var snapshot = _clientSnapshot;
            return ShouldPoll && snapshot != null && DateTimeOffset.UtcNow - snapshot.UpdatedAt < TimeSpan.FromSeconds(15)
                ? snapshot : null;
        }
    }
    /// <summary>Count of named_certs[].connected; null when polling is disabled, unavailable or older than 15 seconds.</summary>
    public int? ActiveClientCount => FreshSnapshot?.Clients.Count(c => c.Connected);
    public IReadOnlyList<ApolloClientPresence>? Clients => FreshSnapshot?.Clients;
    public DateTimeOffset? ClientsUpdatedAt => FreshSnapshot?.UpdatedAt;
    public string? ClientStatusError { get; private set; }

    public ApolloClient(AppSettings settings)
    {
        _settings = settings;
        var handler = new HttpClientHandler
        {
            CookieContainer = new CookieContainer(),
            UseCookies = true,
            // Apollo uses a self-signed certificate; only ever accepted for localhost.
            ServerCertificateCustomValidationCallback = (msg, _, _, _) => msg.RequestUri?.IsLoopback == true,
        };
        _http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(8) };
        _clientPoll = new Timer(_ => _ = PollClientsAsync(), null, TimeSpan.Zero, TimeSpan.FromSeconds(5));
    }

    public bool HasCredentials => !string.IsNullOrEmpty(_settings.ApolloUser) && !string.IsNullOrEmpty(_settings.ApolloPassword);

    /// <summary>Checks the saved login works. Returns null on success, or a reason.</summary>
    public async Task<string?> TestLoginAsync()
    {
        await _requests.WaitAsync();
        try { _loggedIn = false; return await LoginAsync(); }
        finally { _requests.Release(); }
    }

    /// <summary>Submits the PIN a phone shows during pairing, so nobody has to type it in the web panel.</summary>
    public async Task<string?> SubmitPinAsync(string pin, string deviceName) =>
        await PostAsync("/api/pin", new { pin, name = deviceName });

    public async Task<string?> RestartAsync() => await PostAsync("/api/restart", new { });

    public async Task<string?> UnpairAllAsync() => await PostAsync("/api/clients/unpair-all", new { });

    private async Task<string?> PostAsync(string path, object body) =>
        (await RequestAsync(HttpMethod.Post, path, body)).Error;

    /// <summary>Explicit local UI refresh, also available before co-op opt-in for guest selection.</summary>
    public async Task<(IReadOnlyList<ApolloClientPresence>? Clients, string? Error)> ListClientsAsync()
    {
        var (response, error) = await RequestAsync(HttpMethod.Get, "/api/clients/list");
        if (error != null) return (null, error);
        try { return (Array.AsReadOnly(CoopGuestPolicy.ReadClients(response!)), null); }
        catch (Exception e) when (e is InvalidOperationException or JsonException) { return (null, e.Message); }
    }

    /// <summary>Local Windows UI only. Preserves commands; never restarts or edits host config.</summary>
    public async Task<string?> ApplyCoopAsync(bool enabled, string? guestUuid)
    {
        await _coopApply.WaitAsync();
        try
        {
            if (enabled && string.IsNullOrEmpty(guestUuid)) return "Select the manually paired guest phone first.";
            if (_settings.CoopGuestBackupJson != null && enabled && guestUuid != _settings.CoopGuestUuid)
                return "Disable and restore the previous guest before selecting another phone.";
            if (!enabled && _settings.CoopGuestBackupJson == null)
                return _settings.CoopEnabled || _settings.CoopApplyPending ? "Guest backup is missing. Restore permissions manually in Apollo." : null;
            var uuid = enabled ? guestUuid : _settings.CoopGuestUuid;
            var (response, error) = await RequestAsync(HttpMethod.Get, "/api/clients/list");
            if (error != null) return error;
            CoopGuestPolicy.ReadClients(response!); // Validate connected before using it as a safety gate.
            var client = ((JsonArray)response!["named_certs"]!).OfType<JsonObject>()
                .SingleOrDefault(c => c["uuid"]!.GetValue<string>() == uuid);
            if (client == null) return "Selected guest is no longer paired with Apollo. No changes were made.";
            if (client["connected"]!.GetValue<bool>()) return "Disconnect the guest stream before applying or restoring guest permissions.";
            var current = CoopGuestPolicy.ReadRecord(client);
            JsonObject original;
            if (_settings.CoopGuestBackupJson == null)
            {
                original = current;
                _settings.CoopGuestUuid = uuid;
                _settings.CoopGuestBackupJson = original.ToJsonString();
            }
            else original = JsonNode.Parse(_settings.CoopGuestBackupJson) as JsonObject
                ?? throw new InvalidOperationException("Guest backup is invalid. Restore manually in Apollo.");
            // Refuse external changes on retries as well as restoration.
            CoopGuestPolicy.Restore(current, original);
            var payload = enabled ? CoopGuestPolicy.GuestRecord(original) : original;
            // Write recovery information BEFORE POST: an interrupted request may still have saved.
            _settings.CoopApplyPending = true;
            _settings.SaveCoopState();
            var (_, saveError) = await RequestAsync(HttpMethod.Post, "/api/clients/update", payload);
            if (saveError != null) return saveError + " Apply is unresolved; retry or uncheck co-op and Apply to restore the guest. Apollo was not restarted.";
            var (saved, verifyError) = await RequestAsync(HttpMethod.Get, "/api/clients/list");
            if (verifyError != null) return "Apollo accepted the write, but read-back failed: " + verifyError;
            CoopGuestPolicy.ReadClients(saved!);
            var verified = ((JsonArray)saved!["named_certs"]!).OfType<JsonObject>()
                .SingleOrDefault(c => c["uuid"]!.GetValue<string>() == uuid);
            if (verified == null || !JsonNode.DeepEquals(payload, CoopGuestPolicy.ReadRecord(verified)))
                return "Apollo guest read-back differs from the requested record. Apply remains unresolved; inspect Apollo.";
            _settings.CoopEnabled = enabled;
            _settings.CoopApplyPending = false;
            _settings.SaveCoopState();
            // Keep backup until the entire disable transition is durably acknowledged.
            if (!enabled)
            {
                _settings.CoopGuestUuid = null;
                _settings.CoopGuestBackupJson = null;
                _settings.SaveCoopState();
                _clientSnapshot = null;
            }
            else _ = PollClientsAsync();
            return null;
        }
        catch (Exception e) when (e is System.IO.IOException or UnauthorizedAccessException or InvalidOperationException or JsonException)
        { return "Could not apply co-op: " + e.Message; }
        finally { _coopApply.Release(); }
    }

    private async Task PollClientsAsync()
    {
        if (Interlocked.Exchange(ref _polling, 1) != 0) return;
        try
        {
            if (!ShouldPoll) { _clientSnapshot = null; ClientStatusError = null; return; }
            var (response, error) = await RequestAsync(HttpMethod.Get, "/api/clients/list");
            if (error != null) throw new InvalidOperationException(error);
            var clients = CoopGuestPolicy.ReadClients(response!);
            _clientSnapshot = new(Array.AsReadOnly(clients), DateTimeOffset.UtcNow);
            ClientStatusError = null;
        }
        catch (Exception e) when (e is InvalidOperationException or JsonException or ObjectDisposedException)
        { _clientSnapshot = null; ClientStatusError = e.Message; }
        finally { Volatile.Write(ref _polling, 0); }
    }

    private async Task<(JsonObject? Body, string? Error)> RequestAsync(HttpMethod method, string path, object? body = null)
    {
        await _requests.WaitAsync();
        try
        {
            if (!HasCredentials) return (null, "Enter your Apollo login in OphiStreamer Settings");
            for (int attempt = 0; attempt < 2; attempt++)
            {
                if (!_loggedIn)
                {
                    var error = await LoginAsync();
                    if (error != null) return (null, error);
                }
                using var request = new HttpRequestMessage(method, BaseUrl + path);
                if (body != null) request.Content = Json(body);
                using var response = await _http.SendAsync(request);
                var raw = await response.Content.ReadAsStringAsync();
                if (response.StatusCode == HttpStatusCode.Unauthorized) { _loggedIn = false; continue; }
                if (!response.IsSuccessStatusCode)
                    return (null, $"Apollo {path} HTTP {(int)response.StatusCode}: {raw}");
                if (path == "/api/restart" && string.IsNullOrWhiteSpace(raw)) return (null, null);
                JsonObject? json;
                try { json = JsonNode.Parse(raw) as JsonObject; }
                catch (JsonException) { return (null, $"Apollo {path} returned invalid JSON: {raw}"); }
                if (json == null || json["status"]?.ToString() != "true" || json.ContainsKey("error") ||
                    (json["status_code"] is JsonValue code && code.TryGetValue<int>(out int number) && number >= 400))
                    return (null, $"Apollo rejected {path}: {raw}");
                return (json, null);
            }
            return (null, "Apollo login expired; check the saved login");
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return (null, path == "/api/restart"
                ? "Restart request lost its connection (Apollo normally disconnects while restarting). Verify Apollo is running; restart completion is unconfirmed. " + e.Message
                : $"Apollo {path} is unavailable: {e.Message}");
        }
        finally { _requests.Release(); }
    }

    private async Task<string?> LoginAsync()
    {
        if (!HasCredentials) return "Enter your Apollo login in OphiStreamer Settings";
        try
        {
            using var resp = await _http.PostAsync(BaseUrl + "/api/login", Json(new { username = _settings.ApolloUser, password = _settings.ApolloPassword }));
            var raw = await resp.Content.ReadAsStringAsync();
            // Verified upstream login returns only Set-Cookie and an empty body on success.
            _loggedIn = resp.IsSuccessStatusCode && (string.IsNullOrWhiteSpace(raw) || !Rejected(raw));
            return _loggedIn ? null : $"Apollo login was refused (HTTP {(int)resp.StatusCode}): {raw}";
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return "Apollo isn't answering: " + e.Message;
        }
    }

    private static StringContent Json(object body) =>
        new(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

    /// <summary>{"status": false} or, from older builds, {"status": "false"}.</summary>
    private static bool Rejected(string text)
    {
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(text);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return true;
            if (doc.RootElement.TryGetProperty("error", out _)) return true;
            if (!doc.RootElement.TryGetProperty("status", out var st)) return false;
            return st.ValueKind == System.Text.Json.JsonValueKind.False
                || (st.ValueKind == System.Text.Json.JsonValueKind.String && st.GetString() == "false");
        }
        catch (System.Text.Json.JsonException)
        {
            return true;
        }
    }

    public void Dispose()
    {
        _clientPoll.Dispose();
        _http.Dispose();
    }
}
