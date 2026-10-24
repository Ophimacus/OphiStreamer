using System;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace OphiStreamer.Core;

/// <summary>
/// Talks to Apollo's local web API (https://localhost:47990), the same API its web panel uses.
/// Apollo authenticates with a session cookie from POST /api/login. Note: Apollo keeps one web
/// session at a time, so logging in here signs a browser out of the panel.
/// </summary>
public sealed class ApolloClient
{
    private const string BaseUrl = "https://127.0.0.1:47990";
    private readonly AppSettings _settings;
    private readonly HttpClient _http;
    private bool _loggedIn;

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
    }

    public bool HasCredentials => !string.IsNullOrEmpty(_settings.ApolloUser) && !string.IsNullOrEmpty(_settings.ApolloPassword);

    /// <summary>Checks the saved login works. Returns null on success, or a reason.</summary>
    public async Task<string?> TestLoginAsync()
    {
        _loggedIn = false;
        return await LoginAsync();
    }

    /// <summary>Submits the PIN a phone shows during pairing, so nobody has to type it in the web panel.</summary>
    public async Task<string?> SubmitPinAsync(string pin, string deviceName) =>
        await PostAsync("/api/pin", new { pin, name = deviceName });

    public async Task<string?> RestartAsync() => await PostAsync("/api/restart", new { });

    public async Task<string?> UnpairAllAsync() => await PostAsync("/api/clients/unpair-all", new { });

    /// <summary>POSTs JSON; logs in first (and once more if the session expired). Returns null on success.</summary>
    private async Task<string?> PostAsync(string path, object body)
    {
        if (!HasCredentials) return "Enter your Apollo login in OphiStreamer Settings";
        for (int attempt = 0; attempt < 2; attempt++)
        {
            if (!_loggedIn)
            {
                var err = await LoginAsync();
                if (err != null) return err;
            }
            try
            {
                using var resp = await _http.PostAsync(BaseUrl + path, Json(body));
                if (resp.StatusCode == HttpStatusCode.Unauthorized)
                {
                    _loggedIn = false;
                    continue;
                }
                if (!resp.IsSuccessStatusCode) return $"Apollo answered {(int)resp.StatusCode}";
                var text = await resp.Content.ReadAsStringAsync();
                // /api/pin answers {"status": true|false}
                if (Rejected(text)) return "Apollo rejected it (no pairing in progress?)";
                return null;
            }
            catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
            {
                // A restart drops the connection before it answers; that's success for /api/restart.
                if (path == "/api/restart") return null;
                return "Apollo isn't answering. Is it running?";
            }
        }
        return "Apollo login expired; check the saved login";
    }

    private async Task<string?> LoginAsync()
    {
        if (!HasCredentials) return "Enter your Apollo login in OphiStreamer Settings";
        try
        {
            using var resp = await _http.PostAsync(BaseUrl + "/api/login", Json(new { username = _settings.ApolloUser, password = _settings.ApolloPassword }));
            _loggedIn = resp.IsSuccessStatusCode;
            return _loggedIn ? null : "Apollo login was refused: check the username and password";
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return "Apollo isn't answering. Is it running?";
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
            if (!doc.RootElement.TryGetProperty("status", out var st)) return false;
            return st.ValueKind == System.Text.Json.JsonValueKind.False
                || (st.ValueKind == System.Text.Json.JsonValueKind.String && st.GetString() == "false");
        }
        catch (System.Text.Json.JsonException)
        {
            return false;
        }
    }
}
