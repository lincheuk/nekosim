; Inno Setup Installer Script for NekoSim (community public build).
; Compiled with Inno Setup Compiler (ISCC.exe).

#define AppName "NekoSim Community"
#define AppShortName "nekosim"
#define AppPublisher "CyberPulse"
#define AppURL "https://github.com/lincheuk/nekosim"
#define AppExeName "nlpa2.exe"

#ifndef AppVersion
#define AppVersion "2.0.0"
#endif

#ifndef AppBuildNumber
#define AppBuildNumber "0"
#endif
#define AppVersionFull AppVersion + "." + AppBuildNumber

[Setup]
AppId={{8831809D-E61C-43B8-A60E-82CD4681AC8D}
AppName={#AppName}
AppVersion={#AppVersionFull}
AppVerName={#AppName} {#AppVersionFull}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\NekoSim
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputDir=..\build\windows\installer
OutputBaseFilename=io.github.lincheuk.nekosim-{#AppVersion}-{#AppBuildNumber}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64

VersionInfoVersion={#AppVersionFull}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName}
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersionFull}
VersionInfoCopyright=Copyright (C) 2026 CyberPulse. Based on NekokoLPA2 (C) Nekoko.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
