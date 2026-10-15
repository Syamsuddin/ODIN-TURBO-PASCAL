{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bagian unit System: dukungan debugger untuk build --debug. Program
  berbicara dengan `odinpc debug` lewat Unix socket ($ODIN_DEBUG_SOCKET) dan
  berbagi memori ($ODIN_DEBUG_SHM) berisi flag langkah, pause, dan
  breakpoint. Protokolnya ada di rtl/COMPILER_INTERFACE.md. Tanpa kedua
  variabel lingkungan itu, program berjalan biasa. }

type
{$IFDEF DARWIN}
  TSockAddrUn = record
    Len, Family: Byte;
    Path: array[0..103] of Char;
  end;
{$ELSE}
  { Linux has no sun_len: the family is 16 bits and the path 108 bytes. }
  TSockAddrUn = record
    Family: Word;
    Path: array[0..107] of Char;
  end;
{$ENDIF}

function c_getenv(Name: PChar): PChar; cdecl; external 'c' name 'getenv';
function c_socket(Domain, Kind, Protocol: LongInt): LongInt; cdecl; external 'c' name 'socket';
function c_connect(Fd: LongInt; Addr: Pointer; Len: LongInt): LongInt; cdecl; external 'c' name 'connect';
function c_mmap(Addr: Pointer; Len: Int64; Prot, Flags, Fd: LongInt; Offset: Int64): Pointer; cdecl;
  external 'c' name 'mmap';
function c_pipe(Fds: Pointer): LongInt; cdecl; external 'c' name 'pipe';
function c_fcntl(Fd, Cmd, Arg: LongInt): LongInt; cdecl; external 'c' name 'fcntl';
function c_dbgsignal(Sig: LongInt; Handler: Pointer): Pointer; cdecl; external 'c' name 'signal';

const
  { program -> debugger }
  DbgHello = 1;
  DbgStop = 2;
  DbgRtErr = 3;
  DbgExit = 4;
  DbgData = 5;
  DbgAck = 6;
  { debugger -> program }
  DbgResume = 1;
  DbgRead = 2;
  DbgWrite = 3;
  { resume modes }
  StepRun = 0;
  StepInto = 1;
  StepOver = 2;
  StepOut = 3;
  { stop reasons }
  StopEntry = 0;
  StopPause = 1;
  StopBreak = 2;
  StopStep = 3;
  DbgProtocol = 1;
  DbgChunk = 4096;
  SocketVar: array[0..17] of Char = 'ODIN_DEBUG_SOCKET'#0;
  ShmVar: array[0..14] of Char = 'ODIN_DEBUG_SHM'#0;

var
  DbgActive: Boolean;
  DbgSocket: LongInt;
  DbgPipe: array[0..1] of LongInt;
  DbgMode: Byte;
  DbgTarget: LongInt;
  DbgBuf: array[0..DbgChunk + 15] of Byte;

procedure DbgSendRaw(P: PByteArray; N: Int64);
var
  Done, R: Int64;
begin
  Done := 0;
  while DbgActive and (Done < N) do
  begin
    R := c_write(DbgSocket, @P^[Done], N - Done);
    if R > 0 then
      Done := Done + R
    else if (R < 0) and (c_errno^ = EINTR) then
    else
      DbgActive := False;
  end;
end;

{ One frame: kind byte, 32-bit little-endian payload length, payload. }
procedure DbgSend(Kind: Byte; P: Pointer; N: LongInt);
var
  Head: array[0..4] of Byte;
begin
  Head[0] := Kind;
  Move(N, Head[1], 4);
  DbgSendRaw(@Head, 5);
  if N > 0 then
    DbgSendRaw(P, N);
end;

function DbgRecv(P: PByteArray; N: Int64): Boolean;
var
  Done, R: Int64;
begin
  Done := 0;
  while DbgActive and (Done < N) do
  begin
    R := c_read(DbgSocket, @P^[Done], N - Done);
    if R > 0 then
      Done := Done + R
    else if (R < 0) and (c_errno^ = EINTR) then
    else
      DbgActive := False;
  end;
  DbgRecv := DbgActive;
end;

{ Copies N bytes through a pipe: a bad address makes the kernel answer
  EFAULT instead of crashing the program. }
