; Public installer. build.ps1 refuses any payload containing the private Lossless.dll.
#ifndef SourceRoot
  #error SourceRoot is required; use build.ps1
#endif
#ifndef FileList
  #error FileList is required; use build.ps1
#endif
#ifndef AppKey
  #define AppKey "mpvNeon"
#endif
#ifndef ProductName
  #define ProductName "mpv Neon"
#endif
#ifndef RegisteredExe
  #define RegisteredExe "mpv-neon.exe"
#endif
#ifndef OutputRoot
  #define OutputRoot ".."
#endif
#ifndef OutputName
  #define OutputName "mpv-Neon-Setup-v6-public"
#endif
#define VideoExts "mp4|mkv|avi|mov|wmv|webm|m4v|ts|m2ts|mts|mpg|mpeg|vob|flv|ogv|3gp|3g2|ogm|m2v|m1v|divx|f4v|rm|rmvb|asf|hevc|h264|h265|av1|y4m"
#define PlaylistExts "m3u|m3u8|pls"

[Setup]
AppId={#AppKey}.Personal
AppName={#ProductName}
AppVersion=6.0
AppVerName={#ProductName} 6
AppPublisher=Personal mpv build
DefaultDirName={localappdata}\Programs\{#ProductName}
DefaultGroupName={#ProductName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
SetupIconFile={#SourceRoot}\assets\player-neon-07.ico
UninstallDisplayIcon={app}\{#RegisteredExe}
OutputDir={#OutputRoot}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes
DisableProgramGroupPage=yes
AllowNoIcons=yes
CloseApplications=yes
RestartApplications=no
InfoBeforeFile=install-notes.txt
UninstallFilesDir={app}\uninstall

[Languages]
Name: russian; MessagesFile: compiler:Languages\Russian.isl

[Tasks]
Name: fileassoc; Description: "Добавить в «Открыть с помощью» и список приложений по умолчанию"; GroupDescription: "Интеграция с Windows:"; Flags: checkedonce
Name: desktopicon; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"; Flags: unchecked

[Files]
#include FileList
Source: "{#SourceRoot}\Player.exe"; DestDir: "{app}"; DestName: "{#RegisteredExe}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#ProductName}"; Filename: "{app}\{#RegisteredExe}"; WorkingDir: "{app}"; IconFilename: "{app}\assets\player-neon-07.ico"
Name: "{group}\TorrServer — {#ProductName}"; Filename: "{app}\{#RegisteredExe}"; Parameters: "--script=portable_config/launch-torrserver.lua"; WorkingDir: "{app}"; IconFilename: "{app}\assets\player-neon-07.ico"
Name: "{group}\Приложения по умолчанию Windows"; Filename: "ms-settings:defaultapps"
Name: "{group}\Удалить {#ProductName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#ProductName}"; Filename: "{app}\{#RegisteredExe}"; WorkingDir: "{app}"; IconFilename: "{app}\assets\player-neon-07.ico"; Tasks: desktopicon

[Registry]
; Only our own keys are removed; extension defaults and UserChoice are never written.
Root: HKCU; Subkey: "Software\Classes\{#AppKey}.Video"; ValueType: string; ValueData: "Видео — {#ProductName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\{#AppKey}.Video\DefaultIcon"; ValueType: string; ValueData: "{app}\assets\player-neon-07.ico"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\{#AppKey}.Video\shell\open\command"; ValueType: string; ValueData: """{app}\{#RegisteredExe}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\{#AppKey}.Playlist"; ValueType: string; ValueData: "Плейлист — {#ProductName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\{#AppKey}.Playlist\DefaultIcon"; ValueType: string; ValueData: "{app}\assets\player-neon-07.ico"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\{#AppKey}.Playlist\shell\open\command"; ValueType: string; ValueData: """{app}\{#RegisteredExe}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#RegisteredExe}"; ValueType: string; ValueName: FriendlyAppName; ValueData: "{#ProductName}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#RegisteredExe}\DefaultIcon"; ValueType: string; ValueData: "{app}\assets\player-neon-07.ico"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#RegisteredExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#RegisteredExe}"" ""%1"""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\{#AppKey}"; Flags: uninsdeletekey; Tasks: fileassoc
Root: HKCU; Subkey: "Software\{#AppKey}\Capabilities"; ValueType: string; ValueName: ApplicationName; ValueData: "{#ProductName}"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\{#AppKey}\Capabilities"; ValueType: string; ValueName: ApplicationDescription; ValueData: "Видеоплеер mpv с русским интерфейсом, шейдерами и TorrServer"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\{#AppKey}\Capabilities"; ValueType: string; ValueName: ApplicationIcon; ValueData: "{app}\assets\player-neon-07.ico"; Tasks: fileassoc
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "{#ProductName}"; ValueData: "Software\{#AppKey}\Capabilities"; Flags: uninsdeletevalue; Tasks: fileassoc

#sub RegisterExtension
  #define Ext Copy(ExtList, 1, Pos("|", ExtList) - 1)
Root: HKCU; Subkey: "Software\Classes\.{#Ext}\OpenWithProgids"; ValueType: string; ValueName: "{#AppKey}.{#Kind}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: fileassoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#RegisteredExe}\SupportedTypes"; ValueType: string; ValueName: ".{#Ext}"; ValueData: ""; Tasks: fileassoc
Root: HKCU; Subkey: "Software\{#AppKey}\Capabilities\FileAssociations"; ValueType: string; ValueName: ".{#Ext}"; ValueData: "{#AppKey}.{#Kind}"; Tasks: fileassoc
  #expr ExtList = Copy(ExtList, Pos("|", ExtList) + 1)
#endsub
#define Kind "Video"
#define ExtList VideoExts + "|"
#define Index 1
#for {Index = 1; Pos("|", ExtList) > 0; Index++} RegisterExtension
#define Kind "Playlist"
#define ExtList PlaylistExts + "|"
#for {Index = 1; Pos("|", ExtList) > 0; Index++} RegisterExtension

[Run]
Filename: "{app}\{#RegisteredExe}"; Description: "Запустить {#ProductName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent unchecked
Filename: "ms-settings:defaultapps"; Description: "Выбрать приложения по умолчанию в Windows"; Flags: shellexec nowait postinstall skipifsilent unchecked
