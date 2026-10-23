using System;
using System.ServiceProcess;

namespace OphiStreamer.Core;

public enum CheckLevel { Good, Warn, Bad, Off }

public sealed record Check(string Name, string Status, CheckLevel Level, string? Hint = null);

/// <summary>The PC-side items shown in the window's "Optimizations" card.</summary>
public static class SystemChecks
{
    public static Check Host()
    {
        var apollo = ServiceStatus("ApolloService");
        var sunshine = ServiceStatus("SunshineService");
        if (apollo == ServiceControllerStatus.Running && sunshine == ServiceControllerStatus.Running)
            return new Check("Streaming host", "Conflict", CheckLevel.Bad, "Apollo and Sunshine both running: disable SunshineService");
        if (apollo == ServiceControllerStatus.Running) return new Check("Streaming host", "Apollo", CheckLevel.Good);
        if (sunshine == ServiceControllerStatus.Running) return new Check("Streaming host", "Sunshine", CheckLevel.Warn, "Apollo is the preferred host");
        if (apollo != null) return new Check("Streaming host", "Stopped", CheckLevel.Bad, "Start Apollo (Services > Apollo Service)");
        return new Check("Streaming host", "Not installed", CheckLevel.Bad, "winget install ClassicOldSong.Apollo");
    }

    public static Check ControllerDriver() =>
        ServiceStatus("ViGEmBus") != null
            ? new Check("Controller driver", "Ready", CheckLevel.Good)
            : new Check("Controller driver", "Missing", CheckLevel.Bad, "winget install ViGEm.ViGEmBus");

    public static Check Firewall()
    {
        int rules = CountFirewallRules("OphiStreamer");
        return rules > 0
            ? new Check("Firewall rules", "Ready", CheckLevel.Good)
            : new Check("Firewall rules", "Missing", CheckLevel.Warn, "Run Firewall-Setup.cmd from the test kit (installer will do this)");
    }

    public static Check Charger()
    {
        var power = System.Windows.Forms.SystemInformation.PowerStatus;
        return power.PowerLineStatus == System.Windows.Forms.PowerLineStatus.Online
            ? new Check("On charger", "Yes", CheckLevel.Good)
            : new Check("On charger", "On battery", CheckLevel.Warn, "Windows slows Wi-Fi and the GPU on battery");
    }

    public static Check WifiStandards(bool legacyOnly) =>
        legacyOnly
            ? new Check("Wi-Fi standards", "802.11a/g only", CheckLevel.Bad, "Device Manager > Wi-Fi > Advanced: enable 802.11n/ac")
            : new Check("Wi-Fi standards", "802.11ac", CheckLevel.Good);

    private static ServiceControllerStatus? ServiceStatus(string name)
    {
        try
        {
            using var sc = new ServiceController(name);
            return sc.Status;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Counts firewall rules whose group starts with the given prefix (covers the test kit's "OphiStreamer-Test").</summary>
    private static int CountFirewallRules(string groupPrefix)
    {
        try
        {
            var type = Type.GetTypeFromProgID("HNetCfg.FwPolicy2");
            if (type == null) return 0;
            dynamic policy = Activator.CreateInstance(type)!;
            int count = 0;
            foreach (dynamic rule in policy.Rules)
            {
                string? group = rule.Grouping;
                if (group != null && group.StartsWith(groupPrefix, StringComparison.OrdinalIgnoreCase)) count++;
            }
            return count;
        }
        catch
        {
            return 0;
        }
    }
}
