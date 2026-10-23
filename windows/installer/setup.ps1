#Requires -Version 5.1
<#
.SYNOPSIS
    OphiStreamer setup steps, run by the installer as administrator (the one admin prompt).

.DESCRIPTION
    - Firewall: allow OphiStreamer's phone link and the streaming host, from the local network only
    - Installs Apollo and ViGEmBus with winget if missing (optional)
    - Turns Sunshine off when Apollo is present (they fight over the same ports)
    - Tunes the Wi-Fi adapter for streaming (optional)
    -Uninstall removes the firewall rules and the startup entry.

    Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less scripts as ANSI).
#>
param(
    [string]$AppPath,
    [switch]$InstallApollo,
    [switch]$InstallViGEm,
    [switch]$TuneWifi,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Continue'
$group = 'OphiStreamer'
$logDir = Join-Path $env:ProgramData 'OphiStreamer'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Transcript -Path (Join-Path $logDir 'setup.log') -Append | Out-Null

function Step([string]$text) { Write-Output "== $text" }

if ($Uninstall) {
    Step 'Removing firewall rules'
    Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OphiStreamer -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------- hosts and drivers
function Install-WithWinget([string]$id) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { Write-Output "winget not available; install $id manually"; return }
    & winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    Write-Output "winget $id exit code $LASTEXITCODE"
}

if ($InstallApollo -and -not (Get-Service ApolloService -ErrorAction SilentlyContinue)) {
    Step 'Installing Apollo'
    Install-WithWinget 'ClassicOldSong.Apollo'
}
if ($InstallViGEm -and -not (Get-Service ViGEmBus -ErrorAction SilentlyContinue)) {
    Step 'Installing ViGEmBus (controller driver)'
    Install-WithWinget 'ViGEm.ViGEmBus'
}

# Apollo and Sunshine share ports 47984-48010 and both run as sunshine.exe: keep only Apollo.
if ((Get-Service ApolloService -ErrorAction SilentlyContinue) -and (Get-Service SunshineService -ErrorAction SilentlyContinue)) {
    Step 'Turning Sunshine off (Apollo is the host)'
    Stop-Service SunshineService -Force -ErrorAction SilentlyContinue
    Set-Service SunshineService -StartupType Disabled -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- firewall (local network only)
Step 'Firewall rules'
Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue | Remove-NetFirewallRule
if ($AppPath -and (Test-Path $AppPath)) {
    New-NetFirewallRule -DisplayName 'OphiStreamer phone link' -Group $group -Direction Inbound -Action Allow `
        -Program $AppPath -Protocol TCP -LocalPort 47900 -Profile Any -RemoteAddress LocalSubnet | Out-Null
}
foreach ($hostExe in @("$env:ProgramFiles\Apollo\sunshine.exe", "$env:ProgramFiles\Sunshine\sunshine.exe")) {
    if (Test-Path $hostExe) {
        New-NetFirewallRule -DisplayName "OphiStreamer host ($(Split-Path (Split-Path $hostExe) -Leaf))" -Group $group `
            -Direction Inbound -Action Allow -Program $hostExe -Profile Any -RemoteAddress LocalSubnet | Out-Null
    }
}
foreach ($proto in 'TCP', 'UDP') {
    New-NetFirewallRule -DisplayName "OphiStreamer host ports $proto" -Group $group -Direction Inbound -Action Allow `
        -Protocol $proto -LocalPort '47984-48010' -Profile Any -RemoteAddress LocalSubnet | Out-Null
}

# ---------------------------------------------------------------- Wi-Fi adapter tuning
if ($TuneWifi) {
    $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -match '802\.11' } | Select-Object -First 1
    if ($nic) {
        Step "Tuning $($nic.InterfaceDescription)"
        $changed = $false
        # Pick the first allowed value matching the pattern, so it works across driver versions.
        function Set-Adv([string]$namePattern, [string]$valuePattern) {
            $prop = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match $namePattern } | Select-Object -First 1
            if (-not $prop) { Write-Output "  (no '$namePattern' on this adapter)"; return }
            $value = $prop.ValidDisplayValues | Where-Object { $_ -match $valuePattern } | Select-Object -First 1
            if (-not $value) { Write-Output "  '$($prop.DisplayName)': no value like '$valuePattern'"; return }
            if ($prop.DisplayValue -ne $value) {
                Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $prop.DisplayName -DisplayValue $value -NoRestart
                Write-Output "  $($prop.DisplayName): $($prop.DisplayValue) -> $value"
                $script:changed = $true
            }
        }
        Set-Adv '802\.11n/ac' 'ac'                 # "802.11n/ac/ax Wireless Mode": the 54 Mbps cap seen in Milestone 0
        Set-Adv '^HT Mode' 'VHT'
        Set-Adv 'Roaming Aggressiveness' 'Lowest'
        Set-Adv 'MIMO Power Save' 'No SMPS'
        Set-Adv 'U-APSD' 'Disabled'
        Set-Adv 'Packet Coalescing' 'Disabled'
        Set-Adv 'Preferred Band' '5'
        if ($changed) { Restart-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue }
    }
}

Stop-Transcript | Out-Null
exit 0
