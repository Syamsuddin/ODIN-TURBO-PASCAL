{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Drivers dari Odin Vision: layar, keyboard, mouse, dan rutin string
  untuk aplikasi bergaya Turbo Vision di terminal ANSI/xterm. Implementasi
  clean-room berdasarkan dokumentasi API Turbo Vision TP7.

  Views menulis sel (karakter CP437 + atribut) ke ScreenBuffer; UpdateScreen
  hanya mengirim sel yang berubah ke terminal. Karakter CP437 diubah ke
  UTF-8. Input dibaca dari terminal dalam mode raw: tombol menjadi kode TP
  (scan shl 8 + karakter), klik mouse dari laporan SGR xterm (mode 1006). }
unit Drivers;

{$R-,Q-,I-,X+}

interface

uses Objects;

const
  { Event codes }
  evNothing = $0000;
  evMouseDown = $0001;
  evMouseUp = $0002;
  evMouseMove = $0004;
  evMouseAuto = $0008;
  evKeyDown = $0010;
  evCommand = $0100;
  evBroadcast = $0200;
  evMouse = $000F;
  evKeyboard = $0010;
  evMessage = $FF00;

  { Mouse buttons }
  mbLeftButton = $01;
  mbRightButton = $02;

  { Shift state }
  kbRightShift = $0001;
  kbLeftShift = $0002;
  kbCtrlShift = $0004;
  kbAltShift = $0008;
  kbScrollState = $0010;
  kbNumState = $0020;
  kbCapsState = $0040;
  kbInsState = $0080;

  { Key codes: scan code shl 8 + character (PC keyboard) }
  kbNoKey = $0000;
  kbEsc = $011B;
  kbAltSpace = $0200;
  kbCtrlIns = $0400;
  kbShiftIns = $0500;
  kbCtrlDel = $0600;
  kbShiftDel = $0700;
  kbAltBack = $0800;
  kbBack = $0E08;
  kbCtrlBack = $0E7F;
  kbShiftTab = $0F00;
  kbTab = $0F09;
  kbAltQ = $1000;
  kbAltW = $1100;
  kbAltE = $1200;
  kbAltR = $1300;
  kbAltT = $1400;
  kbAltY = $1500;
  kbAltU = $1600;
  kbAltI = $1700;
  kbAltO = $1800;
  kbAltP = $1900;
  kbCtrlEnter = $1C0A;
  kbEnter = $1C0D;
  kbAltA = $1E00;
  kbAltS = $1F00;
  kbAltD = $2000;
  kbAltF = $2100;
  kbAltG = $2200;
  kbAltH = $2300;
  kbAltJ = $2400;
  kbAltK = $2500;
  kbAltL = $2600;
  kbAltZ = $2C00;
  kbAltX = $2D00;
  kbAltC = $2E00;
  kbAltV = $2F00;
  kbAltB = $3000;
  kbAltN = $3100;
  kbAltM = $3200;
  kbF1 = $3B00;
  kbF2 = $3C00;
  kbF3 = $3D00;
  kbF4 = $3E00;
  kbF5 = $3F00;
  kbF6 = $4000;
  kbF7 = $4100;
  kbF8 = $4200;
  kbF9 = $4300;
  kbF10 = $4400;
  kbHome = $4700;
  kbUp = $4800;
  kbPgUp = $4900;
  kbGrayMinus = $4A2D;
  kbLeft = $4B00;
  kbRight = $4D00;
  kbGrayPlus = $4E2B;
  kbEnd = $4F00;
  kbDown = $5000;
  kbPgDn = $5100;
  kbIns = $5200;
  kbDel = $5300;
  kbShiftF1 = $5400;
  kbShiftF2 = $5500;
  kbShiftF3 = $5600;
  kbShiftF4 = $5700;
  kbShiftF5 = $5800;
  kbShiftF6 = $5900;
  kbShiftF7 = $5A00;
  kbShiftF8 = $5B00;
  kbShiftF9 = $5C00;
  kbShiftF10 = $5D00;
  kbCtrlF1 = $5E00;
  kbCtrlF2 = $5F00;
  kbCtrlF3 = $6000;
  kbCtrlF4 = $6100;
  kbCtrlF5 = $6200;
  kbCtrlF6 = $6300;
  kbCtrlF7 = $6400;
  kbCtrlF8 = $6500;
  kbCtrlF9 = $6600;
  kbCtrlF10 = $6700;
  kbAltF1 = $6800;
  kbAltF2 = $6900;
  kbAltF3 = $6A00;
  kbAltF4 = $6B00;
  kbAltF5 = $6C00;
  kbAltF6 = $6D00;
  kbAltF7 = $6E00;
  kbAltF8 = $6F00;
  kbAltF9 = $7000;
  kbAltF10 = $7100;
  kbCtrlPrtSc = $7200;
  kbCtrlLeft = $7300;
  kbCtrlRight = $7400;
  kbCtrlEnd = $7500;
  kbCtrlPgDn = $7600;
  kbCtrlHome = $7700;
  kbAlt1 = $7800;
  kbAlt2 = $7900;
  kbAlt3 = $7A00;
  kbAlt4 = $7B00;
  kbAlt5 = $7C00;
  kbAlt6 = $7D00;
  kbAlt7 = $7E00;
  kbAlt8 = $7F00;
  kbAlt9 = $8000;
  kbAlt0 = $8100;
  kbAltMinus = $8200;
  kbAltEqual = $8300;
  kbCtrlPgUp = $8400;
  kbF11 = $8500;
  kbF12 = $8600;
  kbCtrlUp = $8D00;
  kbCtrlDown = $9100;

  { Screen modes }
  smBW80 = $0002;
  smCO80 = $0003;
  smMono = $0007;
  smFont8x8 = $0100;

  MaxScreenWidth = 255;
  MaxScreenHeight = 255;

