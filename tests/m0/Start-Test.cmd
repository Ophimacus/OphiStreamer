@echo off
rem OphiStreamer Milestone 0 - one click: join the phone hotspot, set up, run the test.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0m0-start.ps1" %*
echo.
pause