function SafeCopy(Src, Dst: Pointer; N: LongInt): Boolean;
var
  W, R: Int64;
  Junk: array[0..255] of Byte;
begin
  SafeCopy := N = 0;
  if N <= 0 then
    Exit;
  W := c_write(DbgPipe[1], Src, N);
  if W <= 0 then
    Exit;
  R := c_read(DbgPipe[0], Dst, W);
  SafeCopy := (W = N) and (R = W);
  { The read end does not block: drop whatever an EFAULT left behind. }
  while c_read(DbgPipe[0], @Junk, SizeOf(Junk)) > 0 do;
end;

{ Answers READ and WRITE until the debugger says RESUME. }
procedure DbgServe;
var
  Head: array[0..4] of Byte;
  Len, N: LongInt;
  Addr: Int64;
  Status: Byte;
begin
  while DbgActive do
  begin
    if not DbgRecv(@Head, 5) then
      Exit;
    Move(Head[1], Len, 4);
    if (Len < 0) or (Len > SizeOf(DbgBuf)) then
    begin
      DbgActive := False;
      Exit;
    end;
    if (Len > 0) and not DbgRecv(@DbgBuf, Len) then
      Exit;
    case Head[0] of
      DbgResume:
        begin
          DbgMode := DbgBuf[0];
          Move(DbgBuf[1], DbgTarget, 4);
          if DbgMode = StepRun then
            ODIN_DBG_SHARED^[0] := 0
          else
            ODIN_DBG_SHARED^[0] := 1;
          Exit;
        end;
      DbgRead:
        begin
          Move(DbgBuf[0], Addr, 8);
          Move(DbgBuf[8], N, 4);
          if (N < 0) or (N > DbgChunk) then
            N := 0;
          if SafeCopy(Pointer(Addr), @DbgBuf[1], N) then
            DbgBuf[0] := 0
          else
          begin
            DbgBuf[0] := 1;
            N := 0;
          end;
          DbgSend(DbgData, @DbgBuf, N + 1);
        end;
      DbgWrite:
        begin
          Move(DbgBuf[0], Addr, 8);
          if SafeCopy(@DbgBuf[8], Pointer(Addr), Len - 8) then
            Status := 0
          else
            Status := 1;
          DbgSend(DbgAck, @Status, 1);
        end;
    end;
  end;
end;

procedure DbgStopAt(Id: LongInt; Reason: Byte);
var
  P: array[0..8] of Byte;
begin
  { The user screen shows everything written so far. }
  if (Output.Mode = fmOutput) and (Output.BufPos > 0) then
    FlushText(Output);
  Move(Id, P[0], 4);
  Move(ODIN_DBG_DEPTH, P[4], 4);
  P[8] := Reason;
  DbgSend(DbgStop, @P, 9);
  DbgServe;
end;

procedure ODIN_DBG_HOOK(Id: LongInt);
var
  Reason: Byte;
begin
  if not DbgActive then
    Exit;
  Reason := StopEntry;
  if ODIN_DBG_SHARED^[1] <> 0 then
  begin
    ODIN_DBG_SHARED^[1] := 0;
    Reason := StopPause;
  end
  else if ODIN_DBG_SHARED^[16 + Id] <> 0 then
    Reason := StopBreak
  else
    case DbgMode of
      StepInto:
        Reason := StopStep;
      StepOver:
        if ODIN_DBG_DEPTH <= DbgTarget then
          Reason := StopStep;
      StepOut:
        if ODIN_DBG_DEPTH < DbgTarget then
          Reason := StopStep;
    end;
  if Reason <> StopEntry then
    DbgStopAt(Id, Reason);
end;

{ Ctrl-C in the user screen pauses at the next statement. }
procedure DbgInterrupt(Sig: LongInt);
begin
  if ODIN_DBG_SHARED <> nil then
    ODIN_DBG_SHARED^[1] := 1;
end;

procedure ODIN_DBG_INIT(LineCount: LongInt);
const
{$IFDEF DARWIN}
  O_NONBLOCK = 4;
{$ELSE}
  O_NONBLOCK = $800;
{$ENDIF}
  F_SETFL = 4;
  PROT_RW = 3;
  MAP_SHARED = 1;
  AF_UNIX = 1;
  SOCK_STREAM = 1;
  SIGINT = 2;
