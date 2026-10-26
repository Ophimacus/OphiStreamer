using System;
using System.IO;
using System.Text.Json;
using Microsoft.Win32;

namespace OphiStreamer.Core;

/// <summary>User settings, stored as JSON in %LOCALAPPDATA%\OphiStreamer.</summary>
public sealed class AppSettings
{
    /// <summary>Wi-Fi name of the phone hotspot. Joining it turns Gaming mode on automatically.</summary>
    public string? PhoneSsid { get; set; }
    public bool AutoGamingMode { get; set; } = true;
    public bool StartWithWindows { get; set; } = true;

    /// <summary>Show the game only on the phone while it streams (laptop screen off). Off by default.</summary>
    public bool PhoneOnlyScreen { get; set; }
    /// <summary>Last acknowledged co-op opt-in. Only explicit Apply changes the selected Apollo guest.</summary>
    public bool CoopEnabled { get; set; }
    public string? CoopGuestUuid { get; set; }
    /// <summary>Full original client record, persisted before modifying permissions. Commands are preserved.</summary>
    public string? CoopGuestBackupJson { get; set; }
    public bool CoopApplyPending { get; set; }
    /// <summary>Set while the laptop screen is off because of <see cref="PhoneOnlyScreen"/>, so a crash can be undone on next start.</summary>
    public bool ScreenSwitched { get; set; }
    /// <summary>Win+P layout to go back to (1 laptop only, 2 duplicate, 4 extend).</summary>
    public int ScreenRestoreTopology { get; set; }

    /// <summary>Apollo web-panel login, used for PIN-free pairing and Repair.</summary>
    public string? ApolloUser { get; set; }

    /// <summary>Stored encrypted for this Windows user (DPAPI); use <see cref="ApolloPassword"/>.</summary>
    public string? ApolloPasswordProtected { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string? ApolloPassword
    {
        get
        {
            if (string.IsNullOrEmpty(ApolloPasswordProtected)) return null;
            try
            {
                var bytes = System.Security.Cryptography.ProtectedData.Unprotect(
                    Convert.FromBase64String(ApolloPasswordProtected), null, System.Security.Cryptography.DataProtectionScope.CurrentUser);
                return System.Text.Encoding.UTF8.GetString(bytes);
            }
            catch
            {
                return null;
            }
        }
        set
        {
            ApolloPasswordProtected = string.IsNullOrEmpty(value)
                ? null
                : Convert.ToBase64String(System.Security.Cryptography.ProtectedData.Protect(
                    System.Text.Encoding.UTF8.GetBytes(value), null, System.Security.Cryptography.DataProtectionScope.CurrentUser));
        }
    }

    public static string Folder { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OphiStreamer");
    private static string FilePath => Path.Combine(Folder, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath)) return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch
        {
            // Corrupt file: start fresh.
        }
        return new AppSettings();
    }

    private static readonly object SaveLock = new();

    /// <summary>Durable co-op recovery state; propagate errors and do not change Windows startup.</summary>
    public void SaveCoopState()
    {
        lock (SaveLock)
        {
            Directory.CreateDirectory(Folder);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, FilePath, overwrite: true);
        }
    }

    public void Save()
    {
        // Saved from the UI and from the screen switch's timer; never let a file clash crash the app.
        lock (SaveLock)
        {
            try
            {
                // Keep the co-op recovery backup intact even if a routine save is interrupted.
                SaveCoopState();
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        ApplyStartWithWindows();
    }

    /// <summary>Per-user "Run" entry, so no admin is needed.</summary>
    public void ApplyStartWithWindows()
    {
        const string runKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        using var key = Registry.CurrentUser.OpenSubKey(runKey, writable: true);
        if (key == null) return;
        var exe = Environment.ProcessPath;
        if (StartWithWindows && exe != null) key.SetValue("OphiStreamer", $"\"{exe}\" --tray");
        else key.DeleteValue("OphiStreamer", throwOnMissingValue: false);
    }
}

/// <summary>Event log for drops, reconnects and Gaming mode changes (CSV, one file per day).</summary>
public static class EventLog
{
    public static string Folder { get; } = Path.Combine(AppSettings.Folder, "logs");

    public static void Write(string kind, string detail, WifiState? link = null)
    {
        try
        {
            Directory.CreateDirectory(Folder);
            var file = Path.Combine(Folder, $"events-{DateTime.Now:yyyyMMdd}.csv");
            bool header = !File.Exists(file);
            using var w = new StreamWriter(file, append: true);
            if (header) w.WriteLine("time,event,detail,ssid,band,channel,signal");
            w.WriteLine(string.Join(",",
                DateTime.Now.ToString("HH:mm:ss"),
                kind,
                Quote(detail),
                Quote(link?.Ssid ?? ""),
                link?.Band ?? "",
                link?.Channel.ToString() ?? "",
                link?.SignalPercent.ToString() ?? ""));
        }
        catch
        {
            // Logging must never break the app.
        }
    }

    private static string Quote(string s) => "\"" + s.Replace("\"", "'") + "\"";
}
