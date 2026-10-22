{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit SysUtils: nama berkas dan direktori, operasi berkas di folder kerja. }
program SYSUTILS_FILES;

uses SysUtils;

var
  F: Text;
  Old: String;
begin
  WriteLn('ExtractFileName: [', ExtractFileName('/usr/lib/x.tar.gz'), '] [', ExtractFileName('abc'), '] [',
    ExtractFileName('/usr/lib/'), '] [', ExtractFileName(''), ']');
  WriteLn('ExtractFilePath: [', ExtractFilePath('/usr/lib/x.tar.gz'), '] [', ExtractFilePath('abc'), ']');
  WriteLn('ExtractFileDir: [', ExtractFileDir('/usr/lib/x.tar.gz'), '] [', ExtractFileDir('/x'), '] [',
    ExtractFileDir('abc'), ']');
  WriteLn('ExtractFileExt: [', ExtractFileExt('/usr/lib/x.tar.gz'), '] [', ExtractFileExt('a.b/c'), '] [',
    ExtractFileExt('noext'), '] [', ExtractFileExt('.hidden'), ']');
  WriteLn('ChangeFileExt: ', ChangeFileExt('/a/b.pas', '.exe'), ' ', ChangeFileExt('/a.b/c', '.x'), ' ',
    ChangeFileExt('file.txt', ''), ' ', ChangeFileExt('x.tar.gz', '.zip'));
  WriteLn('Delimiter: ', ExcludeTrailingPathDelimiter('/a/b/'), ' ', ExcludeTrailingPathDelimiter('/'), ' ',
    ExcludeTrailingPathDelimiter('abc'), ' ', IncludeTrailingPathDelimiter('/a/b/'));

  Old := GetCurrentDir;
  WriteLn('GetCurrentDir tidak kosong: ', Old <> '');
  WriteLn('FileExists / DirectoryExists tidak ada: ', FileExists('tidak_ada.xyz'), ' ', DirectoryExists('tidak_ada_dir'),
    ' ', FileExists(''));

  Assign(F, 'sysutils_uji.txt');
  Rewrite(F);
  WriteLn(F, 'isi');
  Close(F);
  WriteLn('FileExists: ', FileExists('sysutils_uji.txt'), ' DirectoryExists: ', DirectoryExists('sysutils_uji.txt'));
  WriteLn('RenameFile: ', RenameFile('sysutils_uji.txt', 'sysutils_baru.txt'), ' ', FileExists('sysutils_uji.txt'), ' ',
    FileExists('sysutils_baru.txt'), ' ', RenameFile('tidak_ada.xyz', 'x.y'));
  WriteLn('DeleteFile: ', DeleteFile('sysutils_baru.txt'), ' ', FileExists('sysutils_baru.txt'), ' ',
    DeleteFile('sysutils_baru.txt'));

  WriteLn('CreateDir: ', CreateDir('sysutils_dir'), ' ', DirectoryExists('sysutils_dir'), ' ', CreateDir('sysutils_dir'));
  WriteLn('FileExists(direktori): ', FileExists('sysutils_dir'));
  WriteLn('ForceDirectories: ', ForceDirectories('sysutils_dir/a/b/c'), ' ', DirectoryExists('sysutils_dir/a/b/c'), ' ',
    ForceDirectories('sysutils_dir/a/b/c'));
  WriteLn('SetCurrentDir: ', SetCurrentDir('sysutils_dir'), ' ', DirectoryExists('a'), ' ', SetCurrentDir('..'), ' ',
    SetCurrentDir('tidak_ada_dir'));
  WriteLn('RemoveDir: ', RemoveDir('sysutils_dir/a/b/c'), ' ', RemoveDir('sysutils_dir/a/b'), ' ',
    RemoveDir('sysutils_dir/a'), ' ', RemoveDir('sysutils_dir'), ' ', RemoveDir('sysutils_dir'));
  WriteLn('ExpandFileName: ', ExpandFileName('x') <> 'x', ' ', ExtractFileName(ExpandFileName('sub/x.txt')));
  WriteLn('GetEnvironmentVariable: ', GetEnvironmentVariable('ODIN_PASTI_TIDAK_ADA_1234') = '');
end.