var
  SockPath, ShmPath: PChar;
  Addr: TSockAddrUn;
  Fd, I: LongInt;
  Map: Pointer;
  Hello: array[0..17] of Byte;
  Proto: Word;
  A: Int64;
begin
  SockPath := c_getenv(@SocketVar);
  ShmPath := c_getenv(@ShmVar);
  if (SockPath = nil) or (ShmPath = nil) then
    Exit;
  Fd := c_open(ShmPath, O_RDWR, 0);
  if Fd < 0 then
    Exit;
  Map := c_mmap(nil, 16 + Int64(LineCount), PROT_RW, MAP_SHARED, Fd, 0);
  c_close(Fd);
  if Int64(Map) = -1 then
    Exit;
  FillChar(Addr, SizeOf(Addr), 0);
{$IFDEF DARWIN}
  Addr.Len := SizeOf(Addr);
{$ENDIF}
  Addr.Family := AF_UNIX;
  I := 0;
  while (SockPath[I] <> #0) and (I < 103) do
  begin
    Addr.Path[I] := SockPath[I];
    Inc(I);
  end;
  DbgSocket := c_socket(AF_UNIX, SOCK_STREAM, 0);
  if (DbgSocket < 0) or (c_connect(DbgSocket, @Addr, SizeOf(Addr)) <> 0) then
    Exit;
  if c_pipe(@DbgPipe) <> 0 then
    Exit;
  c_fcntl(DbgPipe[0], F_SETFL, O_NONBLOCK);
  ODIN_DBG_SHARED := Map;
  DbgActive := True;
  c_dbgsignal(SIGINT, @DbgInterrupt);
  Proto := DbgProtocol;
  Move(Proto, Hello[0], 2);
  A := Int64(@ODIN_DBG_LINE);
  Move(A, Hello[2], 8);
  A := Int64(@ODIN_DBG_STACK);
  Move(A, Hello[10], 8);
  DbgSend(DbgHello, @Hello, 18);
  { Breakpoints arrive in shared memory; wait for the first RESUME. }
  DbgServe;
end;

{ Called by RunErrorAt: tells the debugger where the program failed. }
procedure DbgRuntimeError(Code: LongInt; Addr: Pointer);
var
  P: array[0..15] of Byte;
  A: Int64;
begin
  if not DbgActive then
    Exit;
  A := Int64(Addr);
  Move(Code, P[0], 4);
  Move(A, P[4], 8);
  Move(ODIN_DBG_LINE, P[12], 4);
  DbgSend(DbgRtErr, @P, 16);
end;

{ Called by DoExit just before the process ends. }
procedure DbgExitCode(Code: LongInt);
begin
  if DbgActive then
    DbgSend(DbgExit, @Code, 4);
  DbgActive := False;
end;

{$IFDEF DARWIN}
function c_image_header(Index: LongInt): Pointer; cdecl; external 'c' name '_dyld_get_image_header';
{$ELSE}
function ODIN_IMAGEBASE: Pointer; external 'odinrtl' name 'ODIN_IMAGEBASE';
{$ENDIF}

{ Called by RunErrorAt. When $ODIN_ERROR_FILE names a file (the IDE sets it
  for Run), writes "code address header" there in decimal: with the
  program's load address the IDE finds the source line in NAME.odbg. }
procedure ReportErrorFile(Code: LongInt; Addr: Pointer);
const
  ErrorVar: array[0..15] of Char = 'ODIN_ERROR_FILE'#0;
var
  Path: PChar;
  Fd: LongInt;
  S, T: String;
  Header: Int64;
begin
  Path := c_getenv(@ErrorVar);
  if Path = nil then
    Exit;
{$IFDEF DARWIN}
  Header := Int64(c_image_header(0));
{$ELSE}
  Header := Int64(ODIN_IMAGEBASE);
{$ENDIF}
  IntToStr(Code, S);
  IntToStr(Int64(Addr), T);
  S := S + ' ' + T;
  IntToStr(Header, T);
  S := S + ' ' + T + #10;
  Fd := c_open(Path, O_WRONLY or O_CREAT or O_TRUNC, 420);
  if Fd >= 0 then
  begin
    c_write(Fd, @S[1], Length(S));
    c_close(Fd);
  end;
end;