type
  PEvent = ^TEvent;
  TEvent = record
    What: Word;
    case Word of
      evNothing: ();
      evMouse: (
        Buttons: Byte;
        Double: Boolean;
        Where: TPoint);
      evKeyDown: (
        case Integer of
          0: (KeyCode: Word);
          1: (CharCode: Char; ScanCode: Byte));
      evMessage: (
        Command: Word;
        case Word of
          0: (InfoPtr: Pointer);
          1: (InfoLong: LongInt);
          2: (InfoWord: Word);
          3: (InfoInt: Integer);
          4: (InfoByte: Byte);
          5: (InfoChar: Char));
  end;

  PVideoBuf = ^TVideoBuf;
  TVideoBuf = array[0..MaxScreenWidth * MaxScreenHeight - 1] of Word;

  TSysErrorFunc = function(ErrorCode: Integer; Drive: Byte): Integer;

var
  { Event manager }
  MouseEvents: Boolean;
  MouseReverse: Boolean;
  DoubleDelay: Word;
  RepeatDelay: Word;
  MouseIntFlag: Byte;
  MouseButtons: Byte;
  MouseWhere: TPoint;
  ButtonCount: Byte;

  { Screen manager }
  StartupMode: Word;
  ScreenMode: Word;
  ScreenWidth: Word;
  ScreenHeight: Word;
  CheckSnow: Boolean;
  HiResScreen: Boolean;
  ScreenBuffer: PVideoBuf;
  CursorLines: Word;

  { System error handler }
  SysErrorFunc: TSysErrorFunc;
  SysColorAttr: Word;
  SysMonoAttr: Word;
  CtrlBreakHit: Boolean;
  SaveCtrlBreak: Boolean;
  SysErrActive: Boolean;
  FailSysErrors: Boolean;

procedure InitEvents;
procedure DoneEvents;
procedure ShowMouse;
procedure HideMouse;
procedure GetMouseEvent(var Event: TEvent);
procedure GetKeyEvent(var Event: TEvent);
function GetShiftState: Byte;

procedure InitVideo;
procedure DoneVideo;
procedure SetVideoMode(Mode: Word);
procedure ClearScreen;

procedure InitSysError;
procedure DoneSysError;

function GetAltChar(KeyCode: Word): Char;
function GetAltCode(Ch: Char): Word;
function GetCtrlChar(KeyCode: Word): Char;
function GetCtrlCode(Ch: Char): Word;
function CtrlToArrow(KeyCode: Word): Word;

function CStrLen(const S: String): Integer;
procedure MoveBuf(var Dest; var Source; Attr: Byte; Count: Word);
procedure MoveChar(var Dest; C: Char; Attr: Byte; Count: Word);
procedure MoveCStr(var Dest; const Str: String; Attrs: Word);
procedure MoveStr(var Dest; const Str: String; Attr: Byte);
procedure FormatStr(var Result: String; const Format: String; var Params);
procedure PrintStr(const S: String);

{ Odin additions used by Views and App. }
procedure UpdateScreen;
procedure SetCursorState(X, Y: Integer; Visible, Insert: Boolean);
procedure WaitForEvent(Milliseconds: LongInt);
function GetTicks: LongInt;

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

  TTimeVal = record
    Sec: Int64;
    USec: LongInt;
    Pad: LongInt;
  end;

