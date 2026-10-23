#Requires -Version 5.1
<#
.SYNOPSIS
    OphiStreamer Milestone 0 - one-click start.

.DESCRIPTION
    Does every laptop-side step for you, then runs the hardware test:
      1. Joins the phone's hotspot (creates the Wi-Fi profile the first time).
      2. Adds the firewall rules and pins the phone network, asking for admin
         only if that hasn't been done yet.
      3. Runs m0-hardware-proof.ps1 as a normal user.

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
$group = 'OphiStreamer-Test'

function Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }

function Get-WlanField([string]$Name) {
    $line = netsh wlan show interfaces | Where-Object { $_ -match "^\s*$Name\s*:" } | Select-Object -First 1
    if ($line) { ($line -replace '^[^:]*:\s*', '').Trim() }
}

function Test-Connected { (Get-WlanField 'State') -eq 'connected' }

function Test-ProfileExists([string]$Name) {
    $null = netsh wlan show profile name="$Name"
    $LASTEXITCODE -eq 0
}

function Test-Pinned([string]$Name) {
    $p = netsh wlan show profile name="$Name"
    ($p -match '^\s*AutoSwitch\s*:.*Do not switch') -and ($p -match '^\s*Cost\s*:.*Fixed')
}

function Add-HotspotProfile([string]$Name, [Security.SecureString]$Password) {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    $n = [Security.SecurityElement]::Escape($Name)
    $k = [Security.SecurityElement]::Escape($plain)
    $xml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$n</name>
  <SSIDConfig><SSID><name>$n</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <autoSwitch>false</autoSwitch>
  <MSM><security>
    <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
    <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$k</keyMaterial></sharedKey>
  </security></MSM>
</WLANProfile>
"@
    # The profile file holds the password in plain text, so it lives only for the add call.
    $file = Join-Path $env:TEMP "ophi-wlan-$([guid]::NewGuid()).xml"
    try {
        Set-Content -Path $file -Value $xml -Encoding UTF8
        netsh wlan add profile filename="$file" user=current | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Windows rejected the Wi-Fi profile for '$Name'." }
    } finally {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
}

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

        if ($current -ne $HotspotName) {
            if (-not (Test-ProfileExists $HotspotName)) {
                $pw = Read-Host "  Password for '$HotspotName'" -AsSecureString
                Add-HotspotProfile $HotspotName $pw
                Write-Host '  Saved the Wi-Fi profile (auto-connect, no auto-switching).'
            }
            netsh wlan connect name="$HotspotName" | Out-Null
            $deadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $deadline -and -not ((Test-Connected) -and (Get-WlanField 'SSID') -eq $HotspotName)) {
                Start-Sleep -Seconds 1
            }
            if ((Get-WlanField 'SSID') -ne $HotspotName) {
                throw "Couldn't connect to '$HotspotName'. Is the phone hotspot on, and the password right?"
            }
        }
        Write-Host "  Connected to '$HotspotName'." -ForegroundColor Green
    }

    Step 'Firewall and network pinning'
    $hasRules = @(Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue).Count -gt 0
    $needPin = $Mode -eq 'PhoneHotspot' -and -not (Test-Pinned $HotspotName)
    if ($hasRules -and -not $needPin) {
        Write-Host '  Already set up, no admin needed.' -ForegroundColor Green
    } else {
        Write-Host '  Windows will ask for admin once.'
        $fwArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$here\m0-firewall.ps1`"", '-NoPause')
        if ($needPin) { $fwArgs += @('-PinNetwork', "`"$HotspotName`"") }
        $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $fwArgs -Wait -PassThru
        $hasRules = @(Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $hasRules) { Write-Host '  Firewall rules are missing (admin prompt declined?). Moonlight may not connect.' -ForegroundColor Yellow }
        elseif ($proc.ExitCode -ne 0) { Write-Host "  Setup exited with code $($proc.ExitCode)." -ForegroundColor Yellow }
        else { Write-Host '  Done.' -ForegroundColor Green }
    }

    Step 'Hardware test (normal user)'
    $testArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$here\m0-hardware-proof.ps1", '-Mode', $Mode, '-LagSeconds', $LagSeconds)
    if ($Mode -eq 'PhoneHotspot') { $testArgs += '-AssumeConnected' }
    & powershell.exe @testArgs
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
