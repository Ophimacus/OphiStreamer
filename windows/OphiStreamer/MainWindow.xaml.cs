using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using OphiStreamer.Core;

namespace OphiStreamer;

public partial class MainWindow : Window
{
    private static readonly Brush Good = Brush("#59BF40");
    private static readonly Brush Warn = Brush("#E6B450");
    private static readonly Brush Bad = Brush("#E5534B");
    private static readonly Brush Muted = Brush("#8B98A5");
    private static readonly Brush TextBrush = Brush("#DCDEDF");

    private readonly SessionController _session;
    private readonly AppSettings _settings;
    private List<Check> _checks = new();
    private DateTime _lastChecks = DateTime.MinValue;
    private bool _checking;
    private bool _updatingSwitch;

    /// <summary>Set by App when the user really exits (tray menu), so closing doesn't just hide.</summary>
    public bool AllowClose { get; set; }

    public MainWindow(SessionController session, AppSettings settings)
    {
        InitializeComponent();
        _session = session;
        _settings = settings;

        TitleBar.MouseLeftButtonDown += (_, _) => DragMove();
        MinBtn.Click += (_, _) => WindowState = WindowState.Minimized;
        CloseBtn.Click += (_, _) => Hide();
        NavStream.Checked += (_, _) => ShowPage(StreamPage);
        NavLog.Checked += (_, _) => { ShowPage(LogPage); LoadLog(); };
        NavSettings.Checked += (_, _) => { ShowPage(SettingsPage); LoadSettings(); };

        GamingSwitch.Click += (_, _) => { if (!_updatingSwitch) Toggle(); };
        MainBtn.Click += (_, _) => Toggle();
        UseCurrentBtn.Click += (_, _) => UseCurrentNetwork();
        CopyIpBtn.Click += (_, _) => { if (_session.Link.LaptopIp != null) Clipboard.SetText(_session.Link.LaptopIp); };
        OpenLogsBtn.Click += (_, _) => { Directory.CreateDirectory(Core.EventLog.Folder); Process.Start("explorer.exe", Core.EventLog.Folder); };
        SaveBtn.Click += (_, _) => SaveSettings();

        _session.Changed += () => Dispatcher.BeginInvoke(Refresh);
        Refresh();
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // The close button hides to the tray, like Steam; Exit lives in the tray menu.
        if (!AllowClose)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }

