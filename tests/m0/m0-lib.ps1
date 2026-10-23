# Shared helpers for the Milestone 0 launchers (console and window). Dot-source this file.

$OphiTestGroup = 'OphiStreamer-Test'

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
    [bool](($p -match '^\s*AutoSwitch\s*:.*Do not switch') -and ($p -match '^\s*Cost\s*:.*Fixed'))
}

function Test-FirewallReady { @(Get-NetFirewallRule -Group $OphiTestGroup -ErrorAction SilentlyContinue).Count -gt 0 }

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

# Connects to the phone hotspot, creating the profile when a password is given. Returns the SSID or throws.
function Connect-PhoneHotspot([string]$Name, [Security.SecureString]$Password) {
    if ((Get-WlanField 'SSID') -eq $Name -and (Test-Connected)) { return $Name }
    if (-not (Test-ProfileExists $Name)) {
        if (-not $Password -or $Password.Length -eq 0) { throw "No saved Wi-Fi profile for '$Name'. Enter the hotspot password." }
        Add-HotspotProfile $Name $Password
    }
    netsh wlan connect name="$Name" | Out-Null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and -not ((Test-Connected) -and (Get-WlanField 'SSID') -eq $Name)) {
        Start-Sleep -Seconds 1
    }
    if ((Get-WlanField 'SSID') -ne $Name) {
        throw "Couldn't connect to '$Name'. Is the phone hotspot on, and the password right?"
    }
    $Name
}

# Adds firewall rules and pins the network with one admin prompt. Returns $true when the rules exist afterwards.
function Invoke-AdminSetup([string]$Here, [string]$PinNetwork) {
    $fwArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Here\m0-firewall.ps1`"", '-NoPause')
    if ($PinNetwork) { $fwArgs += @('-PinNetwork', "`"$PinNetwork`"") }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $fwArgs -Wait -WindowStyle Hidden | Out-Null
    } catch {
        # The admin prompt was declined.
    }
    Test-FirewallReady
}
