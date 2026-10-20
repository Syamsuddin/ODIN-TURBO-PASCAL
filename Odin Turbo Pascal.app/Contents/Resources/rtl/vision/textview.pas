{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit TextView dari Odin Vision: TTextDevice (scroller yang menjadi
  perangkat teks), TTerminal (terminal sederhana dengan buffer melingkar),
  dan AssignDevice untuk menulis ke view itu dengan Write/WriteLn.
  Implementasi clean-room berdasarkan dokumentasi API Turbo Vision TP7.

  AssignDevice memakai hook FlushFunc milik TextRec
  (rtl/COMPILER_INTERFACE.md bagian 4), seperti AssignCrt di unit Crt:
  setiap pernyataan Write/WriteLn ke berkas itu sampai ke StrWrite. }
unit TextView;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views;

type
  PTextDevice = ^TTextDevice;
  TTextDevice = object(TScroller)
    function StrRead(var S: TextBuf): Byte; virtual;
    procedure StrWrite(var S: TextBuf; Count: Byte); virtual;
  end;

  PTerminalBuffer = ^TTerminalBuffer;
  TTerminalBuffer = array[0..65534] of Char;

  PTerminal = ^TTerminal;
  TTerminal = object(TTextDevice)
    BufSize: Word;
    Buffer: PTerminalBuffer;
    QueFront, QueBack: Word;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; ABufSize: Word);
    destructor Done; virtual;
    procedure BufDec(var Val: Word);
    procedure BufInc(var Val: Word);
    function CalcWidth: Integer;
    function CanInsert(Amount: Word): Boolean;
    procedure Draw; virtual;
    function NextLine(Pos: Word): Word;
    function PrevLines(Pos: Word; Lines: Word): Word;
    function StrRead(var S: TextBuf): Byte; virtual;
    procedure StrWrite(var S: TextBuf; Count: Byte); virtual;
    function QueEmpty: Boolean;
    { Odin: the columns of the line starting at Pos (tabs to multiples of 8). }
    function LineWidth(Pos: Word): Integer;
  end;

procedure AssignDevice(var T: Text; Screen: PTextDevice);

implementation

const
  TabSize = 8;

{ Column after character C written at column Col. }
function NextCol(Col: Integer; C: Char): Integer;
begin
  if C = #9 then
    NextCol := (Col div TabSize + 1) * TabSize
  else
    NextCol := Col + 1;
end;

{ ---- TTextDevice ------------------------------------------------------------------------ }

function TTextDevice.StrRead(var S: TextBuf): Byte;
begin
  StrRead := 0;
end;

procedure TTextDevice.StrWrite(var S: TextBuf; Count: Byte);
begin
  Abstract;
end;

{ ---- TTerminal --------------------------------------------------------------------------- }

constructor TTerminal.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; ABufSize: Word);
begin
  inherited Init(Bounds, AHScrollBar, AVScrollBar);
  GrowMode := gfGrowHiX + gfGrowHiY;
  if ABufSize < 2 then
    ABufSize := 2;
  BufSize := ABufSize;
  GetMem(Buffer, BufSize);
  QueFront := 0;
  QueBack := 0;
  SetLimit(0, 1);
  SetCursor(0, 0);
  ShowCursor;
end;

destructor TTerminal.Done;
begin
  if Buffer <> nil then
    FreeMem(Buffer, BufSize);
  Buffer := nil;
  inherited Done;
end;

procedure TTerminal.BufDec(var Val: Word);
begin
  if Val = 0 then
    Val := BufSize - 1
  else
    Dec(Val);
end;

procedure TTerminal.BufInc(var Val: Word);
begin
  Inc(Val);
  if Val >= BufSize then
    Val := 0;
end;

function TTerminal.QueEmpty: Boolean;
begin
  QueEmpty := QueFront = QueBack;
end;

function TTerminal.CanInsert(Amount: Word): Boolean;
var
  Used: LongInt;
begin
  Used := (LongInt(QueFront) - LongInt(QueBack) + BufSize) mod BufSize;
  CanInsert := LongInt(Amount) <= LongInt(BufSize) - 1 - Used;
end;

function TTerminal.NextLine(Pos: Word): Word;
var
  C: Char;
begin
  while Pos <> QueFront do
  begin
    C := Buffer^[Pos];
    BufInc(Pos);
    if C = #10 then
      Break;
  end;
  NextLine := Pos;
end;

function TTerminal.PrevLines(Pos: Word; Lines: Word): Word;
var
  Q: Word;
  N: LongInt;
