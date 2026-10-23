; OphiStreamer installer (Inno Setup 6). Built by .github/workflows/windows.yml:
;   ISCC.exe /DAppVersion=0.2.0 /DExeDir=..\..\out windows\installer\OphiStreamer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef ExeDir
  #define ExeDir "..\..\out"
#endif

[Setup]
AppId={{6B1C3E52-8F0A-4D6B-9C7E-2E5D8A4F1B37}
AppName=OphiStreamer
AppVersion={#AppVersion}
AppPublisher=Ophimacus
DefaultDirName={autopf}\OphiStreamer
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\out
OutputBaseFilename=OphiStreamerSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\OphiStreamer.exe
; Ask to close a running OphiStreamer before replacing it.
AppMutex=OphiStreamer.SingleInstance
CloseApplications=yes

[Tasks]
Name: "apollo"; Description: "Install Apollo (the streaming host) if it isn't installed"
Name: "vigem"; Description: "Install ViGEmBus (so your controller works in games) if it isn't installed"
Name: "wifi"; Description: "Tune the Wi-Fi adapter for streaming (802.11ac on, lowest roaming, power saving off, prefer 5 GHz)"

[Files]
Source: "{#ExeDir}\OphiStreamer.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "setup.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\OphiStreamer"; Filename: "{app}\OphiStreamer.exe"

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -AppPath ""{app}\OphiStreamer.exe"" {code:SetupArgs}"; \
  StatusMsg: "Setting up streaming (firewall, Apollo, controller driver, Wi-Fi)..."; \
  Flags: runhidden waituntilterminated
Filename: "{app}\OphiStreamer.exe"; Description: "Start OphiStreamer"; Flags: postinstall nowait skipifsilent runasoriginaluser

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -Uninstall"; \
  Flags: runhidden waituntilterminated; RunOnceId: "OphiStreamerCleanup"

[Code]
function SetupArgs(Param: String): String;
begin
  Result := '';
  if WizardIsTaskSelected('apollo') then Result := Result + ' -InstallApollo';
  if WizardIsTaskSelected('vigem') then Result := Result + ' -InstallViGEm';
  if WizardIsTaskSelected('wifi') then Result := Result + ' -TuneWifi';
end;
