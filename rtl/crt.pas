{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Crt dari runtime library Odin untuk terminal ANSI/xterm di macOS.
  Implementasi clean-room berdasarkan dokumentasi publik API Turbo Pascal 7.
  Crt menyimpan salinan layar (karakter dan atribut) supaya Window, InsLine,
  DelLine, dan scroll bisa digambar ulang. Output diproses lewat hook
  FlushFunc milik Output; Input dibaca lewat editor baris milik Crt saat
  stdin adalah terminal. Kontrak hook ada di rtl/COMPILER_INTERFACE.md. }
unit Crt;

{$R-,Q-,I-,X+}

interface

const
  BW40 = 0;
  CO40 = 1;
  BW80 = 2;
  CO80 = 3;
  Mono = 7;
  Font8x8 = 256;
  C40 = CO40;
  C80 = CO80;

  Black = 0;
  Blue = 1;
  Green = 2;
  Cyan = 3;
  Red = 4;
  Magenta = 5;
  Brown = 6;
  LightGray = 7;
  DarkGray = 8;
  LightBlue = 9;
  LightGreen = 10;
  LightCyan = 11;
  LightRed = 12;
  LightMagenta = 13;
  Yellow = 14;
  White = 15;
  Blink = 128;

var
  CheckBreak: Boolean;
  CheckEOF: Boolean;
  DirectVideo: Boolean;
  CheckSnow: Boolean;
  LastMode: Word;
  TextAttr: Byte;
  WindMin: Word;
  WindMax: Word;

procedure AssignCrt(var F: Text);
function KeyPressed: Boolean;
function ReadKey: Char;
procedure TextMode(Mode: Integer);
procedure Window(X1, Y1, X2, Y2: Byte);
procedure GotoXY(X, Y: Byte);
function WhereX: Byte;
function WhereY: Byte;
procedure ClrScr;
procedure ClrEol;
procedure InsLine;
procedure DelLine;
procedure TextColor(Color: Byte);
procedure TextBackground(Color: Byte);
procedure LowVideo;
procedure HighVideo;
procedure NormVideo;
procedure Delay(MS: Word);
procedure Sound(Hz: Word);
procedure NoSound;

implementation

type
{$IFDEF DARWIN}
  { struct termios (macOS 64-bit: tcflag_t and speed_t are 8 bytes) }
  TTermios = record
    IFlag, OFlag, CFlag, LFlag: Int64;
    CC: array[0..19] of Byte;
    ISpeed, OSpeed: Int64;
  end;
{$ELSE}
  { struct termios (glibc): 32-bit flags, c_line, 32 control characters }
  TTermios = record
    IFlag, OFlag, CFlag, LFlag: LongInt;
    Line: Byte;
    CC: array[0..31] of Byte;
    ISpeed, OSpeed: LongInt;
  end;
{$ENDIF}

  TWinSize = record
    Row, Col, XPixel, YPixel: Word;
  end;

  TPollFd = record
    Fd: LongInt;
    Events, REvents: SmallInt;
  end;

  TTimeSpec = record
    Sec, NSec: Int64;
  end;

