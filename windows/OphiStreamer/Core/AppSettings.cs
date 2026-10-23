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

    public void Save()
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
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