begin
  N := Lines;
  while N > 0 do
  begin
    { Back to the start of the line holding Pos. }
    while Pos <> QueBack do
    begin
      Q := Pos;
      BufDec(Q);
      if Buffer^[Q] = #10 then
        Break;
      Pos := Q;
    end;
    Dec(N);
    if N > 0 then
    begin
      if Pos = QueBack then
        Break;
      { Onto the #10 that ends the line above. }
      BufDec(Pos);
    end;
  end;
  PrevLines := Pos;
end;

function TTerminal.LineWidth(Pos: Word): Integer;
var
  W: Integer;
begin
  W := 0;
  while (Pos <> QueFront) and (Buffer^[Pos] <> #10) do
  begin
    W := NextCol(W, Buffer^[Pos]);
    BufInc(Pos);
  end;
  LineWidth := W;
end;

function TTerminal.CalcWidth: Integer;
var
  P: Word;
  W, Max: Integer;
begin
  P := QueBack;
  W := 0;
  Max := 0;
  while P <> QueFront do
  begin
    if Buffer^[P] = #10 then
    begin
      if W > Max then
        Max := W;
      W := 0;
    end
    else
      W := NextCol(W, Buffer^[P]);
    BufInc(P);
  end;
  if W > Max then
    Max := W;
  CalcWidth := Max;
end;

procedure TTerminal.Draw;
var
  B: TDrawBuffer;
  Color: Byte;
  Y, Col, X: Integer;
  P: Word;
  C: Char;
begin
  Color := Byte(GetColor(1));
  P := PrevLines(QueFront, Limit.Y - Delta.Y);
  for Y := 0 to Size.Y - 1 do
  begin
    MoveChar(B, ' ', Color, Size.X);
    if Delta.Y + Y < Limit.Y then
    begin
      Col := 0;
      while (P <> QueFront) and (Buffer^[P] <> #10) do
      begin
        C := Buffer^[P];
        if C <> #9 then
        begin
          X := Col - Delta.X;
          if (X >= 0) and (X < Size.X) then
            B[X] := (Word(Color) shl 8) or Ord(C);
        end;
        Col := NextCol(Col, C);
        BufInc(P);
      end;
      if P <> QueFront then
        BufInc(P);
    end;
    WriteLine(0, Y, Size.X, 1, B);
  end;
  SetCursor(LineWidth(PrevLines(QueFront, 1)) - Delta.X, Limit.Y - 1 - Delta.Y);
end;

function TTerminal.StrRead(var S: TextBuf): Byte;
begin
  StrRead := 0;
end;

procedure TTerminal.StrWrite(var S: TextBuf; Count: Byte);
var
  I: Integer;
  C: Char;
  Lines, Width, Col, Top: LongInt;
  Recalc: Boolean;

  { Makes room for one character: drops the top line, or the first
    character of a line that fills the whole buffer. }
  procedure DiscardTop;
  var
    P: Word;
    W: Integer;
  begin
    P := QueBack;
    W := 0;
    while (P <> QueFront) and (Buffer^[P] <> #10) do
    begin
      W := NextCol(W, Buffer^[P]);
      BufInc(P);
    end;
    if P = QueFront then
    begin
      BufInc(QueBack);
      Recalc := True;
    end
    else
    begin
      BufInc(P);
      QueBack := P;
      Dec(Lines);
      { It may have been the widest line. }
      if W >= Width then
        Recalc := True;
    end;
  end;

begin
  if Count = 0 then
    Exit;
  Lines := Limit.Y;
  Width := Limit.X;
  Recalc := False;
  Col := LineWidth(PrevLines(QueFront, 1));
  for I := 0 to Count - 1 do
  begin
    C := S[I];
    if C <> #13 then
    begin
      if not CanInsert(1) then
        DiscardTop;
      Buffer^[QueFront] := C;
      BufInc(QueFront);
      if C = #10 then
      begin
        if Col > Width then
          Width := Col;
        Col := 0;
        Inc(Lines);
      end
      else
        Col := NextCol(Col, C);
    end;
  end;
  if Col > Width then
    Width := Col;
  if Recalc then
    Width := CalcWidth;
  { One redraw at the end, with the last line at the bottom. }
  Inc(DrawLock);
  SetLimit(Width, Lines);
  Top := Lines - Size.Y;
  if Top < 0 then
    Top := 0;
  if VScrollBar <> nil then
    ScrollTo(Delta.X, Top)
  else
    Delta.Y := Top;
  Dec(DrawLock);
  DrawFlag := False;
  DrawView;
end;

{ ---- AssignDevice ------------------------------------------------------------------------ }

{ FlushFunc of a text file assigned to a device: output goes to StrWrite
  in pieces of at most 255 characters; input comes from StrRead. }
procedure DeviceIO(var F: TextRec);
var
  Device: PTextDevice;
  Piece: TextBuf;
  I, N: LongInt;
begin
  Device := PTextDevice(PPointer(@F.UserData)^);
  if F.Mode = fmInput then
  begin
    F.BufPos := 0;
    F.BufEnd := 0;
    if Device <> nil then
      F.BufEnd := Device^.StrRead(F.Buffer);
    Exit;
  end;
  I := 0;
  while (Device <> nil) and (I < F.BufPos) do
  begin
    N := F.BufPos - I;
    if N > 255 then
      N := 255;
    Move(F.Buffer[I], Piece, N);
    Device^.StrWrite(Piece, N);
    Inc(I, N);
  end;
  F.BufPos := 0;
end;

procedure AssignDevice(var T: Text; Screen: PTextDevice);
begin
  Assign(T, '');
  TextRec(T).FlushFunc := @DeviceIO;
  PPointer(@TextRec(T).UserData)^ := Screen;
end;

end.
