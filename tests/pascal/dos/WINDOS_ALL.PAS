{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit WinDos: Dos dengan PChar. }
program WINDOS_ALL;

uses WinDos, Strings;

var
  Dir, Name, Ext, Buf: array[0..259] of Char;
  Flags: Word;
  SR: TSearchRec;
  F: Text;
  Names: array[1..8] of String;
  Sizes: array[1..8] of LongInt;
  Count, I, J: Integer;
  T: String;
  Dt: TDateTime;
  P: LongInt;
  Y, M, D, W: Word;
  Attr: Word;
  Ok: Boolean;

procedure MakeFile(const N: String; Size: Integer);
var
  K: Integer;
begin
  Assign(F, N);
  Rewrite(F);
  for K := 1 to Size do
    Write(F, 'x');
  Close(F);
end;

begin
  Flags := FileSplit('dir/sub/name.ext', Dir, Name, Ext);
  WriteLn('FileSplit: ', Flags, ' [', StrPas(Dir), '] [', StrPas(Name), '] [', StrPas(Ext), ']');
  Flags := FileSplit('name', Dir, Name, Ext);
  WriteLn('FileSplit: ', Flags, ' [', StrPas(Dir), '] [', StrPas(Name), '] [', StrPas(Ext), ']');
  Flags := FileSplit('*.pas', Dir, Name, Ext);
  WriteLn('FileSplit: ', Flags, ' [', StrPas(Dir), '] [', StrPas(Name), '] [', StrPas(Ext), ']');
  WriteLn('Konstanta: ', faReadOnly, ' ', faHidden, ' ', faSysFile, ' ', faVolumeID, ' ', faDirectory, ' ', faArchive,
    ' ', faAnyFile, ' ', fcExtension, ' ', fcFileName, ' ', fcDirectory, ' ', fcWildcards);
  WriteLn('Batas nama: ', fsPathName >= 79, ' ', fsDirectory >= 67, ' ', fsFileName >= 8, ' ', fsExtension >= 4);

  MakeFile('windos_a1.wdt', 5);
  MakeFile('windos_a2.wdt', 0);
  MakeFile('windos_b1.wdt', 3);
  Count := 0;
  FindFirst('windos_a*.wdt', faAnyFile, SR);
  while DosError = 0 do
  begin
    Inc(Count);
    Names[Count] := StrPas(SR.Name);
    Sizes[Count] := SR.Size;
    if SR.Attr and faDirectory <> 0 then
      WriteLn('bukan berkas: ', Names[Count]);
    FindNext(SR);
  end;
  FindClose(SR);
  WriteLn('FindNext selesai: ', DosError <> 0);
  for I := 1 to Count - 1 do
    for J := I + 1 to Count do
      if Names[J] < Names[I] then
      begin
        T := Names[I];
        Names[I] := Names[J];
        Names[J] := T;
        P := Sizes[I];
        Sizes[I] := Sizes[J];
        Sizes[J] := P;
      end;
  for I := 1 to Count do
    WriteLn(I, ': ', Names[I], ' ukuran ', Sizes[I]);
  FindFirst('tidak_ada_*.zzz', faAnyFile, SR);
  WriteLn('Tanpa hasil: ', DosError <> 0);
  FindClose(SR);

  Assign(F, 'windos_a1.wdt');
  GetFAttr(F, Attr);
  WriteLn('GetFAttr: ', DosError, ' folder=', Attr and faDirectory);
  Assign(F, 'windos_tidak_ada.wdt');
  GetFAttr(F, Attr);
  WriteLn('GetFAttr tanpa berkas: ', DosError <> 0);
  Assign(F, 'windos_a1.wdt');
  Reset(F);
  GetFTime(F, P);
  Close(F);
  UnpackTime(P, Dt);
  WriteLn('GetFTime: ', DosError, ' ', Dt.Year >= 2024);

  Dt.Year := 2024;
  Dt.Month := 3;
  Dt.Day := 5;
  Dt.Hour := 10;
  Dt.Min := 20;
  Dt.Sec := 30;
  PackTime(Dt, P);
  Dt.Year := 0;
  UnpackTime(P, Dt);
  WriteLn('PackTime: ', Dt.Year, '-', Dt.Month, '-', Dt.Day, ' ', Dt.Hour, ':', Dt.Min, ':', Dt.Sec);

  Ok := StrPas(FileSearch(Buf, 'windos_a1.wdt', '.')) <> '';
  WriteLn('FileSearch ketemu: ', Ok);
  Ok := StrPas(FileSearch(Buf, 'windos_tidak_ada.wdt', '.')) = '';
  WriteLn('FileSearch tidak ada: ', Ok);
  WriteLn('FileExpand: ', StrPas(FileExpand(Buf, 'windos_a1.wdt')) <> 'windos_a1.wdt');

  CreateDir('windos_dir');
  WriteLn('CreateDir: ', DosError);
  Assign(F, 'windos_dir');
  GetFAttr(F, Attr);
  WriteLn('folder: ', Attr and faDirectory);
  SetCurDir('windos_dir');
  WriteLn('SetCurDir: ', DosError);
  SetCurDir('..');
  GetCurDir(Buf, 0);
  WriteLn('GetCurDir: ', StrLen(Buf) > 0);
  SetCurDir('windos_tidak_ada_dir');
  WriteLn('SetCurDir gagal: ', DosError <> 0);
  RemoveDir('windos_dir');
  WriteLn('RemoveDir: ', DosError);
  RemoveDir('windos_dir');
  WriteLn('RemoveDir gagal: ', DosError <> 0);

  WriteLn('Argumen: ', GetArgCount, ' ', StrLen(GetArgStr(Buf, 0, 255)) > 0, ' ', StrLen(GetArgStr(Buf, 9, 255)));
  WriteLn('GetEnvVar: ', GetEnvVar('ODIN_PASTI_TIDAK_ADA_1234') = nil);
  GetDate(Y, M, D, W);
  WriteLn('GetDate: ', Y >= 2024, ' ', W <= 6);
  WriteLn('DosVersion: ', DosVersion <> 0);

  Assign(F, 'windos_a1.wdt');
  Erase(F);
  Assign(F, 'windos_a2.wdt');
  Erase(F);
  Assign(F, 'windos_b1.wdt');
  Erase(F);
end.
