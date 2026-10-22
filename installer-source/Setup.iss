#ifndef Payload
  #define Payload "..\..\work\package-v11.4"
#endif
#ifndef SetupOut
  #define SetupOut ".."
#endif
#ifndef BuildName
  #define BuildName "mpv-Neon-Setup-v11.4-public"
#endif
#ifdef HandoffTest
  #define TestBuild
#endif
#ifdef TestBuild
  #define Identity "mpvNeon.PackagingTest"
#else
  #define Identity "mpvNeon.Personal"
#endif
[Setup]
AppId={#Identity}
AppName=mpv Neon
AppVersion=11.4
AppPublisher=Personal mpv build
DefaultDirName={code:DefaultPath}
UsePreviousAppDir=not IsPortable
DefaultGroupName=mpv Neon
UninstallFilesDir={app}\uninstall
UninstallDisplayIcon={app}\mpv-neon.exe
SetupIconFile={#Payload}\assets\player-neon-07.ico
OutputDir={#SetupOut}
OutputBaseFilename={#BuildName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
UsePreviousPrivileges=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
#ifdef TestBuild
Compression=zip
SolidCompression=no
#else
Compression=lzma2/fast
SolidCompression=yes
#endif
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
Uninstallable=not IsPortable
CreateUninstallRegKey=not IsPortable
ChangesAssociations=not IsPortable
CloseApplications=yes
CloseApplicationsFilter=mpv.exe,Player.exe,mpv-neon.exe,PlaylistWindow.exe,TorrServer-windows-amd64.exe
RestartApplications=no
SetupLogging=yes

[Languages]
Name: russian; MessagesFile: compiler:Languages\Russian.isl
Name: english; MessagesFile: compiler:Default.isl

[Tasks]
Name: desktopicon; Description: "Создать ярлык на рабочем столе"; Flags: unchecked; Check: NotPortable
Name: fileassoc; Description: "Добавить mpv Neon в «Открыть с помощью»"; Check: NotPortable

[Files]
#ifndef HandoffTest
Source: "StopBundledTorrServer.ps1"; Flags: dontcopy
#endif
#ifndef HandoffTest
Source: "{#Payload}\*"; DestDir: "{app}"; Excludes: "portable_config\*,installation-mode.txt"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Payload}\portable_config\*"; DestDir: "{app}\portable_config"; Excludes: "*.conf,script-opts\*.json"; Flags: ignoreversion recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#Payload}\portable_config\*.conf"; DestDir: "{app}\portable_config"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs uninsneveruninstall
Source: "{#Payload}\portable_config\script-opts\*.json"; DestDir: "{app}\portable_config\script-opts"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs uninsneveruninstall
#endif

[Icons]
Name: "{autoprograms}\mpv Neon\mpv Neon"; Filename: "{app}\mpv-neon.exe"; WorkingDir: "{app}"; IconFilename: "{app}\assets\player-neon-07.ico"; Check: NotPortable
Name: "{autoprograms}\mpv Neon\Удалить mpv Neon"; Filename: "{uninstallexe}"; Check: NotPortable
Name: "{autodesktop}\mpv Neon"; Filename: "{app}\mpv-neon.exe"; WorkingDir: "{app}"; IconFilename: "{app}\assets\player-neon-07.ico"; Tasks: desktopicon; Check: NotPortable

[InstallDelete]
Type: files; Name: "{app}\Player.exe"
Type: files; Name: "{app}\Player.pdb"

[Registry]
#ifndef TestBuild
Root: HKA; Subkey: "Software\Classes\Applications\mpv-neon.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "mpv Neon"; Flags: uninsdeletekey; Tasks: fileassoc; Check: NotPortable
Root: HKA; Subkey: "Software\Classes\Applications\mpv-neon.exe\DefaultIcon"; ValueType: string; ValueData: "{app}\assets\player-neon-07.ico"; Tasks: fileassoc; Check: NotPortable
Root: HKA; Subkey: "Software\Classes\Applications\mpv-neon.exe\shell\open\command"; ValueType: string; ValueData: """{app}\mpv-neon.exe"" ""%1"""; Tasks: fileassoc; Check: NotPortable
Root: HKA; Subkey: "Software\mpvNeon\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "mpv Neon"; Flags: uninsdeletekey; Tasks: fileassoc; Check: NotPortable
Root: HKA; Subkey: "Software\mpvNeon\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Видеоплеер mpv Neon"; Tasks: fileassoc; Check: NotPortable
Root: HKA; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "mpv Neon"; ValueData: "Software\mpvNeon\Capabilities"; Flags: uninsdeletevalue; Tasks: fileassoc; Check: NotPortable
#include "Associations.iss"
#endif

[Run]
Filename: "{app}\mpv-neon.exe"; Description: "Запустить mpv Neon"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
var ModePage: TInputOptionWizardPage;
    CurrentMode: String;
    RestartSucceeded: Boolean;

// Inno's ShellExec/Exec reject relaunching {srcexe} before installation.
// Use the documented Windows shell API for this mode handoff.
function WindowsShellExecute(Parent: HWND; Verb, Filename, Params, Directory: String;
  ShowCmd: Integer): THandle;
  external 'ShellExecuteW@shell32.dll stdcall';

function RestartVerb(Mode: String): String;
begin
  if Mode = 'all' then Result := 'runas' else Result := 'open';
end;

function LaunchSetup(Parent: HWND; Verb, Params: String; var ErrorCode: Integer): Boolean;
var Handle: THandle;
begin
  Handle := WindowsShellExecute(Parent, Verb, ExpandConstant('{srcexe}'), Params,
    ExtractFileDir(ExpandConstant('{srcexe}')), SW_SHOWNORMAL);
  Result := Handle > 32;
  if Result then ErrorCode := 0 else ErrorCode := Handle;
end;

#ifdef HandoffTest
function InitializeSetup: Boolean;
var TestMode, Marker, Params: String; Code: Integer;
begin
  Result := False;
  TestMode := ExpandConstant('{param:NATIVE_TEST|}');
  Marker := ExpandConstant('{param:MARKER|}');
  if Marker = '' then Exit;
  if TestMode = 'child' then begin
    SaveStringToFile(Marker + '.child', 'native self-relaunch reached child InitializeSetup', False);
    Exit;
  end;
  if (RestartVerb('all') <> 'runas') or (RestartVerb('user') <> 'open') or
    (RestartVerb('portable') <> 'open') then Exit;
  Params := '/CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NATIVE_TEST=child /MARKER="' + Marker + '"';
  if LaunchSetup(0, RestartVerb('user'), Params, Code) then
    SaveStringToFile(Marker + '.parent', 'native self-relaunch accepted before installation', False)
  else SaveStringToFile(Marker + '.error', IntToStr(Code), False);
end;
#endif

function IsPortable: Boolean;
begin Result := (CurrentMode = 'portable') or (ExpandConstant('{param:MODE|}') = 'portable'); end;
function NotPortable: Boolean;
begin Result := not IsPortable; end;

function DefaultPath(Param: String): String;
begin
  if IsPortable then Result := ExpandConstant('{userdocs}\mpv Neon Portable')
  else Result := ExpandConstant('{autopf}\mpv Neon');
end;

function GetMode: String;
begin
  Result := ExpandConstant('{param:MODE|}');
  if Result = '' then begin
    if IsAdminInstallMode then Result := 'all' else Result := 'user';
  end;
end;

procedure InitializeWizard;
begin
  CurrentMode := GetMode;
  ModePage := CreateInputOptionPage(wpWelcome, 'Как установить mpv Neon?',
    'Выберите подходящий вариант',
    'При обновлении выберите тот же режим, что использовался раньше. Настройки и история сохраняются.', True, False);
  ModePage.Add('Portable — распаковать в папку, без регистрации в Windows');
  ModePage.Add('Установить для меня — без прав администратора');
  ModePage.Add('Установить для всех пользователей — нужны права администратора');
  if CurrentMode = 'portable' then ModePage.SelectedValueIndex := 0
  else if CurrentMode = 'all' then ModePage.SelectedValueIndex := 2
  else ModePage.SelectedValueIndex := 1;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := IsPortable and ((PageID = wpSelectTasks) or (PageID = wpSelectProgramGroup));
  if (PageID = ModePage.ID) and (ExpandConstant('{param:MODE|}') <> '') then Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var Code: Integer; Params, ExplicitDir: String;
begin
  Result := True;
  if CurPageID = ModePage.ID then begin
    if ModePage.SelectedValueIndex = 0 then CurrentMode := 'portable'
    else if ModePage.SelectedValueIndex = 2 then CurrentMode := 'all'
    else CurrentMode := 'user';
    if (CurrentMode = 'all') <> IsAdminInstallMode then begin
      if CurrentMode = 'all' then Params := '/ALLUSERS /MODE=all'
      else Params := '/CURRENTUSER /MODE=' + CurrentMode;
      Params := Params + ' /LANG=' + ActiveLanguage;
      ExplicitDir := ExpandConstant('{param:DIR|}');
      if ExplicitDir <> '' then Params := Params + ' /DIR="' + ExplicitDir + '"';
      if WizardSilent then Params := Params + ' /VERYSILENT /SUPPRESSMSGBOXES';
      if LaunchSetup(WizardForm.Handle, RestartVerb(CurrentMode), Params, Code) then begin
        RestartSucceeded := True;
        WizardForm.Close;
      end else begin
        Log('Mode handoff was not started. ShellExecute code: ' + IntToStr(Code));
        if Code = 5 then
          MsgBox('Запрос прав администратора отменён или доступ запрещён. Можно повторить попытку либо выбрать установку для себя.', mbInformation, MB_OK)
        else MsgBox('Не удалось перезапустить установку. Код: ' + IntToStr(Code) + #13#10 + SysErrorMessage(Code), mbError, MB_OK);
      end;
      Result := False; Exit;
    end;
    if IsPortable then WizardForm.DirEdit.Text := ExpandConstant('{userdocs}\mpv Neon Portable')
    else if CurrentMode = 'all' then begin
      if not RegQueryStringValue(HKLM64, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#Identity}_is1', 'InstallLocation', Params)
        then Params := ExpandConstant('{autopf}\mpv Neon');
      WizardForm.DirEdit.Text := Params;
    end
    else begin
      if not RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#Identity}_is1', 'InstallLocation', Params)
        then Params := ExpandConstant('{localappdata}\Programs\mpv Neon');
      WizardForm.DirEdit.Text := Params;
    end;
  end;
  if (CurPageID = wpSelectDir) and IsPortable and
    DirExists(AddBackslash(WizardDirValue) + 'uninstall') then begin
    MsgBox('Здесь установлена обычная версия. Для Portable выберите другую папку.', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if RestartSucceeded then Confirm := False;
end;

procedure BackupTree(Src, Dst: String);
var F: TFindRec;
begin
  if FindFirst(AddBackslash(Src) + '*', F) then begin
    try
      repeat
        if (F.Name <> '.') and (F.Name <> '..') and (F.Name <> 'cache') then begin
          if (F.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
            BackupTree(AddBackslash(Src)+F.Name, AddBackslash(Dst)+F.Name)
          else begin
            ForceDirectories(Dst);
            if not FileCopy(AddBackslash(Src)+F.Name, AddBackslash(Dst)+F.Name, False) then
              RaiseException('Не удалось сохранить резервную копию: ' + F.Name);
          end;
        end;
      until not FindNext(F);
    finally FindClose(F); end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var StopCode: Integer; StopArgs: String;
begin
  Result := '';
  if IsPortable and DirExists(ExpandConstant('{app}\uninstall')) then begin
    Result := 'Выбрана папка установленной версии. Для Portable укажите другую папку.'; Exit;
  end;
  if (CurrentMode = 'all') <> IsAdminInstallMode then begin
    Result := 'Для этого режима перезапустите установщик с /ALLUSERS или /CURRENTUSER.'; Exit;
  end;
  ExtractTemporaryFile('StopBundledTorrServer.ps1');
  StopArgs := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\StopBundledTorrServer.ps1') + '" -AppDir "' + ExpandConstant('{app}') + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), StopArgs,
      ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, StopCode) or (StopCode <> 0) then begin
    Result := 'Не удалось остановить TorrServer из папки обновляемого плеера. Закройте его и повторите установку.';
    Exit;
  end;
  if DirExists(ExpandConstant('{app}\portable_config')) then
    BackupTree(ExpandConstant('{app}\portable_config'),
      ExpandConstant('{app}\config-backups\') + GetDateTimeString('yyyymmdd-hhnnss', '-', ':'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer;
begin
  if CurStep = ssPostInstall then begin
    if not IsPortable then begin
      if not SaveStringToFile(ExpandConstant('{app}\installation-mode.txt'), CurrentMode, False) then
        RaiseException('Не удалось записать режим установки');
    end else begin
      if not Exec(ExpandConstant('{app}\mpv-neon.exe'), '--neon-update-portable', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
        RaiseException('Не удалось обновить стандартные настройки Portable');
    end;
  end;
end;
