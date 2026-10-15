{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Dos dari runtime library Odin untuk macOS. Implementasi clean-room
  berdasarkan dokumentasi publik API Turbo Pascal 7 dan pengamatan keluaran
  program. Layout struct libc di bawah ini mengikuti header macOS 64-bit. }
unit Dos;

{$R-,Q-,I-,X+}

interface

const
  FCarry = $0001;
  FParity = $0004;
  FAuxiliary = $0010;
  FZero = $0040;
  FSign = $0080;
  FOverflow = $0800;

  ReadOnly = $01;
  Hidden = $02;
  SysFile = $04;
  VolumeID = $08;
  Directory = $10;
  Archive = $20;
  AnyFile = $3F;

type
  ComStr = String;
  PathStr = String;
  DirStr = String;
  NameStr = String;
  ExtStr = String;

  DateTime = record
    Year, Month, Day, Hour, Min, Sec: Word;
  end;

  SearchRec = record
    Attr: Byte;
    Time: LongInt;
    Size: LongInt;
    Name: String;
    { Data internal FindFirst/FindNext. }
    FindHandle: Pointer;
    FindAttr: Byte;
    FindDir: PathStr;
    FindPattern: String;
  end;

var
  DosError: Integer;

function DosVersion: Word;
procedure GetDate(var Year, Month, Day, DayOfWeek: Word);
procedure SetDate(Year, Month, Day: Word);
procedure GetTime(var Hour, Minute, Second, Sec100: Word);
procedure SetTime(Hour, Minute, Second, Sec100: Word);
procedure GetCBreak(var Break: Boolean);
procedure SetCBreak(Break: Boolean);
procedure GetVerify(var Verify: Boolean);
procedure SetVerify(Verify: Boolean);
function DiskFree(Drive: Byte): Int64;
function DiskSize(Drive: Byte): Int64;
procedure GetFAttr(var F; var Attr: Word);
procedure SetFAttr(var F; Attr: Word);
procedure GetFTime(var F; var Time: LongInt);
procedure SetFTime(var F; Time: LongInt);
procedure FindFirst(const Path: PathStr; Attr: Word; var F: SearchRec);
procedure FindNext(var F: SearchRec);
procedure FindClose(var F: SearchRec);
procedure UnpackTime(P: LongInt; var T: DateTime);
procedure PackTime(var T: DateTime; var P: LongInt);
function FSearch(Path: PathStr; DirList: String): PathStr;
function FExpand(const Path: PathStr): PathStr;
procedure FSplit(Path: PathStr; var Dir: DirStr; var Name: NameStr; var Ext: ExtStr);
function EnvCount: Integer;
function EnvStr(Index: Integer): String;
function GetEnv(EnvVar: String): String;
procedure Exec(const Path: PathStr; const ComLine: ComStr);
function DosExitCode: Word;
procedure SwapVectors;
procedure GetIntVec(IntNo: Byte; var Vector: Pointer);
procedure SetIntVec(IntNo: Byte; Vector: Pointer);
procedure Keep(ExitCode: Word);

implementation

type
  PEnviron = ^PPCharArray;
  CName = array[0..1023] of Char;

