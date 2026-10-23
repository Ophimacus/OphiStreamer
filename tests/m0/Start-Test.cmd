@echo off
rem OphiStreamer Milestone 0 - opens the test launcher window.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0m0-launcher.ps1"
