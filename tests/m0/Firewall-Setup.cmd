@echo off
rem OphiStreamer Milestone 0 - add (or with -Remove, delete) the test firewall rules. Asks for admin.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0m0-firewall.ps1" %*
