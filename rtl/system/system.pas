{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit System dari runtime library Odin. Implementasi clean-room: ditulis
  dari dokumentasi publik perilaku Turbo Pascal dan pengamatan keluaran
  program, tanpa menyalin sumber Borland atau Free Pascal. Kontrak dengan
  compiler ada di rtl/COMPILER_INTERFACE.md. }
unit System;

{$R-,Q-,I-,X+}

interface

const
  fmClosed = $D7B0;
  fmInput = $D7B1;
  fmOutput = $D7B2;
  fmInOut = $D7B3;
  FileMode: Byte = 2;

type
  PByte = ^Byte;
  { Integer types the size of a pointer, as FPC's System declares them. }
  PtrInt = Int64;
  PtrUInt = QWord;
  SizeInt = Int64;
  SizeUInt = QWord;
  PPointer = ^Pointer;
  PLongInt = ^LongInt;
  PInt64 = ^Int64;
  PString = ^String;
  TProcedure = procedure;
  TByteArray = array[0..65535] of Byte;
  PByteArray = ^TByteArray;
  TPCharArray = array[0..65535] of PChar;
  PPCharArray = ^TPCharArray;
  TextBuf = array[0..1023] of Char;
  TextRec = record
    Handle: LongInt;
    Mode: LongInt;
    BufSize: LongInt;
    BufPos: LongInt;
    BufEnd: LongInt;
    Flags: LongInt;
    FlushFunc: Pointer;
    UserData: array[1..16] of Byte;
    Name: array[0..255] of Char;
    Buffer: TextBuf;
  end;
  Text = TextRec;
  TTextHook = procedure(var F: TextRec);
  { Shadow call stack of --debug builds (COMPILER_INTERFACE.md). }
  TDbgFrame = record
    Line, Routine: LongInt;
    Fp: Pointer;
  end;
  FileRec = record
    Handle: LongInt;
    Mode: LongInt;
    RecSize: LongInt;
    Reserved: array[1..36] of Byte;
    Name: array[0..255] of Char;
  end;

var
  Input, Output: Text;
  ExitCode: LongInt;
  InOutRes: LongInt;
  ErrorAddr: Pointer;
  ExitProc: Pointer;
  RandSeed: LongInt;
  { Debugger state of --debug builds; the compiler refers to these. }
  ODIN_DBG_LINE: LongInt;
  ODIN_DBG_DEPTH: LongInt;
  ODIN_DBG_SHARED: PByteArray;
  ODIN_DBG_STACK: array[0..4095] of TDbgFrame;

function ParamCount: LongInt;
function ParamStr(Index: LongInt): String;
function IOResult: Integer;
function UpCase(C: Char): Char;
function Copy(const S: String; Index, Count: Integer): String;
function Pos(const Substr, S: String): Integer;
procedure Delete(var S: String; Index, Count: Integer);
procedure Insert(const Source: String; var S: String; Index: Integer);
procedure Move(const Source; var Dest; Count: LongInt);
procedure Randomize;
procedure MkDir(const S: String);
procedure RmDir(const S: String);
procedure ChDir(const S: String);
procedure GetDir(D: Byte; var S: String);
function CSeg: Word;
function DSeg: Word;
function SSeg: Word;
function Pi: Real;
function Sin(X: Real): Real;
function Cos(X: Real): Real;
function ArcTan(X: Real): Real;
function Exp(X: Real): Real;
function Ln(X: Real): Real;

{ Rutin yang dipanggil oleh compiler (lihat COMPILER_INTERFACE.md). }
procedure ODIN_STARTUP(ArgC: LongInt; ArgV: Pointer);
procedure ODIN_DBG_INIT(LineCount: LongInt);
procedure ODIN_DBG_HOOK(Id: LongInt);
procedure ODIN_HALT(Code: LongInt);
procedure ODIN_RUNERROR(Code: LongInt);
procedure ODIN_RANGEERROR;
procedure ODIN_OVERFLOWERROR;
procedure ODIN_DIVZEROERROR;
procedure ODIN_OBJECTERROR;
procedure ODIN_IOCHECK;
procedure ODIN_STRASSIGN(Dest: Pointer; MaxLen: Int64; Src: Pointer);
procedure ODIN_STRAPPEND(Dest: Pointer; Src: Pointer);
function ODIN_STRCOMPARE(A, B: Pointer): LongInt;
function ODIN_GETMEM(Size: Int64): Pointer;
procedure ODIN_FREEMEM(P: Pointer; Size: Int64);
procedure ODIN_FILLCHAR(var X; Count: Int64; Value: Byte);
function ODIN_RANDOM_INT(Range: Int64): Int64;
function ODIN_RANDOM_REAL: Real;
procedure ODIN_WRITE_INT(var F: Text; V: Int64; Width: LongInt);
procedure ODIN_WRITE_STR(var F: Text; const S: String; Width: LongInt);
procedure ODIN_WRITE_CHAR(var F: Text; C: Char; Width: LongInt);
procedure ODIN_WRITE_BOOL(var F: Text; B: Boolean; Width: LongInt);
procedure ODIN_WRITE_PCHAR(var F: Text; P: PChar; Width: LongInt);
procedure ODIN_WRITE_CHARS(var F: Text; const A; Len: LongInt; ZeroBased: Boolean; Width: LongInt);
procedure ODIN_WRITE_REAL(var F: Text; V: Real; Width, Decimals: LongInt);
procedure ODIN_WRITELN(var F: Text);
procedure ODIN_WRITE_END(var F: Text);
function ODIN_READ_INT(var F: Text): Int64;
function ODIN_READ_CHAR(var F: Text): Char;
function ODIN_READ_REAL(var F: Text): Real;
procedure ODIN_READ_STR(var F: Text; var S; MaxLen: LongInt);
procedure ODIN_READLN(var F: Text);
procedure ODIN_TEXT_ASSIGN(var F: Text; const Name: String);
procedure ODIN_TEXT_RESET(var F: Text);
procedure ODIN_TEXT_REWRITE(var F: Text);
procedure ODIN_TEXT_APPEND(var F: Text);
procedure ODIN_TEXT_CLOSE(var F: Text);
procedure ODIN_TEXT_FLUSH(var F: Text);
procedure ODIN_TEXT_ERASE(var F: Text);
procedure ODIN_TEXT_RENAME(var F: Text; const NewName: String);
function ODIN_TEXT_EOF(var F: Text): Boolean;
function ODIN_TEXT_EOLN(var F: Text): Boolean;
function ODIN_TEXT_SEEKEOF(var F: Text): Boolean;
function ODIN_TEXT_SEEKEOLN(var F: Text): Boolean;
procedure ODIN_FILE_ASSIGN(var F; const Name: String);
procedure ODIN_FILE_RESET(var F; RecSize: LongInt);
procedure ODIN_FILE_REWRITE(var F; RecSize: LongInt);
procedure ODIN_FILE_CLOSE(var F);
procedure ODIN_FILE_ERASE(var F);
procedure ODIN_FILE_RENAME(var F; const NewName: String);
procedure ODIN_FILE_TRUNCATE(var F);
procedure ODIN_FILE_READ(var F; var V; Size: LongInt);
procedure ODIN_FILE_WRITE(var F; const V; Size: LongInt);
procedure ODIN_FILE_BLOCKREAD(var F; var Buf; Count: Int64; var Res: LongInt);
procedure ODIN_FILE_BLOCKWRITE(var F; const Buf; Count: Int64; var Res: LongInt);
procedure ODIN_FILE_SEEK(var F; N: Int64);
function ODIN_FILE_POS(var F): Int64;
function ODIN_FILE_SIZE(var F): Int64;
function ODIN_FILE_EOF(var F): Boolean;
procedure ODIN_STR_INT(V: Int64; Width: LongInt; var S; MaxLen: LongInt);
procedure ODIN_STR_REAL(V: Real; Width, Decimals: LongInt; var S; MaxLen: LongInt);
procedure ODIN_STR_TO_CHARS(const S: String; var A; Len: LongInt);
function ODIN_VAL_INT(const S: String; var Code: LongInt): Int64;
function ODIN_VAL_REAL(const S: String; var Code: LongInt): Real;

implementation

{ ---- C library: libSystem, glibc or the Windows UCRT ---------------------- }

{$IFDEF WINDOWS}
{ The UCRT's POSIX-style functions carry an underscore and take and return
  32-bit counts; everything else matches the Unix declarations below. }
function c_write(Fd: LongInt; Buf: Pointer; Count: LongInt): LongInt; cdecl; external 'c' name '_write';
function c_read(Fd: LongInt; Buf: Pointer; Count: LongInt): LongInt; cdecl; external 'c' name '_read';
function c_open(Path: PChar; Flags: LongInt; Mode: LongInt): LongInt; cdecl; external 'c' name '_open';
function c_close(Fd: LongInt): LongInt; cdecl; external 'c' name '_close';
function c_lseek(Fd: LongInt; Offset: Int64; Whence: LongInt): Int64; cdecl; external 'c' name '_lseeki64';
function c_ftruncate(Fd: LongInt; Len: Int64): LongInt; cdecl; external 'c' name '_chsize_s';
procedure c_exit(Code: LongInt); cdecl; external 'c' name 'exit';
function c_malloc(Size: Int64): Pointer; cdecl; external 'c' name 'malloc';
procedure c_free(P: Pointer); cdecl; external 'c' name 'free';
function c_isatty(Fd: LongInt): LongInt; cdecl; external 'c' name '_isatty';
function c_unlink(Path: PChar): LongInt; cdecl; external 'c' name '_unlink';
function c_rename(OldPath, NewPath: PChar): LongInt; cdecl; external 'c' name 'rename';
function c_mkdir(Path: PChar; Mode: LongInt): LongInt; cdecl; external 'c' name '_mkdir';
function c_rmdir(Path: PChar): LongInt; cdecl; external 'c' name '_rmdir';
function c_chdir(Path: PChar): LongInt; cdecl; external 'c' name '_chdir';
function c_getcwd(Buf: PChar; Size: LongInt): PChar; cdecl; external 'c' name '_getcwd';
function c_time(T: Pointer): Int64; cdecl; external 'c' name '_time64';
function c_errno: PLongInt; cdecl; external 'c' name '_errno';
function c_setmode(Fd, Mode: LongInt): LongInt; cdecl; external 'c' name '_setmode';
{$ELSE}
function c_write(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'write';
function c_read(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'read';
function c_open(Path: PChar; Flags: LongInt; Mode: LongInt): LongInt; cdecl; external 'c' name 'open';
function c_close(Fd: LongInt): LongInt; cdecl; external 'c' name 'close';
function c_lseek(Fd: LongInt; Offset: Int64; Whence: LongInt): Int64; cdecl; external 'c' name 'lseek';
function c_ftruncate(Fd: LongInt; Len: Int64): LongInt; cdecl; external 'c' name 'ftruncate';
procedure c_exit(Code: LongInt); cdecl; external 'c' name 'exit';
function c_malloc(Size: Int64): Pointer; cdecl; external 'c' name 'malloc';
procedure c_free(P: Pointer); cdecl; external 'c' name 'free';
function c_isatty(Fd: LongInt): LongInt; cdecl; external 'c' name 'isatty';
function c_unlink(Path: PChar): LongInt; cdecl; external 'c' name 'unlink';
function c_rename(OldPath, NewPath: PChar): LongInt; cdecl; external 'c' name 'rename';
function c_mkdir(Path: PChar; Mode: LongInt): LongInt; cdecl; external 'c' name 'mkdir';
function c_rmdir(Path: PChar): LongInt; cdecl; external 'c' name 'rmdir';
function c_chdir(Path: PChar): LongInt; cdecl; external 'c' name 'chdir';
function c_getcwd(Buf: PChar; Size: Int64): PChar; cdecl; external 'c' name 'getcwd';
function c_time(T: Pointer): Int64; cdecl; external 'c' name 'time';
{$IFDEF DARWIN}
function c_errno: PLongInt; cdecl; external 'c' name '__error';
{$ELSE}
function c_errno: PLongInt; cdecl; external 'c' name '__errno_location';
{$ENDIF}
{$ENDIF}
function c_sin(X: Double): Double; cdecl; external 'c' name 'sin';
function c_cos(X: Double): Double; cdecl; external 'c' name 'cos';
function c_atan(X: Double): Double; cdecl; external 'c' name 'atan';
function c_exp(X: Double): Double; cdecl; external 'c' name 'exp';
function c_log(X: Double): Double; cdecl; external 'c' name 'log';
function c_pow(X, Y: Double): Double; cdecl; external 'c' name 'pow';
function ODIN_RETADDR: Pointer; external 'odinrtl' name 'ODIN_RETADDR';
{$IFDEF CPUX86_64}
procedure ODIN_SETMXCSR(Value: LongInt); external 'odinrtl' name 'ODIN_SETMXCSR';
{$ENDIF}
{$IFDEF UNIX}
function c_sigaction(Sig: LongInt; Act: Pointer; Old: Pointer): LongInt; cdecl; external 'c' name 'sigaction';
function c_sigaltstack(SS: Pointer; Old: Pointer): LongInt; cdecl; external 'c' name 'sigaltstack';
{$ENDIF}

const
{$IFDEF DARWIN}
  O_RDONLY = 0;
  O_WRONLY = 1;
  O_RDWR = 2;
  O_APPEND = $8;
  O_CREAT = $200;
  O_TRUNC = $400;
{$ENDIF}
{$IFDEF LINUX}
  O_RDONLY = 0;
  O_WRONLY = 1;
  O_RDWR = 2;
  O_APPEND = $400;
  O_CREAT = $40;
  O_TRUNC = $200;
{$ENDIF}
{$IFDEF WINDOWS}
  { Every mode carries _O_BINARY ($8000): the UCRT would otherwise turn
    #10 into #13#10 and stop reading at ^Z. }
  O_BINARY = $8000;
  O_RDONLY = O_BINARY;
  O_WRONLY = O_BINARY or 1;
  O_RDWR = O_BINARY or 2;
  O_APPEND = $8;
  O_CREAT = $100;
  O_TRUNC = $200;
{$ENDIF}
  TerminalFlag = 1;
  FlushEachWrite = 2;
  ENOENT = 2;
  EACCES = 13;
  EEXIST = 17;
  ENOTDIR = 20;
  EISDIR = 21;
  EMFILE = 24;
  EINTR = 4;

type
  TCName = array[0..255] of Char;

var
  ArgCount: LongInt;
  ArgVector: PPCharArray;

{ ---- small helpers ----------------------------------------------------- }

procedure StrToCName(const S: String; var C: TCName);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    C[I - 1] := S[I];
  C[Length(S)] := #0;
end;

function PCharToStr(P: PChar): String;
var
  S: String;
  N: Integer;
begin
  N := 0;
  if P <> nil then
    while (P^ <> #0) and (N < 255) do
    begin
      Inc(N);
      S[N] := P^;
      Inc(P);
    end;
  S[0] := Chr(N);
  PCharToStr := S;
end;

procedure IntToStr(V: Int64; var S: String);
var
  Digits: array[0..20] of Char;
  N, I, D: Integer;
  Neg: Boolean;
begin
  N := 0;
  Neg := V < 0;
  if V = 0 then
  begin
    Digits[0] := '0';
    N := 1;
  end;
  while V <> 0 do
  begin
    D := V mod 10;
    if D < 0 then
      D := -D;
    Digits[N] := Chr(Ord('0') + D);
    Inc(N);
    V := V div 10;
  end;
  if Neg then
  begin
    Digits[N] := '-';
    Inc(N);
  end;
  S[0] := Chr(N);
  for I := 1 to N do
    S[I] := Digits[N - I];
end;

function HexStr(V: Int64; Digits: Integer): String;
const
  HexDigits: array[0..15] of Char = '0123456789ABCDEF';
var
  S: String;
  I: Integer;
begin
  S[0] := Chr(Digits);
  for I := Digits downto 1 do
  begin
    S[I] := HexDigits[V and 15];
    V := V shr 4;
  end;
  HexStr := S;
end;

procedure WriteRaw(Fd: LongInt; const S: String);
var
  Dummy: Int64;
begin
  Dummy := c_write(Fd, @S[1], Length(S));
end;

{ Maps errno to a Turbo Pascal I/O error code. }
function ErrnoToIO: LongInt;
var
  E: LongInt;
begin
  E := c_errno^;
  case E of
    ENOENT: ErrnoToIO := 2;
    ENOTDIR: ErrnoToIO := 3;
    EMFILE: ErrnoToIO := 4;
  else
    ErrnoToIO := 5;
  end;
end;

{ ---- text buffers ------------------------------------------------------- }

procedure InitText(var F: Text; Fd, Mode: LongInt);
begin
  F.Handle := Fd;
  F.Mode := Mode;
  F.BufSize := 1024;
  F.BufPos := 0;
  F.BufEnd := 0;
  F.Flags := 0;
  F.FlushFunc := nil;
  if c_isatty(Fd) <> 0 then
    F.Flags := TerminalFlag;
  F.Name[0] := #0;
end;

procedure FlushText(var F: Text);
var
  Done, N: Int64;
  Hook: TTextHook;
begin
  if F.FlushFunc <> nil then
  begin
    Hook := TTextHook(F.FlushFunc);
    Hook(F);
    F.BufPos := 0;
    Exit;
  end;
  Done := 0;
  while Done < F.BufPos do
  begin
    N := c_write(F.Handle, @F.Buffer[Done], F.BufPos - Done);
    if N <= 0 then
    begin
      InOutRes := 101;
      Done := F.BufPos;
    end
    else
      Done := Done + N;
  end;
  F.BufPos := 0;
end;

{$I debug.inc}

{ ---- program start and end ---------------------------------------------- }

procedure InstallFaultHandlers; forward;

procedure ODIN_STARTUP(ArgC: LongInt; ArgV: Pointer);
begin
  ArgCount := ArgC;
  ArgVector := PPCharArray(ArgV);
  InitText(Input, 0, fmInput);
  InitText(Output, 1, fmOutput);
  ExitCode := 0;
  InOutRes := 0;
  ErrorAddr := nil;
  ExitProc := nil;
  RandSeed := 0;
{$IFDEF WINDOWS}
  c_setmode(0, O_BINARY);
  c_setmode(1, O_BINARY);
  c_setmode(2, O_BINARY);
{$ENDIF}
  InstallFaultHandlers;
end;

{ Runs the exit procedures, reports a runtime error and ends the process. }
procedure DoExit;
var
  P: Pointer;
  Proc: TProcedure;
  S: String;
begin
  while ExitProc <> nil do
  begin
    P := ExitProc;
    ExitProc := nil;
    Proc := TProcedure(P);
    Proc;
  end;
  if Output.Mode = fmOutput then
    FlushText(Output);
  if ErrorAddr <> nil then
  begin
    IntToStr(ExitCode, S);
    WriteRaw(2, 'Runtime error ' + S + ' at $' + HexStr(Int64(ErrorAddr), 16) + #10);
    WriteRaw(2, '  $' + HexStr(Int64(ErrorAddr), 16) + #10#10);
  end;
  DbgExitCode(ExitCode);
  c_exit(ExitCode);
end;

procedure ODIN_HALT(Code: LongInt);
begin
  ExitCode := Code;
  DoExit;
end;

procedure RunErrorAt(Code: LongInt; Addr: Pointer);
begin
  DbgRuntimeError(Code, Addr);
  ReportErrorFile(Code, Addr);
  ErrorAddr := Addr;
  if ErrorAddr = nil then
    ErrorAddr := Pointer(1);
  ExitCode := Code;
  DoExit;
end;

procedure ODIN_RUNERROR(Code: LongInt);
begin
  RunErrorAt(Code, ODIN_RETADDR);
end;

{ ---- runtime errors from processor faults --------------------------------- }

{ Like FPC, the invalid operation, divide by zero and overflow exceptions of
  the FPU are unmasked: they end the program with runtime error 207, 200 or
  205. A bad memory access is 216, a stack overflow 202. }

{$IFDEF UNIX}
type
{$IFDEF DARWIN}
  TSigAction = record
    Handler: Pointer;
    Mask: LongInt;
    Flags: LongInt;
  end;

  TSigStack = record
    Sp: Pointer;
    Size: Int64;
    Flags: LongInt;
  end;
{$ENDIF}
{$IFDEF LINUX}
  { glibc's struct sigaction: the mask is a 1024-bit sigset_t. }
  TSigAction = record
    Handler: Pointer;
    Mask: array[0..127] of Byte;
    Flags: LongInt;
    Pad: LongInt;
    Restorer: Pointer;
  end;

  TSigStack = record
    Sp: Pointer;
    Flags: LongInt;
    Pad: LongInt;
    Size: Int64;
  end;
{$ENDIF}

const
  SIGILL = 4;
  SIGFPE = 8;
  SIGSEGV = 11;
  MxcsrDefault = $1F80;
  MxcsrTraps = $1900;
{$IFDEF DARWIN}
  SIGBUS = 10;
  SA_ONSTACK = $1;
  SA_SIGINFO = $40;
  FPE_FLTDIV = 1;
  FPE_FLTOVF = 2;
  FPE_FLTUND = 3;
  FPE_INTDIV = 7;
  FPE_INTOVF = 8;
  SiCode = 8;
  SiAddr = 24;
  { ucontext: uc_mcontext is a pointer to the machine state. }
  CtxMContext = 48;
{$IFDEF CPUX86_64}
  { __darwin_mcontext64: exception state (16 bytes), then rax.. rip }
  StateArg0 = 48;     { rdi }
  StateArg1 = 56;     { rsi }
  StateSp = 72;       { rsp }
  StatePc = 144;      { rip }
{$ELSE}
  { __darwin_mcontext64 (arm64): exception state (16 bytes), then x0..x28, fp, lr, sp, pc }
  StateArg0 = 16;     { x0 }
  StateArg1 = 24;     { x1 }
  StateSp = 264;
  StatePc = 272;
{$ENDIF}
{$ENDIF}
{$IFDEF LINUX}
  SIGBUS = 7;
  SA_ONSTACK = $08000000;
  SA_SIGINFO = 4;
  FPE_INTDIV = 1;
  FPE_INTOVF = 2;
  FPE_FLTDIV = 3;
  FPE_FLTOVF = 4;
  FPE_FLTUND = 5;
  SiCode = 8;
  SiAddr = 16;
{$IFDEF CPUX86_64}
  { ucontext_t: uc_mcontext.gregs[] sits inline after uc_stack. }
  CtxMContext = 40;
  StateArg0 = 64;     { gregs[REG_RDI] }
  StateArg1 = 72;     { gregs[REG_RSI] }
  StateSp = 120;      { gregs[REG_RSP] }
  StatePc = 128;      { gregs[REG_RIP] }
{$ELSE}
  { ucontext_t (aarch64): uc_mcontext (struct sigcontext) at 176, after the
    1024-bit uc_sigmask: fault_address, regs[31], sp, pc }
  CtxMContext = 176;
  StateArg0 = 8;      { x0 }
  StateArg1 = 16;     { x1 }
  StateSp = 256;
  StatePc = 264;
{$ENDIF}
{$ENDIF}

var
  SignalStack: array[0..65535] of Byte;
  FaultStack: array[0..65535] of Byte;

{ Runs, outside signal context and on FaultStack, in place of the
  instruction that faulted. }
procedure FaultEntry(Code: LongInt; Addr: Pointer);
begin
{$IFDEF CPUX86_64}
  ODIN_SETMXCSR(MxcsrDefault);
{$ENDIF}
  RunErrorAt(Code, Addr);
end;

{ Signal handler (on SignalStack). It rewrites the interrupted thread state
  so that returning from the signal calls FaultEntry(Code, address of the
  faulting instruction). }
procedure FaultHandler(Sig: LongInt; Info, Ctx: PByteArray);
var
  Code: LongInt;
  State: PByteArray;
  Pc, Sp, Fault, Top: Int64;
begin
{$IFDEF DARWIN}
  State := PByteArray(Pointer(PInt64(@Ctx^[CtxMContext])^));
{$ELSE}
  State := PByteArray(@Ctx^[CtxMContext]);
{$ENDIF}
  Pc := PInt64(@State^[StatePc])^;
  Sp := PInt64(@State^[StateSp])^;
  Fault := PInt64(@Info^[SiAddr])^;
  Code := 216;
  if Sig = SIGFPE then
    case PLongInt(@Info^[SiCode])^ of
      FPE_FLTDIV, FPE_INTDIV: Code := 200;
      FPE_FLTOVF: Code := 205;
      FPE_FLTUND: Code := 206;
      FPE_INTOVF: Code := 215;
    else
      Code := 207;
    end
  else if (Sig = SIGSEGV) and (Fault < Sp + 4096) and (Fault > Sp - 65536) then
    Code := 202;
  Top := (Int64(@FaultStack) + SizeOf(FaultStack)) and not Int64(15);
  PInt64(@State^[StateArg0])^ := Code;
  PInt64(@State^[StateArg1])^ := Pc;
{$IFDEF CPUX86_64}
  { FaultEntry starts as if called: its return address slot is below Top. }
  PInt64(@State^[StateSp])^ := Top - 8;
{$ELSE}
  PInt64(@State^[StateSp])^ := Top;
{$ENDIF}
  PInt64(@State^[StatePc])^ := Int64(@FaultEntry);
end;

procedure InstallFaultHandlers;
var
  SS: TSigStack;
  Act: TSigAction;
begin
  FillChar(SS, SizeOf(SS), 0);
  SS.Sp := @SignalStack;
  SS.Size := SizeOf(SignalStack);
  SS.Flags := 0;
  c_sigaltstack(@SS, nil);
  FillChar(Act, SizeOf(Act), 0);
  Act.Handler := @FaultHandler;
  Act.Flags := SA_SIGINFO or SA_ONSTACK;
  c_sigaction(SIGFPE, @Act, nil);
  c_sigaction(SIGSEGV, @Act, nil);
  c_sigaction(SIGBUS, @Act, nil);
  c_sigaction(SIGILL, @Act, nil);
{$IFDEF CPUX86_64}
  ODIN_SETMXCSR(MxcsrTraps);
{$ENDIF}
end;
{$ENDIF}
{$IFDEF WINDOWS}
function AddVectoredExceptionHandler(First: LongInt; Handler: Pointer): Pointer; external 'kernel32' name 'AddVectoredExceptionHandler';
function SetThreadStackGuarantee(var Size: LongInt): LongInt; external 'kernel32' name 'SetThreadStackGuarantee';

const
  MxcsrDefault = $1F80;
  MxcsrTraps = $1900;
  { Offsets in the x64 CONTEXT record. }
  CtxMxCsr = $34;
  CtxRcx = $80;
  CtxRdx = $88;
  CtxRsp = $98;
  CtxRip = $F8;

var
  FaultStack: array[0..65535] of Byte;

{ Runs, outside the exception dispatch and on FaultStack, in place of the
  instruction that faulted. }
procedure FaultEntry(Code: LongInt; Addr: Pointer);
begin
  ODIN_SETMXCSR(MxcsrDefault);
  RunErrorAt(Code, Addr);
end;

{ Vectored exception handler: like the Unix signal handler, it rewrites the
  thread context so that execution resumes in FaultEntry(Code, address of
  the faulting instruction). Exceptions that are not processor faults
  (breakpoints, C++ exceptions, ...) go on to the next handler. }
function FaultHandler(Info: Pointer): LongInt;
var
  Rec, Ctx: PByteArray;
  E, Code, Top, Mx: Int64;
begin
  Rec := PByteArray(PPointer(Info)^);
  Ctx := PByteArray(PPointer(Int64(Info) + 8)^);
  E := Int64(PLongInt(@Rec^[0])^) and $FFFFFFFF;
  Mx := PLongInt(@Ctx^[CtxMxCsr])^;
  case E of
    $C0000005, $C0000006, $C000001D, $C0000096: Code := 216;  { access, in-page, illegal, privileged }
    $C00000FD: Code := 202;                                     { stack overflow }
    $C0000094, $C000008E: Code := 200;                          { integer / real division by zero }
    $C0000095: Code := 215;                                     { integer overflow }
    $C0000091: Code := 205;                                     { real overflow }
    $C0000093: Code := 206;                                     { real underflow }
    $C000008F, $C0000090, $C0000092: Code := 207;               { inexact, invalid, stack check }
    $C00002B4, $C00002B5:                                       { SSE: which flag fired }
      if Mx and 4 <> 0 then
        Code := 200
      else if Mx and 8 <> 0 then
        Code := 205
      else
        Code := 207;
  else
    begin
      FaultHandler := 0;
      Exit;
    end;
  end;
  { Win64 entry state: a return-address slot below 32 bytes of shadow space. }
  Top := (Int64(@FaultStack) + SizeOf(FaultStack)) and not Int64(15);
  PInt64(@Ctx^[CtxRcx])^ := Code;
  PInt64(@Ctx^[CtxRdx])^ := PInt64(@Ctx^[CtxRip])^;
  PInt64(@Ctx^[CtxRsp])^ := Top - 40;
  PInt64(@Ctx^[CtxRip])^ := Int64(@FaultEntry);
  FaultHandler := -1;
end;

procedure InstallFaultHandlers;
var
  Guarantee: LongInt;
begin
  { Room for the handler itself once a stack overflow has used the guard page. }
  Guarantee := 65536;
  SetThreadStackGuarantee(Guarantee);
  AddVectoredExceptionHandler(1, @FaultHandler);
  ODIN_SETMXCSR(MxcsrTraps);
end;
{$ENDIF}

procedure ODIN_RANGEERROR;
begin
  RunErrorAt(201, ODIN_RETADDR);
end;

procedure ODIN_OVERFLOWERROR;
begin
  RunErrorAt(215, ODIN_RETADDR);
end;

procedure ODIN_DIVZEROERROR;
begin
  RunErrorAt(200, ODIN_RETADDR);
end;

{ A virtual method called on an object whose constructor never ran ($R+). }
procedure ODIN_OBJECTERROR;
begin
  RunErrorAt(210, ODIN_RETADDR);
end;

procedure ODIN_IOCHECK;
var
  Code: LongInt;
begin
  if InOutRes <> 0 then
  begin
    Code := InOutRes;
    InOutRes := 0;
    RunErrorAt(Code, ODIN_RETADDR);
  end;
end;

function IOResult: Integer;
begin
  IOResult := InOutRes;
  InOutRes := 0;
end;

function ParamCount: LongInt;
begin
  ParamCount := ArgCount - 1;
end;

function ParamStr(Index: LongInt): String;
begin
  if (Index < 0) or (Index >= ArgCount) then
    ParamStr := ''
  else
    ParamStr := PCharToStr(ArgVector^[Index]);
end;

function CSeg: Word;
begin
  CSeg := 0;
end;

function DSeg: Word;
begin
  DSeg := 0;
end;

function SSeg: Word;
begin
  SSeg := 0;
end;

{ ---- memory -------------------------------------------------------------- }

function ODIN_GETMEM(Size: Int64): Pointer;
var
  P: Pointer;
begin
  if Size <= 0 then
    Size := 1;
  P := c_malloc(Size);
  if P = nil then
    RunErrorAt(203, ODIN_RETADDR);
  ODIN_GETMEM := P;
end;

procedure ODIN_FREEMEM(P: Pointer; Size: Int64);
begin
  if P <> nil then
    c_free(P);
end;

procedure ODIN_FILLCHAR(var X; Count: Int64; Value: Byte);
var
  P: PByteArray;
  I: Int64;
begin
  P := PByteArray(@X);
  I := 0;
  while I < Count do
  begin
    P^[I] := Value;
    I := I + 1;
  end;
end;

procedure Move(const Source; var Dest; Count: LongInt);
var
  S, D: PByteArray;
  I: LongInt;
begin
  S := PByteArray(@Source);
  D := PByteArray(@Dest);
  if Int64(D) < Int64(S) then
  begin
    for I := 0 to Count - 1 do
      D^[I] := S^[I];
  end
  else
    for I := Count - 1 downto 0 do
      D^[I] := S^[I];
end;

{ ---- random numbers (the linear congruential generator of TP) ---------- }

function NextRandom: Int64;
var
  Next: Int64;
begin
  Next := (Int64(RandSeed) * 134775813 + 1) and $FFFFFFFF;
  RandSeed := LongInt(Next);
  NextRandom := Next;
end;

function ODIN_RANDOM_INT(Range: Int64): Int64;
var
  U: Int64;
begin
  if Range <= 0 then
  begin
    ODIN_RANDOM_INT := 0;
    Exit;
  end;
  U := NextRandom;
  if Range <= $7FFFFFFF then
    ODIN_RANDOM_INT := (U * Range) shr 32
  else
  begin
    U := (U shl 31) xor NextRandom;
    if U < 0 then
      U := -U;
    ODIN_RANDOM_INT := U mod Range;
  end;
end;

function ODIN_RANDOM_REAL: Real;
begin
  ODIN_RANDOM_REAL := NextRandom / 4294967296.0;
end;

procedure Randomize;
begin
  RandSeed := LongInt(c_time(nil));
end;

{ ---- strings ------------------------------------------------------------ }

procedure ODIN_STRASSIGN(Dest: Pointer; MaxLen: Int64; Src: Pointer);
var
  D, S: PByteArray;
  N, I: LongInt;
begin
  if Dest = Src then
    Exit;
  D := PByteArray(Dest);
  S := PByteArray(Src);
  N := S^[0];
  if N > MaxLen then
    N := MaxLen;
  for I := 1 to N do
    D^[I] := S^[I];
  D^[0] := N;
end;

procedure ODIN_STRAPPEND(Dest: Pointer; Src: Pointer);
var
  D, S: PByteArray;
  N, M, I: LongInt;
begin
  D := PByteArray(Dest);
  S := PByteArray(Src);
  N := D^[0];
  M := S^[0];
  if N + M > 255 then
    M := 255 - N;
  for I := 1 to M do
    D^[N + I] := S^[I];
  D^[0] := N + M;
end;

function ODIN_STRCOMPARE(A, B: Pointer): LongInt;
var
  X, Y: PByteArray;
  N, I: LongInt;
begin
  X := PByteArray(A);
  Y := PByteArray(B);
  N := X^[0];
  if Y^[0] < N then
    N := Y^[0];
  for I := 1 to N do
    if X^[I] <> Y^[I] then
    begin
      if X^[I] < Y^[I] then
        ODIN_STRCOMPARE := -1
      else
        ODIN_STRCOMPARE := 1;
      Exit;
    end;
  if X^[0] < Y^[0] then
    ODIN_STRCOMPARE := -1
  else if X^[0] > Y^[0] then
    ODIN_STRCOMPARE := 1
  else
    ODIN_STRCOMPARE := 0;
end;

function UpCase(C: Char): Char;
begin
  if C in ['a'..'z'] then
    UpCase := Chr(Ord(C) - 32)
  else
    UpCase := C;
end;

function Copy(const S: String; Index, Count: Integer): String;
var
  R: String;
  I, N: Integer;
begin
  if Index < 1 then
    Index := 1;
  N := 0;
  if (Count > 0) and (Index <= Length(S)) then
  begin
    N := Length(S) - Index + 1;
    if Count < N then
      N := Count;
    for I := 1 to N do
      R[I] := S[Index + I - 1];
  end;
  R[0] := Chr(N);
  Copy := R;
end;

function Pos(const Substr, S: String): Integer;
var
  I, J: Integer;
  Found: Boolean;
begin
  Pos := 0;
  if Length(Substr) = 0 then
    Exit;
  for I := 1 to Length(S) - Length(Substr) + 1 do
  begin
    Found := True;
    J := 1;
    while Found and (J <= Length(Substr)) do
    begin
      if S[I + J - 1] <> Substr[J] then
        Found := False;
      Inc(J);
    end;
    if Found then
    begin
      Pos := I;
      Exit;
    end;
  end;
end;

procedure Delete(var S: String; Index, Count: Integer);
var
  I, L: Integer;
begin
  L := Length(S);
  if (Index < 1) or (Index > L) or (Count <= 0) then
    Exit;
  if Count > L - Index + 1 then
    Count := L - Index + 1;
  for I := Index to L - Count do
    S[I] := S[I + Count];
  S[0] := Chr(L - Count);
end;

procedure Insert(const Source: String; var S: String; Index: Integer);
var
  R: String;
begin
  if Index < 1 then
    Index := 1;
  if Index > Length(S) + 1 then
    Index := Length(S) + 1;
  R := Copy(S, 1, Index - 1) + Source + Copy(S, Index, 255);
  S := R;
end;

{ ---- directories --------------------------------------------------------- }

procedure MkDir(const S: String);
var
  C: TCName;
begin
  if InOutRes <> 0 then
    Exit;
  StrToCName(S, C);
  if c_mkdir(@C, 511) <> 0 then
    InOutRes := ErrnoToIO;
end;

procedure RmDir(const S: String);
var
  C: TCName;
begin
  if InOutRes <> 0 then
    Exit;
  StrToCName(S, C);
  if c_rmdir(@C) <> 0 then
    InOutRes := ErrnoToIO;
end;

procedure ChDir(const S: String);
var
  C: TCName;
begin
  if InOutRes <> 0 then
    Exit;
  StrToCName(S, C);
  if c_chdir(@C) <> 0 then
  begin
    { A missing directory is "path not found" here. }
    if c_errno^ = ENOENT then
      InOutRes := 3
    else
      InOutRes := ErrnoToIO;
  end;
end;

procedure GetDir(D: Byte; var S: String);
var
  C: TCName;
begin
  if c_getcwd(@C, 256) = nil then
    S := '/'
  else
    S := PCharToStr(@C);
end;

{ ---- text files ------------------------------------------------------------ }

procedure ODIN_TEXT_ASSIGN(var F: Text; const Name: String);
begin
  F.Handle := -1;
  F.Mode := fmClosed;
  F.BufSize := 1024;
  F.BufPos := 0;
  F.BufEnd := 0;
  F.Flags := 0;
  F.FlushFunc := nil;
  StrToCName(Name, TCName(F.Name));
end;

procedure ODIN_TEXT_CLOSE(var F: Text);
var
  R: LongInt;
begin
  if InOutRes <> 0 then
    Exit;
  if (F.Mode <> fmInput) and (F.Mode <> fmOutput) then
  begin
    InOutRes := 103;
    Exit;
  end;
  if F.Mode = fmOutput then
    FlushText(F);
  if F.Handle > 2 then
    R := c_close(F.Handle);
  F.Mode := fmClosed;
end;

procedure OpenText(var F: Text; Flags, Mode: LongInt);
var
  Fd: LongInt;
begin
  if InOutRes <> 0 then
    Exit;
  if (F.Mode = fmInput) or (F.Mode = fmOutput) then
    ODIN_TEXT_CLOSE(F);
  if F.Name[0] = #0 then
  begin
    { An empty name means standard input or output. }
    if Mode = fmInput then
      Fd := 0
    else
      Fd := 1;
  end
  else
  begin
    Fd := c_open(@F.Name, Flags, 438);
    if Fd < 0 then
    begin
      InOutRes := ErrnoToIO;
      Exit;
    end;
  end;
  F.Handle := Fd;
  F.Mode := Mode;
  F.BufPos := 0;
  F.BufEnd := 0;
  F.Flags := 0;
  if c_isatty(Fd) <> 0 then
    F.Flags := TerminalFlag;
  { A device with a hook (such as Crt) sees every Write at once. }
  if F.FlushFunc <> nil then
    F.Flags := F.Flags or FlushEachWrite;
end;

procedure ODIN_TEXT_RESET(var F: Text);
begin
  OpenText(F, O_RDONLY, fmInput);
end;

procedure ODIN_TEXT_REWRITE(var F: Text);
begin
  OpenText(F, O_WRONLY or O_CREAT or O_TRUNC, fmOutput);
end;

procedure ODIN_TEXT_APPEND(var F: Text);
begin
  OpenText(F, O_WRONLY or O_APPEND, fmOutput);
end;

procedure ODIN_TEXT_FLUSH(var F: Text);
begin
  if InOutRes <> 0 then
    Exit;
  if F.Mode = fmOutput then
    FlushText(F)
  else if F.Mode <> fmInput then
    InOutRes := 103;
end;

procedure EraseName(var Name: TCName);
begin
  if InOutRes <> 0 then
    Exit;
  if c_unlink(@Name) <> 0 then
    InOutRes := ErrnoToIO;
end;

procedure RenameName(var Name: TCName; const NewName: String);
var
  Buf: TCName;
begin
  if InOutRes <> 0 then
    Exit;
  StrToCName(NewName, Buf);
  if c_rename(@Name, @Buf) <> 0 then
    InOutRes := ErrnoToIO
  else
    Name := Buf;
end;

procedure ODIN_TEXT_ERASE(var F: Text);
begin
  EraseName(TCName(F.Name));
end;

procedure ODIN_TEXT_RENAME(var F: Text; const NewName: String);
begin
  RenameName(TCName(F.Name), NewName);
end;

function CanWrite(var F: Text): Boolean;
begin
  CanWrite := False;
  if InOutRes <> 0 then
    Exit;
  if F.Mode = fmOutput then
    CanWrite := True
  else if F.Mode = fmInput then
    InOutRes := 105
  else
    InOutRes := 103;
end;

function CanRead(var F: Text): Boolean;
begin
  CanRead := False;
  if InOutRes <> 0 then
    Exit;
  if F.Mode = fmInput then
    CanRead := True
  else if F.Mode = fmOutput then
    InOutRes := 104
  else
    InOutRes := 103;
end;

procedure PutChar(var F: Text; C: Char);
begin
  if F.BufPos >= F.BufSize then
    FlushText(F);
  F.Buffer[F.BufPos] := C;
  Inc(F.BufPos);
end;

procedure PutStr(var F: Text; const S: String; Width: LongInt);
var
  I: LongInt;
begin
  for I := Length(S) + 1 to Width do
    PutChar(F, ' ');
  for I := 1 to Length(S) do
    PutChar(F, S[I]);
end;

{ End of a Write statement: a file with flag FlushEachWrite shows the text
  now. Flushing per statement, not per item, keeps a function such as
  Crt.WhereX inside the same Write seeing the position before it. }
procedure ODIN_WRITE_END(var F: Text);
begin
  if (F.Mode = fmOutput) and (F.Flags and FlushEachWrite <> 0) then
    FlushText(F);
end;

procedure ODIN_WRITE_STR(var F: Text; const S: String; Width: LongInt);
begin
  if CanWrite(F) then
  begin
    PutStr(F, S, Width);
  end;
end;

procedure ODIN_WRITE_INT(var F: Text; V: Int64; Width: LongInt);
var
  S: String;
begin
  if CanWrite(F) then
  begin
    IntToStr(V, S);
    PutStr(F, S, Width);
  end;
end;

procedure ODIN_WRITE_CHAR(var F: Text; C: Char; Width: LongInt);
var
  I: LongInt;
begin
  if CanWrite(F) then
  begin
    for I := 2 to Width do
      PutChar(F, ' ');
    PutChar(F, C);
  end;
end;

procedure ODIN_WRITE_BOOL(var F: Text; B: Boolean; Width: LongInt);
begin
  if CanWrite(F) then
  begin
    if B then
      PutStr(F, 'TRUE', Width)
    else
      PutStr(F, 'FALSE', Width);
  end;
end;

procedure PutChars(var F: Text; P: PChar; Len, Width: LongInt);
var
  I: LongInt;
begin
  for I := Len + 1 to Width do
    PutChar(F, ' ');
  for I := 0 to Len - 1 do
    PutChar(F, P[I]);
end;

procedure ODIN_WRITE_PCHAR(var F: Text; P: PChar; Width: LongInt);
var
  N: LongInt;
begin
  if CanWrite(F) then
  begin
    N := 0;
    if P <> nil then
      while P[N] <> #0 do
        Inc(N);
    PutChars(F, P, N, Width);
  end;
end;

{ Writes an array of Char. A zero-based array ends at its first #0. }
procedure ODIN_WRITE_CHARS(var F: Text; const A; Len: LongInt; ZeroBased: Boolean; Width: LongInt);
var
  P: PChar;
  N: LongInt;
begin
  if CanWrite(F) then
  begin
    P := @A;
    N := Len;
    if ZeroBased then
    begin
      N := 0;
      while (N < Len) and (P[N] <> #0) do
        Inc(N);
    end;
    PutChars(F, P, N, Width);
  end;
end;

procedure ODIN_WRITELN(var F: Text);
begin
  if CanWrite(F) then
  begin
{$IFDEF WINDOWS}
    { DOS and Windows end a text line with CR LF; ReadLn accepts both. }
    PutChar(F, #13);
{$ENDIF}
    PutChar(F, #10);
    if F.Flags and (TerminalFlag or FlushEachWrite) <> 0 then
      FlushText(F);
  end;
end;

{ ---- exact decimal conversion of reals ---------------------------------- }

const
  LimbBase = 1000000000;
  MaxLimbs = 100;
  MaxKeep = 40;

type
  TBig = record
    Count: Integer;
    Limb: array[0..MaxLimbs - 1] of LongInt;
  end;

procedure BigMulSmall(var B: TBig; M: LongInt);
var
  I: Integer;
  Carry, T: Int64;
begin
  Carry := 0;
  for I := 0 to B.Count - 1 do
  begin
    T := Int64(B.Limb[I]) * M + Carry;
    B.Limb[I] := T mod LimbBase;
    Carry := T div LimbBase;
  end;
  while Carry > 0 do
  begin
    B.Limb[B.Count] := Carry mod LimbBase;
    Carry := Carry div LimbBase;
    Inc(B.Count);
  end;
end;

{ A > 0, finite. Digits gets the leading significant decimal digits (up to
  MaxKeep), E the decimal exponent of the first digit, Sticky whether a
  non-zero digit was cut off. The expansion is exact. }
procedure ExactDigits(A: Real; var Digits: String; var E: Integer; var Sticky: Boolean);
var
  Bits, Mant: Int64;
  Exp2, K, Shift, I, J, Total: Integer;
  M: LongInt;
  B: TBig;
  Chunk: String;
begin
  Bits := PInt64(@A)^;
  Exp2 := (Bits shr 52) and $7FF;
  Mant := Bits and $FFFFFFFFFFFFF;
  if Exp2 = 0 then
    Exp2 := -1074
  else
  begin
    Mant := Mant or $10000000000000;
    Exp2 := Exp2 - 1075;
  end;
  B.Count := 0;
  while Mant > 0 do
  begin
    B.Limb[B.Count] := Mant mod LimbBase;
    Mant := Mant div LimbBase;
    Inc(B.Count);
  end;
  Shift := 0;
  if Exp2 >= 0 then
  begin
    K := Exp2;
    while K >= 30 do
    begin
      BigMulSmall(B, 1073741824);
      K := K - 30;
    end;
    BigMulSmall(B, LongInt(1) shl K);
  end
  else
  begin
    { m * 2^-k = m * 5^k / 10^k }
    K := -Exp2;
    Shift := K;
    while K >= 13 do
    begin
      BigMulSmall(B, 1220703125);
      K := K - 13;
    end;
    M := 1;
    for I := 1 to K do
      M := M * 5;
    BigMulSmall(B, M);
  end;
  { Decimal digits, most significant limb first. }
  IntToStr(B.Limb[B.Count - 1], Digits);
  Total := Length(Digits) + 9 * (B.Count - 1);
  Sticky := False;
  for I := B.Count - 2 downto 0 do
  begin
    IntToStr(B.Limb[I], Chunk);
    while Length(Chunk) < 9 do
      Chunk := '0' + Chunk;
    for J := 1 to 9 do
      if Length(Digits) < MaxKeep then
        Digits := Digits + Chunk[J]
      else if Chunk[J] <> '0' then
        Sticky := True;
  end;
  E := Total - 1 - Shift;
end;

{ Rounds the digit string half up to N digits (N >= 1); a carry out of
  the first digit increases E. }
procedure RoundDigits(var Digits: String; N: Integer; var E: Integer);
var
  I: Integer;
  Carry: Boolean;
begin
  if Length(Digits) <= N then
  begin
    while Length(Digits) < N do
      Digits := Digits + '0';
    Exit;
  end;
  Carry := Digits[N + 1] >= '5';
  Digits[0] := Chr(N);
  I := N;
  while Carry and (I >= 1) do
  begin
    if Digits[I] = '9' then
      Digits[I] := '0'
    else
    begin
      Digits[I] := Chr(Ord(Digits[I]) + 1);
      Carry := False;
    end;
    Dec(I);
  end;
  if Carry then
  begin
    Digits := '1' + Copy(Digits, 1, N - 1);
    E := E + 1;
  end;
end;

{ Significant digits as FPC prints them: when at most 15 are shown the
  value is first rounded to 15 digits, otherwise to 17; then rounded half
  up to the digits shown. }
procedure ShownDigits(A: Real; P: Integer; var Digits: String; var E: Integer);
var
  Sticky: Boolean;
begin
  ExactDigits(A, Digits, E, Sticky);
  if P <= 15 then
    RoundDigits(Digits, 15, E)
  else
    RoundDigits(Digits, 17, E);
  if P < Length(Digits) then
    RoundDigits(Digits, P, E);
end;

procedure RealToStr(V: Real; Width, Decimals: LongInt; var S: String);
var
  Digits, ES: String;
  E, Mant, P, I, K: Integer;
  Neg, Sticky: Boolean;
  A: Real;
  Bits: Int64;
begin
  Bits := PInt64(@V)^;
  Neg := Bits < 0;
  A := V;
  if Neg then
    A := -V;
  if (Bits shr 52) and $7FF = $7FF then
  begin
    if Bits and $FFFFFFFFFFFFF <> 0 then
      S := 'Nan'
    else if Neg then
      S := '-Inf'
    else
      S := '+Inf';
    Exit;
  end;
  if Decimals < 0 then
  begin
    { Exponent format: " d.dddddddddddddddE+ddd". }
    Mant := 16;
    if Width >= 0 then
    begin
      Mant := Width - 8;
      if Mant < 1 then
        Mant := 1;
      if Mant > 16 then
        Mant := 16;
    end;
    if A = 0 then
    begin
      Digits := '0';
      E := 0;
      RoundDigits(Digits, Mant + 1, E);
    end
    else
      ShownDigits(A, Mant + 1, Digits, E);
    if Neg then
      S := '-'
    else
      S := ' ';
    S := S + Digits[1] + '.' + Copy(Digits, 2, Mant) + 'E';
    if E < 0 then
    begin
      S := S + '-';
      E := -E;
    end
    else
      S := S + '+';
    IntToStr(E, ES);
    while Length(ES) < 3 do
      ES := '0' + ES;
    S := S + ES;
    Exit;
  end;
  { Fixed format. }
  if A = 0 then
  begin
    Digits := '0';
    E := 0;
  end
  else
  begin
    ExactDigits(A, Digits, E, Sticky);
    P := E + 1 + Decimals;
    if P <= 15 then
      RoundDigits(Digits, 15, E)
    else
      RoundDigits(Digits, 17, E);
    { A carry may have added a digit in front. }
    P := E + 1 + Decimals;
    if P >= 1 then
    begin
      if P < Length(Digits) then
        RoundDigits(Digits, P, E);
    end
    else if (P = 0) and (Digits[1] >= '5') then
    begin
      { Rounds up to one unit of the last decimal place. }
      Digits := '1';
      E := E + 1;
    end
    else
    begin
      Digits := '0';
      E := 0;
    end;
  end;
  S := '';
  if E >= 0 then
    for I := 1 to E + 1 do
      if I <= Length(Digits) then
        S := S + Digits[I]
      else
        S := S + '0'
  else
    S := '0';
  if Decimals > 0 then
  begin
    S := S + '.';
    for I := 1 to Decimals do
    begin
      K := E + 1 + I;
      if (K >= 1) and (K <= Length(Digits)) then
        S := S + Digits[K]
      else
        S := S + '0';
    end;
  end;
  if Neg then
    S := '-' + S;
end;

procedure ODIN_WRITE_REAL(var F: Text; V: Real; Width, Decimals: LongInt);
var
  S: String;
begin
  if CanWrite(F) then
  begin
    RealToStr(V, Width, Decimals, S);
    PutStr(F, S, Width);
  end;
end;

function Pi: Real;
begin
  Pi := 3.141592653589793238;
end;

function Sin(X: Real): Real;
begin
  Sin := c_sin(X);
end;

function Cos(X: Real): Real;
begin
  Cos := c_cos(X);
end;

function ArcTan(X: Real): Real;
begin
  ArcTan := c_atan(X);
end;

function Exp(X: Real): Real;
begin
  Exp := c_exp(X);
end;

function Ln(X: Real): Real;
begin
  { Like FPC: the logarithm of 0 divides by zero, of a negative number is invalid. }
  if X = 0 then
    RunErrorAt(200, ODIN_RETADDR)
  else if X < 0 then
    RunErrorAt(207, ODIN_RETADDR);
  Ln := c_log(X);
end;

{ ---- reading ------------------------------------------------------------- }

function FillBuf(var F: Text): Boolean;
var
  N: Int64;
  Hook: TTextHook;
begin
  { Show any pending prompt before waiting for input. }
  if (Output.Mode = fmOutput) and (Output.BufPos > 0) then
    FlushText(Output);
  if F.FlushFunc <> nil then
  begin
    { The hook of an input file fills Buffer and sets BufEnd. }
    F.BufPos := 0;
    F.BufEnd := 0;
    Hook := TTextHook(F.FlushFunc);
    Hook(F);
    F.BufPos := 0;
    FillBuf := F.BufEnd > 0;
    Exit;
  end;
  N := c_read(F.Handle, @F.Buffer, F.BufSize);
  if N < 0 then
  begin
    InOutRes := 100;
    N := 0;
  end;
  F.BufPos := 0;
  F.BufEnd := N;
  FillBuf := N > 0;
end;

function PeekChar(var F: Text; var C: Char): Boolean;
begin
  if F.BufPos >= F.BufEnd then
    if not FillBuf(F) then
    begin
      PeekChar := False;
      Exit;
    end;
  C := F.Buffer[F.BufPos];
  PeekChar := True;
end;

function ODIN_TEXT_EOF(var F: Text): Boolean;
var
  C: Char;
begin
  if not CanRead(F) then
    ODIN_TEXT_EOF := True
  else
    ODIN_TEXT_EOF := not PeekChar(F, C);
end;

function ODIN_TEXT_EOLN(var F: Text): Boolean;
var
  C: Char;
begin
  if not CanRead(F) then
    ODIN_TEXT_EOLN := True
  else if not PeekChar(F, C) then
    ODIN_TEXT_EOLN := True
  else
    ODIN_TEXT_EOLN := (C = #10) or (C = #13);
end;

function ODIN_TEXT_SEEKEOF(var F: Text): Boolean;
var
  C: Char;
begin
  ODIN_TEXT_SEEKEOF := True;
  if not CanRead(F) then
    Exit;
  while PeekChar(F, C) do
  begin
    if not (C in [' ', #9, #10, #13]) then
    begin
      ODIN_TEXT_SEEKEOF := False;
      Exit;
    end;
    Inc(F.BufPos);
  end;
end;

function ODIN_TEXT_SEEKEOLN(var F: Text): Boolean;
var
  C: Char;
begin
  ODIN_TEXT_SEEKEOLN := True;
  if not CanRead(F) then
    Exit;
  while PeekChar(F, C) do
  begin
    if (C = #10) or (C = #13) then
      Exit;
    if not (C in [' ', #9]) then
    begin
      ODIN_TEXT_SEEKEOLN := False;
      Exit;
    end;
    Inc(F.BufPos);
  end;
end;

procedure SkipBlanks(var F: Text);
var
  C: Char;
begin
  while PeekChar(F, C) and (C in [' ', #9, #10, #13]) do
    Inc(F.BufPos);
end;

{ Reads a number token (characters up to the next blank) into S. }
procedure ReadToken(var F: Text; var S: String);
var
  C: Char;
begin
  S := '';
  SkipBlanks(F);
  while PeekChar(F, C) and not (C in [' ', #9, #10, #13]) do
  begin
    if Length(S) < 255 then
      S := S + C;
    Inc(F.BufPos);
  end;
end;

{ Str into an array of Char: copies the digits, no terminating #0. }
procedure ODIN_STR_TO_CHARS(const S: String; var A; Len: LongInt);
var
  N: LongInt;
begin
  N := Length(S);
  if N > Len then
    N := Len;
  Move(S[1], A, N);
end;

function ODIN_VAL_INT(const S: String; var Code: LongInt): Int64;
var
  I: Integer;
  V: Int64;
  Neg, Any: Boolean;
begin
  V := 0;
  I := 1;
  Neg := False;
  Any := False;
  while (I <= Length(S)) and (S[I] = ' ') do
    Inc(I);
  if (I <= Length(S)) and ((S[I] = '-') or (S[I] = '+')) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  if (I <= Length(S)) and (S[I] = '$') then
  begin
    Inc(I);
    while (I <= Length(S)) and (UpCase(S[I]) in ['0'..'9', 'A'..'F']) do
    begin
      if S[I] <= '9' then
        V := V * 16 + Ord(S[I]) - Ord('0')
      else
        V := V * 16 + Ord(UpCase(S[I])) - Ord('A') + 10;
      Any := True;
      Inc(I);
    end;
  end
  else
    while (I <= Length(S)) and (S[I] >= '0') and (S[I] <= '9') do
    begin
      V := V * 10 + Ord(S[I]) - Ord('0');
      Any := True;
      Inc(I);
    end;
  if Neg then
    V := -V;
  if not Any then
  begin
    if I > Length(S) then
      Code := Length(S) + 1
    else
      Code := I;
    ODIN_VAL_INT := 0;
  end
  else if I <= Length(S) then
  begin
    Code := I;
    ODIN_VAL_INT := 0;
  end
  else
  begin
    Code := 0;
    ODIN_VAL_INT := V;
  end;
end;

function ODIN_VAL_REAL(const S: String; var Code: LongInt): Real;
var
  I, Exp10, ExpSign, K: Integer;
  Mant: Real;
  Neg, Any: Boolean;
begin
  I := 1;
  Mant := 0;
  Exp10 := 0;
  Neg := False;
  Any := False;
  while (I <= Length(S)) and (S[I] = ' ') do
    Inc(I);
  if (I <= Length(S)) and ((S[I] = '-') or (S[I] = '+')) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  while (I <= Length(S)) and (S[I] >= '0') and (S[I] <= '9') do
  begin
    Mant := Mant * 10 + (Ord(S[I]) - Ord('0'));
    Any := True;
    Inc(I);
  end;
  if (I <= Length(S)) and (S[I] = '.') then
  begin
    Inc(I);
    while (I <= Length(S)) and (S[I] >= '0') and (S[I] <= '9') do
    begin
      Mant := Mant * 10 + (Ord(S[I]) - Ord('0'));
      Exp10 := Exp10 - 1;
      Any := True;
      Inc(I);
    end;
  end;
  if Any and (I <= Length(S)) and ((S[I] = 'E') or (S[I] = 'e')) then
  begin
    Inc(I);
    ExpSign := 1;
    if (I <= Length(S)) and ((S[I] = '-') or (S[I] = '+')) then
    begin
      if S[I] = '-' then
        ExpSign := -1;
      Inc(I);
    end;
    K := 0;
    while (I <= Length(S)) and (S[I] >= '0') and (S[I] <= '9') do
    begin
      K := K * 10 + Ord(S[I]) - Ord('0');
      Inc(I);
    end;
    Exp10 := Exp10 + ExpSign * K;
  end;
  if (not Any) or (I <= Length(S)) then
  begin
    if I > Length(S) then
      Code := Length(S) + 1
    else
      Code := I;
    ODIN_VAL_REAL := 0;
    Exit;
  end;
  Code := 0;
  if Exp10 <> 0 then
    Mant := Mant * c_pow(10, Exp10);
  if Neg then
    Mant := -Mant;
  ODIN_VAL_REAL := Mant;
end;

function ODIN_READ_INT(var F: Text): Int64;
var
  S: String;
  Code: LongInt;
  V: Int64;
begin
  ODIN_READ_INT := 0;
  if not CanRead(F) then
    Exit;
  ReadToken(F, S);
  if Length(S) = 0 then
    Exit;
  V := ODIN_VAL_INT(S, Code);
  if Code <> 0 then
    InOutRes := 106
  else
    ODIN_READ_INT := V;
end;

function ODIN_READ_REAL(var F: Text): Real;
var
  S: String;
  Code: LongInt;
  V: Real;
begin
  ODIN_READ_REAL := 0;
  if not CanRead(F) then
    Exit;
  ReadToken(F, S);
  { Unlike integers, a real at the end of the file is an error. }
  if Length(S) = 0 then
  begin
    InOutRes := 106;
    Exit;
  end;
  V := ODIN_VAL_REAL(S, Code);
  if Code <> 0 then
    InOutRes := 106
  else
    ODIN_READ_REAL := V;
end;

function ODIN_READ_CHAR(var F: Text): Char;
var
  C: Char;
begin
  ODIN_READ_CHAR := #26;
  if not CanRead(F) then
    Exit;
  if PeekChar(F, C) then
  begin
    Inc(F.BufPos);
    ODIN_READ_CHAR := C;
  end;
end;

procedure ODIN_READ_STR(var F: Text; var S; MaxLen: LongInt);
var
  P: PByteArray;
  C: Char;
  N: LongInt;
begin
  P := PByteArray(@S);
  N := 0;
  if CanRead(F) then
    { Stops at the end of the line or when the string is full; the rest
      of the line stays for the next Read. }
    while (N < MaxLen) and PeekChar(F, C) and (C <> #10) and (C <> #13) do
    begin
      Inc(N);
      P^[N] := Ord(C);
      Inc(F.BufPos);
    end;
  P^[0] := N;
end;

procedure ODIN_READLN(var F: Text);
var
  C: Char;
begin
  if not CanRead(F) then
    Exit;
  while PeekChar(F, C) do
  begin
    Inc(F.BufPos);
    if C = #10 then
      Exit;
    if C = #13 then
    begin
      { CR LF, or a lone CR, ends the line. }
      if PeekChar(F, C) and (C = #10) then
        Inc(F.BufPos);
      Exit;
    end;
  end;
end;

{ ---- typed and untyped files ------------------------------------------------ }

procedure ODIN_FILE_ASSIGN(var F; const Name: String);
begin
  FileRec(F).Handle := -1;
  FileRec(F).Mode := fmClosed;
  FileRec(F).RecSize := 128;
  StrToCName(Name, TCName(FileRec(F).Name));
end;

{ fmInput, fmOutput or fmInOut: a typed or untyped file is open. }
function FileModeOpen(Mode: LongInt): Boolean;
begin
  FileModeOpen := (Mode >= fmInput) and (Mode <= fmInOut);
end;

procedure ODIN_FILE_CLOSE(var F);
var
  R: LongInt;
begin
  if InOutRes <> 0 then
    Exit;
  if not FileModeOpen(FileRec(F).Mode) then
  begin
    InOutRes := 103;
    Exit;
  end;
  if FileRec(F).Handle > 2 then
    R := c_close(FileRec(F).Handle);
  FileRec(F).Mode := fmClosed;
end;

procedure OpenFile(var F; Flags, Mode, RecSize: LongInt);
var
  Fd: LongInt;
begin
  if InOutRes <> 0 then
    Exit;
  if FileModeOpen(FileRec(F).Mode) then
    ODIN_FILE_CLOSE(F);
  if RecSize <= 0 then
    RecSize := 128;
  if FileRec(F).Name[0] = #0 then
    Fd := 1
  else
  begin
    Fd := c_open(@FileRec(F).Name, Flags, 438);
    if Fd < 0 then
    begin
      InOutRes := ErrnoToIO;
      Exit;
    end;
  end;
  FileRec(F).Handle := Fd;
  FileRec(F).Mode := Mode;
  FileRec(F).RecSize := RecSize;
end;

procedure ODIN_FILE_RESET(var F; RecSize: LongInt);
begin
  case FileMode of
    0: OpenFile(F, O_RDONLY, fmInput, RecSize);
    1: OpenFile(F, O_WRONLY, fmOutput, RecSize);
  else
    OpenFile(F, O_RDWR, fmInOut, RecSize);
  end;
end;

procedure ODIN_FILE_REWRITE(var F; RecSize: LongInt);
begin
  OpenFile(F, O_RDWR or O_CREAT or O_TRUNC, fmInOut, RecSize);
end;

procedure ODIN_FILE_ERASE(var F);
begin
  EraseName(TCName(FileRec(F).Name));
end;

procedure ODIN_FILE_RENAME(var F; const NewName: String);
begin
  RenameName(TCName(FileRec(F).Name), NewName);
end;

function FileOpen(var F): Boolean;
begin
  FileOpen := False;
  if InOutRes <> 0 then
    Exit;
  if not FileModeOpen(FileRec(F).Mode) then
    InOutRes := 103
  else
    FileOpen := True;
end;

{ Reads up to Size bytes; returns how many arrived. }
function ReadBytes(Fd: LongInt; P: PByteArray; Size: Int64): Int64;
var
  Done, N: Int64;
begin
  Done := 0;
  while Done < Size do
  begin
    N := c_read(Fd, @P^[Done], Size - Done);
    if N <= 0 then
    begin
      ReadBytes := Done;
      Exit;
    end;
    Done := Done + N;
  end;
  ReadBytes := Done;
end;

function WriteBytes(Fd: LongInt; P: PByteArray; Size: Int64): Int64;
var
  Done, N: Int64;
begin
  Done := 0;
  while Done < Size do
  begin
    N := c_write(Fd, @P^[Done], Size - Done);
    if N <= 0 then
    begin
      WriteBytes := Done;
      Exit;
    end;
    Done := Done + N;
  end;
  WriteBytes := Done;
end;

procedure ODIN_FILE_READ(var F; var V; Size: LongInt);
begin
  if FileOpen(F) then
    if ReadBytes(FileRec(F).Handle, PByteArray(@V), Size) <> Size then
      InOutRes := 100;
end;

procedure ODIN_FILE_WRITE(var F; const V; Size: LongInt);
begin
  if FileOpen(F) then
    if WriteBytes(FileRec(F).Handle, PByteArray(@V), Size) <> Size then
      InOutRes := 101;
end;

procedure ODIN_FILE_BLOCKREAD(var F; var Buf; Count: Int64; var Res: LongInt);
var
  Got: Int64;
begin
  if not FileOpen(F) then
    Exit;
  Got := ReadBytes(FileRec(F).Handle, PByteArray(@Buf), Count * FileRec(F).RecSize) div FileRec(F).RecSize;
  if (Res = -1) and (Got < Count) then
    InOutRes := 100;
  Res := Got;
end;

procedure ODIN_FILE_BLOCKWRITE(var F; const Buf; Count: Int64; var Res: LongInt);
var
  Put: Int64;
begin
  if not FileOpen(F) then
    Exit;
  Put := WriteBytes(FileRec(F).Handle, PByteArray(@Buf), Count * FileRec(F).RecSize) div FileRec(F).RecSize;
  if (Res = -1) and (Put < Count) then
    InOutRes := 101;
  Res := Put;
end;

procedure ODIN_FILE_SEEK(var F; N: Int64);
begin
  if FileOpen(F) then
    if c_lseek(FileRec(F).Handle, N * FileRec(F).RecSize, 0) < 0 then
      InOutRes := ErrnoToIO;
end;

function ODIN_FILE_POS(var F): Int64;
begin
  ODIN_FILE_POS := 0;
  if FileOpen(F) then
    ODIN_FILE_POS := c_lseek(FileRec(F).Handle, 0, 1) div FileRec(F).RecSize;
end;

function ODIN_FILE_SIZE(var F): Int64;
var
  Cur, Last: Int64;
begin
  ODIN_FILE_SIZE := 0;
  if FileOpen(F) then
  begin
    Cur := c_lseek(FileRec(F).Handle, 0, 1);
    Last := c_lseek(FileRec(F).Handle, 0, 2);
    Cur := c_lseek(FileRec(F).Handle, Cur, 0);
    ODIN_FILE_SIZE := Last div FileRec(F).RecSize;
  end;
end;

function ODIN_FILE_EOF(var F): Boolean;
begin
  ODIN_FILE_EOF := True;
  if FileOpen(F) then
    ODIN_FILE_EOF := ODIN_FILE_POS(F) >= ODIN_FILE_SIZE(F);
end;

procedure ODIN_FILE_TRUNCATE(var F);
begin
  if FileOpen(F) then
    if c_ftruncate(FileRec(F).Handle, c_lseek(FileRec(F).Handle, 0, 1)) <> 0 then
      InOutRes := ErrnoToIO;
end;

{ ---- Str -------------------------------------------------------------------- }

procedure StoreStr(const R: String; var S; MaxLen: LongInt);
var
  P: PByteArray;
  N, I: LongInt;
begin
  P := PByteArray(@S);
  N := Length(R);
  if N > MaxLen then
    N := MaxLen;
  for I := 1 to N do
    P^[I] := Ord(R[I]);
  P^[0] := N;
end;

procedure ODIN_STR_INT(V: Int64; Width: LongInt; var S; MaxLen: LongInt);
var
  R: String;
begin
  IntToStr(V, R);
  while Length(R) < Width do
    R := ' ' + R;
  StoreStr(R, S, MaxLen);
end;

procedure ODIN_STR_REAL(V: Real; Width, Decimals: LongInt; var S; MaxLen: LongInt);
var
  R: String;
begin
  RealToStr(V, Width, Decimals, R);
  while Length(R) < Width do
    R := ' ' + R;
  StoreStr(R, S, MaxLen);
end;

end.
