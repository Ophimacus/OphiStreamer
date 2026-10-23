using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace OphiStreamer.Core;

/// <summary>Native Wi-Fi (wlanapi.dll) calls used by the lag fix. Same code proven in tests/m0.</summary>
internal static class WlanNative
{
    [DllImport("wlanapi.dll")] private static extern uint WlanOpenHandle(uint dwClientVersion, IntPtr pReserved, out uint pdwNegotiatedVersion, out IntPtr phClientHandle);
    [DllImport("wlanapi.dll")] private static extern uint WlanCloseHandle(IntPtr hClientHandle, IntPtr pReserved);
    [DllImport("wlanapi.dll")] private static extern uint WlanEnumInterfaces(IntPtr hClientHandle, IntPtr pReserved, out IntPtr ppInterfaceList);
    [DllImport("wlanapi.dll")] private static extern uint WlanQueryInterface(IntPtr hClientHandle, ref Guid pInterfaceGuid, int opCode, IntPtr pReserved, out uint pdwDataSize, out IntPtr ppData, IntPtr pWlanOpcodeValueType);
    [DllImport("wlanapi.dll")] private static extern uint WlanSetInterface(IntPtr hClientHandle, ref Guid pInterfaceGuid, int opCode, uint dwDataSize, IntPtr pData, IntPtr pReserved);
    [DllImport("wlanapi.dll")] private static extern void WlanFreeMemory(IntPtr pMemory);

    public const int OpBackgroundScan = 2;
    public const int OpMediaStreaming = 3;
    public const int StateConnected = 1;

    public sealed record Iface(Guid Guid, string Description, int State);

    public static IntPtr Open()
    {
        uint r = WlanOpenHandle(2, IntPtr.Zero, out _, out IntPtr handle);
        if (r != 0) throw new Win32Exception((int)r);
        return handle;
    }

    public static void Close(IntPtr handle)
    {
        if (handle != IntPtr.Zero) WlanCloseHandle(handle, IntPtr.Zero);
    }

    public static List<Iface> Interfaces(IntPtr handle)
    {
        uint r = WlanEnumInterfaces(handle, IntPtr.Zero, out IntPtr list);
        if (r != 0) throw new Win32Exception((int)r);
        try
        {
            // WLAN_INTERFACE_INFO_LIST: DWORD count, DWORD index, then 532-byte entries
            // (GUID 16 + WCHAR[256] 512 + state DWORD 4).
            const int itemSize = 16 + 512 + 4;
            int count = Marshal.ReadInt32(list, 0);
            var result = new List<Iface>();
            for (int i = 0; i < count; i++)
            {
                IntPtr item = IntPtr.Add(list, 8 + i * itemSize);
                var guid = new byte[16];
                Marshal.Copy(item, guid, 0, 16);
                result.Add(new Iface(new Guid(guid), Marshal.PtrToStringUni(IntPtr.Add(item, 16)) ?? "", Marshal.ReadInt32(item, 16 + 512)));
            }
            return result;
        }
        finally { WlanFreeMemory(list); }
    }

    public static uint Query(IntPtr handle, Guid iface, int opcode, out int value)
    {
        value = -1;
        uint r = WlanQueryInterface(handle, ref iface, opcode, IntPtr.Zero, out _, out IntPtr data, IntPtr.Zero);
        if (r == 0)
        {
            value = Marshal.ReadInt32(data);
            WlanFreeMemory(data);
        }
        return r;
    }

    public static uint Set(IntPtr handle, Guid iface, int opcode, int value)
    {
        IntPtr data = Marshal.AllocHGlobal(4);
        try
        {
            Marshal.WriteInt32(data, value);
            return WlanSetInterface(handle, ref iface, opcode, 4, data, IntPtr.Zero);
        }
        finally { Marshal.FreeHGlobal(data); }
    }
}
