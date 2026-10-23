#Requires -Version 5.1
<#
.SYNOPSIS
    OphiStreamer Milestone 0 - temporary firewall rules for Sunshine, and phone-network pinning.

.DESCRIPTION
    Asks for admin (once), then allows Sunshine traffic coming from the local
    network only (Windows "LocalSubnet": works for both the laptop hotspot and the
    phone hotspot, whose address range Android randomises):
      - a program rule for sunshine.exe (primary)
      - TCP + UDP ports 47984-48010 (fallback)
    All rules are in the group "OphiStreamer-Test" and can be removed with -Remove.

    -PinNetwork "<Wi-Fi profile>" also pins the phone hotspot: connect automatically,
    never auto-switch to another network, and mark it metered (no Windows Update).
    -PinNetwork with -Remove un-meters it again.

.EXAMPLE
    .\m0-firewall.ps1
.EXAMPLE
    .\m0-firewall.ps1 -Remove
.EXAMPLE
    .\m0-firewall.ps1 -SunshinePath 'D:\Apps\Sunshine\sunshine.exe'
.EXAMPLE
    .\m0-firewall.ps1 -PinNetwork 'HONOR X7d'
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$SunshinePath,
    [string]$PinNetwork
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Remove) { $relaunch += '-Remove' }
    if ($SunshinePath) { $relaunch += @('-SunshinePath', "`"$SunshinePath`"") }
    if ($PinNetwork) { $relaunch += @('-PinNetwork', "`"$PinNetwork`"") }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $relaunch
    exit
}

$group = 'OphiStreamer-Test'
$subnet = 'LocalSubnet'
$ports = '47984-48010'

try {
    if ($PinNetwork) {
        if ($Remove) {
            netsh wlan set profileparameter name="$PinNetwork" cost=Unrestricted
            Write-Host "Un-metered '$PinNetwork'." -ForegroundColor Green
        } else {
            netsh wlan set profileparameter name="$PinNetwork" connectionmode=auto autoswitch=No cost=Fixed
            Write-Host "Pinned '$PinNetwork': auto-connect, no auto-switching, metered." -ForegroundColor Green
        }
    }

    $old = @(Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue)
    if ($old.Count -gt 0) {
        $old | Remove-NetFirewallRule
        Write-Host "Removed $($old.Count) previous OphiStreamer test rule(s)."
    }
    if ($Remove) {
        Write-Host 'Done. No OphiStreamer test rules remain.' -ForegroundColor Green
        return
    }

    if (-not $SunshinePath) {
        $running = Get-Process sunshine -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
        $candidates = @(
            $running
            "$env:ProgramFiles\Sunshine\sunshine.exe"
            "$env:ProgramFiles\Apollo\sunshine.exe"
            "${env:ProgramFiles(x86)}\Sunshine\sunshine.exe"
        )
        $SunshinePath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    }

    if ($SunshinePath -and (Test-Path $SunshinePath)) {
        New-NetFirewallRule -DisplayName 'OphiStreamer-Test Sunshine (local network)' -Group $group `
            -Direction Inbound -Action Allow -Program $SunshinePath -Profile Any -RemoteAddress $subnet | Out-Null
        Write-Host "Allowed $SunshinePath from $subnet" -ForegroundColor Green

        # A Block rule always wins over an Allow rule in Windows Firewall.
        $blocks = @(Get-NetFirewallApplicationFilter -Program $SunshinePath -ErrorAction SilentlyContinue |
            Get-NetFirewallRule | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' })
        foreach ($b in $blocks) {
            Write-Host "WARNING: block rule '$($b.DisplayName)' (profile $($b.Profile)) overrides this. Disable it in Windows Defender Firewall > Advanced settings." -ForegroundColor Yellow
        }
    } else {
        Write-Host 'Sunshine not found - only port rules added. Use -SunshinePath to point at sunshine.exe.' -ForegroundColor Yellow
    }

    foreach ($proto in 'TCP', 'UDP') {
        New-NetFirewallRule -DisplayName "OphiStreamer-Test Sunshine ports $proto (local network)" -Group $group `
            -Direction Inbound -Action Allow -Protocol $proto -LocalPort $ports -Profile Any -RemoteAddress $subnet | Out-Null
    }
    Write-Host "Allowed TCP+UDP $ports from $subnet" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Remove these rules after testing with: Firewall-Setup.cmd -Remove'
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host ''
    Read-Host 'Press Enter to close'
}
