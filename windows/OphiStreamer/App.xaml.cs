using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Threading;
using System.Windows;
using Microsoft.Win32;
using OphiStreamer.Core;
using Forms = System.Windows.Forms;

namespace OphiStreamer;

public partial class App : System.Windows.Application
{
    private const string InstanceName = "OphiStreamer.SingleInstance";
    private Mutex? _mutex;
    private EventWaitHandle? _showSignal;
    private SessionController? _session;
    private PhoneLink? _phoneLink;
    private MainWindow? _window;
    private Forms.NotifyIcon? _tray;
    private Forms.ToolStripMenuItem? _trayToggle;
    private Icon? _iconOn, _iconOff;
    private bool? _trayActive;

    private const uint EsContinuous = 0x80000000, EsSystemRequired = 0x00000001;
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint flags);

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // One instance: a second launch just brings the existing window forward.
        _mutex = new Mutex(true, InstanceName, out bool first);
        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, InstanceName + ".Show");
        if (!first)
        {
            _showSignal.Set();
            Shutdown();
            return;
        }
        new Thread(() =>
        {
            while (_showSignal.WaitOne()) Dispatcher.BeginInvoke(ShowWindow);
        }) { IsBackground = true }.Start();

        var settings = AppSettings.Load();
        settings.ApplyStartWithWindows();
        _session = new SessionController(settings);
        var apollo = new ApolloClient(settings);
        _phoneLink = new PhoneLink(_session, apollo);
        _phoneLink.Start();
        _window = new MainWindow(_session, settings, apollo, _phoneLink);
        _iconOn = MakeIcon(Color.FromArgb(0x59, 0xBF, 0x40));
        _iconOff = MakeIcon(Color.FromArgb(0x8B, 0x98, 0xA5));
        _window.Icon = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
            _iconOn.Handle, Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
        CreateTray();
        _phoneLink.Notice += msg => Dispatcher.BeginInvoke(() => _tray?.ShowBalloonTip(4000, "OphiStreamer", msg, Forms.ToolTipIcon.Info));

        // Restore normal Wi-Fi before the laptop sleeps, and on logoff/shutdown.
        SystemEvents.PowerModeChanged += (_, args) =>
        {
            if (args.Mode == PowerModes.Suspend) _session.OnSuspend();
        };
        // Only restore Wi-Fi here: the logoff can still be cancelled, and the app must keep working if it is.
        SystemEvents.SessionEnding += (_, _) => _session.OnSuspend();

        // Developer check: "--screenshot <file.png>" renders the window to a PNG and exits.
        int shot = Array.IndexOf(e.Args, "--screenshot");
        if (shot >= 0 && shot + 1 < e.Args.Length)
        {
            var path = e.Args[shot + 1];
            _window.ContentRendered += async (_, _) =>
            {
                await System.Threading.Tasks.Task.Delay(3000); // let the first Wi-Fi read and checks land
                var root = (FrameworkElement)_window.Content;
                var bmp = new System.Windows.Media.Imaging.RenderTargetBitmap((int)root.ActualWidth, (int)root.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                bmp.Render(root);
                var png = new System.Windows.Media.Imaging.PngBitmapEncoder();
                png.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bmp));
                using (var fs = System.IO.File.Create(path)) png.Save(fs);
                ExitApp();
            };
        }

        if (!e.Args.Contains("--tray")) ShowWindow();
    }

    private void CreateTray()
    {
        _trayToggle = new Forms.ToolStripMenuItem("Start Gaming mode", null, (_, _) =>
        {
            if (_session!.Active) _session.TurnOff();
            else _session.TurnOn();
        });
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(_trayToggle);
        menu.Items.Add("Open OphiStreamer", null, (_, _) => ShowWindow());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApp());

        _tray = new Forms.NotifyIcon
        {
            Icon = _iconOff,
            Text = "OphiStreamer",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) ShowWindow(); };
    }

    /// <summary>Gray icon = off, green = Gaming mode on.</summary>
    public void UpdateTray(bool active, string status)
    {
        if (_tray == null) return;
        if (_trayActive != active)
        {
            _tray.Icon = active ? _iconOn : _iconOff;
            _trayActive = active;
            // Keep the laptop from sleeping while Gaming mode is on (the screen may still turn off).
            // Windows drops this by itself if the app closes or crashes.
            SetThreadExecutionState(active ? EsContinuous | EsSystemRequired : EsContinuous);
        }
        var text = (active ? "Gaming mode on - " : "OphiStreamer - ") + status;
        _tray.Text = text.Length > 63 ? text[..63] : text;
        if (_trayToggle != null) _trayToggle.Text = active ? "Stop Gaming mode" : "Start Gaming mode";
    }

    private void ShowWindow()
    {
        if (_window == null) return;
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private void ExitApp()
    {
        _phoneLink?.Dispose();
        _session?.Dispose();
        if (_tray != null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        if (_window != null)
        {
            _window.AllowClose = true;
            _window.Close();
        }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _session?.Dispose();
        _tray?.Dispose();
        _mutex?.Dispose();
        base.OnExit(e);
    }

    /// <summary>Draws the tray icon: a filled dot inside a ring.</summary>
    private static Icon MakeIcon(Color color)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var ring = new Pen(color, 3);
            g.DrawEllipse(ring, 3, 3, 26, 26);
            using var fill = new SolidBrush(color);
            g.FillEllipse(fill, 10, 10, 12, 12);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }
}
