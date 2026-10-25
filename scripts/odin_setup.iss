; SPDX-License-Identifier: GPL-3.0-or-later
; Copyright (c) 2026 Syams Ideris
;
; Inno Setup script for the single-file offline Windows installer. Do not run ISCC on it by
; hand: scripts/build_setup_windows.py prepares the staging folder (the app, odinpc.exe and a
; private Python 3.13 with Tk) and passes these definitions:
;   /DVersion=2.3.0  /DFileVersion=2.3.0  /DStaging=C:\...\app  /DOutDir=C:\...\dist
; FileVersion is Version without a pre-release suffix (3.0.0 for 3.0.0-beta.1): Windows file
; versions are numbers only.
; Keep this file ASCII.

#ifndef Version
  #error Version is not defined: run scripts/build_setup_windows.py
#endif
#ifndef Staging
  #error Staging is not defined: run scripts/build_setup_windows.py
#endif
#ifndef OutDir
  #define OutDir "dist"
#endif
#ifndef FileVersion
  #define FileVersion Version
#endif

[Setup]
; Never change AppId: it ties upgrades and the uninstaller to this program.
AppId={{8BDFFEC5-4A07-4791-ADB8-2CE29C6E1209}
AppName=Odin Turbo Pascal
AppVersion={#Version}
AppVerName=Odin Turbo Pascal {#Version}
AppPublisher=Syams Ideris
AppCopyright=Copyright (c) 2026 Syams Ideris
AppPublisherURL=https://github.com/Syamsuddin/ODIN-TURBO-PASCAL
AppSupportURL=https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/issues
AppUpdatesURL=https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases
VersionInfoVersion={#FileVersion}
VersionInfoDescription=Odin Turbo Pascal setup
; Per user, no administrator rights; same folder as Install.ps1, so it upgrades that install.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\OdinTurboPascal
DefaultGroupName=Odin Turbo Pascal
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
; ConPTY (the Output window) needs Windows 10 1809.
MinVersion=10.0.17763
LicenseFile={#Staging}\LICENSE
SetupIconFile={#Staging}\odin.ico
UninstallDisplayIcon={app}\odin.ico
UninstallDisplayName=Odin Turbo Pascal
OutputDir={#OutDir}
OutputBaseFilename=OdinTurboPascal-{#Version}-Setup-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
; Without this, Setup registers every staged file (the private Python/Tk tree, thousands of
; files) with Restart Manager to check it is not in use, which hangs for minutes on some
; machines (observed in CI). Only the executables can plausibly be locked by a running Odin.
CloseApplicationsFilter=*.exe
RestartApplications=no

[Languages]
Name: "default"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1=Selamat datang di pemasang [name]
WelcomeLabel2=Pemasang ini akan memasang [name/ver] di komputer Anda, lengkap dengan compiler Pascal (odinpc) dan Python+Tk-nya sendiri. Tidak memerlukan internet maupun hak administrator.%n%nTutup program lain sebelum melanjutkan.
SelectDirLabel3=Odin Turbo Pascal akan dipasang di folder berikut.
FinishedHeadingLabel=Pemasangan [name] selesai
FinishedLabel=Odin Turbo Pascal sudah terpasang. Buka dari menu Start atau Desktop.
ClickFinish=Klik Selesai untuk menutup pemasang.
ButtonInstall=&Pasang
ButtonNext=&Lanjut >
ButtonBack=< &Kembali
ButtonCancel=Batal
ButtonFinish=&Selesai
LicenseLabel=Baca lisensi berikut sebelum melanjutkan.
LicenseAccepted=Saya &menyetujui lisensi
LicenseNotAccepted=Saya &tidak menyetujui lisensi
InstallingLabel=Mohon tunggu, [name] sedang dipasang.

[CustomMessages]
RunApp=Jalankan Odin Turbo Pascal
CheckFailed=Aplikasi sudah disalin, tetapi pemeriksaan kompilasi dengan odinpc.exe gagal (kode %1).%n%nLaporan: %2%n%nOdin mungkin tidak bisa mengompilasi di komputer ini.

[Tasks]
Name: "desktopicon"; Description: "Buat pintasan di &Desktop"; GroupDescription: "Pintasan:"

[InstallDelete]
; An upgrade replaces these folders whole, so no stale file of an older version stays.
Type: filesandordirs; Name: "{app}\odin"
Type: filesandordirs; Name: "{app}\examples"
Type: filesandordirs; Name: "{app}\docs"
Type: filesandordirs; Name: "{app}\rtl"
Type: filesandordirs; Name: "{app}\assets"
Type: filesandordirs; Name: "{app}\python"
Type: filesandordirs; Name: "{app}\toolchain"
Type: filesandordirs; Name: "{app}\scripts"

[Files]
; Uninstall.* belong to the script installer; this setup has its own uninstaller.
Source: "{#Staging}\*"; DestDir: "{app}"; Excludes: "Uninstall.ps1,Uninstall.cmd"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; The private Python, in UTF-8 mode, ignoring PYTHON* variables of the user (-E).
Name: "{autoprograms}\Odin Turbo Pascal"; Filename: "{app}\python\pythonw.exe"; Parameters: "-E -X utf8 ""{app}\OdinTurboPascal.pyw"""; WorkingDir: "{%USERPROFILE}"; IconFilename: "{app}\odin.ico"; Comment: "Odin Turbo Pascal"
Name: "{autodesktop}\Odin Turbo Pascal"; Filename: "{app}\python\pythonw.exe"; Parameters: "-E -X utf8 ""{app}\OdinTurboPascal.pyw"""; WorkingDir: "{%USERPROFILE}"; IconFilename: "{app}\odin.ico"; Comment: "Odin Turbo Pascal"; Tasks: desktopicon

[Run]
Filename: "{app}\python\pythonw.exe"; Parameters: "-E -X utf8 ""{app}\OdinTurboPascal.pyw"""; WorkingDir: "{%USERPROFILE}"; Description: "{cm:RunApp}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Python writes __pycache__ and the tutorials write data files here at run time.
; Pascal programs and settings (%APPDATA%\OdinTurboPascal) are elsewhere and stay.
Type: filesandordirs; Name: "{app}"

[Code]
// The gate of Install.ps1: compile and run a small program with the installed odinpc.exe.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
  Report: String;
begin
  if CurStep = ssPostInstall then
  begin
    Report := ExpandConstant('{tmp}\odin-check.log');
    if (not Exec(ExpandConstant('{cmd}'),
        ExpandConstant('/C ""{app}\python\python.exe" -E -X utf8 "{app}\scripts\check_windows.py" > "' + Report + '" 2>&1"'),
        '', SW_HIDE, ewWaitUntilTerminated, Code)) or (Code <> 0) then
    begin
      if FileExists(Report) then
        FileCopy(Report, ExpandConstant('{app}\check-failed.log'), False);
      // A line may not start with "[": Inno reads it as a section tag.
      SuppressibleMsgBox(FmtMessage(CustomMessage('CheckFailed'), [IntToStr(Code), ExpandConstant('{app}\check-failed.log')]), mbError, MB_OK, IDOK);
    end;
  end;
end;