{$IFDEF DARWIN}
  { struct stat (64-bit inode) }
  TCStat = record
    Dev: LongInt;
    Mode: Word;
    NLink: Word;
    Ino: Int64;
    Uid, Gid: LongInt;
    RDev: LongInt;
    ATime, ATimeNs, MTime, MTimeNs, CTime, CTimeNs, BTime, BTimeNs: Int64;
    Size: Int64;
    Blocks: Int64;
    BlkSize: LongInt;
    Flags, Gen, LSpare: LongInt;
    QSpare: array[0..1] of Int64;
  end;

  { struct dirent (64-bit inode) }
  TCDirent = record
    Ino: Int64;
    SeekOff: Int64;
    RecLen: Word;
    NamLen: Word;
    DType: Byte;
    Name: CName;
  end;
  PCDirent = ^TCDirent;

  { struct statfs (64-bit) }
  TCStatFs = record
    BSize: LongInt;
    IOSize: LongInt;
    Blocks, BFree, BAvail, Files, FFree: Int64;
    Rest: array[0..4095] of Byte;
  end;

  TCUtsName = record
    SysName, NodeName, Release, Version, Machine: array[0..255] of Char;
  end;
{$ENDIF}
{$IFDEF LINUX}
{$IFDEF CPUX86_64}
  { struct stat, x86-64 Linux }
  TCStat = record
    Dev, Ino, NLink: Int64;
    Mode, Uid, Gid, Pad0: LongInt;
    RDev, Size, BlkSize, Blocks: Int64;
    ATime, ATimeNs, MTime, MTimeNs, CTime, CTimeNs: Int64;
    Reserved: array[0..2] of Int64;
  end;
{$ELSE}
  { struct stat, the generic Linux layout that aarch64 uses }
  TCStat = record
    Dev, Ino: Int64;
    Mode, NLink, Uid, Gid: LongInt;
    RDev, Pad1, Size: Int64;
    BlkSize, Pad2: LongInt;
    Blocks: Int64;
    ATime, ATimeNs, MTime, MTimeNs, CTime, CTimeNs: Int64;
    Unused: array[0..1] of LongInt;
  end;
{$ENDIF}

  { struct dirent (64-bit) }
  TCDirent = record
    Ino: Int64;
    Off: Int64;
    RecLen: Word;
    DType: Byte;
    Name: CName;
  end;
  PCDirent = ^TCDirent;

  { struct statfs (64-bit) }
  TCStatFs = record
    FType, BSize: Int64;
    Blocks, BFree, BAvail, Files, FFree: Int64;
    Rest: array[0..4095] of Byte;
  end;

  TCUtsName = record
    SysName, NodeName, Release, Version, Machine, DomainName: array[0..64] of Char;
  end;
{$ENDIF}
{$IFDEF WINDOWS}
  { struct _stat64 of the UCRT }
  TCStat = record
    Dev: LongInt;
    Ino, Mode: Word;
    NLink, Uid, Gid: SmallInt;
    RDev: LongInt;
    Size: Int64;
    ATime, MTime, CTime: Int64;
  end;

  { What c_readdir below hands out: just the name. }
  TCDirent = record
    Name: CName;
  end;
  PCDirent = ^TCDirent;

  { Filled by c_statfs below, in bytes. }
  TCStatFs = record
    BSize, Blocks, BFree, BAvail: Int64;
  end;

  { struct __finddata64_t of the UCRT }
  TFindData = record
    Attrib, Pad: LongInt;
    Created, Accessed, Written, Size: Int64;
    Name: array[0..259] of Char;
  end;

  { A directory being read: the UCRT's find handle and the entry that
    _findfirst64 already returned. }
  TDirHandle = record
    Handle: Int64;
    Pending: Boolean;
    Data: TFindData;
    Ent: TCDirent;
  end;
  PDirHandle = ^TDirHandle;
{$ENDIF}

  TCTm = record
    Sec, Min, Hour, MDay, Mon, Year, WDay, YDay, IsDst: LongInt;
    GmtOff: Int64;
    Zone: PChar;
  end;

  TCTimeVal = record
    Sec: Int64;
    USec: LongInt;
    Pad: LongInt;
  end;

{$IFDEF DARWIN}
{$IFDEF CPUX86_64}
function c_stat(Path: PChar; var St: TCStat): LongInt; cdecl; external 'c' name 'stat$INODE64';
function c_fstat(Fd: LongInt; var St: TCStat): LongInt; cdecl; external 'c' name 'fstat$INODE64';
function c_statfs(Path: PChar; var St: TCStatFs): LongInt; cdecl; external 'c' name 'statfs$INODE64';
function c_opendir(Path: PChar): Pointer; cdecl; external 'c' name 'opendir$INODE64';
function c_readdir(Dir: Pointer): PCDirent; cdecl; external 'c' name 'readdir$INODE64';
{$ELSE}
function c_stat(Path: PChar; var St: TCStat): LongInt; cdecl; external 'c' name 'stat';
function c_fstat(Fd: LongInt; var St: TCStat): LongInt; cdecl; external 'c' name 'fstat';
function c_statfs(Path: PChar; var St: TCStatFs): LongInt; cdecl; external 'c' name 'statfs';
function c_opendir(Path: PChar): Pointer; cdecl; external 'c' name 'opendir';
function c_readdir(Dir: Pointer): PCDirent; cdecl; external 'c' name 'readdir';
{$ENDIF}
function c_environ: PEnviron; cdecl; external 'c' name '_NSGetEnviron';
function c_errno: PLongInt; cdecl; external 'c' name '__error';
{$ENDIF}
{$IFDEF LINUX}
{ glibc 2.33 and later export stat and fstat as functions. }
function c_stat(Path: PChar; var St: TCStat): LongInt; cdecl; external 'c' name 'stat';
function c_fstat(Fd: LongInt; var St: TCStat): LongInt; cdecl; external 'c' name 'fstat';
function c_statfs(Path: PChar; var St: TCStatFs): LongInt; cdecl; external 'c' name 'statfs';
function c_opendir(Path: PChar): Pointer; cdecl; external 'c' name 'opendir';
function c_readdir(Dir: Pointer): PCDirent; cdecl; external 'c' name 'readdir';
function c_environ: PEnviron; external 'odinrtl' name 'ODIN_NSGETENVIRON';
function c_errno: PLongInt; cdecl; external 'c' name '__errno_location';
{$ENDIF}
{$IFDEF UNIX}
function c_closedir(Dir: Pointer): LongInt; cdecl; external 'c' name 'closedir';
function c_access(Path: PChar; Mode: LongInt): LongInt; cdecl; external 'c' name 'access';
function c_getenv(Name: PChar): PChar; cdecl; external 'c' name 'getenv';
function c_gettimeofday(var TV: TCTimeVal; TZ: Pointer): LongInt; cdecl; external 'c' name 'gettimeofday';
function c_localtime_r(var T: Int64; var Tm: TCTm): Pointer; cdecl; external 'c' name 'localtime_r';
function c_mktime(var Tm: TCTm): Int64; cdecl; external 'c' name 'mktime';
function c_utimes(Path: PChar; Times: Pointer): LongInt; cdecl; external 'c' name 'utimes';
function c_uname(var U: TCUtsName): LongInt; cdecl; external 'c' name 'uname';
function c_posix_spawn(var Pid: LongInt; Path: PChar; Actions, Attr: Pointer; Argv, Envp: Pointer): LongInt;
  cdecl; external 'c' name 'posix_spawn';
