{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit WinDos dari runtime library Odin: versi unit Dos (Borland Pascal 7)
  yang memakai string berakhiran #0 (PChar). Semua rutin diteruskan ke unit
  Dos Odin, jadi perilakunya sama; DosError milik unit ini ikut disetel.

  Beda dengan Borland: batas panjang fsPathName, fsDirectory, fsFileName, dan
  fsExtension di sini besar (sistem berkas modern), TSearchRec.Name berisi
  nama berkas sampai 255 karakter, dan Intr/MsDos/TRegisters serta
  GetIntVec/SetIntVec tidak ada (tidak ada interrupt DOS). DiskFree dan
  DiskSize mengembalikan Int64. }
unit WinDos;

{$R-,Q-,I-,X+}

interface

uses
  Dos, Strings;

const
  { Atribut berkas }
  faReadOnly = $01;
  faHidden = $02;
  faSysFile = $04;
  faVolumeID = $08;
  faDirectory = $10;
  faArchive = $20;
  faAnyFile = $3F;

  { Panjang maksimum komponen nama (jumlah karakter tanpa #0) }
  fsPathName = 259;
  fsDirectory = 255;
  fsFileName = 255;
  fsExtension = 255;

  { Hasil FileSplit }
  fcExtension = $0001;
  fcFileName = $0002;
  fcDirectory = $0004;
  fcWildcards = $0008;

type
  TDateTime = record
    Year, Month, Day, Hour, Min, Sec: Word;
  end;

  TSearchRec = record
    Fill: array[1..21] of Byte;
    Attr: Byte;
    Time: LongInt;
    Size: LongInt;
    Name: array[0..255] of Char;
    Priv: Dos.SearchRec;
  end;

var
  DosError: Integer;

function DosVersion: Word;
procedure GetDate(var Year, Month, Day, DayOfWeek: Word);
procedure SetDate(Year, Month, Day: Word);
procedure GetTime(var Hour, Minute, Second, Sec100: Word);
procedure SetTime(Hour, Minute, Second, Sec100: Word);
procedure GetCBreak(var BreakOn: Boolean);
procedure SetCBreak(BreakOn: Boolean);
procedure GetVerify(var Verify: Boolean);
procedure SetVerify(Verify: Boolean);
function DiskFree(Drive: Byte): Int64;
function DiskSize(Drive: Byte): Int64;
procedure GetFAttr(var F; var Attr: Word);
procedure SetFAttr(var F; Attr: Word);
procedure GetFTime(var F; var Time: LongInt);
procedure SetFTime(var F; Time: LongInt);
procedure FindFirst(Path: PChar; Attr: Word; var F: TSearchRec);
procedure FindNext(var F: TSearchRec);
procedure FindClose(var F: TSearchRec);
procedure UnpackTime(P: LongInt; var T: TDateTime);
procedure PackTime(var T: TDateTime; var P: LongInt);
function FileSearch(Dest, Name, List: PChar): PChar;
function FileExpand(Dest, Name: PChar): PChar;
function FileSplit(Path, Dir, Name, Ext: PChar): Word;
function GetCurDir(Dir: PChar; Drive: Byte): PChar;
procedure SetCurDir(Dir: PChar);
procedure CreateDir(Dir: PChar);
procedure RemoveDir(Dir: PChar);
function GetArgCount: Integer;
function GetArgStr(Dest: PChar; Index: Integer; MaxLen: Word): PChar;
function GetEnvVar(VarName: PChar): PChar;
procedure Exec(Name, CmdLine: PChar);
function DosExitCode: Word;
procedure SwapVectors;
procedure Keep(ExitCode: Word);

implementation

function c_getenv(Name: PChar): PChar; cdecl; external 'c' name 'getenv';

function DosVersion: Word;
begin
  DosVersion := Dos.DosVersion;
end;

procedure GetDate(var Year, Month, Day, DayOfWeek: Word);
begin
  Dos.GetDate(Year, Month, Day, DayOfWeek);
end;

procedure SetDate(Year, Month, Day: Word);
begin
  Dos.SetDate(Year, Month, Day);
end;

procedure GetTime(var Hour, Minute, Second, Sec100: Word);
begin
  Dos.GetTime(Hour, Minute, Second, Sec100);
end;

procedure SetTime(Hour, Minute, Second, Sec100: Word);
begin
  Dos.SetTime(Hour, Minute, Second, Sec100);
end;

procedure GetCBreak(var BreakOn: Boolean);
begin
  Dos.GetCBreak(BreakOn);
end;

procedure SetCBreak(BreakOn: Boolean);
begin
  Dos.SetCBreak(BreakOn);
end;

procedure GetVerify(var Verify: Boolean);
begin
  Dos.GetVerify(Verify);
end;

procedure SetVerify(Verify: Boolean);
begin
  Dos.SetVerify(Verify);
end;

function DiskFree(Drive: Byte): Int64;
begin
  DiskFree := Dos.DiskFree(Drive);
end;

function DiskSize(Drive: Byte): Int64;
begin
  DiskSize := Dos.DiskSize(Drive);
end;

procedure GetFAttr(var F; var Attr: Word);
begin
  Dos.GetFAttr(F, Attr);
  DosError := Dos.DosError;
end;

procedure SetFAttr(var F; Attr: Word);
begin
  Dos.SetFAttr(F, Attr);
  DosError := Dos.DosError;
end;

procedure GetFTime(var F; var Time: LongInt);
begin
  Dos.GetFTime(F, Time);
  DosError := Dos.DosError;
end;

procedure SetFTime(var F; Time: LongInt);
begin
  Dos.SetFTime(F, Time);
  DosError := Dos.DosError;
end;

{ Menyalin hasil pencarian Dos ke bagian yang terlihat pemakai. }
procedure CopyFound(var F: TSearchRec);
var
  I, N: Integer;
begin
  DosError := Dos.DosError;
  if DosError <> 0 then
    Exit;
  F.Attr := F.Priv.Attr;
  F.Time := F.Priv.Time;
  F.Size := F.Priv.Size;
  N := Length(F.Priv.Name);
  if N > 255 then
    N := 255;
  for I := 1 to N do
    F.Name[I - 1] := F.Priv.Name[I];
  F.Name[N] := #0;
end;

procedure FindFirst(Path: PChar; Attr: Word; var F: TSearchRec);
begin
  FillChar(F.Fill, SizeOf(F.Fill), 0);
  F.Name[0] := #0;
  Dos.FindFirst(StrPas(Path), Attr, F.Priv);
  CopyFound(F);
end;

procedure FindNext(var F: TSearchRec);
begin
  Dos.FindNext(F.Priv);
  CopyFound(F);
end;

procedure FindClose(var F: TSearchRec);
begin
  Dos.FindClose(F.Priv);
end;

procedure UnpackTime(P: LongInt; var T: TDateTime);
var
  D: Dos.DateTime;
begin
  Dos.UnpackTime(P, D);
  T.Year := D.Year;
  T.Month := D.Month;
  T.Day := D.Day;
  T.Hour := D.Hour;
  T.Min := D.Min;
  T.Sec := D.Sec;
end;

procedure PackTime(var T: TDateTime; var P: LongInt);
var
  D: Dos.DateTime;
begin
  D.Year := T.Year;
  D.Month := T.Month;
  D.Day := T.Day;
  D.Hour := T.Hour;
  D.Min := T.Min;
  D.Sec := T.Sec;
  Dos.PackTime(D, P);
end;

{ Menyalin S ke Dest, paling banyak Max karakter; mengembalikan Dest. }
function PutString(Dest: PChar; const S: String; Max: Integer): PChar;
var
  T: String;
begin
  T := S;
  if Length(T) > Max then
    T := Copy(T, 1, Max);
  PutString := StrPCopy(Dest, T);
end;

function FileSearch(Dest, Name, List: PChar): PChar;
begin
  FileSearch := PutString(Dest, Dos.FSearch(StrPas(Name), StrPas(List)), fsPathName);
end;

function FileExpand(Dest, Name: PChar): PChar;
begin
  FileExpand := PutString(Dest, Dos.FExpand(StrPas(Name)), fsPathName);
end;

function FileSplit(Path, Dir, Name, Ext: PChar): Word;
var
  D: Dos.DirStr;
  N: Dos.NameStr;
  E: Dos.ExtStr;
  P: String;
  Flags: Word;
  I: Integer;
begin
  P := StrPas(Path);
  Dos.FSplit(P, D, N, E);
  Flags := 0;
  if E <> '' then
    Flags := Flags or fcExtension;
  if N <> '' then
    Flags := Flags or fcFileName;
  if D <> '' then
    Flags := Flags or fcDirectory;
  for I := 1 to Length(P) do
    if (P[I] = '*') or (P[I] = '?') then
      Flags := Flags or fcWildcards;
  if Dir <> nil then
    PutString(Dir, D, fsDirectory);
  if Name <> nil then
    PutString(Name, N, fsFileName);
  if Ext <> nil then
    PutString(Ext, E, fsExtension);
  FileSplit := Flags;
end;

function GetCurDir(Dir: PChar; Drive: Byte): PChar;
var
  S: String;
begin
  GetDir(Drive, S);
  DosError := IOResult;
  GetCurDir := PutString(Dir, S, fsPathName);
end;

procedure SetCurDir(Dir: PChar);
begin
  ChDir(StrPas(Dir));
  if IOResult <> 0 then
    DosError := 3
  else
    DosError := 0;
end;

procedure CreateDir(Dir: PChar);
begin
  MkDir(StrPas(Dir));
  if IOResult <> 0 then
    DosError := 3
  else
    DosError := 0;
end;

procedure RemoveDir(Dir: PChar);
begin
  RmDir(StrPas(Dir));
  if IOResult <> 0 then
    DosError := 3
  else
    DosError := 0;
end;

function GetArgCount: Integer;
begin
  GetArgCount := ParamCount;
end;

function GetArgStr(Dest: PChar; Index: Integer; MaxLen: Word): PChar;
begin
  if (Index < 0) or (Index > ParamCount) then
  begin
    Dest[0] := #0;
    GetArgStr := Dest;
  end
  else
    GetArgStr := PutString(Dest, ParamStr(Index), MaxLen);
end;

{ Menunjuk ke lingkungan proses, atau nil bila tidak ada. }
function GetEnvVar(VarName: PChar): PChar;
begin
  GetEnvVar := c_getenv(VarName);
end;

procedure Exec(Name, CmdLine: PChar);
begin
  Dos.Exec(StrPas(Name), StrPas(CmdLine));
  DosError := Dos.DosError;
end;

function DosExitCode: Word;
begin
  DosExitCode := Dos.DosExitCode;
end;

procedure SwapVectors;
begin
end;

procedure Keep(ExitCode: Word);
begin
  Dos.Keep(ExitCode);
end;

begin
  DosError := 0;
end.
