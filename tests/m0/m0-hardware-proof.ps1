#Requires -Version 5.1
<#
.SYNOPSIS
    OphiStreamer Milestone 0 - hardware proof test.

.DESCRIPTION
    Run on a laptop with Wi-Fi (with your Android phone nearby) from a NORMAL,
    non-admin PowerShell window. It checks the assumptions PLAN.md depends on:

      Hotspot    Mobile Hotspot starts without admin
      Band       Hotspot can be set to 5 GHz
      WlanSet    WlanSetInterface (background scan off, streaming mode on) works without admin
      Revert     Those settings are undone when the app closes its handle
      Crash      Those settings are undone when the app is killed
      Phone      The phone connects to the hotspot
      Lag        Latency spikes are lower with the fix (pings the phone or the router)
      Moonlight  Moonlight streams over the hotspot (you answer y/n)

    Everything it changes is put back at the end. A report (without your hotspot
    password) is saved next to this script.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\m0-hardware-proof.ps1

.EXAMPLE
    .\m0-hardware-proof.ps1 -NoPhone -LagSeconds 120
#>
[CmdletBinding()]
param(
    # Seconds per latency phase. Windows scans roughly once a minute, so keep this >= 90.
    [int]$LagSeconds = 90,
    [switch]$SkipLagTest,
    # Skip everything that needs the phone (lag test falls back to pinging the router).
    [switch]$NoPhone,
    # Internal: used by the crash test to run a helper process. Do not pass by hand.
    [string]$ChildHold
)

$ErrorActionPreference = 'Stop'

$wlanSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class OphiWlan
{
    [DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint dwClientVersion, IntPtr pReserved, out uint pdwNegotiatedVersion, out IntPtr phClientHandle);
    [DllImport("wlanapi.dll")] static extern uint WlanCloseHandle(IntPtr hClientHandle, IntPtr pReserved);
    [DllImport("wlanapi.dll")] static extern uint WlanEnumInterfaces(IntPtr hClientHandle, IntPtr pReserved, out IntPtr ppInterfaceList);
    [DllImport("wlanapi.dll")] static extern uint WlanQueryInterface(IntPtr hClientHandle, ref Guid pInterfaceGuid, int OpCode, IntPtr pReserved, out uint pdwDataSize, out IntPtr ppData, IntPtr pWlanOpcodeValueType);
    [DllImport("wlanapi.dll")] static extern uint WlanSetInterface(IntPtr hClientHandle, ref Guid pInterfaceGuid, int OpCode, uint dwDataSize, IntPtr pData, IntPtr pReserved);
    [DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr pMemory);

    // WLAN_INTF_OPCODE values
    public const int OpBackgroundScan = 2;
    public const int OpMediaStreaming = 3;
    // WLAN_INTERFACE_STATE value
    public const int StateConnected = 1;

    static readonly string[] StateNames = {
        "not_ready", "connected", "ad_hoc_formed", "disconnecting",
        "disconnected", "associating", "discovering", "authenticating" };

    public class Iface
    {
        public Guid Guid;
        public string Description;
        public int State;
    }

    public static string StateName(int state)
    {
        return state >= 0 && state < StateNames.Length ? StateNames[state] : state.ToString();
    }

    public static IntPtr Open()
    {
        uint negotiated;
        IntPtr handle;
        uint r = WlanOpenHandle(2, IntPtr.Zero, out negotiated, out handle);
        if (r != 0) throw new Win32Exception((int)r);
        return handle;
    }

    public static void Close(IntPtr handle)
    {
        if (handle != IntPtr.Zero) WlanCloseHandle(handle, IntPtr.Zero);
    }

    public static List<Iface> Interfaces(IntPtr handle)
    {
        IntPtr list;
        uint r = WlanEnumInterfaces(handle, IntPtr.Zero, out list);
        if (r != 0) throw new Win32Exception((int)r);
        try
        {
            // WLAN_INTERFACE_INFO_LIST: DWORD count, DWORD index, then WLAN_INTERFACE_INFO[]
            // WLAN_INTERFACE_INFO: GUID (16) + WCHAR[256] (512) + state DWORD (4) = 532 bytes
            const int itemSize = 16 + 512 + 4;
            int count = Marshal.ReadInt32(list, 0);
            var result = new List<Iface>();
            for (int i = 0; i < count; i++)
            {
                IntPtr item = IntPtr.Add(list, 8 + i * itemSize);
                byte[] guid = new byte[16];
                Marshal.Copy(item, guid, 0, 16);
                result.Add(new Iface {
                    Guid = new Guid(guid),
                    Description = Marshal.PtrToStringUni(IntPtr.Add(item, 16)),
                    State = Marshal.ReadInt32(item, 16 + 512)
                });
            }
            return result;
        }
        finally { WlanFreeMemory(list); }
    }

    public static uint Query(IntPtr handle, Guid iface, int opcode, out int value)
    {
        uint size;
        IntPtr data;
        value = -1;
        uint r = WlanQueryInterface(handle, ref iface, opcode, IntPtr.Zero, out size, out data, IntPtr.Zero);
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
'@
if (-not ('OphiWlan' -as [type])) { Add-Type -TypeDefinition $wlanSource -Language CSharp }

# --- Helper process for the crash test: apply the fix, then wait to be killed ---
if ($ChildHold) {
    $readyFile = Join-Path $env:TEMP "ophi-m0-child-$PID.ready"
    $h = [OphiWlan]::Open()
    $g = [Guid]$ChildHold
    $r1 = [OphiWlan]::Set($h, $g, [OphiWlan]::OpBackgroundScan, 0)
    $r2 = [OphiWlan]::Set($h, $g, [OphiWlan]::OpMediaStreaming, 1)
    Set-Content -Path $readyFile -Value "$r1,$r2"
    Start-Sleep -Seconds 600
    exit 0
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Host 'Run this with Windows PowerShell 5.1 (powershell.exe), not PowerShell 7 (pwsh).' -ForegroundColor Red
    Write-Host 'PowerShell 7 cannot call the Windows hotspot API.' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- helpers

$script:Results = New-Object System.Collections.Generic.List[object]

function Record {
    param([string]$Step, [string]$Result, [string]$Detail = '', [string]$Key = '')
    $script:Results.Add([pscustomobject]@{ Key = $Key; Step = $Step; Result = $Result; Detail = $Detail })
    $color = switch ($Result) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'SKIP' { 'DarkYellow' } default { 'Gray' } }
    $line = "[$Result] $Step"
    if ($Detail) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Section([string]$Title) {
    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Get-InnerMessage($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    $e.Message
}

# WinRT async -> .NET Task (Windows PowerShell 5.1 pattern)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$script:AsTaskOp = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } |
    Select-Object -First 1
$script:AsTaskAction = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } |
    Select-Object -First 1

function Await-Op($Operation, [Type]$ResultType) {
    $task = $script:AsTaskOp.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $null = $task.Wait(-1)
    $task.Result
}

function Await-Action($Action) {
    $task = $script:AsTaskAction.Invoke($null, @($Action))
    $null = $task.Wait(-1)
}

function Get-WlanValues([IntPtr]$Handle) {
    $scan = 0; $stream = 0
    $r1 = [OphiWlan]::Query($Handle, $script:Iface, [OphiWlan]::OpBackgroundScan, [ref]$scan)
    $r2 = [OphiWlan]::Query($Handle, $script:Iface, [OphiWlan]::OpMediaStreaming, [ref]$stream)
    if ($r1 -ne 0) { $scan = -1 }
    if ($r2 -ne 0) { $stream = -1 }
    , @($scan, $stream)
}

function Test-WlanIsOriginal([int[]]$Values) {
    $Values[0] -eq $script:OrigScan -and $Values[1] -eq $script:OrigStream
}

function Restore-Wlan([IntPtr]$Handle) {
    if ($Handle -eq [IntPtr]::Zero -or -not $script:Iface) { return }
    if ($script:OrigScan -ge 0) { $null = [OphiWlan]::Set($Handle, $script:Iface, [OphiWlan]::OpBackgroundScan, $script:OrigScan) }
    if ($script:OrigStream -ge 0) { $null = [OphiWlan]::Set($Handle, $script:Iface, [OphiWlan]::OpMediaStreaming, $script:OrigStream) }
}

function Enable-Fix([IntPtr]$Handle) {
    $r1 = [OphiWlan]::Set($Handle, $script:Iface, [OphiWlan]::OpBackgroundScan, 0)
    $r2 = [OphiWlan]::Set($Handle, $script:Iface, [OphiWlan]::OpMediaStreaming, 1)
    , @($r1, $r2)
}

function Measure-Latency([string]$Target, [int]$Seconds) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $times = New-Object System.Collections.Generic.List[double]
    $lost = 0
    $sent = 0
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        try {
            $reply = $ping.Send($Target, 1000)
            if ($reply.Status -eq 'Success') { $times.Add($reply.RoundtripTime) } else { $lost++ }
        } catch { $lost++ }
        $sent++
        if ($sent % 50 -eq 0) { Write-Host -NoNewline '.' }
        Start-Sleep -Milliseconds 100
    }
    Write-Host ''
    $sorted = @($times | Sort-Object)
    $stats = [pscustomobject]@{ Sent = $sent; Replies = $sorted.Count; Lost = $lost; Avg = 0; P99 = 0; Max = 0; Spikes = 0 }
    if ($sorted.Count -gt 0) {
        $stats.Avg = [math]::Round(($sorted | Measure-Object -Average).Average, 1)
        $stats.P99 = $sorted[[math]::Min($sorted.Count - 1, [int][math]::Floor($sorted.Count * 0.99))]
        $stats.Max = $sorted[-1]
        $stats.Spikes = @($sorted | Where-Object { $_ -ge 50 }).Count
    }
    $stats
}

function Format-Latency($s) {
    "avg $($s.Avg) ms, p99 $($s.P99) ms, max $($s.Max) ms, spikes>=50ms: $($s.Spikes), lost: $($s.Lost)/$($s.Sent)"
}

# ---------------------------------------------------------------- state

$script:Mgr = $null
$script:StartedHotspot = $false
$script:RestoreOn = $false
$script:BandChanged = $false
$script:OrigBand = $null
$script:Iface = $null
$script:OrigScan = -1
$script:OrigStream = -1
$script:HQuery = [IntPtr]::Zero
$script:HWork = [IntPtr]::Zero
$script:HFix = [IntPtr]::Zero
$script:Child = $null
$wifi = @()
$hostIp = $null
$phoneIp = $null
$phoneConnected = $false

$NS = 'Windows.Networking.NetworkOperators'

Write-Host ''
Write-Host 'OphiStreamer - Milestone 0 hardware proof' -ForegroundColor White
Write-Host 'Everything this test changes is put back at the end. Press Ctrl+C to abort safely.'

try {
    # ------------------------------------------------------------ 1. Environment
    Section '1. Environment'

    $os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    # ProductName still says "Windows 10" on Windows 11; the build number tells them apart.
    $winName = if ([int]$os.CurrentBuild -ge 22000) { $os.ProductName -replace 'Windows 10', 'Windows 11' } else { $os.ProductName }
    Record 'Windows version' 'INFO' "$winName $($os.DisplayVersion) build $($os.CurrentBuild).$($os.UBR)"

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Record 'Running as normal user' 'WARN' 'This window is elevated, so "no admin" results are NOT proven. Re-run from a normal window.'
    } else {
        Record 'Running as normal user' 'PASS'
    }

    $wifi = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -match '802\.11' })
    if ($wifi.Count -eq 0) {
        Record 'Wi-Fi adapter present' 'FAIL' 'No Wi-Fi adapter found. Run this on a laptop/PC with Wi-Fi.'
        return
    }
    foreach ($a in $wifi) {
        Record 'Wi-Fi adapter' 'INFO' "$($a.Name): $($a.InterfaceDescription) [$($a.Status)] driver $($a.DriverVersion)"
    }

    $svc = Get-Service wlansvc
    if ($svc.Status -ne 'Running') {
        Record 'WLAN AutoConfig service' 'FAIL' "wlansvc is $($svc.Status)"
        return
    }

    netsh wlan show drivers | Where-Object { $_ -match 'Radio types supported|Hosted network supported|Wi-Fi Direct' } |
        ForEach-Object { Record 'Driver' 'INFO' $_.Trim() }

    $link = @(netsh wlan show interfaces | Where-Object { $_ -match '^\s*(Name|State|SSID|Radio type|Band|Channel|Signal)\s*:' })
    foreach ($l in $link) { Record 'Laptop Wi-Fi link' 'INFO' $l.Trim() }
    $bandLine = $link | Where-Object { $_ -match '^\s*Band\s*:' } | Select-Object -First 1
    $chanLine = $link | Where-Object { $_ -match '^\s*Channel\s*:' } | Select-Object -First 1
    $on24 = ($bandLine -match '2\.4') -or ($chanLine -match ':\s*([1-9]|1[0-4])\s*$')
    $stateLine = $link | Where-Object { $_ -match '^\s*State\s*:' } | Select-Object -First 1
    $wifiConnected = $stateLine -match ':\s*connected\s*$'
    if ($on24) {
        Record 'Laptop Wi-Fi band' 'WARN' 'Laptop is on 2.4 GHz Wi-Fi. Single-radio cards may force the hotspot onto 2.4 GHz too.'
    }
    # Intel rule (support article 000029083): a 5 GHz hotspot is only allowed while the
    # PC is also connected to a 5 GHz Wi-Fi access point. Ethernet alone is not enough.
    if (($wifi | Where-Object { $_.InterfaceDescription -match 'Intel' }) -and (-not $wifiConnected -or $on24)) {
        Record 'Intel 5 GHz rule' 'WARN' 'Intel cards only allow a 5 GHz hotspot while the laptop is connected to a 5 GHz Wi-Fi network. Connect to your router''s 5 GHz Wi-Fi first.'
    }

    $peerless = $null
    try { $peerless = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings' -ErrorAction Stop).PeerlessTimeoutEnabled } catch { }
    if ($null -eq $peerless) {
        Record 'Hotspot idle timeout' 'INFO' 'PeerlessTimeoutEnabled not set (Windows default: hotspot turns off ~5 min after last device leaves)'
    } else {
        Record 'Hotspot idle timeout' 'INFO' "PeerlessTimeoutEnabled = $peerless"
    }

    # ------------------------------------------------------------ 2. Hotspot
    Section '2. Mobile Hotspot (no admin)'

    try {
        $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
        $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
        $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
    } catch {
        Record 'Load Windows hotspot API' 'FAIL' (Get-InnerMessage $_) -Key Hotspot
        return
    }
    $bandTypeLoaded = $true
    try { $null = [Windows.Networking.NetworkOperators.TetheringWiFiBand, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime] }
    catch { $bandTypeLoaded = $false }
    $resultType = "$NS.NetworkOperatorTetheringOperationResult" -as [type]

    $connProfile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if (-not $connProfile) {
        $connProfile = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles() |
            Where-Object { "$($_.GetNetworkConnectivityLevel())" -ne 'None' } | Select-Object -First 1
    }
    if (-not $connProfile) {
        Record 'Connection to share' 'FAIL' 'No connected network. Connect the laptop to Wi-Fi or Ethernet first.' -Key Hotspot
        return
    }
    Record 'Connection to share' 'INFO' "$($connProfile.ProfileName) (connectivity: $($connProfile.GetNetworkConnectivityLevel()))"

    $cap = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::GetTetheringCapabilityFromConnectionProfile($connProfile)
    if ("$cap" -ne 'Enabled') {
        Record 'Hotspot capability' 'FAIL' "Windows says: $cap" -Key Hotspot
        return
    }
    Record 'Hotspot capability' 'PASS'

    $script:Mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($connProfile)
    $mgr = $script:Mgr

    if ("$($mgr.TetheringOperationalState)" -eq 'On') {
        $script:RestoreOn = $true
        Record 'Hotspot was already on' 'INFO' 'Stopping it to apply test settings; it will be turned back on at the end'
        $null = Await-Op ($mgr.StopTetheringAsync()) $resultType
    }

    $cfg = $mgr.GetCurrentAccessPointConfiguration()
    Record 'Hotspot name' 'INFO' $cfg.Ssid

    $bandApi = $bandTypeLoaded
    if ($bandApi) { try { $script:OrigBand = $cfg.Band } catch { $bandApi = $false } }
    if (-not $bandApi -or $null -eq $script:OrigBand) {
        Record '5 GHz band' 'FAIL' 'This Windows build has no band setting in the hotspot API' -Key Band
    } else {
        Record 'Band setting before test' 'INFO' "$($script:OrigBand)"
        $support = @{}
        foreach ($b in 'TwoPointFourGigahertz', 'FiveGigahertz', 'SixGigahertz') {
            try { $support[$b] = $cfg.IsBandSupported([Windows.Networking.NetworkOperators.TetheringWiFiBand]$b) }
            catch { $support[$b] = 'unknown' }
            Record "Band supported: $b" 'INFO' "$($support[$b])"
        }
        if ($support['FiveGigahertz'] -eq $false) {
            Record '5 GHz band' 'FAIL' 'Adapter/driver reports 5 GHz hotspot is not supported' -Key Band
        } else {
            try {
                $cfg.Band = [Windows.Networking.NetworkOperators.TetheringWiFiBand]::FiveGigahertz
                Await-Action ($mgr.ConfigureAccessPointAsync($cfg))
                $script:BandChanged = $true
                $now = $mgr.GetCurrentAccessPointConfiguration().Band
                if ("$now" -eq 'FiveGigahertz') {
                    Record '5 GHz band' 'PASS' 'Configured without admin' -Key Band
                } else {
                    Record '5 GHz band' 'FAIL' "Windows kept band = $now" -Key Band
                }
            } catch {
                Record '5 GHz band' 'FAIL' (Get-InnerMessage $_) -Key Band
            }
        }
    }

    $startError = $null
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $res = Await-Op ($mgr.StartTetheringAsync()) $resultType
        if ("$($res.Status)" -eq 'Success') {
            $script:StartedHotspot = $true
            Record 'Start hotspot without admin' 'PASS' "started in $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s" -Key Hotspot
        } else {
            $startError = "$($res.Status) $($res.AdditionalErrorMessage)"
        }
    } catch { $startError = Get-InnerMessage $_ }

    # Same fallback the app will use: if 5 GHz blocks the start, retry on Auto.
    if ($startError -and $script:BandChanged) {
        Record 'Start hotspot on 5 GHz' 'WARN' "$startError - retrying with Auto band"
        try {
            $cfg = $mgr.GetCurrentAccessPointConfiguration()
            $cfg.Band = [Windows.Networking.NetworkOperators.TetheringWiFiBand]::Auto
            Await-Action ($mgr.ConfigureAccessPointAsync($cfg))
            Record '5 GHz band' 'FAIL' 'Hotspot would not start on 5 GHz (Auto fallback used)' -Key Band
            $res = Await-Op ($mgr.StartTetheringAsync()) $resultType
            if ("$($res.Status)" -eq 'Success') {
                $script:StartedHotspot = $true
                $startError = $null
                Record 'Start hotspot without admin' 'PASS' 'started on Auto band' -Key Hotspot
            } else {
                $startError = "$($res.Status) $($res.AdditionalErrorMessage)"
            }
        } catch { $startError = Get-InnerMessage $_ }
    }
    if ($startError) { Record 'Start hotspot without admin' 'FAIL' $startError -Key Hotspot }

    if ($script:StartedHotspot) {
        Record 'Max devices' 'INFO' "$($mgr.MaxClientCount)"
        for ($i = 0; $i -lt 10 -and -not $hostIp; $i++) {
            $hostIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -like '192.168.137.*' } | Select-Object -First 1).IPAddress
            if (-not $hostIp) { Start-Sleep -Seconds 1 }
        }
        if ($hostIp) { Record 'PC address on hotspot (for Moonlight)' 'INFO' $hostIp }
        else { Record 'PC address on hotspot (for Moonlight)' 'WARN' 'No 192.168.137.x address found' }
    }

    # ------------------------------------------------------------ 3. WLAN streaming mode
    Section '3. Lag fix: WlanSetInterface (no admin)'

    try {
        $script:HQuery = [OphiWlan]::Open()
    } catch {
        Record 'Open WLAN handle' 'FAIL' (Get-InnerMessage $_) -Key WlanSet
    }

    if ($script:HQuery -ne [IntPtr]::Zero) {
        $ifs = [OphiWlan]::Interfaces($script:HQuery)
        foreach ($i in $ifs) { Record 'WLAN interface' 'INFO' "$($i.Description) - $([OphiWlan]::StateName($i.State))" }
        $target = $ifs | Where-Object { $_.State -eq [OphiWlan]::StateConnected } | Select-Object -First 1

        if (-not $target) {
            $why = 'No Wi-Fi interface is connected to a network (laptop on Ethernet?). Connect the laptop to your router over Wi-Fi to test the lag fix.'
            Record 'Lag fix works without admin' 'SKIP' $why -Key WlanSet
        } else {
            $script:Iface = $target.Guid
            $orig = Get-WlanValues $script:HQuery
            $script:OrigScan = $orig[0]
            $script:OrigStream = $orig[1]
            Record 'Values before test' 'INFO' "background scan = $($orig[0]), streaming mode = $($orig[1]) (-1 = could not read)"

            $script:HWork = [OphiWlan]::Open()
            $codes = Enable-Fix $script:HWork
            if ($codes[0] -eq 0 -and $codes[1] -eq 0) {
                Record 'Lag fix works without admin' 'PASS' 'background scan off + streaming mode on' -Key WlanSet

                $seen = Get-WlanValues $script:HQuery
                $visible = ($seen[0] -eq 0 -and $seen[1] -eq 1)
                if ($visible) {
                    Record 'Change visible from a second handle' 'INFO' 'yes - revert can be measured'
                } else {
                    Record 'Change visible from a second handle' 'INFO' "no (sees scan = $($seen[0]), streaming = $($seen[1])) - revert can't be measured by query; the lag test is the real proof"
                }

                # Revert when the handle is closed (normal app exit)
                [OphiWlan]::Close($script:HWork)
                $script:HWork = [IntPtr]::Zero
                Start-Sleep -Seconds 1
                if ($visible) {
                    $after = Get-WlanValues $script:HQuery
                    if (Test-WlanIsOriginal $after) {
                        Record 'Lag fix undone when app closes' 'PASS' -Key Revert
                    } else {
                        Record 'Lag fix undone when app closes' 'FAIL' "still scan = $($after[0]), streaming = $($after[1]); the app must restore explicitly" -Key Revert
                        Restore-Wlan $script:HQuery
                    }
                } else {
                    Record 'Lag fix undone when app closes' 'SKIP' 'not measurable on this driver' -Key Revert
                }

                # Revert when the process is killed (crash)
                if ($visible) {
                    $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ChildHold', $script:Iface.ToString())
                    $script:Child = Start-Process powershell.exe -ArgumentList $childArgs -WindowStyle Hidden -PassThru
                    $ready = Join-Path $env:TEMP "ophi-m0-child-$($script:Child.Id).ready"
                    $deadline = (Get-Date).AddSeconds(30)
                    while (-not (Test-Path $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }

                    if (-not (Test-Path $ready)) {
                        Record 'Lag fix undone when app crashes' 'FAIL' 'helper process did not start' -Key Crash
                    } else {
                        $childCodes = (Get-Content $ready) -join ''
                        $during = Get-WlanValues $script:HQuery
                        Stop-Process -Id $script:Child.Id -Force
                        $null = $script:Child.WaitForExit(5000)
                        Start-Sleep -Seconds 2
                        $after = Get-WlanValues $script:HQuery
                        if ($during[0] -ne 0) {
                            Record 'Lag fix undone when app crashes' 'FAIL' "helper could not apply the fix (codes $childCodes)" -Key Crash
                        } elseif (Test-WlanIsOriginal $after) {
                            Record 'Lag fix undone when app crashes' 'PASS' 'Windows reverted it after the process was killed' -Key Crash
                        } else {
                            Record 'Lag fix undone when app crashes' 'FAIL' 'Settings stayed after kill; the app must restore on next start' -Key Crash
                            Restore-Wlan $script:HQuery
                        }
                        Remove-Item $ready -ErrorAction SilentlyContinue
                    }
                } else {
                    Record 'Lag fix undone when app crashes' 'SKIP' 'not measurable on this driver' -Key Crash
                }
            } else {
                Record 'Lag fix works without admin' 'FAIL' "error codes: scan = $($codes[0]), streaming = $($codes[1]) (5 = access denied, 50 = not supported, 5023 = invalid state)" -Key WlanSet
                Restore-Wlan $script:HWork
                [OphiWlan]::Close($script:HWork)
                $script:HWork = [IntPtr]::Zero
            }
        }
    }

    # ------------------------------------------------------------ 4. Phone
    Section '4. Phone'

    if ($NoPhone) {
        Record 'Phone connects' 'SKIP' '-NoPhone' -Key Phone
    } elseif (-not $script:StartedHotspot) {
        Record 'Phone connects' 'SKIP' 'hotspot did not start' -Key Phone
    } else {
        $ap = $mgr.GetCurrentAccessPointConfiguration()
        Write-Host ''
        Write-Host '  Connect your phone to this Wi-Fi:' -ForegroundColor White
        Write-Host "    Name:     $($ap.Ssid)"
        Write-Host "    Password: $($ap.Passphrase)"
        Write-Host '  Waiting up to 3 minutes...'
        $deadline = (Get-Date).AddMinutes(3)
        while ($mgr.ClientCount -eq 0 -and (Get-Date) -lt $deadline) {
            if ("$($mgr.TetheringOperationalState)" -ne 'On') { break }
            Start-Sleep -Seconds 2
        }

        if ($mgr.ClientCount -gt 0) {
            $phoneConnected = $true
            Start-Sleep -Seconds 3   # let DHCP finish so the client has an IP
            foreach ($c in $mgr.GetTetheringClients()) {
                $names = @($c.HostNames | ForEach-Object { $_.DisplayName }) -join ', '
                Record 'Connected device' 'INFO' "$($c.MacAddress) $names"
                $ip = $c.HostNames | Where-Object { "$($_.Type)" -eq 'Ipv4' } | Select-Object -First 1
                if ($ip -and -not $phoneIp) { $phoneIp = $ip.CanonicalName }
            }
            if (-not $phoneIp) {
                $phoneIp = (Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -like '192.168.137.*' -and $_.IPAddress -ne $hostIp -and
                                   $_.IPAddress -notlike '*.255' -and "$($_.State)" -ne 'Permanent' -and "$($_.State)" -ne 'Unreachable' } |
                    Select-Object -First 1).IPAddress
            }
            Record 'Phone connects' 'PASS' "IP: $(if ($phoneIp) { $phoneIp } else { 'unknown' })" -Key Phone
        } elseif ("$($mgr.TetheringOperationalState)" -ne 'On') {
            Record 'Phone connects' 'FAIL' 'Hotspot turned off while waiting' -Key Phone
        } else {
            Record 'Phone connects' 'FAIL' 'No device connected within 3 minutes' -Key Phone
        }
    }

    # ------------------------------------------------------------ 5. Lag test
    Section '5. Latency: without vs. with the lag fix'

    $pingTarget = $phoneIp
    $pingName = 'phone'
    if (-not $pingTarget) {
        $gw = (Get-NetIPConfiguration -InterfaceAlias $wifi[0].Name -ErrorAction SilentlyContinue).IPv4DefaultGateway.NextHop
        if ($gw) { $pingTarget = $gw; $pingName = 'router (over laptop Wi-Fi)' }
    }

    if ($SkipLagTest) {
        Record 'Lag spikes reduced' 'SKIP' '-SkipLagTest' -Key Lag
    } elseif (-not $pingTarget) {
        Record 'Lag spikes reduced' 'SKIP' 'nothing to ping (no phone IP, no Wi-Fi gateway)' -Key Lag
    } elseif (-not $script:Iface) {
        Record 'Lag spikes reduced' 'SKIP' 'no connected Wi-Fi interface to apply the fix to' -Key Lag
    } else {
        Write-Host "Phase A: normal Windows behavior, $LagSeconds s, pinging $pingName $pingTarget"
        $a = Measure-Latency $pingTarget $LagSeconds
        Record 'Latency WITHOUT fix' 'INFO' (Format-Latency $a)

        $script:HFix = [OphiWlan]::Open()
        $null = Enable-Fix $script:HFix
        Write-Host "Phase B: lag fix ON, $LagSeconds s, pinging $pingName $pingTarget"
        $b = Measure-Latency $pingTarget $LagSeconds
        Record 'Latency WITH fix' 'INFO' (Format-Latency $b)

        if ($a.Replies -eq 0 -or $b.Replies -eq 0) {
            Record 'Lag spikes reduced' 'WARN' "$pingName did not answer pings; can't measure" -Key Lag
        } elseif ($a.Spikes -eq 0) {
            Record 'Lag spikes reduced' 'WARN' 'No spikes even without the fix; try -LagSeconds 180' -Key Lag
        } elseif ($b.Spikes -lt $a.Spikes) {
            Record 'Lag spikes reduced' 'PASS' "spikes $($a.Spikes) -> $($b.Spikes), max $($a.Max) -> $($b.Max) ms" -Key Lag
        } else {
            Record 'Lag spikes reduced' 'FAIL' "spikes $($a.Spikes) -> $($b.Spikes), max $($a.Max) -> $($b.Max) ms" -Key Lag
        }
        # Lag fix stays on for the Moonlight test below.
    }

    # ------------------------------------------------------------ 6. Moonlight
    Section '6. Moonlight stream (manual)'

    if (-not $phoneConnected) {
        Record 'Moonlight streams over hotspot' 'SKIP' 'no phone connected' -Key Moonlight
    } else {
        $fixState = if ($script:HFix -ne [IntPtr]::Zero) { 'ON' } else { 'OFF' }
        Write-Host ''
        Write-Host "  Test a real stream now (lag fix is $fixState):" -ForegroundColor White
        Write-Host '    1. Make sure Sunshine is running on this PC.'
        Write-Host '    2. First time? Run Firewall-Setup.cmd (asks for admin once).'
        Write-Host "    3. On the phone: Moonlight -> + (Add PC) -> $hostIp"
        Write-Host '    4. Pair and play for a minute or two.'
        $ans = Read-Host 'Did it stream? [y = yes, n = no, s = skip]'
        switch -Regex ($ans) {
            '^[yY]' { Record 'Moonlight streams over hotspot' 'PASS' -Key Moonlight }
            '^[nN]' { Record 'Moonlight streams over hotspot' 'FAIL' 'see notes' -Key Moonlight }
            default { Record 'Moonlight streams over hotspot' 'SKIP' -Key Moonlight }
        }
        $notes = Read-Host 'Notes (stutter, quality, errors)? Press Enter to skip'
        if ($notes) { Record 'Your notes' 'INFO' $notes }
    }
}
catch {
    Record 'Unexpected error' 'FAIL' (Get-InnerMessage $_)
}
finally {
    Section 'Cleanup'

    try { if ($script:Child -and -not $script:Child.HasExited) { Stop-Process -Id $script:Child.Id -Force } } catch { }

    foreach ($name in 'HFix', 'HWork', 'HQuery') {
        $h = Get-Variable -Scope Script -Name $name -ValueOnly
        if ($h -ne [IntPtr]::Zero) {
            try { Restore-Wlan $h } catch { }
            [OphiWlan]::Close($h)
            Set-Variable -Scope Script -Name $name -Value ([IntPtr]::Zero)
        }
    }
    if ($script:Iface) { Record 'Wi-Fi scan settings restored' 'INFO' }

    if ($script:Mgr) {
        $resultType = "$NS.NetworkOperatorTetheringOperationResult" -as [type]
        try {
            if ($script:StartedHotspot -or $script:RestoreOn) {
                $null = Await-Op ($script:Mgr.StopTetheringAsync()) $resultType
            }
            if ($script:BandChanged -and $null -ne $script:OrigBand) {
                $cfg = $script:Mgr.GetCurrentAccessPointConfiguration()
                $cfg.Band = $script:OrigBand
                Await-Action ($script:Mgr.ConfigureAccessPointAsync($cfg))
            }
            if ($script:RestoreOn) {
                $null = Await-Op ($script:Mgr.StartTetheringAsync()) $resultType
                Record 'Hotspot restored' 'INFO' 'turned back on with original band'
            } elseif ($script:StartedHotspot) {
                Record 'Hotspot restored' 'INFO' 'turned off, original band restored'
            }
        } catch {
            Record 'Hotspot restore' 'WARN' "$(Get-InnerMessage $_) - check Settings > Network > Mobile hotspot"
        }
    }

    # ------------------------------------------------------------ Summary + report
    $checks = [ordered]@{
        Hotspot   = 'Hotspot starts without admin'
        Band      = 'Hotspot runs on 5 GHz'
        WlanSet   = 'Lag fix works without admin'
        Revert    = 'Lag fix undone when app closes'
        Crash     = 'Lag fix undone when app crashes'
        Phone     = 'Phone connects'
        Lag       = 'Lag spikes reduced'
        Moonlight = 'Moonlight streams over hotspot'
    }
    $summary = foreach ($k in $checks.Keys) {
        $r = $script:Results | Where-Object { $_.Key -eq $k } | Select-Object -Last 1
        [pscustomobject]@{ Check = $checks[$k]; Result = $(if ($r) { $r.Result } else { 'NOT RUN' }); Detail = $(if ($r) { $r.Detail } else { '' }) }
    }

    Section 'Summary'
    foreach ($s in $summary) {
        $color = switch ($s.Result) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'DarkYellow' } }
        Write-Host ("  {0,-8} {1}" -f $s.Result, $s.Check) -ForegroundColor $color
    }

    $reportDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $reportPath = Join-Path $reportDir ("m0-report-{0}-{1:yyyyMMdd-HHmmss}.txt" -f $env:COMPUTERNAME, (Get-Date))
    $report = @(
        'OphiStreamer - Milestone 0 hardware proof'
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Computer: $env:COMPUTERNAME"
        ''
        'SUMMARY'
        ($summary | Format-Table -AutoSize -Wrap | Out-String -Width 250)
        'ALL STEPS'
        ($script:Results | Select-Object Result, Step, Detail | Format-Table -AutoSize -Wrap | Out-String -Width 250)
    )
    $report | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host ''
    Write-Host "Report saved: $reportPath" -ForegroundColor White
    Write-Host '(It does not contain your hotspot password.)'
}
