; LocalShare Windows x64 installer.
; Build the Flutter Release bundle before compiling this script with ISCC.exe.

#define MyAppName "LocalShare"
#define MyAppVersion "0.1.1.61"
#define MyAppPublisher "LocalShare"
#define MyAppExeName "LocalShare.exe"
#define ProjectRoot AddBackslash(SourcePath) + ".."
#define BuildDir ProjectRoot + "\app\build\windows\x64\runner\Release"
#define RuntimeDir AddBackslash(SourcePath) + "windows\x64"
#define InstallerOutputDir ProjectRoot + "\dist"

[Setup]
; This AppId belongs to LocalShare and must not be reused by LocalSend.
AppId={{9B6CDEAA-A42B-4ED6-9965-743C1A5F70E8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#InstallerOutputDir}
OutputBaseFilename=LocalShare-Setup-{#MyAppVersion}-x64
SetupIconFile={#ProjectRoot}\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "{#SourcePath}\Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