function c_waitpid(Pid: LongInt; var Status: LongInt; Options: LongInt): LongInt; cdecl; external 'c' name 'waitpid';
{$ENDIF}
{$IFDEF WINDOWS}
function c_stat(Path: PChar; var St: TCStat): LongInt; cdecl; external 'c' name '_stat64';
function c_fstat(Fd: LongInt; var St: TCStat): LongInt; cdecl; external 'c' name '_fstat64';
function c_access(Path: PChar; Mode: LongInt): LongInt; cdecl; external 'c' name '_access';
function c_getenv(Name: PChar): PChar; cdecl; external 'c' name 'getenv';
function c_mktime(var Tm: TCTm): Int64; cdecl; external 'c' name '_mktime64';
function c_environ: PEnviron; external 'odinrtl' name 'ODIN_NSGETENVIRON';
function c_errno: PLongInt; cdecl; external 'c' name '_errno';
function w_findfirst(Spec: PChar; var Data: TFindData): Int64; cdecl; external 'c' name '_findfirst64';
function w_findnext(Handle: Int64; var Data: TFindData): LongInt; cdecl; external 'c' name '_findnext64';
function w_findclose(Handle: Int64): LongInt; cdecl; external 'c' name '_findclose';
function w_localtime(var Tm: TCTm; var T: Int64): LongInt; cdecl; external 'c' name '_localtime64_s';
function w_utime(Path: PChar; Times: Pointer): LongInt; cdecl; external 'c' name '_utime64';
function w_spawnve(Mode: LongInt; Path: PChar; Argv, Envp: Pointer): Int64; cdecl; external 'c' name '_spawnve';
function GetDiskFreeSpaceExA(Dir: PChar; var Avail, Total, Free: Int64): LongInt;
  external 'kernel32' name 'GetDiskFreeSpaceExA';
procedure GetSystemTimeAsFileTime(var Time: Int64); external 'kernel32' name 'GetSystemTimeAsFileTime';
function GetVersion: LongInt; external 'kernel32' name 'GetVersion';
function GetFileAttributesA(Name: PChar): LongInt; external 'kernel32' name 'GetFileAttributesA';
function SetFileAttributesA(Name: PChar; Attr: LongInt): LongInt; external 'kernel32' name 'SetFileAttributesA';

{ The few POSIX calls the rest of this unit is written against, on top of
  the UCRT and Win32. }

function c_localtime_r(var T: Int64; var Tm: TCTm): Pointer;
begin
  FillChar(Tm, SizeOf(Tm), 0);
  w_localtime(Tm, T);
  c_localtime_r := @Tm;
end;

function c_gettimeofday(var TV: TCTimeVal; TZ: Pointer): LongInt;
var
  T: Int64;
begin
  { 100 ns units since 1601-01-01 }
  GetSystemTimeAsFileTime(T);
  T := T - 116444736000000000;
  TV.Sec := T div 10000000;
  TV.USec := (T mod 10000000) div 10;
  TV.Pad := 0;
  c_gettimeofday := 0;
end;

{ Times points at two TCTimeVal (access, modification). }
function c_utimes(Path: PChar; Times: Pointer): LongInt;
var
  B: array[0..1] of Int64;
  TV: ^TCTimeVal;
begin
  TV := Times;
  B[0] := TV^.Sec;
  TV := Pointer(Int64(Times) + SizeOf(TCTimeVal));
  B[1] := TV^.Sec;
  c_utimes := w_utime(Path, @B);
end;

function c_statfs(Path: PChar; var St: TCStatFs): LongInt;
var
  Avail, Total, Free: Int64;
begin
  c_statfs := -1;
  if GetDiskFreeSpaceExA(Path, Avail, Total, Free) = 0 then
    Exit;
  St.BSize := 1;
  St.Blocks := Total;
  St.BFree := Free;
  St.BAvail := Avail;
  c_statfs := 0;
end;

function c_opendir(Path: PChar): Pointer;
var
  D: PDirHandle;
  Spec: CName;
  I: Integer;