function c_write(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'write';
function c_read(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'read';
function c_isatty(Fd: LongInt): LongInt; cdecl; external 'c' name 'isatty';
function c_tcgetattr(Fd: LongInt; var T: TTermios): LongInt; cdecl; external 'c' name 'tcgetattr';
function c_tcsetattr(Fd, Action: LongInt; var T: TTermios): LongInt; cdecl; external 'c' name 'tcsetattr';
function c_ioctl(Fd: LongInt; Request: Int64; Arg: Pointer): LongInt; cdecl; external 'c' name 'ioctl';
function c_poll(var Fds: TPollFd; NFds: LongInt; Timeout: LongInt): LongInt; cdecl; external 'c' name 'poll';
function c_nanosleep(var Req: TTimeSpec; Rem: Pointer): LongInt; cdecl; external 'c' name 'nanosleep';
function c_signal(Sig: LongInt; Handler: Pointer): Pointer; cdecl; external 'c' name 'signal';
function c_raise(Sig: LongInt): LongInt; cdecl; external 'c' name 'raise';
{$IFDEF DARWIN}
function c_errno: PLongInt; cdecl; external 'c' name '__error';
{$ELSE}
function c_errno: PLongInt; cdecl; external 'c' name '__errno_location';
{$ENDIF}

const
  MaxCols = 255;
  MaxRows = 255;
  QueueSize = 256;

  ICRNL = $100;
  ECHO = $8;
  TCSANOW = 0;
{$IFDEF DARWIN}
  IXON = $200;
  ISIG = $80;
  ICANON = $100;
  IEXTEN = $400;
  VMIN = 16;
  VTIME = 17;
  TIOCGWINSZ = $40087468;
{$ELSE}
  IXON = $400;
  ISIG = $1;
  ICANON = $2;
  IEXTEN = $8000;
  VMIN = 6;
  VTIME = 5;
  TIOCGWINSZ = $5413;
{$ENDIF}
  POLLIN = 1;
  EINTR = 4;
  SIGHUP = 1;
  SIGINT = 2;
  SIGQUIT = 3;
  SIGTERM = 15;

  { DOS color number -> ANSI color digit }
  AnsiColor: array[0..7] of Char = '04261537';
  { TP scan codes for Alt+A .. Alt+Z }
  AltLetter: array[0..25] of Byte = (30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19,
    31, 20, 22, 47, 17, 45, 21, 44);

var
  Cells: array[0..MaxRows - 1, 0..MaxCols - 1] of Word;   { char or attr shl 8 }
  Cols, Rows: Integer;
  CurX, CurY: Integer;          { Crt cursor, 0-based screen position }
  TermX, TermY: Integer;        { terminal cursor; -1 when unknown }
  TermAttr: Integer;            { attribute last sent; -1 when unknown }
  NormAttr: Byte;
  Utf8Left: Integer;            { continuation bytes still to come }
  OutBuf: array[0..4095] of Char;
  OutLen: Integer;
  Queue: array[0..QueueSize - 1] of Char;
  QueueHead, QueueCount: Integer;
  PendingScan: Char;
  HasPending: Boolean;
  InTty, OutTty, RawMode: Boolean;
  Saved: TTermios;
  OldExitProc: Pointer;

{ ---- terminal output ------------------------------------------------------ }

procedure FlushOut;
var
  Done, N: Int64;
begin
  Done := 0;
  while Done < OutLen do
  begin
    N := c_write(1, @OutBuf[Done], OutLen - Done);
    if N <= 0 then
      Done := OutLen
    else
      Done := Done + N;
  end;
  OutLen := 0;
end;

procedure Emit(C: Char);
begin
  if OutLen = SizeOf(OutBuf) then
    FlushOut;
  OutBuf[OutLen] := C;
  Inc(OutLen);
end;

procedure EmitStr(const S: String);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    Emit(S[I]);
end;

procedure EmitCsi(N: Integer);
var
  S: String;
begin
  Str(N, S);
  Emit(#27);
  Emit('[');
  EmitStr(S);
end;

procedure MoveTo(X, Y: Integer);
var
  S: String;
begin
  if (X = TermX) and (Y = TermY) then
    Exit;
  EmitCsi(Y + 1);
  Str(X + 1, S);
  Emit(';');
  EmitStr(S);
  Emit('H');
  TermX := X;
  TermY := Y;
end;

procedure SetAttr(A: Byte);
begin
  if A = TermAttr then
    Exit;
  Emit(#27);
  EmitStr('[0;');
  if A and 8 <> 0 then
    Emit('9')
  else
    Emit('3');
  Emit(AnsiColor[A and 7]);
  EmitStr(';4');
  Emit(AnsiColor[(A shr 4) and 7]);
  if A and $80 <> 0 then
    EmitStr(';5');
  Emit('m');
  TermAttr := A;
end;

{ Writes one cell at the terminal cursor, which must be at (X, Y). }
procedure EmitCell(X: Integer; C: Char);
begin
  if C < ' ' then
    C := ' ';
  Emit(C);
  if X + 1 >= Cols then
    TermX := -1
  else
    TermX := X + 1;
end;

procedure PutCell(X, Y: Integer; C: Char; A: Byte);
begin
  Cells[Y, X] := Ord(C) or (Word(A) shl 8);
  MoveTo(X, Y);
  SetAttr(A);
  EmitCell(X, C);
end;

procedure RedrawRow(Y, X1, X2: Integer);
var
  X: Integer;
  W: Word;
begin
  for X := X1 to X2 do
  begin
    W := Cells[Y, X];
    MoveTo(X, Y);
    SetAttr(W shr 8);
    EmitCell(X, Chr(W and $FF));
  end;
end;

function FullWidth: Boolean;
begin
  FullWidth := (Lo(WindMin) = 0) and (Lo(WindMax) = Cols - 1);
end;

{ Moves window rows Y1..Y2 one line up (Up) or down; the freed row is
  blank in TextAttr. }
procedure ShiftRows(Y1, Y2: Integer; Up: Boolean);
var
  X, Y, X1, X2: Integer;
  Blank: Word;
begin
  X1 := Lo(WindMin);
  X2 := Lo(WindMax);
  Blank := Ord(' ') or (Word(TextAttr) shl 8);
  if Up then
  begin
    for Y := Y1 to Y2 - 1 do
      for X := X1 to X2 do
        Cells[Y, X] := Cells[Y + 1, X];
    for X := X1 to X2 do
      Cells[Y2, X] := Blank;
  end
  else
  begin
    for Y := Y2 downto Y1 + 1 do
      for X := X1 to X2 do
        Cells[Y, X] := Cells[Y - 1, X];
    for X := X1 to X2 do
      Cells[Y1, X] := Blank;
  end;
end;

{ Shows the result of ShiftRows. A full-width window lets the terminal
  move the lines inside a scroll region; otherwise the rows are redrawn. }
procedure WriteRegion(Y1, Y2: Integer; Up: Boolean);
var
  S: String;
  Y: Integer;
begin
  if FullWidth and (Y1 < Y2) then
  begin
    SetAttr(TextAttr);
    Str(Y1 + 1, S);
    Emit(#27);
    Emit('[');
    EmitStr(S);
    Emit(';');
    Str(Y2 + 1, S);
    EmitStr(S);
    Emit('r');
    TermX := -1;
    TermY := -1;
    MoveTo(0, Y1);
    Emit(#27);
    Emit('[');
    if Up then
      Emit('M')
    else
      Emit('L');
    Emit(#27);
    EmitStr('[r');
    TermX := -1;
    TermY := -1;
  end
  else
    for Y := Y1 to Y2 do
      RedrawRow(Y, Lo(WindMin), Lo(WindMax));
end;

procedure LineFeed;
begin
  if CurY < Hi(WindMax) then
    Inc(CurY)
  else
  begin
    ShiftRows(Hi(WindMin), Hi(WindMax), True);
    WriteRegion(Hi(WindMin), Hi(WindMax), True);
  end;
end;

procedure WriteChar(C: Char);
begin
  if (Utf8Left > 0) and (C >= #$80) and (C <= #$BF) then
  begin
    { The rest of a UTF-8 character takes no column of its own. }
    Emit(C);
    Dec(Utf8Left);
    Exit;
  end;
  Utf8Left := 0;
  case C of
    #7:
      Emit(#7);
    #8:
      if CurX > Lo(WindMin) then
        Dec(CurX);
    #10:
      begin
        CurX := Lo(WindMin);
        LineFeed;
      end;
    #13:
      CurX := Lo(WindMin);
  else
    PutCell(CurX, CurY, C, TextAttr);
    if (C >= #$C0) and (C <= #$DF) then
      Utf8Left := 1
    else if (C >= #$E0) and (C <= #$EF) then
      Utf8Left := 2
    else if (C >= #$F0) and (C <= #$F7) then
      Utf8Left := 3;
    Inc(CurX);
    if CurX > Lo(WindMax) then
    begin
      CurX := Lo(WindMin);
      LineFeed;
    end;
  end;
end;

{ Leaves the terminal cursor at the Crt cursor and sends everything. }
procedure Show;
begin
  MoveTo(CurX, CurY);
  FlushOut;
end;

{ FlushFunc of a Crt output file. }
procedure CrtOut(var F: TextRec);
var
  I: LongInt;
begin
  for I := 0 to F.BufPos - 1 do
    WriteChar(F.Buffer[I]);
  F.BufPos := 0;
  Show;
end;

{ Text written to Output but not yet shown, when Output is not Crt's. }
procedure Sync;
begin
  if (TextRec(Output).Mode = fmOutput) and (TextRec(Output).BufPos > 0) then
    Flush(Output);
end;

{ ---- keyboard --------------------------------------------------------------- }

function Poll(Timeout: LongInt): Boolean;
var
  P: TPollFd;
begin
  P.Fd := 0;
  P.Events := POLLIN;
  P.REvents := 0;
  Poll := c_poll(P, 1, Timeout) > 0;
end;

function ByteReady(Timeout: LongInt): Boolean;
begin
  ByteReady := (QueueCount > 0) or Poll(Timeout);
end;

procedure PushBack(C: Char);
begin
  if QueueCount = QueueSize then
    Exit;
  QueueHead := (QueueHead + QueueSize - 1) mod QueueSize;
  Queue[QueueHead] := C;
  Inc(QueueCount);
end;

procedure Enqueue(C: Char);
begin
  if QueueCount = QueueSize then
    Exit;
  Queue[(QueueHead + QueueCount) mod QueueSize] := C;
  Inc(QueueCount);
end;

{ Next input byte; False at the end of the input. }
function NextByte(var C: Char): Boolean;
var
  N: Int64;
begin
  if QueueCount > 0 then
  begin
    C := Queue[QueueHead];
    QueueHead := (QueueHead + 1) mod QueueSize;
    Dec(QueueCount);
    NextByte := True;
    Exit;
  end;
  repeat
    N := c_read(0, @C, 1);
  until (N >= 0) or (c_errno^ <> EINTR);
  NextByte := N = 1;
end;

{ Decodes what follows Esc into a TP scan code, or 0 for a plain Esc. }
function EscapeKey: Byte;
var
  C, Final: Char;
  N: Integer;
  HasSemicolon: Boolean;
begin
  EscapeKey := 0;
  if not ByteReady(50) then
    Exit;
  if not NextByte(C) then
    Exit;
  if (C = '[') or (C = 'O') then
  begin
    N := 0;
    HasSemicolon := False;
    repeat
      if not ByteReady(50) then
        Exit;
      if not NextByte(Final) then
        Exit;
      if Final = ';' then
        HasSemicolon := True
      else if (Final >= '0') and (Final <= '9') and not HasSemicolon then
        N := N * 10 + Ord(Final) - Ord('0');
    until not (((Final >= '0') and (Final <= '9')) or (Final = ';'));
    case Final of
      'A': EscapeKey := 72;
      'B': EscapeKey := 80;
      'C': EscapeKey := 77;
      'D': EscapeKey := 75;
      'H': EscapeKey := 71;
      'F': EscapeKey := 79;
      'P': EscapeKey := 59;
      'Q': EscapeKey := 60;
      'R': EscapeKey := 61;
      'S': EscapeKey := 62;
      'Z': EscapeKey := 15;
      '~':
        case N of
          1, 7: EscapeKey := 71;
          2: EscapeKey := 82;
          3: EscapeKey := 83;
          4, 8: EscapeKey := 79;
          5: EscapeKey := 73;
          6: EscapeKey := 81;
          11..15: EscapeKey := 59 + N - 11;
          17..21: EscapeKey := 64 + N - 17;
          23: EscapeKey := 133;
          24: EscapeKey := 134;
        end;
    end;
    Exit;
  end;
  { Esc followed by a key is how terminals send Alt+key. }
  if (C >= 'a') and (C <= 'z') then
    EscapeKey := AltLetter[Ord(C) - Ord('a')]
  else if (C >= 'A') and (C <= 'Z') then
    EscapeKey := AltLetter[Ord(C) - Ord('A')]
  else if (C >= '1') and (C <= '9') then
    EscapeKey := 120 + Ord(C) - Ord('1')
  else if C = '0' then
    EscapeKey := 129
  else
    PushBack(C);
end;

function KeyPressed: Boolean;
begin
  Sync;
  KeyPressed := HasPending or ByteReady(0);
end;

function ReadKey: Char;
var
  C: Char;
  Code: Byte;
begin
  Sync;
  if HasPending then
  begin
    HasPending := False;
    ReadKey := PendingScan;
    Exit;
  end;
  if not NextByte(C) then
  begin
    ReadKey := #26;
    Exit;
  end;
  if C = #27 then
  begin
    Code := EscapeKey;
    if Code <> 0 then
    begin
      PendingScan := Chr(Code);
      HasPending := True;
      C := #0;
    end;
  end
  else if C = #127 then
    C := #8;
  ReadKey := C;
end;

{ FlushFunc of a Crt input file: a line editor with echo. }
procedure CrtIn(var F: TextRec);
var
  C: Char;
  N: LongInt;
  Done: Boolean;
begin
  N := 0;
  Done := False;
  while not Done do
  begin
    C := ReadKey;
    case C of
      #0:
        ReadKey;
      #8:
        if N > 0 then
        begin
          Dec(N);
          if CurX > Lo(WindMin) then
            Dec(CurX)
          else if CurY > Hi(WindMin) then
          begin
            Dec(CurY);
            CurX := Lo(WindMax);
          end;
          PutCell(CurX, CurY, ' ', TextAttr);
        end;
      #10, #13:
        begin
          F.Buffer[N] := #10;
          Inc(N);
          WriteChar(#10);
          Done := True;
        end;
      #4, #26:
        if N = 0 then
          Done := True;
    else
      if (C >= ' ') and (N < F.BufSize - 1) then
      begin
        F.Buffer[N] := C;
        Inc(N);
        WriteChar(C);
      end;
    end;
    Show;
  end;
  F.BufEnd := N;
end;

{ ---- terminal modes ---------------------------------------------------------- }

procedure EnterRaw;
var
  T: TTermios;
begin
  if c_tcgetattr(0, Saved) <> 0 then
  begin
    InTty := False;
    Exit;
  end;
  T := Saved;
  T.IFlag := T.IFlag and not (ICRNL or IXON);
  T.LFlag := T.LFlag and not (ICANON or ECHO or IEXTEN);
  T.CC[VMIN] := 1;
  T.CC[VTIME] := 0;
  c_tcsetattr(0, TCSANOW, T);
  RawMode := True;
end;

procedure LeaveRaw;
begin
  if RawMode then
    c_tcsetattr(0, TCSANOW, Saved);
  RawMode := False;
end;

{ Ctrl-C and friends: give the terminal back, then die from the signal. }
procedure OnSignal(Sig: LongInt);
const
  Reset: array[0..3] of Char = #27'[0m';
begin
  LeaveRaw;
  c_write(1, @Reset, 4);
  c_signal(Sig, nil);
  c_raise(Sig);
end;

{ Installs OnSignal unless the signal is already handled (the debugger
  pauses on Ctrl-C) or ignored. }
procedure Catch(Sig: LongInt);
var
  Old: Pointer;
begin
  Old := c_signal(Sig, @OnSignal);
  if Old <> nil then
    c_signal(Sig, Old);
end;

{ Asks the terminal where the cursor is (ESC [ 6 n). Keys typed meanwhile
  stay queued for ReadKey. }
function QueryCursor: Boolean;
const
  Ask: array[0..3] of Char = #27'[6n';
var
  S: String;
  C: Char;
  P, I, Row, Col: Integer;
  Semi: Boolean;
begin
  QueryCursor := False;
  c_write(1, @Ask, 4);
  S := '';
  while (Length(S) < 255) and Poll(200) do
  begin
    if c_read(0, @C, 1) <> 1 then
      Break;
    S := S + C;
    if C = 'R' then
    begin
      P := Length(S);
      while (P > 0) and (S[P] <> #27) do
        Dec(P);
      if (P > 0) and (P + 1 < Length(S)) and (S[P + 1] = '[') then
      begin
        Row := 0;
        Col := 0;
        Semi := False;
        for I := P + 2 to Length(S) - 1 do
          if S[I] = ';' then
            Semi := True
          else if Semi then
            Col := Col * 10 + Ord(S[I]) - Ord('0')
          else
            Row := Row * 10 + Ord(S[I]) - Ord('0');
        if Semi and (Row > 0) and (Col > 0) then
        begin
          for I := 1 to P - 1 do
            Enqueue(S[I]);
          if Row > Rows then
            Row := Rows;
          if Col > Cols then
            Col := Cols;
          CurY := Row - 1;
          CurX := Col - 1;
          QueryCursor := True;
          Exit;
        end;
      end;
    end;
  end;
  for I := 1 to Length(S) do
    Enqueue(S[I]);
end;

{ ---- the TP7 Crt routines -------------------------------------------------- }

procedure AssignCrt(var F: Text);
begin
  Assign(F, '');
  TextRec(F).FlushFunc := @CrtOut;
end;

procedure AssignCrtInput(var F: Text);
begin
  Assign(F, '');
  TextRec(F).FlushFunc := @CrtIn;
end;

procedure TextMode(Mode: Integer);
begin
  Sync;
  LastMode := Mode;
  WindMin := 0;
  WindMax := (Cols - 1) or ((Rows - 1) shl 8);
  TextAttr := NormAttr;
  ClrScr;
end;

procedure Window(X1, Y1, X2, Y2: Byte);
begin
  if (X1 < 1) or (Y1 < 1) or (X1 > X2) or (Y1 > Y2) or (X2 > Cols) or (Y2 > Rows) then
    Exit;
  WindMin := (X1 - 1) or ((Y1 - 1) shl 8);
  WindMax := (X2 - 1) or ((Y2 - 1) shl 8);
  GotoXY(1, 1);
end;

procedure GotoXY(X, Y: Byte);
begin
  Sync;
  if (X < 1) or (Y < 1) or (X - 1 > Lo(WindMax) - Lo(WindMin)) or (Y - 1 > Hi(WindMax) - Hi(WindMin)) then
    Exit;
  CurX := Lo(WindMin) + X - 1;
  CurY := Hi(WindMin) + Y - 1;
  Show;
end;

function WhereX: Byte;
begin
  WhereX := CurX - Lo(WindMin) + 1;
end;

function WhereY: Byte;
begin
  WhereY := CurY - Hi(WindMin) + 1;
end;

procedure ClrScr;
var
  X, Y: Integer;
  Blank: Word;
begin
  Sync;
  Blank := Ord(' ') or (Word(TextAttr) shl 8);
  for Y := Hi(WindMin) to Hi(WindMax) do
    for X := Lo(WindMin) to Lo(WindMax) do
      Cells[Y, X] := Blank;
  SetAttr(TextAttr);
  if FullWidth and (Hi(WindMin) = 0) and (Hi(WindMax) = Rows - 1) then
  begin
    Emit(#27);
    EmitStr('[2J');
  end
  else
    for Y := Hi(WindMin) to Hi(WindMax) do
      if Lo(WindMax) = Cols - 1 then
      begin
        MoveTo(Lo(WindMin), Y);
        Emit(#27);
        EmitStr('[K');
      end
      else
        RedrawRow(Y, Lo(WindMin), Lo(WindMax));
  CurX := Lo(WindMin);
  CurY := Hi(WindMin);
  Show;
end;

procedure ClrEol;
var
  X: Integer;
begin
  Sync;
  for X := CurX to Lo(WindMax) do
    Cells[CurY, X] := Ord(' ') or (Word(TextAttr) shl 8);
  SetAttr(TextAttr);
  if Lo(WindMax) = Cols - 1 then
  begin
    MoveTo(CurX, CurY);
    Emit(#27);
    EmitStr('[K');
  end
  else
    RedrawRow(CurY, CurX, Lo(WindMax));
  Show;
end;

procedure InsLine;
begin
  Sync;
  ShiftRows(CurY, Hi(WindMax), False);
  WriteRegion(CurY, Hi(WindMax), False);
  Show;
end;

procedure DelLine;
begin
  Sync;
  ShiftRows(CurY, Hi(WindMax), True);
  WriteRegion(CurY, Hi(WindMax), True);
  Show;
end;

procedure TextColor(Color: Byte);
begin
  TextAttr := (TextAttr and $70) or (Color and $8F);
end;

procedure TextBackground(Color: Byte);
begin
  TextAttr := (TextAttr and $8F) or ((Color and 7) shl 4);
end;

procedure LowVideo;
begin
  TextAttr := TextAttr and $F7;
end;

procedure HighVideo;
begin
  TextAttr := TextAttr or $08;
end;

procedure NormVideo;
begin
  TextAttr := NormAttr;
end;

procedure Delay(MS: Word);
var
  T: TTimeSpec;
begin
  Sync;
  T.Sec := MS div 1000;
  T.NSec := Int64(MS mod 1000) * 1000000;
  while (c_nanosleep(T, @T) <> 0) and (c_errno^ = EINTR) do;
end;

{ There is no PC speaker to drive. }
procedure Sound(Hz: Word);
begin
end;

procedure NoSound;
begin
end;

{ ---- start and end ------------------------------------------------------------ }

procedure CrtExit;
begin
  ExitProc := OldExitProc;
  if TermAttr <> -1 then
  begin
    Emit(#27);
    EmitStr('[0m');
  end;
  FlushOut;
  LeaveRaw;
end;

procedure InitCrt;
var
  WS: TWinSize;
  X, Y: Integer;
begin
  CheckBreak := True;
  CheckEOF := False;
  DirectVideo := True;
  CheckSnow := False;
  LastMode := CO80;
  NormAttr := LightGray;
  TextAttr := NormAttr;
  InTty := c_isatty(0) <> 0;
  OutTty := c_isatty(1) <> 0;
  Cols := 80;
  Rows := 25;
  if OutTty and (c_ioctl(1, TIOCGWINSZ, @WS) = 0) and (WS.Col > 0) and (WS.Row > 0) then
  begin
    Cols := WS.Col;
    Rows := WS.Row;
  end;
  if Cols > MaxCols then
    Cols := MaxCols;
  if Rows > MaxRows then
    Rows := MaxRows;
  WindMin := 0;
  WindMax := (Cols - 1) or ((Rows - 1) shl 8);
  for Y := 0 to Rows - 1 do
    for X := 0 to Cols - 1 do
      Cells[Y, X] := Ord(' ') or (Word(NormAttr) shl 8);
  TermX := -1;
  TermY := -1;
  TermAttr := -1;
  CurX := 0;
  CurY := 0;
  if InTty then
  begin
    EnterRaw;
    Catch(SIGHUP);
    Catch(SIGINT);
    Catch(SIGQUIT);
    Catch(SIGTERM);
  end;
  if OutTty then
  begin
    { Without an answer, start at the top left corner, as FPC's Crt does. }
    if not (InTty and QueryCursor) then
    begin
      Emit(#27);
      EmitStr('[H');
      CurX := 0;
      CurY := 0;
    end;
    TermX := CurX;
    TermY := CurY;
  end;
  Sync;
  AssignCrt(Output);
  Rewrite(Output);
  if InTty then
  begin
    AssignCrtInput(Input);
    Reset(Input);
  end;
  OldExitProc := ExitProc;
  ExitProc := @CrtExit;
end;

begin
  InitCrt;
end.