    private void ShowPage(FrameworkElement page)
    {
        foreach (var p in new FrameworkElement[] { StreamPage, LogPage, SettingsPage }) p.Visibility = p == page ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Toggle()
    {
        if (_session.Active) _session.TurnOff();
        else _session.TurnOn();
    }

    private void UseCurrentNetwork()
    {
        var ssid = _session.Link.Ssid;
        if (ssid == null) return;
        _settings.PhoneSsid = ssid;
        _settings.Save();
        Refresh();
    }

    private void Refresh()
    {
        var link = _session.Link;
        var active = _session.Active;

        HeroTitle.Text = active ? "Gaming mode active" : "Gaming mode off";
        HeroSub.Text = active && link.Connected
            ? $"{link.Ssid} · {(link.Is5GHz ? "5 GHz" : "2.4 GHz")} · channel {link.Channel}{(link.IsDfs ? " (radar channel)" : "")}"
            : _session.Status;
        _updatingSwitch = true;
        GamingSwitch.IsChecked = active;
        _updatingSwitch = false;
        MainBtn.Content = active ? "STOP GAMING MODE" : "START GAMING MODE";
        Tiles.Opacity = active ? 1 : 0.4;

        var lat = _session.Latency;
        TileLatency.Text = lat.Samples > 0 ? $"{lat.AvgMs:0} ms" : "-";
        TileLatency.Foreground = lat.Samples == 0 ? TextBrush : lat.AvgMs < 15 ? Good : lat.AvgMs < 40 ? Warn : Bad;
        TileBand.Text = link.Connected ? (link.Is5GHz ? "5 GHz" : "2.4 GHz") : "-";
        TileBand.Foreground = !link.Connected ? TextBrush : link.Is5GHz && !link.IsDfs ? Good : Warn;
        TileSignal.Text = link.Connected ? $"{link.SignalPercent}%" : "-";
        TileSignal.Foreground = !link.Connected ? TextBrush : link.SignalPercent >= 70 ? Good : link.SignalPercent >= 50 ? Warn : Bad;
        TileSpikes.Text = lat.Samples > 0 ? lat.Spikes.ToString() : "-";
        TileSpikes.Foreground = lat.Samples == 0 ? TextBrush : lat.Spikes == 0 ? Good : lat.Spikes <= 2 ? Warn : Bad;

        PhoneSsidText.Text = _settings.PhoneSsid ?? "Not set. Join your phone hotspot, then press Use current network.";
        UseCurrentBtn.IsEnabled = link.Ssid != null && link.Ssid != _settings.PhoneSsid;
        LaptopIpText.Text = link.LaptopIp ?? "-";

        RenderChecks(link, active);
        if (DateTime.UtcNow - _lastChecks > TimeSpan.FromSeconds(15)) RunChecksInBackground();
        if (LogPage.Visibility == Visibility.Visible) LoadLog();
        (Application.Current as App)?.UpdateTray(active, _session.Status);
    }

    private void RunChecksInBackground()
    {
        if (_checking) return;
        _checking = true;
        _lastChecks = DateTime.UtcNow;
        Task.Run(() => new List<Check>
        {
            SystemChecks.Host(),
            SystemChecks.ControllerDriver(),
            SystemChecks.Firewall(),
            SystemChecks.WifiStandards(WifiLink.LegacyRadioOnly()),
            SystemChecks.Charger(),
        }).ContinueWith(t =>
        {
            _checking = false;
            if (t.IsCompletedSuccessfully)
            {
                _checks = t.Result;
                Dispatcher.BeginInvoke(Refresh);
            }
        });
    }

    private void RenderChecks(WifiState link, bool active)
    {
        var rows = new List<Check>
        {
            active
                ? (_session.LagFixOn
                    ? new Check("Freeze Wi-Fi scanning", "On", CheckLevel.Good, "Stops the once-a-minute lag spike")
                    : new Check("Freeze Wi-Fi scanning", "Failed", CheckLevel.Bad, _session.LagFixError))
                : new Check("Freeze Wi-Fi scanning", "Off", CheckLevel.Off, "Turns on with Gaming mode"),
            active
                ? new Check("Phone keep-alive", "On", CheckLevel.Good, "Stops the phone's radio from dozing")
                : new Check("Phone keep-alive", "Off", CheckLevel.Off),
            new Check("Drops this session", _session.DropsThisSession.ToString(),
                _session.DropsThisSession == 0 ? CheckLevel.Good : CheckLevel.Warn, "Reconnects automatically"),
        };
        rows.AddRange(_checks);

        ChecksPanel.Children.Clear();
        for (int i = 0; i < rows.Count; i++) ChecksPanel.Children.Add(Row(rows[i], last: i == rows.Count - 1));
    }

    private static UIElement Row(Check c, bool last)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(new TextBlock { Text = c.Name, FontSize = 14 });
        if (!string.IsNullOrEmpty(c.Hint)) left.Children.Add(new TextBlock { Text = c.Hint, FontSize = 12, Foreground = Muted, TextWrapping = TextWrapping.Wrap });
        grid.Children.Add(left);

        var color = c.Level switch { CheckLevel.Good => Good, CheckLevel.Warn => Warn, CheckLevel.Bad => Bad, _ => Muted };
        var pill = new Border
        {
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(10, 3, 10, 3),
            VerticalAlignment = VerticalAlignment.Center,
            Background = new SolidColorBrush(Color.FromArgb(0x2A, ((SolidColorBrush)color).Color.R, ((SolidColorBrush)color).Color.G, ((SolidColorBrush)color).Color.B)),
            Child = new TextBlock { Text = c.Status.ToUpperInvariant(), FontSize = 10, FontWeight = FontWeights.Bold, Foreground = color },
        };
        Grid.SetColumn(pill, 1);
        grid.Children.Add(pill);

        return new Border
        {
            BorderBrush = Brush("#212B37"),
            BorderThickness = new Thickness(0, 0, 0, last ? 0 : 1),
            Padding = new Thickness(16, 11, 16, 11),
            Child = grid,
        };
    }

    private void LoadLog()
    {
        LogPanel.Children.Clear();
        var file = Path.Combine(Core.EventLog.Folder, $"events-{DateTime.Now:yyyyMMdd}.csv");
        if (!File.Exists(file))
        {
            LogPanel.Children.Add(new TextBlock { Text = "Nothing logged today yet.", Foreground = Muted, FontSize = 12 });
            return;
        }
        string[] lines;
        try
        {
            using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var reader = new StreamReader(fs);
            lines = reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries).Skip(1).ToArray();
        }
        catch
        {
            return;
        }
        foreach (var line in lines.Reverse().Take(200))
        {
            var parts = line.TrimEnd('\r').Split(',');
            if (parts.Length < 3) continue;
            var kind = parts[1];
            var color = kind switch { "drop" => Bad, "reconnected" => Good, "gaming_on" => Brush("#1A9FFF"), _ => TextBrush };
            LogPanel.Children.Add(new TextBlock
            {
                Text = $"{parts[0]}  {kind.Replace('_', ' ')}  {parts[2].Trim('"')}",
                Foreground = color,
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                FontSize = 12,
                Margin = new Thickness(0, 1, 0, 1),
            });
        }
    }

    private void LoadSettings()
    {
        SsidBox.Text = _settings.PhoneSsid ?? _session.Link.Ssid ?? "";
        AutoBox.IsChecked = _settings.AutoGamingMode;
        StartupBox.IsChecked = _settings.StartWithWindows;
        SavedText.Text = "";
    }

    private void SaveSettings()
    {
        _settings.PhoneSsid = string.IsNullOrWhiteSpace(SsidBox.Text) ? null : SsidBox.Text.Trim();
        _settings.AutoGamingMode = AutoBox.IsChecked == true;
        _settings.StartWithWindows = StartupBox.IsChecked == true;
        _settings.Save();
        SavedText.Text = "Saved.";
        Refresh();
    }

    private static Brush Brush(string hex) => (Brush)new BrushConverter().ConvertFromString(hex)!;
}
