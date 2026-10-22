@echo off
rem OphiStreamer Milestone 0 - double-click to run the hardware test (no admin needed).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0m0-hardware-proof.ps1" %*
echo.
pause
