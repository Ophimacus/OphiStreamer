# OphiStreamer test kit: download the latest version and start it.
# Run on the laptop (normal PowerShell window, not admin):
#   irm https://raw.githubusercontent.com/Ophimacus/OphiStreamer/main/tests/m0/get.ps1 | iex

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$dest = Join-Path $env:USERPROFILE 'OphiStreamer-m0'
$zip = Join-Path $env:TEMP 'ophistreamer-main.zip'
$unpacked = Join-Path $env:TEMP "ophistreamer-$([guid]::NewGuid())"

Write-Host 'Downloading the OphiStreamer test kit...'
Invoke-WebRequest 'https://github.com/Ophimacus/OphiStreamer/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $unpacked
New-Item -ItemType Directory -Force -Path $dest | Out-Null
# Overwrite the scripts but keep earlier m0-report-*.txt files.
Copy-Item -Path (Join-Path $unpacked 'OphiStreamer-main\tests\m0\*') -Destination $dest -Recurse -Force
Remove-Item -Path $zip, $unpacked -Recurse -Force

Write-Host "Test kit ready in $dest" -ForegroundColor Green
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $dest 'm0-launcher.ps1')`"")