function c_write(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'write';
function c_read(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'read';
function c_isatty(Fd: LongInt): LongInt; cdecl; external 'c' name 'isatty';
function c_tcgetattr(Fd: LongInt; var T: TTermios): LongInt; cdecl; external 'c' name 'tcgetattr';
function c_tcsetattr(Fd, Action: LongInt; var T: TTermios): LongInt; cdecl; external 'c' name 'tcsetattr';
function c_ioctl(Fd: LongInt; Request: Int64; Arg: Pointer): LongInt; cdecl; external 'c' name 'ioctl';
function c_poll(var Fds: TPollFd; NFds: LongInt; Timeout: LongInt): LongInt; cdecl; external 'c' name 'poll';
function c_gettimeofday(var TV: TTimeVal; TZ: Pointer): LongInt; cdecl; external 'c' name 'gettimeofday';
function c_signal(Sig: LongInt; Handler: Pointer): Pointer; cdecl; external 'c' name 'signal';
function c_raise(Sig: LongInt): LongInt; cdecl; external 'c' name 'raise';

const
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
  SIGHUP = 1;
  SIGINT = 2;
  SIGQUIT = 3;
  SIGTERM = 15;

  { Unicode code point of every CP437 character (#0 shows as a space). }
  CP437: array[0..255] of Word = (
    $0020, $263A, $263B, $2665, $2666, $2663, $2660, $2022, $25D8, $25CB, $25D9, $2642, $2640, $266A, $266B, $263C,
    $25BA, $25C4, $2195, $203C, $00B6, $00A7, $25AC, $21A8, $2191, $2193, $2192, $2190, $221F, $2194, $25B2, $25BC,
    $0020, $0021, $0022, $0023, $0024, $0025, $0026, $0027, $0028, $0029, $002A, $002B, $002C, $002D, $002E, $002F,
    $0030, $0031, $0032, $0033, $0034, $0035, $0036, $0037, $0038, $0039, $003A, $003B, $003C, $003D, $003E, $003F,
    $0040, $0041, $0042, $0043, $0044, $0045, $0046, $0047, $0048, $0049, $004A, $004B, $004C, $004D, $004E, $004F,
    $0050, $0051, $0052, $0053, $0054, $0055, $0056, $0057, $0058, $0059, $005A, $005B, $005C, $005D, $005E, $005F,
    $0060, $0061, $0062, $0063, $0064, $0065, $0066, $0067, $0068, $0069, $006A, $006B, $006C, $006D, $006E, $006F,
    $0070, $0071, $0072, $0073, $0074, $0075, $0076, $0077, $0078, $0079, $007A, $007B, $007C, $007D, $007E, $2302,
    $00C7, $00FC, $00E9, $00E2, $00E4, $00E0, $00E5, $00E7, $00EA, $00EB, $00E8, $00EF, $00EE, $00EC, $00C4, $00C5,
    $00C9, $00E6, $00C6, $00F4, $00F6, $00F2, $00FB, $00F9, $00FF, $00D6, $00DC, $00A2, $00A3, $00A5, $20A7, $0192,
    $00E1, $00ED, $00F3, $00FA, $00F1, $00D1, $00AA, $00BA, $00BF, $2310, $00AC, $00BD, $00BC, $00A1, $00AB, $00BB,
    $2591, $2592, $2593, $2502, $2524, $2561, $2562, $2556, $2555, $2563, $2551, $2557, $255D, $255C, $255B, $2510,
    $2514, $2534, $252C, $251C, $2500, $253C, $255E, $255F, $255A, $2554, $2569, $2566, $2560, $2550, $256C, $2567,
    $2568, $2564, $2565, $2559, $2558, $2552, $2553, $256B, $256A, $2518, $250C, $2588, $2584, $258C, $2590, $2580,
    $03B1, $00DF, $0393, $03C0, $03A3, $03C3, $00B5, $03C4, $03A6, $0398, $03A9, $03B4, $221E, $03C6, $03B5, $2229,
    $2261, $00B1, $2265, $2264, $2320, $2321, $00F7, $2248, $00B0, $2219, $00B7, $221A, $207F, $00B2, $25A0, $00A0);

  { Scan code of the key that types each ASCII character (US layout). }
  ScanOf: array[32..126] of Byte = (
    $39, $02, $28, $04, $05, $06, $08, $28, $0A, $0B, $09, $0D, $33, $0C, $34, $35,
    $0B, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $27, $27, $33, $0D, $34, $35,
    $03, $1E, $30, $2E, $20, $12, $21, $22, $23, $17, $24, $25, $26, $32, $31, $18,
    $19, $10, $13, $1F, $14, $16, $2F, $11, $2D, $15, $2C, $1A, $2B, $1B, $07, $0C,
    $29, $1E, $30, $2E, $20, $12, $21, $22, $23, $17, $24, $25, $26, $32, $31, $18,
    $19, $10, $13, $1F, $14, $16, $2F, $11, $2D, $15, $2C, $1A, $2B, $1B, $29);

  QueueSize = 64;

var
  Shadow: PVideoBuf;
  OutBuf: array[0..16383] of Char;
  OutLen: LongInt;
  OutTty, InTty, RawMode, VideoOn, EventsOn: Boolean;
  Saved: TTermios;
  TermX, TermY, TermAttr: LongInt;
  CursorX, CursorY: LongInt;
  CursorOn, CursorIns, CursorShown: Boolean;
  FullRedraw: Boolean;
  Bytes: array[0..255] of Char;
  ByteCount: LongInt;
  KeyQueue: array[0..QueueSize - 1] of Word;
  KeyShift: array[0..QueueSize - 1] of Byte;
  KeyHead, KeyCount: LongInt;
  MouseQueue: array[0..QueueSize - 1] of TEvent;
  MouseHead, MouseCount: LongInt;
  LastShift: Byte;
  LastDownTicks: LongInt;
  LastDownWhere: TPoint;
  LastAutoTicks: LongInt;
  OldExitProc: Pointer;

{ ---- time ------------------------------------------------------------------ }

{ Ticks of 1/18.2 s, like the PC timer that TP code expects. }
function GetTicks: LongInt;
var
  TV: TTimeVal;
begin
  c_gettimeofday(TV, nil);
  GetTicks := LongInt((TV.Sec * 1000 + TV.USec div 1000) * 182 div 10000);
end;

{ ---- terminal output ------------------------------------------------------------ }

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
  if OutLen >= SizeOf(OutBuf) then
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

procedure EmitNum(N: LongInt);
var
  S: String;
begin
  Str(N, S);
  EmitStr(S);
end;

procedure EmitUtf8(C: Word);
begin
  if C < $80 then
    Emit(Chr(C))
  else if C < $800 then
  begin
    Emit(Chr($C0 or (C shr 6)));
    Emit(Chr($80 or (C and $3F)));
  end
  else
  begin
    Emit(Chr($E0 or (C shr 12)));
    Emit(Chr($80 or ((C shr 6) and $3F)));
    Emit(Chr($80 or (C and $3F)));
  end;
end;

procedure MoveTo(X, Y: LongInt);
begin
  if (X = TermX) and (Y = TermY) then
    Exit;
  Emit(#27);
  Emit('[');
  EmitNum(Y + 1);
  Emit(';');
  EmitNum(X + 1);
  Emit('H');
  TermX := X;
  TermY := Y;
end;

const
  AnsiColor: array[0..7] of Char = '04261537';

procedure SetAttr(A: Byte);
begin
  if A = TermAttr then
    Exit;
  Emit(#27);
  EmitStr('[0;');
  if A and $08 <> 0 then
    Emit('9')
  else
    Emit('3');
  Emit(AnsiColor[A and 7]);
  Emit(';');
  if A and $80 <> 0 then
    EmitStr('10')
  else
    Emit('4');
  Emit(AnsiColor[(A shr 4) and 7]);
  Emit('m');
  TermAttr := A;
end;

{ Sends the cells that changed since the last update, then places the
  cursor. }
procedure UpdateScreen;
var
  X, Y, I: LongInt;
  Cell: Word;
begin
  if not VideoOn then
    Exit;
  for Y := 0 to ScreenHeight - 1 do
    for X := 0 to ScreenWidth - 1 do
    begin
      I := Y * ScreenWidth + X;
      Cell := ScreenBuffer^[I];
      if FullRedraw or (Cell <> Shadow^[I]) then
      begin
        Shadow^[I] := Cell;
        MoveTo(X, Y);
        SetAttr(Cell shr 8);
        EmitUtf8(CP437[Cell and $FF]);
        if X + 1 >= ScreenWidth then
          TermX := -1
        else
          TermX := X + 1;
      end;
    end;
  FullRedraw := False;
  if CursorOn and (CursorX >= 0) and (CursorY >= 0) and (CursorX < ScreenWidth) and (CursorY < ScreenHeight) then
  begin
    MoveTo(CursorX, CursorY);
    if not CursorShown then
      EmitStr(#27'[?25h');
    CursorShown := True;
  end
  else if CursorShown then
  begin
    EmitStr(#27'[?25l');
    CursorShown := False;
  end;
  FlushOut;
end;

procedure SetCursorState(X, Y: Integer; Visible, Insert: Boolean);
begin
  CursorX := X;
  CursorY := Y;
  CursorOn := Visible;
  CursorIns := Insert;
end;

{ ---- video ------------------------------------------------------------------- }

procedure InitVideo;
var
  WS: TWinSize;
  N: LongInt;
begin
  if VideoOn then
    Exit;
  OutTty := c_isatty(1) <> 0;
  ScreenWidth := 80;
  ScreenHeight := 25;
  if OutTty and (c_ioctl(1, TIOCGWINSZ, @WS) = 0) and (WS.Col > 0) and (WS.Row > 0) then
  begin
    ScreenWidth := WS.Col;
    ScreenHeight := WS.Row;
  end;
  if ScreenWidth > MaxScreenWidth then
    ScreenWidth := MaxScreenWidth;
  if ScreenHeight > MaxScreenHeight then
    ScreenHeight := MaxScreenHeight;
  N := LongInt(ScreenWidth) * ScreenHeight;
  GetMem(ScreenBuffer, N * SizeOf(Word));
  GetMem(Shadow, N * SizeOf(Word));
  ScreenMode := smCO80;
  HiResScreen := ScreenHeight > 25;
  CursorLines := $0607;
  VideoOn := True;
  TermX := -1;
  TermY := -1;
  TermAttr := -1;
  CursorOn := False;
  CursorShown := True;
  { Alternate screen (ignored by terminals without it), cleared. }
  EmitStr(#27'[?1049h'#27'[0m'#27'[2J');
  ClearScreen;
end;

procedure DoneVideo;
begin
  if not VideoOn then
    Exit;
  EmitStr(#27'[0m'#27'[2J'#27'[H'#27'[?25h'#27'[?1049l');
  FlushOut;
  FreeMem(ScreenBuffer, LongInt(ScreenWidth) * ScreenHeight * SizeOf(Word));
  FreeMem(Shadow, LongInt(ScreenWidth) * ScreenHeight * SizeOf(Word));
  ScreenBuffer := nil;
  Shadow := nil;
  VideoOn := False;
end;

procedure SetVideoMode(Mode: Word);
begin
  ScreenMode := Mode;
end;

procedure ClearScreen;
var
  I: LongInt;
begin
  if not VideoOn then
    Exit;
  for I := 0 to LongInt(ScreenWidth) * ScreenHeight - 1 do
    ScreenBuffer^[I] := $0720;
  FullRedraw := True;
  UpdateScreen;
end;

{ ---- keyboard and mouse -------------------------------------------------------- }

procedure PushKey(Code: Word; Shift: Byte);
begin
  if KeyCount = QueueSize then
    Exit;
  KeyQueue[(KeyHead + KeyCount) mod QueueSize] := Code;
  KeyShift[(KeyHead + KeyCount) mod QueueSize] := Shift;
  Inc(KeyCount);
end;

procedure PushMouse(What: Word; Buttons: Byte; X, Y: LongInt);
var
  E: TEvent;
  Now: LongInt;
begin
  FillChar(E, SizeOf(E), 0);
  E.What := What;
  E.Buttons := Buttons;
  E.Where.X := X;
  E.Where.Y := Y;
  Now := GetTicks;
  if What = evMouseDown then
  begin
    E.Double := (Now - LastDownTicks <= DoubleDelay) and (X = LastDownWhere.X) and (Y = LastDownWhere.Y);
    LastDownTicks := Now;
    if E.Double then
      LastDownTicks := 0;
    LastDownWhere.X := X;
    LastDownWhere.Y := Y;
    LastAutoTicks := Now + RepeatDelay;
  end;
  if What = evMouseUp then
    MouseButtons := 0
  else if Buttons <> 0 then
    MouseButtons := Buttons;
  MouseWhere.X := X;
  MouseWhere.Y := Y;
  if MouseCount = QueueSize then
    Exit;
  MouseQueue[(MouseHead + MouseCount) mod QueueSize] := E;
  Inc(MouseCount);
end;

function InputReady(Timeout: LongInt): Boolean;
var
  P: TPollFd;
begin
  P.Fd := 0;
  P.Events := POLLIN;
  P.REvents := 0;
  InputReady := c_poll(P, 1, Timeout) > 0;
end;

{ Reads what the terminal has sent so far, waiting briefly for the rest of
  an escape sequence. }
procedure ReadInput;
var
  N: Int64;
begin
  while (ByteCount < SizeOf(Bytes)) and InputReady(0) do
  begin
    N := c_read(0, @Bytes[ByteCount], SizeOf(Bytes) - ByteCount);
    if N <= 0 then
      Exit;
    Inc(ByteCount, N);
  end;
end;

procedure Consume(N: LongInt);
begin
  if N >= ByteCount then
    ByteCount := 0
  else
  begin
    System.Move(Bytes[N], Bytes[0], ByteCount - N);
    Dec(ByteCount, N);
  end;
end;

function CharKey(C: Char): Word;
begin
  case C of
    #8, #127: CharKey := kbBack;
    #9: CharKey := kbTab;
    #10: CharKey := kbCtrlEnter;
    #13: CharKey := kbEnter;
    #27: CharKey := kbEsc;
    #1..#7, #11, #12, #14..#26:
      CharKey := (Word(ScanOf[Ord(C) + 96]) shl 8) or Ord(C);
    #32..#126: CharKey := (Word(ScanOf[Ord(C)]) shl 8) or Ord(C);
  else
    CharKey := Ord(C);
  end;
end;

const
  AltLetters: array[0..25] of Byte = (
    $1E, $30, $2E, $20, $12, $21, $22, $23, $17, $24, $25, $26, $32, $31, $18, $19,
    $10, $13, $1F, $14, $16, $2F, $11, $2D, $15, $2C);

{ Key code of Alt + C, or 0. }
function AltKey(C: Char): Word;
begin
  case C of
    'a'..'z': AltKey := Word(AltLetters[Ord(C) - Ord('a')]) shl 8;
    'A'..'Z': AltKey := Word(AltLetters[Ord(C) - Ord('A')]) shl 8;
    '1'..'9': AltKey := Word($78 + Ord(C) - Ord('1')) shl 8;
    '0': AltKey := kbAlt0;
    '-': AltKey := kbAltMinus;
    '=': AltKey := kbAltEqual;
    ' ': AltKey := kbAltSpace;
    #8, #127: AltKey := kbAltBack;
  else
    AltKey := 0;
  end;
end;

{ Key code of a CSI or SS3 sequence: final character, first number and
  modifier (1 + shift + 2*alt + 4*ctrl). }
function SequenceKey(Final: Char; N, Modifier: LongInt): Word;
var
  Ctrl, Shift, Alt: Boolean;
  K: Word;
begin
  Shift := (Modifier > 1) and ((Modifier - 1) and 1 <> 0);
  Alt := (Modifier > 1) and ((Modifier - 1) and 2 <> 0);
  Ctrl := (Modifier > 1) and ((Modifier - 1) and 4 <> 0);
  K := 0;
  case Final of
    'A': if Ctrl then K := kbCtrlUp else K := kbUp;
    'B': if Ctrl then K := kbCtrlDown else K := kbDown;
    'C': if Ctrl then K := kbCtrlRight else K := kbRight;
    'D': if Ctrl then K := kbCtrlLeft else K := kbLeft;
    'H': if Ctrl then K := kbCtrlHome else K := kbHome;
    'F': if Ctrl then K := kbCtrlEnd else K := kbEnd;
    'Z': K := kbShiftTab;
    'P': K := kbF1;
    'Q': K := kbF2;
    'R': K := kbF3;
    'S': K := kbF4;
    '~':
      case N of
        1, 7: if Ctrl then K := kbCtrlHome else K := kbHome;
        2: if Shift then K := kbShiftIns else if Ctrl then K := kbCtrlIns else K := kbIns;
        3: if Shift then K := kbShiftDel else if Ctrl then K := kbCtrlDel else K := kbDel;
        4, 8: if Ctrl then K := kbCtrlEnd else K := kbEnd;
        5: if Ctrl then K := kbCtrlPgUp else K := kbPgUp;
        6: if Ctrl then K := kbCtrlPgDn else K := kbPgDn;
        11..15: K := Word($3B + N - 11) shl 8;
        17..21: K := Word($40 + N - 17) shl 8;
        23: K := kbF11;
        24: K := kbF12;
      end;
  end;
  { Function keys with Shift, Ctrl or Alt. }
  if (K >= kbF1) and (K <= kbF10) and (K and $FF = 0) and (Modifier > 1) then
  begin
    if Alt then
      K := K + (kbAltF1 - kbF1)
    else if Ctrl then
      K := K + (kbCtrlF1 - kbF1)
    else if Shift then
      K := K + (kbShiftF1 - kbF1);
  end;
  LastShift := 0;
  if Shift then
    LastShift := LastShift or kbLeftShift;
  if Ctrl then
    LastShift := LastShift or kbCtrlShift;
  if Alt then
    LastShift := LastShift or kbAltShift;
  SequenceKey := K;
end;

function IsDigit(C: Char): Boolean;
begin
  IsDigit := (C >= '0') and (C <= '9');
end;

{ Decodes one input item at the start of Bytes. Returns the bytes used, or
  0 when the item is still incomplete. }
function DecodeOne: LongInt;
var
  I, N, M, Params, B, X, Y: LongInt;
  Num: array[0..3] of LongInt;
  C: Char;
  K: Word;
  CodePoint: LongInt;
  Len, J: LongInt;
begin
  DecodeOne := 0;
  if ByteCount = 0 then
    Exit;
  C := Bytes[0];
  LastShift := 0;
  if C = #27 then
  begin
    if ByteCount = 1 then
    begin
      PushKey(kbEsc, 0);
      DecodeOne := 1;
      Exit;
    end;
    if (Bytes[1] = '[') or (Bytes[1] = 'O') then
    begin
      { CSI / SS3: ESC [ params final, or the SGR mouse report ESC [ < b ; x ; y M }
      I := 2;
      if (Bytes[1] = '[') and (I < ByteCount) and (Bytes[I] = '<') then
      begin
        Inc(I);
        Params := 0;
        FillChar(Num, SizeOf(Num), 0);
        while (I < ByteCount) and (IsDigit(Bytes[I]) or (Bytes[I] = ';')) do
        begin
          if Bytes[I] = ';' then
          begin
            if Params < 3 then
              Inc(Params);
          end
          else
            Num[Params] := Num[Params] * 10 + Ord(Bytes[I]) - Ord('0');
          Inc(I);
        end;
        if I >= ByteCount then
          Exit;
        B := Num[0];
        X := Num[1] - 1;
        Y := Num[2] - 1;
        if B and 64 <> 0 then
        begin
          { Wheel: up/down as arrow keys for the view under the mouse. }
          if Bytes[I] = 'M' then
          begin
            if B and 1 = 0 then
              PushKey(kbUp, 0)
            else
              PushKey(kbDown, 0);
          end;
        end
        else
        begin
          case B and 3 of
            0: M := mbLeftButton;
            2: M := mbRightButton;
          else
            M := mbLeftButton;
          end;
          if MouseReverse then
            M := M xor (mbLeftButton or mbRightButton);
          if Bytes[I] = 'm' then
            PushMouse(evMouseUp, 0, X, Y)
          else if B and 32 <> 0 then
            PushMouse(evMouseMove, MouseButtons, X, Y)
          else
            PushMouse(evMouseDown, M, X, Y);
        end;
        DecodeOne := I + 1;
        Exit;
      end;
      Params := 0;
      FillChar(Num, SizeOf(Num), 0);
      while (I < ByteCount) and (IsDigit(Bytes[I]) or (Bytes[I] = ';')) do
      begin
        if Bytes[I] = ';' then
        begin
          if Params < 3 then
            Inc(Params);
        end
        else
          Num[Params] := Num[Params] * 10 + Ord(Bytes[I]) - Ord('0');
        Inc(I);
      end;
      if I >= ByteCount then
        Exit;
      N := Num[0];
      M := 1;
      if Params >= 1 then
        M := Num[1];
      K := SequenceKey(Bytes[I], N, M);
      if K <> 0 then
        PushKey(K, LastShift);
      DecodeOne := I + 1;
      Exit;
    end;
    { Esc + key: Alt + key. }
    K := AltKey(Bytes[1]);
    if K <> 0 then
    begin
      PushKey(K, kbAltShift);
      DecodeOne := 2;
    end
    else
    begin
      PushKey(kbEsc, 0);
      DecodeOne := 1;
    end;
    Exit;
  end;
  if Ord(C) >= $80 then
  begin
    { UTF-8: map back to CP437 when the character exists there. }
    if Ord(C) >= $F0 then
      Len := 4
    else if Ord(C) >= $E0 then
      Len := 3
    else if Ord(C) >= $C0 then
      Len := 2
    else
      Len := 1;
    if ByteCount < Len then
      Exit;
    if Len = 1 then
      CodePoint := Ord(C)
    else
    begin
      CodePoint := Ord(C) and ($7F shr Len);
      for J := 1 to Len - 1 do
        CodePoint := (CodePoint shl 6) or (Ord(Bytes[J]) and $3F);
    end;
    K := Ord('?');
    for J := 128 to 255 do
      if CP437[J] = CodePoint then
        K := J;
    PushKey(K, 0);
    DecodeOne := Len;
    Exit;
  end;
  PushKey(CharKey(C), 0);
  DecodeOne := 1;
end;

procedure PollInput(Timeout: LongInt);
var
  N: LongInt;
begin
  if not InTty and not InputReady(0) then
    Exit;
  if (ByteCount = 0) and not InputReady(Timeout) then
    Exit;
  ReadInput;
  while ByteCount > 0 do
  begin
    N := DecodeOne;
    if N = 0 then
    begin
      { An incomplete sequence: give the terminal a moment. }
      if InputReady(30) then
      begin
        ReadInput;
        N := DecodeOne;
      end;
      if N = 0 then
      begin
        if Bytes[0] = #27 then
        begin
          PushKey(kbEsc, 0);
          N := 1;
        end
        else
          N := 1;
      end;
    end;
    Consume(N);
  end;
end;

{ Waits until input arrives or Milliseconds pass; the screen is brought up
  to date first. }
procedure WaitForEvent(Milliseconds: LongInt);
begin
  UpdateScreen;
  if (KeyCount > 0) or (MouseCount > 0) then
    Exit;
  if (MouseButtons <> 0) and (Milliseconds > 50) then
    Milliseconds := 50;
  PollInput(Milliseconds);
end;

procedure GetKeyEvent(var Event: TEvent);
begin
  if KeyCount = 0 then
    PollInput(0);
  if KeyCount = 0 then
  begin
    Event.What := evNothing;
    Exit;
  end;
  Event.What := evKeyDown;
  Event.KeyCode := KeyQueue[KeyHead];
  LastShift := KeyShift[KeyHead];
  KeyHead := (KeyHead + 1) mod QueueSize;
  Dec(KeyCount);
end;

procedure GetMouseEvent(var Event: TEvent);
var
  Now: LongInt;
begin
  if MouseCount = 0 then
    PollInput(0);
  if MouseCount > 0 then
  begin
    Event := MouseQueue[MouseHead];
    MouseHead := (MouseHead + 1) mod QueueSize;
    Dec(MouseCount);
    Exit;
  end;
  Event.What := evNothing;
  { A held button repeats as evMouseAuto. }
  if MouseButtons <> 0 then
  begin
    Now := GetTicks;
    if Now >= LastAutoTicks then
    begin
      LastAutoTicks := Now + 1;
      Event.What := evMouseAuto;
      Event.Buttons := MouseButtons;
      Event.Double := False;
      Event.Where := MouseWhere;
    end;
  end;
end;

function GetShiftState: Byte;
begin
  GetShiftState := LastShift;
end;

procedure EnterRaw;
var
  T: TTermios;
begin
  if not InTty or RawMode then
    Exit;
  if c_tcgetattr(0, Saved) <> 0 then
    Exit;
  T := Saved;
  T.IFlag := T.IFlag and not (ICRNL or IXON);
  T.LFlag := T.LFlag and not (ICANON or ECHO or IEXTEN or ISIG);
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

procedure InitEvents;
begin
  if EventsOn then
    Exit;
  InTty := c_isatty(0) <> 0;
  EnterRaw;
  KeyCount := 0;
  MouseCount := 0;
  ByteCount := 0;
  MouseButtons := 0;
  MouseEvents := InTty;
  ButtonCount := 2;
  if MouseEvents then
  begin
    EmitStr(#27'[?1000h'#27'[?1002h'#27'[?1006h');
    FlushOut;
  end;
  EventsOn := True;
end;

procedure DoneEvents;
begin
  if not EventsOn then
    Exit;
  if MouseEvents then
  begin
    EmitStr(#27'[?1006l'#27'[?1002l'#27'[?1000l');
    FlushOut;
  end;
  LeaveRaw;
  EventsOn := False;
end;

procedure ShowMouse;
begin
end;

procedure HideMouse;
begin
end;

procedure InitSysError;
begin
  SysErrActive := True;
end;

procedure DoneSysError;
begin
  SysErrActive := False;
end;

{ Leaves the terminal usable after a runtime error or Halt. }
procedure DriversExit;
begin
  ExitProc := OldExitProc;
  DoneEvents;
  DoneVideo;
end;

procedure OnSignal(Sig: LongInt);
const
  Restore: array[0..44] of Char = #27'[0m'#27'[?25h'#27'[?1000l'#27'[?1002l'#27'[?1006l'#27'[?1049l'#27'[H';
begin
  LeaveRaw;
  c_write(1, @Restore, SizeOf(Restore));
  c_signal(Sig, nil);
  c_raise(Sig);
end;

procedure Catch(Sig: LongInt);
var
  Old: Pointer;
begin
  Old := c_signal(Sig, @OnSignal);
  if Old <> nil then
    c_signal(Sig, Old);
end;

{ ---- keyboard helpers ------------------------------------------------------------ }

function GetAltChar(KeyCode: Word): Char;
var
  C: Char;
begin
  GetAltChar := #0;
  if KeyCode and $FF <> 0 then
    Exit;
  if KeyCode = kbAltSpace then
  begin
    GetAltChar := #240;
    Exit;
  end;
  for C := 'A' to 'Z' do
    if AltKey(C) = KeyCode then
    begin
      GetAltChar := C;
      Exit;
    end;
  for C := '0' to '9' do
    if AltKey(C) = KeyCode then
    begin
      GetAltChar := C;
      Exit;
    end;
end;

function GetAltCode(Ch: Char): Word;
begin
  if Ch = #240 then
    GetAltCode := kbAltSpace
  else
    GetAltCode := AltKey(UpCase(Ch));
end;

function GetCtrlChar(KeyCode: Word): Char;
begin
  if (KeyCode and $FF > 0) and (KeyCode and $FF <= 26) then
    GetCtrlChar := Chr((KeyCode and $FF) + Ord('A') - 1)
  else
    GetCtrlChar := #0;
end;

function GetCtrlCode(Ch: Char): Word;
begin
  GetCtrlCode := GetAltCode(Ch) or (Ord(UpCase(Ch)) - Ord('A') + 1);
end;

{ WordStar control keys to arrow keys (Ctrl-S left, Ctrl-D right, ...). }
function CtrlToArrow(KeyCode: Word): Word;
begin
  case KeyCode and $FF of
    19: CtrlToArrow := kbLeft;
    4: CtrlToArrow := kbRight;
    5: CtrlToArrow := kbUp;
    24: CtrlToArrow := kbDown;
    1: CtrlToArrow := kbHome;
    6: CtrlToArrow := kbEnd;
    18: CtrlToArrow := kbPgUp;
    3: CtrlToArrow := kbPgDn;
    22: CtrlToArrow := kbIns;
    7: CtrlToArrow := kbDel;
    8: CtrlToArrow := kbBack;
  else
    CtrlToArrow := KeyCode;
  end;
end;

{ ---- strings and buffers ---------------------------------------------------------- }

function CStrLen(const S: String): Integer;
var
  I, N: Integer;
begin
  N := 0;
  for I := 1 to Length(S) do
    if S[I] <> '~' then
      Inc(N);
  CStrLen := N;
end;

type
  TWords = array[0..65535] of Word;
  TChars = array[0..65535] of Char;

procedure MoveBuf(var Dest; var Source; Attr: Byte; Count: Word);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if Attr = 0 then
      TWords(Dest)[I] := (TWords(Dest)[I] and $FF00) or Ord(TChars(Source)[I])
    else
      TWords(Dest)[I] := (Word(Attr) shl 8) or Ord(TChars(Source)[I]);
end;

procedure MoveChar(var Dest; C: Char; Attr: Byte; Count: Word);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    if C <> #0 then
      TWords(Dest)[I] := (TWords(Dest)[I] and $FF00) or Ord(C);
    if Attr <> 0 then
      TWords(Dest)[I] := (TWords(Dest)[I] and $00FF) or (Word(Attr) shl 8);
  end;
end;

procedure MoveCStr(var Dest; const Str: String; Attrs: Word);
var
  I, J: Integer;
  Bright: Boolean;
  A: Byte;
begin
  J := 0;
  Bright := False;
  for I := 1 to Length(Str) do
    if Str[I] = '~' then
      Bright := not Bright
    else
    begin
      if Bright then
        A := Hi(Attrs)
      else
        A := Lo(Attrs);
      TWords(Dest)[J] := (Word(A) shl 8) or Ord(Str[I]);
      Inc(J);
    end;
end;

procedure MoveStr(var Dest; const Str: String; Attr: Byte);
var
  I: Integer;
begin
  for I := 1 to Length(Str) do
    if Attr = 0 then
      TWords(Dest)[I - 1] := (TWords(Dest)[I - 1] and $FF00) or Ord(Str[I])
    else
      TWords(Dest)[I - 1] := (Word(Attr) shl 8) or Ord(Str[I]);
end;

{ %[-][0][width]d|x|s|c and %%. Params: one PtrInt per % item (a LongInt,
  a character in the low byte, or a PString). }
procedure FormatStr(var Result: String; const Format: String; var Params);
type
  TParams = array[0..255] of PtrInt;
var
  I, Index, Width: Integer;
  Left, Zero: Boolean;
  Item, Digits: String;
  V: PtrInt;
  P: PString;
  Kind: Char;
const
  Hex: array[0..15] of Char = '0123456789ABCDEF';
begin
  Result := '';
  I := 1;
  Index := 0;
  while I <= Length(Format) do
  begin
    if (Format[I] <> '%') or (I = Length(Format)) then
    begin
      Result := Result + Format[I];
      Inc(I);
      Continue;
    end;
    Inc(I);
    if Format[I] = '%' then
    begin
      Result := Result + '%';
      Inc(I);
      Continue;
    end;
    Left := False;
    Zero := False;
    Width := 0;
    if Format[I] = '-' then
    begin
      Left := True;
      Inc(I);
    end;
    if (I <= Length(Format)) and (Format[I] = '0') then
    begin
      Zero := True;
      Inc(I);
    end;
    while (I <= Length(Format)) and (Format[I] >= '0') and (Format[I] <= '9') do
    begin
      Width := Width * 10 + Ord(Format[I]) - Ord('0');
      Inc(I);
    end;
    if I > Length(Format) then
      Break;
    Kind := UpCase(Format[I]);
    Inc(I);
    V := TParams(Params)[Index];
    Inc(Index);
    case Kind of
      'D':
        Str(V, Item);
      'X':
        begin
          Item := '';
          repeat
            Item := Hex[V and 15] + Item;
            V := V shr 4;
          until V = 0;
        end;
      'C':
        Item := Chr(V and $FF);
      'S':
        begin
          P := PString(V);
          if P = nil then
            Item := ''
          else
            Item := P^;
        end;
    else
      Item := '';
    end;
    while Length(Item) < Width do
      if Left then
        Item := Item + ' '
      else if Zero then
        Item := '0' + Item
      else
        Item := ' ' + Item;
    Digits := Item;
    Result := Result + Digits;
  end;
end;

procedure PrintStr(const S: String);
begin
  if Length(S) > 0 then
    c_write(1, @S[1], Length(S));
end;

begin
  DoubleDelay := 8;
  RepeatDelay := 8;
  SysColorAttr := $4E4F;
  SysMonoAttr := $7070;
  StartupMode := smCO80;
  ScreenMode := smCO80;
  ScreenWidth := 80;
  ScreenHeight := 25;
  OldExitProc := ExitProc;
  ExitProc := @DriversExit;
  if c_isatty(0) <> 0 then
  begin
    Catch(SIGHUP);
    Catch(SIGINT);
    Catch(SIGQUIT);
    Catch(SIGTERM);
  end;
end.
