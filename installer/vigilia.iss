; Установщик Vigilia (Inno Setup 6).
; Сборка: flutter build windows --release, затем
;   iscc installer\vigilia.iss
; Результат: build\installer\Vigilia-<версия>-setup.exe

#define AppVersion "1.1.0"

[Setup]
AppId={{9A4C1BF9-3C8C-4535-90F3-05499110A5FD}
AppName=Vigilia
AppVersion={#AppVersion}
AppVerName=Vigilia {#AppVersion}
AppPublisher=Alex Skvortsov
AppPublisherURL=https://github.com/alexskvo10/vigilia
AppSupportURL=https://github.com/alexskvo10/vigilia/issues
DefaultDirName={autopf}\Vigilia
DisableProgramGroupPage=yes
; ставится для текущего пользователя без прав администратора (можно выбрать «для всех»)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\installer
OutputBaseFilename=Vigilia-{#AppVersion}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\vigilia.exe
LicenseFile=..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; тот же мьютекс, что у приложения: установщик попросит закрыть запущенную Vigilia
AppMutex=Vigilia.SingleInstance

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ru.Autostart=Запускать Vigilia вместе с Windows
en.Autostart=Start Vigilia with Windows
ru.Extra=Дополнительно:
en.Extra=Extra:

[Tasks]
Name: "autostart"; Description: "{cm:Autostart}"; GroupDescription: "{cm:Extra}"; Flags: unchecked
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:Extra}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; AppUserModelID нужен, чтобы уведомления Windows подписывались как «Vigilia»
Name: "{autoprograms}\Vigilia"; Filename: "{app}\vigilia.exe"; AppUserModelID: "alexskvo10.Vigilia"
Name: "{autodesktop}\Vigilia"; Filename: "{app}\vigilia.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Vigilia"; ValueData: """{app}\vigilia.exe"" --hidden"; Tasks: autostart
; при удалении убрать автозапуск, даже если его включили из самого приложения
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Vigilia"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\vigilia.exe"; Description: "{cm:LaunchProgram,Vigilia}"; Flags: nowait postinstall skipifsilent
