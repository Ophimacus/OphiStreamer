#Requires -Version 5.1
<#
.SYNOPSIS
    OphiStreamer Milestone 0 - one-click start (console version).

.DESCRIPTION
    Does every laptop-side step for you, then runs the hardware test:
      1. Joins the phone's hotspot (creates the Wi-Fi profile the first time).
      2. Adds the firewall rules and pins the phone network, asking for admin
         only if that hasn't been done yet.
      3. Runs m0-hardware-proof.ps1 as a normal user.

    The window version is m0-launcher.ps1 (Start-Test.cmd).

    Phone side (Android doesn't let apps do this): set the hotspot AP band to
    5 GHz once, then turn the hotspot on.

.EXAMPLE
    .\m0-start.ps1
.EXAMPLE
    .\m0-start.ps1 -HotspotName "HONOR X7d" -LagSeconds 180
#>
[CmdletBinding()]
param(
    [string]$HotspotName,
    [ValidateSet('PhoneHotspot', 'LaptopHotspot')]
    [string]$Mode = 'PhoneHotspot',
    [int]$LagSeconds = 90
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'm0-lib.ps1')

function Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }

try {
    Write-Host 'OphiStreamer - Milestone 0 one-click start' -ForegroundColor White

    if ($Mode -eq 'PhoneHotspot') {
        Step 'Phone'
        Write-Host '  Once: Settings > Mobile network > Personal hotspot > More > AP band = 5 GHz.'
        Write-Host '  Now:  turn the phone hotspot on (mobile data can stay off).'

        Step 'Join the phone hotspot'
        $current = if (Test-Connected) { Get-WlanField 'SSID' }
        if ((Test-Connected) -and -not $current) {
            # Windows 11 24H2+ hides Wi-Fi names from desktop apps unless location access is on.
            Write-Host '  Windows is hiding the Wi-Fi name. Turn on: Settings > Privacy & security > Location >' -ForegroundColor Yellow
            Write-Host '  "Location services" and "Let desktop apps access your location", then run this again.' -ForegroundColor Yellow
            return
        }
        if (-not $HotspotName -and $current) {
            $ans = Read-Host "  Laptop is on '$current'. Is that the phone hotspot? [Y/n]"
            if ($ans -notmatch '^[nN]') { $HotspotName = $current }
        }
        if (-not $HotspotName) { $HotspotName = Read-Host '  Phone hotspot name (as shown on the phone)' }
        if (-not $HotspotName) { throw 'No hotspot name given.' }

        $pw = $null
        if ($current -ne $HotspotName -and -not (Test-ProfileExists $HotspotName)) {
            $pw = Read-Host "  Password for '$HotspotName'" -AsSecureString
        }
        $null = Connect-PhoneHotspot $HotspotName $pw
        Write-Host "  Connected to '$HotspotName'." -ForegroundColor Green
    }

    Step 'Firewall and network pinning'
    $needPin = $Mode -eq 'PhoneHotspot' -and -not (Test-Pinned $HotspotName)
    if ((Test-FirewallReady) -and -not $needPin) {
        Write-Host '  Already set up, no admin needed.' -ForegroundColor Green
    } else {
        Write-Host '  Windows will ask for admin once.'
        $pin = if ($needPin) { $HotspotName } else { '' }
        if (Invoke-AdminSetup $here $pin) { Write-Host '  Done.' -ForegroundColor Green }
        else { Write-Host '  Firewall rules are missing (admin prompt declined?). Moonlight may not connect.' -ForegroundColor Yellow }
    }

    Step 'Hardware test (normal user)'
    $testArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$here\m0-hardware-proof.ps1", '-Mode', $Mode, '-LagSeconds', $LagSeconds)
    if ($Mode -eq 'PhoneHotspot') { $testArgs += '-AssumeConnected' }
    & powershell.exe @testArgs
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