begin
  c_opendir := nil;
  I := 0;
  while (Path[I] <> #0) and (I < 1000) do
  begin
    Spec[I] := Path[I];
    Inc(I);
  end;
  if (I > 0) and (Spec[I - 1] <> '\') and (Spec[I - 1] <> '/') then
  begin
    Spec[I] := '\';
    Inc(I);
  end;
  Spec[I] := '*';
  Spec[I + 1] := #0;
  New(D);
  D^.Handle := w_findfirst(@Spec, D^.Data);
  if D^.Handle = -1 then
  begin
    Dispose(D);
    Exit;
  end;
  D^.Pending := True;
  c_opendir := D;
end;

function c_readdir(Dir: Pointer): PCDirent;
var
  D: PDirHandle;
begin
  c_readdir := nil;
  D := Dir;
  if not D^.Pending and (w_findnext(D^.Handle, D^.Data) <> 0) then
    Exit;
  D^.Pending := False;
  Move(D^.Data.Name, D^.Ent.Name, SizeOf(D^.Data.Name));
  c_readdir := @D^.Ent;
end;

function c_closedir(Dir: Pointer): LongInt;
begin
  w_findclose(PDirHandle(Dir)^.Handle);
  Dispose(PDirHandle(Dir));
  c_closedir := 0;
end;
{$ENDIF}

const
  S_IFMT = $F000;
  S_IFDIR = $4000;
  W_OK = 2;
  EINTR = 4;

var
  LastExitCode: Word;
  CBreak: Boolean;
  VerifyFlag: Boolean;

procedure ToCName(const S: String; var C: CName);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    C[I - 1] := S[I];
  C[Length(S)] := #0;
end;

function FromCName(P: PChar): String;
var
  S: String;
  N: Integer;
begin
  N := 0;
  if P <> nil then
    while (P[N] <> #0) and (N < 255) do
    begin
      S[N + 1] := P[N];
      Inc(N);
    end;
  S[0] := Chr(N);
  FromCName := S;
end;

{ A directory separator: '/' on Unix; '\', '/' and the ':' after a drive
  letter on Windows. }
function IsSep(C: Char): Boolean;
begin
{$IFDEF WINDOWS}
  IsSep := (C = '\') or (C = '/') or (C = ':');
{$ELSE}
  IsSep := C = '/';
{$ENDIF}
end;

{ File name stored in a TextRec or FileRec: Name sits at offset 48 in both. }
function FileName(var F): String;
begin
  FileName := FromCName(@FileRec(F).Name);
end;

function IsDir(const St: TCStat): Boolean;
begin
  IsDir := St.Mode and S_IFMT = S_IFDIR;
end;

{ DOS attributes of an existing file: Directory, Hidden for names that
  start with a dot, ReadOnly when the user cannot write it. }
function AttrOf(Path: PChar; const Name: String; const St: TCStat): Byte;
var
  A: Byte;
{$IFDEF WINDOWS}
  W: LongInt;
{$ENDIF}
begin
{$IFDEF WINDOWS}
  { Windows keeps the DOS attribute bits themselves. }
  W := GetFileAttributesA(Path);
  if W <> -1 then
  begin
    AttrOf := W and (ReadOnly or Hidden or SysFile or Directory or Archive);
    Exit;
  end;
{$ENDIF}
  A := 0;
  if IsDir(St) then
    A := A or Directory;
  if (Length(Name) > 0) and (Name[1] = '.') then
    A := A or Hidden;
  if c_access(Path, W_OK) <> 0 then
    A := A or ReadOnly;
  AttrOf := A;
end;

function LocalPacked(T: Int64): LongInt;
var
  Tm: TCTm;
  DT: DateTime;
  P: LongInt;
begin
  c_localtime_r(T, Tm);
  DT.Year := Tm.Year + 1900;
  DT.Month := Tm.Mon + 1;
  DT.Day := Tm.MDay;
  DT.Hour := Tm.Hour;
  DT.Min := Tm.Min;
  DT.Sec := Tm.Sec;
  PackTime(DT, P);
  LocalPacked := P;
end;

{ ---- version, date and time --------------------------------------------- }

{$IFDEF WINDOWS}
function DosVersion: Word;
var
  V: LongInt;
begin
  V := GetVersion;
  DosVersion := V and $FFFF;
end;
{$ELSE}
function DosVersion: Word;
var
  U: TCUtsName;
  I, Major, Minor: Integer;
begin
  Major := 0;
  Minor := 0;
  if c_uname(U) = 0 then
  begin
    I := 0;
    while (U.Release[I] >= '0') and (U.Release[I] <= '9') do
    begin
      Major := Major * 10 + Ord(U.Release[I]) - Ord('0');
      Inc(I);
    end;
    if U.Release[I] = '.' then
    begin
      Inc(I);
      while (U.Release[I] >= '0') and (U.Release[I] <= '9') do
      begin
        Minor := Minor * 10 + Ord(U.Release[I]) - Ord('0');
        Inc(I);
      end;
    end;
  end;
  DosVersion := (Major and $FF) or ((Minor and $FF) shl 8);
end;
{$ENDIF}

procedure Now(var Tm: TCTm; var Sec100: Word);
var
  TV: TCTimeVal;
begin
  c_gettimeofday(TV, nil);
  c_localtime_r(TV.Sec, Tm);
  Sec100 := TV.USec div 10000;
end;

procedure GetDate(var Year, Month, Day, DayOfWeek: Word);
var
  Tm: TCTm;
  S100: Word;
begin
  Now(Tm, S100);
  Year := Tm.Year + 1900;
  Month := Tm.Mon + 1;
  Day := Tm.MDay;
  DayOfWeek := Tm.WDay;
end;

{ Changing the system clock needs root on macOS: like FPC, nothing happens. }
procedure SetDate(Year, Month, Day: Word);
begin
  DosError := 0;
end;

procedure GetTime(var Hour, Minute, Second, Sec100: Word);
var
  Tm: TCTm;
begin
  Now(Tm, Sec100);
  Hour := Tm.Hour;
  Minute := Tm.Min;
  Second := Tm.Sec;
end;

procedure SetTime(Hour, Minute, Second, Sec100: Word);
begin
  DosError := 0;
end;

procedure GetCBreak(var Break: Boolean);
begin
  Break := CBreak;
end;

procedure SetCBreak(Break: Boolean);
begin
  CBreak := Break;
end;

procedure GetVerify(var Verify: Boolean);
begin
  Verify := VerifyFlag;
end;

procedure SetVerify(Verify: Boolean);
begin
  VerifyFlag := Verify;
end;

procedure UnpackTime(P: LongInt; var T: DateTime);
begin
  T.Year := 1980 + ((P shr 25) and 127);
  T.Month := (P shr 21) and 15;
  T.Day := (P shr 16) and 31;
  T.Hour := (P shr 11) and 31;
  T.Min := (P shr 5) and 63;
  T.Sec := (P and 31) * 2;
end;

{ The fields are added, not or-ed, so out-of-range values carry over. }
procedure PackTime(var T: DateTime; var P: LongInt);
var
  V: Int64;
begin
  V := (Int64(T.Year) - 1980) * 33554432 + Int64(T.Month) * 2097152 + Int64(T.Day) * 65536 +
    Int64(T.Hour) * 2048 + Int64(T.Min) * 32 + T.Sec div 2;
  P := LongInt(V and $FFFFFFFF);
end;

{ ---- disks and file attributes ------------------------------------------ }

{ Drive 0 is the current directory, 3 (C:) the root; others do not exist. }
function DiskInfo(Drive: Byte; Total: Boolean): Int64;
var
  St: TCStatFs;
  Path: CName;
begin
  DiskInfo := -1;
{$IFDEF WINDOWS}
  { 0 is the current drive, 1 A:, 2 B:, 3 C: ... }
  case Drive of
    0: ToCName('.', Path);
    1..26: ToCName(Chr(Ord('A') + Drive - 1) + ':\', Path);
  else
    Exit;
  end;
{$ELSE}
  case Drive of
    0: ToCName('.', Path);
    3: ToCName('/', Path);
  else
    Exit;
  end;
{$ENDIF}
  if c_statfs(@Path, St) <> 0 then
    Exit;
  if Total then
    DiskInfo := St.Blocks * St.BSize
  else
    DiskInfo := St.BAvail * St.BSize;
end;

function DiskFree(Drive: Byte): Int64;
begin
  DiskFree := DiskInfo(Drive, False);
end;

function DiskSize(Drive: Byte): Int64;
begin
  DiskSize := DiskInfo(Drive, True);
end;

procedure GetFAttr(var F; var Attr: Word);
var
  Name: String;
  Path: CName;
  St: TCStat;
begin
  Name := FileName(F);
  ToCName(Name, Path);
  if c_stat(@Path, St) <> 0 then
  begin
    Attr := 0;
    DosError := 3;
    Exit;
  end;
  { Like FPC, Hidden looks at the start of the whole name, not its last part. }
  Attr := AttrOf(@Path, Name, St);
  DosError := 0;
end;

{$IFDEF WINDOWS}
procedure SetFAttr(var F; Attr: Word);
var
  Path: CName;
begin
  ToCName(FileName(F), Path);
  if SetFileAttributesA(@Path, Attr and (ReadOnly or Hidden or SysFile or Archive)) <> 0 then
    DosError := 0
  else
    DosError := 5;
end;
{$ELSE}
{ DOS attributes have no Unix counterpart to change: like FPC, a no-op. }
procedure SetFAttr(var F; Attr: Word);
begin
  DosError := 0;
end;
{$ENDIF}

procedure GetFTime(var F; var Time: LongInt);
var
  St: TCStat;
begin
  Time := 0;
  if (FileRec(F).Mode = fmClosed) or (c_fstat(FileRec(F).Handle, St) <> 0) then
  begin
    DosError := 6;
    Exit;
  end;
  Time := LocalPacked(St.MTime);
  DosError := 0;
end;

procedure SetFTime(var F; Time: LongInt);
var
  DT: DateTime;
  Tm: TCTm;
  TV: array[0..1] of TCTimeVal;
  Path: CName;
begin
  UnpackTime(Time, DT);
  FillChar(Tm, SizeOf(Tm), 0);
  Tm.Year := DT.Year - 1900;
  Tm.Mon := DT.Month - 1;
  Tm.MDay := DT.Day;
  Tm.Hour := DT.Hour;
  Tm.Min := DT.Min;
  Tm.Sec := DT.Sec;
  Tm.IsDst := -1;
  TV[0].Sec := c_mktime(Tm);
  TV[0].USec := 0;
  TV[0].Pad := 0;
  TV[1] := TV[0];
  ToCName(FileName(F), Path);
  if c_utimes(@Path, @TV) = 0 then
    DosError := 0
  else
    DosError := 3;
end;

{ ---- FindFirst / FindNext ------------------------------------------------ }

{ '*' matches any run of characters and '?' one character. }
function Matches(const Pattern, Name: String): Boolean;
var
  P, N, StarP, StarN: Integer;
begin
  P := 1;
  N := 1;
  StarP := 0;
  StarN := 0;
  while N <= Length(Name) do
  begin
    if (P <= Length(Pattern)) and ((Pattern[P] = '?') or (Pattern[P] = Name[N])) then
    begin
      Inc(P);
      Inc(N);
    end
    else if (P <= Length(Pattern)) and (Pattern[P] = '*') then
    begin
      StarP := P;
      StarN := N;
      Inc(P);
    end
    else if StarP > 0 then
    begin
      P := StarP + 1;
      Inc(StarN);
      N := StarN;
    end
    else
    begin
      Matches := False;
      Exit;
    end;
  end;
  while (P <= Length(Pattern)) and (Pattern[P] = '*') do
    Inc(P);
  Matches := P > Length(Pattern);
end;

{ Directories and hidden files only show up when Attr asks for them. }
function Wanted(EntryAttr, Mask: Byte): Boolean;
begin
  Wanted := EntryAttr and (Directory or Hidden) and not Mask = 0;
end;

function Fill(var F: SearchRec; const Name: String): Boolean;
var
  Path: CName;
  St: TCStat;
  A: Byte;
begin
  Fill := False;
  ToCName(F.FindDir + Name, Path);
  if c_stat(@Path, St) <> 0 then
    Exit;
  A := AttrOf(@Path, Name, St);
  if not Wanted(A, F.FindAttr) then
    Exit;
  F.Attr := A;
  F.Time := LocalPacked(St.MTime);
  F.Size := LongInt(St.Size);
  F.Name := Name;
  Fill := True;
end;

procedure FindNext(var F: SearchRec);
var
  E: PCDirent;
begin
  DosError := 18;
  if F.FindHandle = nil then
    Exit;
  while True do
  begin
    E := c_readdir(F.FindHandle);
    if E = nil then
    begin
      FindClose(F);
      Exit;
    end;
    if Matches(F.FindPattern, FromCName(@E^.Name)) and Fill(F, FromCName(@E^.Name)) then
    begin
      DosError := 0;
      Exit;
    end;
  end;
end;

procedure FindFirst(const Path: PathStr; Attr: Word; var F: SearchRec);
var
  I: Integer;
  Dir: CName;
begin
  F.FindHandle := nil;
  F.FindAttr := Attr;
  if Path = '' then
  begin
    DosError := 3;
    Exit;
  end;
  I := Length(Path);
  while (I > 0) and not IsSep(Path[I]) do
    Dec(I);
  F.FindDir := Copy(Path, 1, I);
  F.FindPattern := Copy(Path, I + 1, 255);
  if (Pos('*', F.FindPattern) = 0) and (Pos('?', F.FindPattern) = 0) then
  begin
    { A plain name: report that one file, if it exists. }
    if Fill(F, F.FindPattern) then
      DosError := 0
    else
      DosError := 18;
    Exit;
  end;
  if F.FindDir = '' then
    ToCName('.', Dir)
  else
    ToCName(F.FindDir, Dir);
  F.FindHandle := c_opendir(@Dir);
  FindNext(F);
end;

procedure FindClose(var F: SearchRec);
begin
  if F.FindHandle <> nil then
    c_closedir(F.FindHandle);
  F.FindHandle := nil;
end;

{ ---- paths ---------------------------------------------------------------- }

function GetEnv(EnvVar: String): String;
var
  Name: CName;
begin
  ToCName(EnvVar, Name);
  GetEnv := FromCName(c_getenv(@Name));
end;

function EnvCount: Integer;
var
  E: PPCharArray;
  N: Integer;
begin
  E := c_environ^;
  N := 0;
  while E^[N] <> nil do
    Inc(N);
  EnvCount := N;
end;

function EnvStr(Index: Integer): String;
begin
  if (Index < 1) or (Index > EnvCount) then
    EnvStr := ''
  else
    EnvStr := FromCName(c_environ^^[Index - 1]);
end;

function IsFile(const Name: String): Boolean;
var
  Path: CName;
  St: TCStat;
begin
  ToCName(Name, Path);
  IsFile := (c_stat(@Path, St) = 0) and not IsDir(St);
end;

{ Looks for Path as given, then in each directory of DirList (separated by
  ';' or ':'). Returns the name found, or ''. }
function FSearch(Path: PathStr; DirList: String): PathStr;
var
  I, Start: Integer;
  Dir: String;
begin
  FSearch := '';
  if Path = '' then
    Exit;
  if IsFile(Path) then
  begin
    FSearch := Path;
    Exit;
  end;
  Start := 1;
  for I := 1 to Length(DirList) + 1 do
{$IFDEF WINDOWS}
    { ':' belongs to drive letters here: only ';' separates. }
    if (I > Length(DirList)) or (DirList[I] = ';') then
{$ELSE}
    if (I > Length(DirList)) or (DirList[I] = ';') or (DirList[I] = ':') then
{$ENDIF}
    begin
      Dir := Copy(DirList, Start, I - Start);
      Start := I + 1;
      if Dir <> '' then
      begin
        if not IsSep(Dir[Length(Dir)]) then
{$IFDEF WINDOWS}
          Dir := Dir + '\';
{$ELSE}
          Dir := Dir + '/';
{$ENDIF}
        if IsFile(Dir + Path) then
        begin
          FSearch := Dir + Path;
          Exit;
        end;
      end;
    end;
end;

{$IFDEF WINDOWS}
{ Absolute form of Path: '/' becomes '\', a missing drive or directory comes
  from the current one, '.' and '..' are resolved and repeated separators
  collapse. A trailing '\' stays; \\server\share names keep their prefix. }
function FExpand(const Path: PathStr): PathStr;
var
  S, Dir, Prefix, Result: String;
  Parts: array[1..128] of String;
  Count, I, Start: Integer;
  Part: String;
  Trailing: Boolean;
begin
  S := Path;
  for I := 1 to Length(S) do
    if S[I] = '/' then
      S[I] := '\';
  GetDir(0, Dir);
  if (Length(S) >= 2) and (S[1] = '\') and (S[2] = '\') then
  begin
    Prefix := '\\';
    S := Copy(S, 3, 255);
  end
  else
  begin
    if (Length(S) >= 2) and (S[2] = ':') then
    begin
      Prefix := UpCase(S[1]) + ':\';
      S := Copy(S, 3, 255);
      { X:name is relative to that drive's current directory; only the
        current drive's is known here. }
      if ((Length(S) = 0) or (S[1] <> '\')) and (UpCase(Dir[1]) = Prefix[1]) then
        S := Copy(Dir, 3, 255) + '\' + S;
    end
    else
    begin
      Prefix := UpCase(Dir[1]) + ':\';
      if (Length(S) = 0) or (S[1] <> '\') then
        S := Copy(Dir, 3, 255) + '\' + S;
    end;
  end;
  Trailing := (Length(S) > 0) and (S[Length(S)] = '\');
  Count := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = '\') then
    begin
      Part := Copy(S, Start, I - Start);
      Start := I + 1;
      if Part = '..' then
      begin
        if Count > 0 then
          Dec(Count);
      end
      else if (Part <> '.') and (Part <> '') then
      begin
        Inc(Count);
        Parts[Count] := Part;
      end;
    end;
  Result := Prefix;
  for I := 1 to Count do
  begin
    Result := Result + Parts[I];
    if (I < Count) or Trailing then
      Result := Result + '\';
  end;
  FExpand := Result;
end;
{$ELSE}
{ Absolute form of Path: '\' becomes '/', '~' is $HOME, '.' and '..' are
  resolved and repeated separators collapse. A trailing '/' stays. }
function FExpand(const Path: PathStr): PathStr;
var
  S, Dir, Prefix, Result: String;
  Parts: array[1..128] of String;
  Count, I, Start: Integer;
  Part: String;
  Trailing: Boolean;
begin
  S := Path;
  for I := 1 to Length(S) do
    if S[I] = '\' then
      S[I] := '/';
  if (Length(S) > 0) and (S[1] = '~') and ((Length(S) = 1) or (S[2] = '/')) then
    S := GetEnv('HOME') + Copy(S, 2, 255)
  else if (Length(S) = 0) or (S[1] <> '/') then
  begin
    GetDir(0, Dir);
    if Dir[Length(Dir)] <> '/' then
      Dir := Dir + '/';
    S := Dir + S;
  end;
  if (Length(S) >= 2) and (S[2] = '/') then
    Prefix := '//'
  else
    Prefix := '/';
  Trailing := S[Length(S)] = '/';
  Count := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = '/') then
    begin
      Part := Copy(S, Start, I - Start);
      Start := I + 1;
      if Part = '..' then
      begin
        if Count > 0 then
          Dec(Count);
      end
      else if (Part <> '.') and (Part <> '') then
      begin
        Inc(Count);
        Parts[Count] := Part;
      end;
    end;
  Result := Prefix;
  for I := 1 to Count do
  begin
    Result := Result + Parts[I];
    if (I < Count) or Trailing then
      Result := Result + '/';
  end;
  FExpand := Result;
end;
{$ENDIF}

procedure FSplit(Path: PathStr; var Dir: DirStr; var Name: NameStr; var Ext: ExtStr);
var
  I, Slash, Dot: Integer;
begin
{$IFDEF UNIX}
  for I := 1 to Length(Path) do
    if Path[I] = '\' then
      Path[I] := '/';
{$ENDIF}
  Slash := Length(Path);
  while (Slash > 0) and not IsSep(Path[Slash]) do
    Dec(Slash);
  Dot := Length(Path);
  while (Dot > Slash) and (Path[Dot] <> '.') do
    Dec(Dot);
  Dir := Copy(Path, 1, Slash);
  if Dot > Slash then
  begin
    Name := Copy(Path, Slash + 1, Dot - Slash - 1);
    Ext := Copy(Path, Dot, 255);
  end
  else
  begin
    Name := Copy(Path, Slash + 1, 255);
    Ext := '';
  end;
end;

{ ---- Exec ----------------------------------------------------------------- }

{ Runs Path (not searched in PATH) with ComLine split at blanks; an
  argument that starts with '"' runs to the next '"'. DosError is 8 when
  the program cannot start (exit code 127) or dies from a signal. }
procedure Exec(const Path: PathStr; const ComLine: ComStr);
var
  Buf: array[0..767] of Char;
  Argv: array[0..131] of PChar;
  Argc, Used, I, Pid, Status, R: LongInt;

  procedure Add(const S: String);
  var
    K: Integer;
    Quote: Boolean;
  begin
    Argv[Argc] := @Buf[Used];
    Inc(Argc);
{$IFDEF WINDOWS}
    Quote := (Argc > 1) and ((Pos(' ', S) > 0) or (S = ''));
{$ELSE}
    Quote := False;
{$ENDIF}
    if Quote then
    begin
      Buf[Used] := '"';
      Inc(Used);
    end;
    for K := 1 to Length(S) do
    begin
      Buf[Used] := S[K];
      Inc(Used);
    end;
    if Quote then
    begin
      Buf[Used] := '"';
      Inc(Used);
    end;
    Buf[Used] := #0;
    Inc(Used);
  end;

var
  Arg: String;
begin
  Flush(Output);
  Argc := 0;
  Used := 0;
  Add(Path);
  I := 1;
  while I <= Length(ComLine) do
  begin
    if ComLine[I] = ' ' then
      Inc(I)
    else if ComLine[I] = '"' then
    begin
      Inc(I);
      Arg := '';
      while (I <= Length(ComLine)) and (ComLine[I] <> '"') do
      begin
        Arg := Arg + ComLine[I];
        Inc(I);
      end;
      Inc(I);
      Add(Arg);
    end
    else
    begin
      Arg := '';
      while (I <= Length(ComLine)) and (ComLine[I] <> ' ') do
      begin
        Arg := Arg + ComLine[I];
        Inc(I);
      end;
      Add(Arg);
    end;
  end;
  Argv[Argc] := nil;
{$IFDEF WINDOWS}
  { _spawnve joins the arguments with blanks: Add quoted those with blanks. }
  R := w_spawnve(0, Argv[0], @Argv, c_environ^);
  if R = -1 then
  begin
    LastExitCode := 127;
    DosError := 8;
    Exit;
  end;
  LastExitCode := Word(R and $FFFF);
  DosError := 0;
{$ELSE}
  if c_posix_spawn(Pid, Argv[0], nil, nil, @Argv, c_environ^) <> 0 then
  begin
    LastExitCode := 127;
    DosError := 8;
    Exit;
  end;
  repeat
    R := c_waitpid(Pid, Status, 0);
  until (R <> -1) or (c_errno^ <> EINTR);
  if Status and $7F = 0 then
  begin
    LastExitCode := (Status shr 8) and $FF;
    if LastExitCode = 127 then
      DosError := 8
    else
      DosError := 0;
  end
  else
  begin
    LastExitCode := Word(-(Status and $7F));
    DosError := 8;
  end;
{$ENDIF}
end;

function DosExitCode: Word;
begin
  DosExitCode := LastExitCode;
end;

{ ---- DOS-only services: present so programs compile ---------------------- }

procedure SwapVectors;
begin
end;

procedure GetIntVec(IntNo: Byte; var Vector: Pointer);
begin
  Vector := nil;
end;

procedure SetIntVec(IntNo: Byte; Vector: Pointer);
begin
end;

procedure Keep(ExitCode: Word);
begin
end;

end.
