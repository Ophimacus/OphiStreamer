using System;
using System.Linq;

namespace OphiStreamer.Core;

/// <summary>
/// Stops Windows' background Wi-Fi scans and turns on media streaming mode while held.
/// No admin needed, and Windows undoes both when the handle closes - including if this app crashes
/// (both proven on the Acer in Milestone 0).
/// </summary>
public sealed class LagFix : IDisposable
{
    private IntPtr _handle = IntPtr.Zero;
    private Guid _iface;
    private int _origScan = -1, _origStream = -1;

    public bool Active => _handle != IntPtr.Zero;
    public string? LastError { get; private set; }

    /// <summary>Applies (or re-applies) the fix to the connected Wi-Fi interface. Returns false if it couldn't.</summary>
    public bool Apply()
    {
        try
        {
            if (_handle == IntPtr.Zero) _handle = WlanNative.Open();
            var iface = WlanNative.Interfaces(_handle).FirstOrDefault(i => i.State == WlanNative.StateConnected);
            if (iface == null)
            {
                LastError = "Wi-Fi is not connected";
                return false;
            }
            if (iface.Guid != _iface || _origScan < 0)
            {
                _iface = iface.Guid;
                WlanNative.Query(_handle, _iface, WlanNative.OpBackgroundScan, out _origScan);
                WlanNative.Query(_handle, _iface, WlanNative.OpMediaStreaming, out _origStream);
            }
            uint r1 = WlanNative.Set(_handle, _iface, WlanNative.OpBackgroundScan, 0);
            uint r2 = WlanNative.Set(_handle, _iface, WlanNative.OpMediaStreaming, 1);
            LastError = r1 == 0 && r2 == 0 ? null : $"Windows refused (codes {r1}/{r2})";
            return LastError == null;
        }
        catch (Exception e)
        {
            LastError = e.Message;
            return false;
        }
    }

    /// <summary>Puts the original values back and closes the handle.</summary>
    public void Release()
    {
        if (_handle == IntPtr.Zero) return;
        try
        {
            if (_origScan >= 0) WlanNative.Set(_handle, _iface, WlanNative.OpBackgroundScan, _origScan);
            if (_origStream >= 0) WlanNative.Set(_handle, _iface, WlanNative.OpMediaStreaming, _origStream);
        }
        catch
        {
            // Closing the handle reverts the settings anyway.
        }
        WlanNative.Close(_handle);
        _handle = IntPtr.Zero;
        _origScan = _origStream = -1;
    }

    public void Dispose() => Release();
}
