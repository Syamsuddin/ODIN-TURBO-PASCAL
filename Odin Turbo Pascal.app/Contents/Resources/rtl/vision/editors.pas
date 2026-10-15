{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Editors dari Odin Vision: TEditor, TMemo, TFileEditor, TEditWindow
  dan TIndicator. Implementasi clean-room berdasarkan dokumentasi API
  Turbo Vision TP7.

  Teks disimpan dalam gap buffer: Buffer^[0..CurPtr-1] adalah teks
  sebelum kursor, lalu celah sepanjang GapLen, lalu sisa teks sampai
  BufSize. Akhir baris boleh LF, CR LF atau CR; Enter menyisipkan LF.
  Tab ditampilkan sampai kolom kelipatan 8. Undo satu langkah: rangkaian
  ketikan atau hapusan berurutan dibatalkan sekaligus, dan Undo kedua
  mengulanginya. Tombol mengikuti TP (WordStar: ^K, ^Q, ^Y, ...). }
unit Editors;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views, Dialogs;

const
  cmFind = 82;
  cmReplace = 83;
  cmSearchAgain = 84;

  cmCharLeft = 500;
  cmCharRight = 501;
  cmWordLeft = 502;
  cmWordRight = 503;
  cmLineStart = 504;
  cmLineEnd = 505;
  cmLineUp = 506;
  cmLineDown = 507;
  cmPageUp = 508;
  cmPageDown = 509;
  cmTextStart = 510;
  cmTextEnd = 511;
  cmNewLine = 512;
  cmBackSpace = 513;
  cmDelChar = 514;
  cmDelWord = 515;
  cmDelStart = 516;
  cmDelEnd = 517;
  cmDelLine = 518;
  cmInsMode = 519;
  cmStartSelect = 520;
  cmHideSelect = 521;
  cmIndentMode = 522;
  cmUpdateTitle = 523;

  edOutOfMemory = 0;
  edReadError = 1;
  edWriteError = 2;
  edCreateError = 3;
  edSaveModify = 4;
  edSaveUntitled = 5;
  edSaveAs = 6;
  edFind = 7;
  edSearchFailed = 8;
  edReplace = 9;
  edReplacePrompt = 10;

  efCaseSensitive = $0001;
  efWholeWordsOnly = $0002;
  efPromptOnReplace = $0004;
  efReplaceAll = $0008;
  efDoReplace = $0010;
  efBackupFiles = $0100;

  CIndicator = #2#3;
  CEditor = #6#7;
  CMemo = #26#27;

  MaxLineLength = 256;

type
  TEditorDialog = function(Dialog: Integer; Info: Pointer): Word;

  PEditBuffer = ^TEditBuffer;
  TEditBuffer = array[0..16777215] of Char;

  PIndicator = ^TIndicator;
  TIndicator = object(TView)
    Location: TPoint;
    Modified: Boolean;
    constructor Init(var Bounds: TRect);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure SetValue(ALocation: TPoint; AModified: Boolean);
  end;

  PEditor = ^TEditor;
  TEditor = object(TView)
    HScrollBar: PScrollBar;
    VScrollBar: PScrollBar;
    Indicator: PIndicator;
    Buffer: PEditBuffer;
    BufSize: Sw_Word;
    BufLen: Sw_Word;
    GapLen: Sw_Word;
    SelStart: Sw_Word;
    SelEnd: Sw_Word;
    CurPtr: Sw_Word;
    CurPos: TPoint;
    Delta: TPoint;
    Limit: TPoint;
    DrawLine: Sw_Integer;
    DrawPtr: Sw_Word;
    DelCount: Sw_Word;
    InsCount: Sw_Word;
    IsValid: Boolean;
    CanUndo: Boolean;
    Modified: Boolean;
    Selecting: Boolean;
    Overwrite: Boolean;
    AutoIndent: Boolean;
    LockCount: Byte;
    UpdateFlags: Byte;
    KeyState: Integer;
    { Odin: undo snapshot and the edit it belongs to. }
    UndoBuf: PEditBuffer;
    UndoLen: Sw_Word;
    UndoPtr: Sw_Word;
    LastEdit: Sw_Word;
    LastKind: Integer;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; AIndicator: PIndicator;
      ABufSize: Sw_Word);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    function BufChar(P: Sw_Word): Char;
    function BufPtr(P: Sw_Word): Sw_Word;
    procedure ChangeBounds(var Bounds: TRect); virtual;
    procedure ConvertEvent(var Event: TEvent); virtual;
    function CursorVisible: Boolean;
    procedure DeleteSelect;
    procedure DoneBuffer; virtual;
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitBuffer; virtual;
    function InsertBuffer(var P: PEditBuffer; Offset, Length: Sw_Word; AllowUndo, SelectText: Boolean): Boolean;
    function InsertFrom(Editor: PEditor): Boolean; virtual;
    function InsertText(Text: Pointer; Length: Sw_Word; SelectText: Boolean): Boolean;
    procedure ScrollTo(X, Y: Sw_Integer);
    function Search(const FindStr: String; Opts: Word): Boolean;
    function SetBufSize(NewSize: Sw_Word): Boolean; virtual;
    procedure SetCmdState(Command: Word; Enable: Boolean);
    procedure SetSelect(NewStart, NewEnd: Sw_Word; CurStart: Boolean);
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
    procedure TrackCursor(Center: Boolean);
    procedure Undo;
    procedure UpdateCommands; virtual;
    function Valid(Command: Word): Boolean; virtual;
    { TP internals, public here. }
    function CharPos(P, Target: Sw_Word): Sw_Integer;
    function CharPtr(P: Sw_Word; Target: Sw_Integer): Sw_Word;
    function ClipCopy: Boolean;
    procedure ClipCut;
    procedure ClipPaste;
    procedure DeleteRange(StartPtr, EndPtr: Sw_Word; DelSelect: Boolean);
    procedure DoUpdate;
    procedure DoSearchReplace;
    procedure Find;
    function GetMousePtr(Mouse: TPoint): Sw_Word;
    function HasSelection: Boolean;
    procedure HideSelect;
    function IsClipboard: Boolean;
    function LineEnd(P: Sw_Word): Sw_Word;
    function LineMove(P: Sw_Word; Count: Sw_Integer): Sw_Word;
    function LineStart(P: Sw_Word): Sw_Word;
    procedure Lock;
    procedure NewLine;
    function NextChar(P: Sw_Word): Sw_Word;
    function NextLine(P: Sw_Word): Sw_Word;
    function NextWord(P: Sw_Word): Sw_Word;
    function PrevChar(P: Sw_Word): Sw_Word;
    function PrevLine(P: Sw_Word): Sw_Word;
    function PrevWord(P: Sw_Word): Sw_Word;
    procedure Replace;
    procedure SetBufLen(Length: Sw_Word);
    procedure SetCurPtr(P: Sw_Word; SelectMode: Byte);
    procedure StartSelect;
    procedure ToggleInsMode;
    procedure Unlock;
    procedure Update(AFlags: Byte);
    { Odin helpers. }
    procedure MoveGap(P: Sw_Word);
    function ReplaceRange(StartPtr, EndPtr: Sw_Word; Text: Pointer; Len: Sw_Word; Kind: Integer): Boolean;
    function GrowBuffer(NewSize: Sw_Word): Boolean;
    function LineOf(P: Sw_Word): Sw_Integer;
    function LinePtr(N: Sw_Integer): Sw_Word;
    function IsLineEnd(P: Sw_Word): Boolean;
    procedure CountLines;
  end;

  TMemoData = record
    Length: Sw_Word;
    Buffer: TEditBuffer;
  end;

  PMemo = ^TMemo;
  TMemo = object(TEditor)
    constructor Load(var S: TStream);
    function DataSize: Word; virtual;
    procedure GetData(var Rec); virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
  end;

  PFileEditor = ^TFileEditor;
  TFileEditor = object(TEditor)
    FileName: FNameStr;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; AIndicator: PIndicator;
      AFileName: FNameStr);
    constructor Load(var S: TStream);
    procedure DoneBuffer; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitBuffer; virtual;
    function LoadFile: Boolean;
    function Save: Boolean;
    function SaveAs: Boolean;
    function SaveFile: Boolean;
    function SetBufSize(NewSize: Sw_Word): Boolean; virtual;
    procedure Store(var S: TStream);
    procedure UpdateCommands; virtual;
    function Valid(Command: Word): Boolean; virtual;
  end;

  PEditWindow = ^TEditWindow;
  TEditWindow = object(TWindow)
    Editor: PFileEditor;
    constructor Init(var Bounds: TRect; FileName: FNameStr; ANumber: Integer);
    constructor Load(var S: TStream);
    procedure Close; virtual;
    function GetTitle(MaxSize: Sw_Integer): TTitleStr; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SizeLimits(var Min, Max: TPoint); virtual;
    procedure Store(var S: TStream);
  end;

  TFindDialogRec = packed record
    Find: String[80];
    Options: Word;
  end;

  TReplaceDialogRec = packed record
    Find: String[80];
    Replace: String[80];
    Options: Word;
  end;

function DefEditorDialog(Dialog: Integer; Info: Pointer): Word;
function StdEditorDialog(Dialog: Integer; Info: Pointer): Word;
function CreateFindDialog: PDialog;
function CreateReplaceDialog: PDialog;
procedure RegisterEditors;

const
  WordChars: set of Char = ['0'..'9', 'A'..'Z', '_', 'a'..'z'];
  EditorDialog: TEditorDialog = DefEditorDialog;
  EditorFlags: Word = efBackupFiles + efPromptOnReplace;
  FindStr: String[80] = '';
  ReplaceStr: String[80] = '';
  Clipboard: PEditor = nil;

  REditor: TStreamRec = (ObjType: 70; VmtLink: Ofs(TypeOf(TEditor)^); Load: @TEditor.Load; Store: @TEditor.Store);
  RMemo: TStreamRec = (ObjType: 71; VmtLink: Ofs(TypeOf(TMemo)^); Load: @TMemo.Load; Store: @TMemo.Store);
  RFileEditor: TStreamRec = (ObjType: 72; VmtLink: Ofs(TypeOf(TFileEditor)^); Load: @TFileEditor.Load;
    Store: @TFileEditor.Store);
  RIndicator: TStreamRec = (ObjType: 73; VmtLink: Ofs(TypeOf(TIndicator)^); Load: @TIndicator.Load;
    Store: @TIndicator.Store);
  REditWindow: TStreamRec = (ObjType: 74; VmtLink: Ofs(TypeOf(TEditWindow)^); Load: @TEditWindow.Load;
    Store: @TEditWindow.Store);

implementation

uses Dos, Memory, MsgBox, App, StdDlg;

const
  ufUpdate = $01;
  ufLine = $02;
  ufView = $04;

  smExtend = $01;
  smDouble = $02;

  { Kinds of edit, for undo: a run of the same kind at the same place is
    one step. }
  ekOther = 0;
  ekInsert = 1;
  ekDelete = 2;

  TabSize = 8;

function Min(A, B: Sw_Integer): Sw_Integer;
begin
  if A < B then Min := A else Min := B;
end;

function Max(A, B: Sw_Integer): Sw_Integer;
begin
  if A > B then Max := A else Max := B;
end;

function DefEditorDialog(Dialog: Integer; Info: Pointer): Word;
begin
  DefEditorDialog := cmCancel;
end;

{ ---- TIndicator --------------------------------------------------------------------- }

constructor TIndicator.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  GrowMode := gfGrowLoY + gfGrowHiY;
end;

procedure TIndicator.Draw;
var
  B: TDrawBuffer;
  Color: Byte;
  Frame: Char;
  S, N: String;
  X: Sw_Integer;
begin
  if State and sfDragging = 0 then
  begin
    Color := GetColor(1);
    Frame := #205;
  end
  else
  begin
    Color := GetColor(2);
    Frame := #196;
  end;
  MoveChar(B, Frame, Color, Size.X);
  if Modified then
    MoveChar(B[0], #15, Color, 1);
  Str(Location.Y + 1, N);
  S := ' ' + N + ':';
  Str(Location.X + 1, N);
  S := S + N + ' ';
  X := 8 - Pos(':', S);
  if X < 1 then
    X := 1;
  if X + Length(S) <= Size.X then
    MoveStr(B[X], S, Color);
  WriteBuf(0, 0, Size.X, 1, B);
end;

function TIndicator.GetPalette: PPalette;
const
  P: String[Length(CIndicator)] = CIndicator;
begin
  GetPalette := @P;
end;

procedure TIndicator.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState = sfDragging then
    DrawView;
end;

procedure TIndicator.SetValue(ALocation: TPoint; AModified: Boolean);
begin
  if (Location.X <> ALocation.X) or (Location.Y <> ALocation.Y) or (Modified <> AModified) then
  begin
    Location := ALocation;
    Modified := AModified;
    DrawView;
  end;
end;

{ ---- TEditor: construction and buffer ------------------------------------------------- }

constructor TEditor.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; AIndicator: PIndicator;
  ABufSize: Sw_Word);
begin
  inherited Init(Bounds);
  GrowMode := gfGrowHiX + gfGrowHiY;
  Options := Options or ofSelectable;
  EventMask := evMouseDown + evKeyDown + evCommand + evBroadcast;
  ShowCursor;
  HScrollBar := AHScrollBar;
  VScrollBar := AVScrollBar;
  Indicator := AIndicator;
  BufSize := ABufSize;
  CanUndo := True;
  InitBuffer;
  if Buffer <> nil then
    IsValid := True
  else
  begin
    EditorDialog(edOutOfMemory, nil);
    BufSize := 0;
  end;
  SetBufLen(0);
end;

constructor TEditor.Load(var S: TStream);
begin
  inherited Load(S);
  GetPeerViewPtr(S, HScrollBar);
  GetPeerViewPtr(S, VScrollBar);
  GetPeerViewPtr(S, Indicator);
  S.Read(BufSize, SizeOf(BufSize));
  S.Read(CanUndo, SizeOf(CanUndo));
  InitBuffer;
  if Buffer <> nil then
    IsValid := True
  else
  begin
    EditorDialog(edOutOfMemory, nil);
    BufSize := 0;
  end;
  Lock;
  SetBufLen(0);
end;

procedure TEditor.Store(var S: TStream);
begin
  inherited Store(S);
  PutPeerViewPtr(S, HScrollBar);
  PutPeerViewPtr(S, VScrollBar);
  PutPeerViewPtr(S, Indicator);
  S.Write(BufSize, SizeOf(BufSize));
  S.Write(CanUndo, SizeOf(CanUndo));
end;

destructor TEditor.Done;
begin
  DoneBuffer;
  if UndoBuf <> nil then
    FreeMem(UndoBuf, UndoLen + 1);
  UndoBuf := nil;
  inherited Done;
end;

procedure TEditor.InitBuffer;
begin
  Buffer := nil;
  if BufSize > 0 then
    GetMem(Buffer, BufSize)
  else
    GetMem(Buffer, 1);
end;

procedure TEditor.DoneBuffer;
begin
  if Buffer <> nil then
  begin
    if BufSize > 0 then
      FreeMem(Buffer, BufSize)
    else
      FreeMem(Buffer, 1);
    Buffer := nil;
  end;
end;

{ A fixed buffer: the text fits when it is not larger. }
function TEditor.SetBufSize(NewSize: Sw_Word): Boolean;
begin
  SetBufSize := NewSize <= BufSize;
end;

{ Reallocates the buffer as NewSize bytes, keeping the text on both sides
  of the gap (the part after it moves to the new end). }
function TEditor.GrowBuffer(NewSize: Sw_Word): Boolean;
var
  NewBuf: PEditBuffer;
  After: Sw_Word;
begin
  GrowBuffer := True;
  if NewSize = BufSize then
    Exit;
  if NewSize < BufLen then
  begin
    GrowBuffer := False;
    Exit;
  end;
  GetMem(NewBuf, Max(NewSize, 1));
  After := BufLen - CurPtr;
  if Buffer <> nil then
  begin
    if CurPtr > 0 then
      Move(Buffer^[0], NewBuf^[0], CurPtr);
    if After > 0 then
      Move(Buffer^[CurPtr + GapLen], NewBuf^[NewSize - After], After);
    if BufSize > 0 then
      FreeMem(Buffer, BufSize)
    else
      FreeMem(Buffer, 1);
  end;
  Buffer := NewBuf;
  BufSize := NewSize;
  GapLen := BufSize - BufLen;
end;

{ The text is BufLen bytes at the end of the buffer (the gap is first). }
procedure TEditor.SetBufLen(Length: Sw_Word);
begin
  BufLen := Length;
  GapLen := BufSize - Length;
  SelStart := 0;
  SelEnd := 0;
  CurPtr := 0;
  CurPos.X := 0;
  CurPos.Y := 0;
  Delta.X := 0;
  Delta.Y := 0;
  Limit.X := MaxLineLength;
  CountLines;
  DrawLine := 0;
  DrawPtr := 0;
  DelCount := 0;
  InsCount := 0;
  Modified := False;
  LastKind := ekOther;
  Update(ufView);
end;

function TEditor.BufPtr(P: Sw_Word): Sw_Word;
begin
  if P < CurPtr then
    BufPtr := P
  else
    BufPtr := P + GapLen;
end;

function TEditor.BufChar(P: Sw_Word): Char;
begin
  if P >= BufLen then
    BufChar := #0
  else if P < CurPtr then
    BufChar := Buffer^[P]
  else
    BufChar := Buffer^[P + GapLen];
end;

procedure TEditor.MoveGap(P: Sw_Word);
begin
  if P > BufLen then
    P := BufLen;
  if P < CurPtr then
    Move(Buffer^[P], Buffer^[P + GapLen], CurPtr - P)
  else if P > CurPtr then
    Move(Buffer^[CurPtr + GapLen], Buffer^[CurPtr], P - CurPtr);
  CurPtr := P;
end;

{ ---- TEditor: positions ------------------------------------------------------------ }

function TEditor.IsLineEnd(P: Sw_Word): Boolean;
var
  C: Char;
begin
  C := BufChar(P);
  IsLineEnd := (P < BufLen) and ((C = #10) or (C = #13));
end;

function TEditor.LineStart(P: Sw_Word): Sw_Word;
var
  C: Char;
begin
  while P > 0 do
  begin
    C := BufChar(P - 1);
    if (C = #10) or (C = #13) then
      Break;
    Dec(P);
  end;
  LineStart := P;
end;

function TEditor.LineEnd(P: Sw_Word): Sw_Word;
begin
  while (P < BufLen) and not IsLineEnd(P) do
    Inc(P);
  LineEnd := P;
end;

function TEditor.NextChar(P: Sw_Word): Sw_Word;
begin
  if P >= BufLen then
    NextChar := BufLen
  else if (BufChar(P) = #13) and (P + 1 < BufLen) and (BufChar(P + 1) = #10) then
    NextChar := P + 2
  else
    NextChar := P + 1;
end;

function TEditor.PrevChar(P: Sw_Word): Sw_Word;
begin
  if P = 0 then
    PrevChar := 0
  else if (P >= 2) and (BufChar(P - 1) = #10) and (BufChar(P - 2) = #13) then
    PrevChar := P - 2
  else
    PrevChar := P - 1;
end;

function TEditor.NextLine(P: Sw_Word): Sw_Word;
begin
  NextLine := NextChar(LineEnd(P));
end;

function TEditor.PrevLine(P: Sw_Word): Sw_Word;
begin
  PrevLine := LineStart(PrevChar(LineStart(P)));
end;

function TEditor.NextWord(P: Sw_Word): Sw_Word;
begin
  while (P < BufLen) and (BufChar(P) in WordChars) do
    P := NextChar(P);
  while (P < BufLen) and not (BufChar(P) in WordChars) do
    P := NextChar(P);
  NextWord := P;
end;

function TEditor.PrevWord(P: Sw_Word): Sw_Word;
begin
  while (P > 0) and not (BufChar(PrevChar(P)) in WordChars) do
    P := PrevChar(P);
  while (P > 0) and (BufChar(PrevChar(P)) in WordChars) do
    P := PrevChar(P);
  PrevWord := P;
end;

{ Screen column of Target, counting from the line start P. }
function TEditor.CharPos(P, Target: Sw_Word): Sw_Integer;
var
  Pos: Sw_Integer;
begin
  Pos := 0;
  while P < Target do
  begin
    if BufChar(P) = #9 then
      Pos := (Pos div TabSize + 1) * TabSize
    else
      Inc(Pos);
    Inc(P);
  end;
  CharPos := Pos;
end;

{ Position in the line starting at P of screen column Target. }
function TEditor.CharPtr(P: Sw_Word; Target: Sw_Integer): Sw_Word;
var
  Pos, Next: Sw_Integer;
begin
  Pos := 0;
  while (P < BufLen) and not IsLineEnd(P) do
  begin
    if BufChar(P) = #9 then
      Next := (Pos div TabSize + 1) * TabSize
    else
      Next := Pos + 1;
    if Next > Target then
      Break;
    Pos := Next;
    Inc(P);
  end;
  CharPtr := P;
end;

function TEditor.LineMove(P: Sw_Word; Count: Sw_Integer): Sw_Word;
var
  Col: Sw_Integer;
  Start: Sw_Word;
begin
  Start := LineStart(P);
  Col := CharPos(Start, P);
  while Count < 0 do
  begin
    Start := PrevLine(Start);
    Inc(Count);
  end;
  while Count > 0 do
  begin
    Start := NextLine(Start);
    Dec(Count);
  end;
  LineMove := CharPtr(Start, Col);
end;

{ Line number of P (lines end with LF, CR LF or CR). }
function TEditor.LineOf(P: Sw_Word): Sw_Integer;
var
  I: Sw_Word;
  N: Sw_Integer;
  C: Char;
begin
  N := 0;
  I := 0;
  while I < P do
  begin
    C := BufChar(I);
    if C = #10 then
      Inc(N)
    else if C = #13 then
      if not ((I + 1 < BufLen) and (BufChar(I + 1) = #10)) then
        Inc(N);
    Inc(I);
  end;
  LineOf := N;
end;

function TEditor.LinePtr(N: Sw_Integer): Sw_Word;
var
  P: Sw_Word;
begin
  P := 0;
  while (N > 0) and (P < BufLen) do
  begin
    P := NextLine(P);
    Dec(N);
  end;
  LinePtr := P;
end;

procedure TEditor.CountLines;
begin
  Limit.Y := LineOf(BufLen) + 1;
end;

function TEditor.GetMousePtr(Mouse: TPoint): Sw_Word;
begin
  MakeLocal(Mouse, Mouse);
  Mouse.X := Max(0, Min(Mouse.X, Size.X - 1));
  Mouse.Y := Max(0, Min(Mouse.Y, Size.Y - 1));
  GetMousePtr := CharPtr(LinePtr(Mouse.Y + Delta.Y), Mouse.X + Delta.X);
end;

{ ---- TEditor: display ------------------------------------------------------------- }

procedure TEditor.ChangeBounds(var Bounds: TRect);
begin
  SetBounds(Bounds);
  Delta.X := Max(0, Min(Delta.X, Limit.X - Size.X));
  Delta.Y := Max(0, Min(Delta.Y, Limit.Y - Size.Y));
  Update(ufView);
end;

function TEditor.CursorVisible: Boolean;
begin
  CursorVisible := (CurPos.Y >= Delta.Y) and (CurPos.Y < Delta.Y + Size.Y);
end;

procedure TEditor.Draw;
var
  B: TDrawBuffer;
  Y, Col: Sw_Integer;
  P, LinePos: Sw_Word;
  Normal, Selected, Color: Byte;
  C: Char;
begin
  Normal := GetColor(1);
  Selected := GetColor(2);
  P := LinePtr(Delta.Y);
  DrawLine := Delta.Y;
  DrawPtr := P;
  for Y := 0 to Size.Y - 1 do
  begin
    MoveChar(B, ' ', Normal, Size.X);
    if (Delta.Y + Y < Limit.Y) then
    begin
      LinePos := P;
      Col := 0;
      while (P < BufLen) and not IsLineEnd(P) and (Col < Delta.X + Size.X) do
      begin
        C := BufChar(P);
        if (P >= SelStart) and (P < SelEnd) then
          Color := Selected
        else
          Color := Normal;
        if C = #9 then
        begin
          repeat
            if (Col >= Delta.X) and (Col < Delta.X + Size.X) then
              MoveChar(B[Col - Delta.X], ' ', Color, 1);
            Inc(Col);
          until Col mod TabSize = 0;
        end
        else
        begin
          if Col >= Delta.X then
            MoveChar(B[Col - Delta.X], C, Color, 1);
          Inc(Col);
        end;
        Inc(P);
      end;
      { A selected line end shows as one selected cell. }
      if (P < BufLen) and IsLineEnd(P) and (P >= SelStart) and (P < SelEnd) and (Col >= Delta.X) and
        (Col < Delta.X + Size.X) then
        MoveChar(B[Col - Delta.X], ' ', Selected, 1);
      P := NextLine(LinePos);
    end;
    WriteLine(0, Y, Size.X, 1, B);
  end;
end;

function TEditor.GetPalette: PPalette;
const
  P: String[Length(CEditor)] = CEditor;
begin
  GetPalette := @P;
end;

procedure TEditor.Lock;
begin
  Inc(LockCount);
end;

procedure TEditor.Unlock;
begin
  if LockCount > 0 then
  begin
    Dec(LockCount);
    if LockCount = 0 then
      DoUpdate;
  end;
end;

procedure TEditor.Update(AFlags: Byte);
begin
  UpdateFlags := UpdateFlags or AFlags;
  if LockCount = 0 then
    DoUpdate;
end;

procedure TEditor.DoUpdate;
begin
  if UpdateFlags = 0 then
    Exit;
  SetCursor(CurPos.X - Delta.X, CurPos.Y - Delta.Y);
  if UpdateFlags and (ufView + ufLine) <> 0 then
    DrawView;
  if HScrollBar <> nil then
    HScrollBar^.SetParams(Delta.X, 0, Max(0, Limit.X - Size.X), Size.X div 2, 1);
  if VScrollBar <> nil then
    VScrollBar^.SetParams(Delta.Y, 0, Max(0, Limit.Y - Size.Y), Size.Y - 1, 1);
  if Indicator <> nil then
    Indicator^.SetValue(CurPos, Modified);
  if State and sfActive <> 0 then
    UpdateCommands;
  UpdateFlags := 0;
end;

procedure TEditor.ScrollTo(X, Y: Sw_Integer);
begin
  X := Max(0, Min(X, Limit.X - Size.X));
  Y := Max(0, Min(Y, Limit.Y - Size.Y));
  if (X <> Delta.X) or (Y <> Delta.Y) then
  begin
    Delta.X := X;
    Delta.Y := Y;
    Update(ufView);
  end;
end;

procedure TEditor.TrackCursor(Center: Boolean);
begin
  if Center then
    ScrollTo(CurPos.X - Size.X + 1, CurPos.Y - Size.Y div 2)
  else
    ScrollTo(Max(CurPos.X - Size.X + 1, Min(Delta.X, CurPos.X)), Max(CurPos.Y - Size.Y + 1, Min(Delta.Y, CurPos.Y)));
end;

{ ---- TEditor: cursor and selection ---------------------------------------------------- }

procedure TEditor.SetSelect(NewStart, NewEnd: Sw_Word; CurStart: Boolean);
var
  P: Sw_Word;
begin
  if NewStart > BufLen then
    NewStart := BufLen;
  if NewEnd > BufLen then
    NewEnd := BufLen;
  if NewEnd < NewStart then
    NewEnd := NewStart;
  if CurStart then
    P := NewStart
  else
    P := NewEnd;
  if P <> CurPtr then
  begin
    MoveGap(P);
    LastKind := ekOther;
  end;
  if (NewStart <> SelStart) or (NewEnd <> SelEnd) then
    Update(ufView);
  SelStart := NewStart;
  SelEnd := NewEnd;
  CurPos.Y := LineOf(CurPtr);
  CurPos.X := CharPos(LineStart(CurPtr), CurPtr);
  Update(ufUpdate);
end;

procedure TEditor.SetCurPtr(P: Sw_Word; SelectMode: Byte);
var
  Anchor: Sw_Word;
begin
  if SelectMode and smExtend = 0 then
    Anchor := P
  else if CurPtr = SelStart then
    Anchor := SelEnd
  else
    Anchor := SelStart;
  if P < Anchor then
  begin
    if SelectMode and smDouble <> 0 then
    begin
      P := LineStart(P);
      Anchor := NextLine(Anchor);
    end;
    SetSelect(P, Anchor, True);
  end
  else
  begin
    if SelectMode and smDouble <> 0 then
    begin
      P := NextLine(P);
      Anchor := LineStart(Anchor);
    end;
    SetSelect(Anchor, P, False);
  end;
end;

function TEditor.HasSelection: Boolean;
begin
  HasSelection := SelStart <> SelEnd;
end;

procedure TEditor.HideSelect;
begin
  Selecting := False;
  SetSelect(CurPtr, CurPtr, False);
end;

procedure TEditor.StartSelect;
begin
  HideSelect;
  Selecting := True;
end;

procedure TEditor.ToggleInsMode;
begin
  Overwrite := not Overwrite;
  SetState(sfCursorIns, not GetState(sfCursorIns));
end;

{ ---- TEditor: editing ----------------------------------------------------------------- }

{ Replaces [StartPtr, EndPtr) by Len bytes of Text; the cursor ends after
  the new text. The single undo step keeps a copy of the text before the
  first edit of a run. }
function TEditor.ReplaceRange(StartPtr, EndPtr: Sw_Word; Text: Pointer; Len: Sw_Word; Kind: Integer): Boolean;
var
  NewLen, N: Sw_Word;
  Continues: Boolean;
begin
  ReplaceRange := True;
  if EndPtr > BufLen then
    EndPtr := BufLen;
  if StartPtr > EndPtr then
    StartPtr := EndPtr;
  if (StartPtr = EndPtr) and (Len = 0) then
    Exit;
  NewLen := BufLen - (EndPtr - StartPtr) + Len;
  if NewLen > BufSize then
    if not SetBufSize(NewLen) then
    begin
      EditorDialog(edOutOfMemory, nil);
      ReplaceRange := False;
      Exit;
    end;
  if CanUndo then
  begin
    Continues := (Kind <> ekOther) and (Kind = LastKind) and
      (((Kind = ekInsert) and (StartPtr = LastEdit)) or
      ((Kind = ekDelete) and ((EndPtr = LastEdit) or (StartPtr = LastEdit))));
    if not Continues then
    begin
      if UndoBuf <> nil then
        FreeMem(UndoBuf, UndoLen + 1);
      UndoLen := BufLen;
      GetMem(UndoBuf, UndoLen + 1);
      N := 0;
      while N < BufLen do
      begin
        UndoBuf^[N] := BufChar(N);
        Inc(N);
      end;
      UndoPtr := CurPtr;
    end;
  end;
  MoveGap(StartPtr);
  N := EndPtr - StartPtr;
  Inc(GapLen, N);
  Dec(BufLen, N);
  if Len > 0 then
  begin
    Move(Text^, Buffer^[CurPtr], Len);
    Inc(CurPtr, Len);
    Dec(GapLen, Len);
    Inc(BufLen, Len);
  end;
  LastEdit := CurPtr;
  LastKind := Kind;
  Modified := True;
  SelStart := CurPtr;
  SelEnd := CurPtr;
  CountLines;
  CurPos.Y := LineOf(CurPtr);
  CurPos.X := CharPos(LineStart(CurPtr), CurPtr);
  Update(ufView);
end;

function TEditor.InsertText(Text: Pointer; Length: Sw_Word; SelectText: Boolean): Boolean;
var
  Start: Sw_Word;
  Kind: Integer;
begin
  Start := SelStart;
  if HasSelection or (Length <> 1) then
    Kind := ekOther
  else
    Kind := ekInsert;
  InsertText := ReplaceRange(SelStart, SelEnd, Text, Length, Kind);
  if SelectText then
    SetSelect(Start, Start + Length, False);
end;

function TEditor.InsertBuffer(var P: PEditBuffer; Offset, Length: Sw_Word; AllowUndo, SelectText: Boolean): Boolean;
var
  SaveUndo: Boolean;
begin
  SaveUndo := CanUndo;
  CanUndo := CanUndo and AllowUndo;
  if Length = 0 then
    InsertBuffer := InsertText(nil, 0, SelectText)
  else
    InsertBuffer := InsertText(@P^[Offset], Length, SelectText);
  CanUndo := SaveUndo;
end;

{ Inserts the selection of Editor (copied out of its gap buffer). }
function TEditor.InsertFrom(Editor: PEditor): Boolean;
var
  Tmp: PEditBuffer;
  N, I: Sw_Word;
begin
  N := Editor^.SelEnd - Editor^.SelStart;
  if N = 0 then
  begin
    InsertFrom := InsertText(nil, 0, IsClipboard);
    Exit;
  end;
  GetMem(Tmp, N);
  I := 0;
  while I < N do
  begin
    Tmp^[I] := Editor^.BufChar(Editor^.SelStart + I);
    Inc(I);
  end;
  InsertFrom := InsertBuffer(Tmp, 0, N, CanUndo, IsClipboard);
  FreeMem(Tmp, N);
end;

procedure TEditor.DeleteRange(StartPtr, EndPtr: Sw_Word; DelSelect: Boolean);
begin
  if HasSelection and DelSelect then
    DeleteSelect
  else
    ReplaceRange(StartPtr, EndPtr, nil, 0, ekDelete);
end;

procedure TEditor.DeleteSelect;
begin
  if HasSelection then
    ReplaceRange(SelStart, SelEnd, nil, 0, ekOther);
end;

procedure TEditor.NewLine;
var
  S: String;
  P: Sw_Word;
begin
  S := #10;
  if AutoIndent then
  begin
    P := LineStart(CurPtr);
    while (P < CurPtr) and ((BufChar(P) = ' ') or (BufChar(P) = #9)) and (Length(S) < 255) do
    begin
      S := S + BufChar(P);
      Inc(P);
    end;
  end;
  InsertText(@S[1], Length(S), False);
end;

procedure TEditor.Undo;
var
  Tmp: PEditBuffer;
  TmpLen, I, P: Sw_Word;
begin
  if not CanUndo or (UndoBuf = nil) then
    Exit;
  { Swap the snapshot and the text, so Undo again redoes. }
  TmpLen := BufLen;
  GetMem(Tmp, TmpLen + 1);
  I := 0;
  while I < TmpLen do
  begin
    Tmp^[I] := BufChar(I);
    Inc(I);
  end;
  P := UndoPtr;
  UndoPtr := CurPtr;
  if not SetBufSize(UndoLen) then
  begin
    FreeMem(Tmp, TmpLen + 1);
    Exit;
  end;
  MoveGap(0);
  BufLen := UndoLen;
  GapLen := BufSize - BufLen;
  if UndoLen > 0 then
    Move(UndoBuf^[0], Buffer^[GapLen], UndoLen);
  FreeMem(UndoBuf, UndoLen + 1);
  UndoBuf := Tmp;
  UndoLen := TmpLen;
  LastKind := ekOther;
  Modified := True;
  CountLines;
  SelStart := 0;
  SelEnd := 0;
  SetSelect(P, P, False);
  Update(ufView);
end;

{ ---- TEditor: clipboard, search ---------------------------------------------------------- }

function TEditor.IsClipboard: Boolean;
begin
  IsClipboard := Clipboard = @Self;
end;

function TEditor.ClipCopy: Boolean;
begin
  ClipCopy := False;
  if (Clipboard <> nil) and (Clipboard <> @Self) then
  begin
    ClipCopy := Clipboard^.InsertFrom(@Self);
    Selecting := False;
    Update(ufUpdate);
  end;
end;

procedure TEditor.ClipCut;
begin
  if ClipCopy then
    DeleteSelect;
end;

procedure TEditor.ClipPaste;
begin
  if (Clipboard <> nil) and (Clipboard <> @Self) then
    InsertFrom(Clipboard);
end;

function TEditor.Search(const FindStr: String; Opts: Word): Boolean;
var
  P, I, L: Sw_Word;
  Match: Boolean;

  function Same(A, B: Char): Boolean;
  begin
    if Opts and efCaseSensitive <> 0 then
      Same := A = B
    else
      Same := UpCase(A) = UpCase(B);
  end;

begin
  Search := False;
  L := Length(FindStr);
  if (L = 0) or (L > BufLen) then
    Exit;
  P := CurPtr;
  while P + L <= BufLen do
  begin
    Match := True;
    I := 0;
    while Match and (I < L) do
    begin
      if not Same(BufChar(P + I), FindStr[I + 1]) then
        Match := False;
      Inc(I);
    end;
    if Match and (Opts and efWholeWordsOnly <> 0) then
      if ((P > 0) and (BufChar(P - 1) in WordChars)) or ((P + L < BufLen) and (BufChar(P + L) in WordChars)) then
        Match := False;
    if Match then
    begin
      Lock;
      SetSelect(P, P + L, False);
      TrackCursor(not CursorVisible);
      Unlock;
      Search := True;
      Exit;
    end;
    Inc(P);
  end;
end;

procedure TEditor.Find;
var
  Rec: TFindDialogRec;
begin
  Rec.Find := FindStr;
  Rec.Options := EditorFlags;
  if EditorDialog(edFind, @Rec) <> cmCancel then
  begin
    FindStr := Rec.Find;
    EditorFlags := Rec.Options and not efDoReplace;
    DoSearchReplace;
  end;
end;

procedure TEditor.Replace;
var
  Rec: TReplaceDialogRec;
begin
  Rec.Find := FindStr;
  Rec.Replace := ReplaceStr;
  Rec.Options := EditorFlags;
  if EditorDialog(edReplace, @Rec) <> cmCancel then
  begin
    FindStr := Rec.Find;
    ReplaceStr := Rec.Replace;
    EditorFlags := Rec.Options or efDoReplace;
    DoSearchReplace;
  end;
end;

procedure TEditor.DoSearchReplace;
var
  I: Word;
  C: TPoint;
begin
  repeat
    I := cmCancel;
    if not Search(FindStr, EditorFlags) then
    begin
      if EditorFlags and (efReplaceAll + efDoReplace) <> (efReplaceAll + efDoReplace) then
        EditorDialog(edSearchFailed, nil);
    end
    else if EditorFlags and efDoReplace <> 0 then
    begin
      I := cmYes;
      if EditorFlags and efPromptOnReplace <> 0 then
      begin
        MakeGlobal(Cursor, C);
        I := EditorDialog(edReplacePrompt, @C);
      end;
      if I = cmYes then
      begin
        Lock;
        InsertText(@ReplaceStr[1], Length(ReplaceStr), False);
        TrackCursor(False);
        Unlock;
      end;
    end;
  until (I = cmCancel) or (EditorFlags and efReplaceAll = 0);
end;

{ ---- TEditor: events ---------------------------------------------------------------- }

{ Turns keys into editor commands (TP WordStar keys, with ^K and ^Q
  prefixes kept in KeyState). }
procedure TEditor.ConvertEvent(var Event: TEvent);
var
  Ch: Char;
  Cmd: Word;
begin
  if Event.What <> evKeyDown then
    Exit;
  Cmd := 0;
  if KeyState <> 0 then
  begin
    Ch := Event.CharCode;
    if (Ch >= #1) and (Ch <= #26) then
      Ch := Chr(Ord(Ch) + 64)
    else
      Ch := UpCase(Ch);
    if KeyState = 1 then
      case Ch of
        'B': Cmd := cmStartSelect;
        'C': Cmd := cmPaste;
        'H': Cmd := cmHideSelect;
        'K': Cmd := cmCopy;
        'Y': Cmd := cmCut;
      end
    else
      case Ch of
        'A': Cmd := cmReplace;
        'C': Cmd := cmTextEnd;
        'D': Cmd := cmLineEnd;
        'F': Cmd := cmFind;
        'H': Cmd := cmDelStart;
        'R': Cmd := cmTextStart;
        'S': Cmd := cmLineStart;
        'Y': Cmd := cmDelEnd;
      end;
    KeyState := 0;
    if Cmd = 0 then
    begin
      ClearEvent(Event);
      Exit;
    end;
  end
  else
  begin
    case Event.KeyCode of
      kbLeft: Cmd := cmCharLeft;
      kbRight: Cmd := cmCharRight;
      kbCtrlLeft: Cmd := cmWordLeft;
      kbCtrlRight: Cmd := cmWordRight;
      kbHome: Cmd := cmLineStart;
      kbEnd: Cmd := cmLineEnd;
      kbUp: Cmd := cmLineUp;
      kbDown: Cmd := cmLineDown;
      kbPgUp: Cmd := cmPageUp;
      kbPgDn: Cmd := cmPageDown;
      kbCtrlPgUp: Cmd := cmTextStart;
      kbCtrlPgDn: Cmd := cmTextEnd;
      kbIns: Cmd := cmInsMode;
      kbDel: Cmd := cmDelChar;
      kbShiftIns: Cmd := cmPaste;
      kbShiftDel: Cmd := cmCut;
      kbCtrlIns: Cmd := cmCopy;
      kbCtrlDel: Cmd := cmClear;
      kbEnter: Cmd := cmNewLine;
      kbBack: Cmd := cmBackSpace;
    else
      case Event.CharCode of
        ^A: Cmd := cmWordLeft;
        ^C: Cmd := cmPageDown;
        ^D: Cmd := cmCharRight;
        ^E: Cmd := cmLineUp;
        ^F: Cmd := cmWordRight;
        ^G: Cmd := cmDelChar;
        ^H: Cmd := cmBackSpace;
        ^K: KeyState := 1;
        ^L: Cmd := cmSearchAgain;
        ^M: Cmd := cmNewLine;
        ^O: Cmd := cmIndentMode;
        ^Q: KeyState := 2;
        ^R: Cmd := cmPageUp;
        ^S: Cmd := cmCharLeft;
        ^T: Cmd := cmDelWord;
        ^U: Cmd := cmUndo;
        ^V: Cmd := cmInsMode;
        ^X: Cmd := cmLineDown;
        ^Y: Cmd := cmDelLine;
      end;
    end;
    if KeyState <> 0 then
    begin
      ClearEvent(Event);
      Exit;
    end;
  end;
  if Cmd <> 0 then
  begin
    Event.What := evCommand;
    Event.Command := Cmd;
    Event.InfoPtr := nil;
  end;
end;

procedure TEditor.HandleEvent(var Event: TEvent);
var
  ShiftState: Byte;
  CenterCursor: Boolean;
  SelectMode: Byte;
  Mouse: TPoint;
  D: Sw_Integer;
  Ch: Char;
begin
  ShiftState := GetShiftState;
  ConvertEvent(Event);
  CenterCursor := not CursorVisible;
  SelectMode := 0;
  if Selecting or ((ShiftState and (kbRightShift + kbLeftShift) <> 0) and (Event.What = evCommand) and
    (Event.Command >= cmCharLeft) and (Event.Command <= cmTextEnd)) then
    SelectMode := smExtend;
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      begin
        if Event.Double then
          SelectMode := SelectMode or smDouble;
        repeat
          Lock;
          if Event.What = evMouseAuto then
          begin
            MakeLocal(Event.Where, Mouse);
            D := Delta.Y;
            if Mouse.Y < 0 then
              Dec(D)
            else if Mouse.Y >= Size.Y then
              Inc(D);
            ScrollTo(Delta.X, D);
          end;
          SetCurPtr(GetMousePtr(Event.Where), SelectMode);
          SelectMode := SelectMode or smExtend;
          Unlock;
        until not MouseEvent(Event, evMouseMove + evMouseAuto);
      end;
    evKeyDown:
      begin
        Ch := Event.CharCode;
        if (Ch = #9) or (Ch >= ' ') then
        begin
          Lock;
          if Overwrite and not HasSelection then
            if CurPtr <> LineEnd(CurPtr) then
              SelEnd := NextChar(CurPtr);
          InsertText(@Ch, 1, False);
          TrackCursor(CenterCursor);
          Unlock;
        end
        else
          Exit;
      end;
    evCommand:
      case Event.Command of
        cmFind: Find;
        cmReplace: Replace;
        cmSearchAgain: DoSearchReplace;
      else
        begin
          Lock;
          case Event.Command of
            cmCut: ClipCut;
            cmCopy: ClipCopy;
            cmPaste: ClipPaste;
            cmUndo: Undo;
            cmClear: DeleteSelect;
            cmCharLeft: SetCurPtr(PrevChar(CurPtr), SelectMode);
            cmCharRight: SetCurPtr(NextChar(CurPtr), SelectMode);
            cmWordLeft: SetCurPtr(PrevWord(CurPtr), SelectMode);
            cmWordRight: SetCurPtr(NextWord(CurPtr), SelectMode);
            cmLineStart: SetCurPtr(LineStart(CurPtr), SelectMode);
            cmLineEnd: SetCurPtr(LineEnd(CurPtr), SelectMode);
            cmLineUp: SetCurPtr(LineMove(CurPtr, -1), SelectMode);
            cmLineDown: SetCurPtr(LineMove(CurPtr, 1), SelectMode);
            cmPageUp: SetCurPtr(LineMove(CurPtr, -(Size.Y - 1)), SelectMode);
            cmPageDown: SetCurPtr(LineMove(CurPtr, Size.Y - 1), SelectMode);
            cmTextStart: SetCurPtr(0, SelectMode);
            cmTextEnd: SetCurPtr(BufLen, SelectMode);
            cmNewLine: NewLine;
            cmBackSpace: DeleteRange(PrevChar(CurPtr), CurPtr, True);
            cmDelChar: DeleteRange(CurPtr, NextChar(CurPtr), True);
            cmDelWord: DeleteRange(CurPtr, NextWord(CurPtr), False);
            cmDelStart: DeleteRange(LineStart(CurPtr), CurPtr, False);
            cmDelEnd: DeleteRange(CurPtr, LineEnd(CurPtr), False);
            cmDelLine: DeleteRange(LineStart(CurPtr), NextLine(CurPtr), False);
            cmInsMode: ToggleInsMode;
            cmStartSelect: StartSelect;
            cmHideSelect: HideSelect;
            cmIndentMode: AutoIndent := not AutoIndent;
          else
            begin
              Unlock;
              Exit;
            end;
          end;
          TrackCursor(CenterCursor);
          Unlock;
        end;
      end;
    evBroadcast:
      if (Event.Command = cmScrollBarChanged) and
        ((Event.InfoPtr = HScrollBar) or (Event.InfoPtr = VScrollBar)) then
      begin
        if HScrollBar <> nil then
          D := HScrollBar^.Value
        else
          D := Delta.X;
        if VScrollBar <> nil then
          ScrollTo(D, VScrollBar^.Value)
        else
          ScrollTo(D, Delta.Y);
      end
      else
        Exit;
  else
    Exit;
  end;
  ClearEvent(Event);
end;

procedure TEditor.SetCmdState(Command: Word; Enable: Boolean);
var
  S: TCommandSet;
begin
  S := [Command];
  if Enable and (State and sfActive <> 0) then
    EnableCommands(S)
  else
    DisableCommands(S);
end;

procedure TEditor.SetState(AState: Word; Enable: Boolean);

  procedure ShowView(P: PView);
  begin
    if P <> nil then
      if GetState(sfActive) then
        P^.Show
      else
        P^.Hide;
  end;

begin
  inherited SetState(AState, Enable);
  case AState of
    sfActive:
      begin
        ShowView(HScrollBar);
        ShowView(VScrollBar);
        ShowView(Indicator);
        UpdateCommands;
      end;
    sfExposed:
      if Enable then
        Unlock;
  end;
end;

procedure TEditor.UpdateCommands;
begin
  SetCmdState(cmUndo, CanUndo and (UndoBuf <> nil));
  SetCmdState(cmCut, HasSelection);
  SetCmdState(cmCopy, HasSelection);
  SetCmdState(cmPaste, (Clipboard <> nil) and Clipboard^.HasSelection);
  SetCmdState(cmClear, HasSelection);
  SetCmdState(cmFind, True);
  SetCmdState(cmReplace, True);
  SetCmdState(cmSearchAgain, True);
end;

function TEditor.Valid(Command: Word): Boolean;
begin
  Valid := IsValid;
end;

{ ---- TMemo -------------------------------------------------------------------------------- }

constructor TMemo.Load(var S: TStream);
var
  Length: Sw_Word;
begin
  inherited Load(S);
  Length := 0;
  S.Read(Length, SizeOf(Length));
  if IsValid and (Length <= BufSize) then
  begin
    S.Read(Buffer^[BufSize - Length], Length);
    SetBufLen(Length);
  end
  else
    S.Seek(S.GetPos + Length);
  Unlock;
end;

procedure TMemo.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(BufLen, SizeOf(BufLen));
  if CurPtr > 0 then
    S.Write(Buffer^[0], CurPtr);
  if BufLen > CurPtr then
    S.Write(Buffer^[CurPtr + GapLen], BufLen - CurPtr);
end;

function TMemo.DataSize: Word;
begin
  DataSize := BufSize + SizeOf(Sw_Word);
end;

procedure TMemo.GetData(var Rec);
var
  I: Sw_Word;
begin
  TMemoData(Rec).Length := BufLen;
  I := 0;
  while I < BufSize do
  begin
    TMemoData(Rec).Buffer[I] := BufChar(I);
    Inc(I);
  end;
end;

procedure TMemo.SetData(var Rec);
var
  N: Sw_Word;
begin
  N := TMemoData(Rec).Length;
  if N > BufSize then
    N := BufSize;
  if N > 0 then
    Move(TMemoData(Rec).Buffer[0], Buffer^[BufSize - N], N);
  SetBufLen(N);
end;

function TMemo.GetPalette: PPalette;
const
  P: String[Length(CMemo)] = CMemo;
begin
  GetPalette := @P;
end;

procedure TMemo.HandleEvent(var Event: TEvent);
begin
  if (Event.What <> evKeyDown) or (Event.KeyCode <> kbTab) then
    inherited HandleEvent(Event);
end;

{ ---- TFileEditor ------------------------------------------------------------------------------ }

constructor TFileEditor.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; AIndicator: PIndicator;
  AFileName: FNameStr);
begin
  inherited Init(Bounds, AHScrollBar, AVScrollBar, AIndicator, 0);
  if AFileName <> '' then
  begin
    FileName := FExpand(AFileName);
    if IsValid then
      IsValid := LoadFile;
  end;
end;

constructor TFileEditor.Load(var S: TStream);
var
  SStart, SEnd, Cur: Sw_Word;
begin
  inherited Load(S);
  BufSize := 0;
  FileName := '';
  S.Read(FileName[0], 1);
  S.Read(FileName[1], Length(FileName));
  if IsValid then
    IsValid := LoadFile;
  S.Read(SStart, SizeOf(SStart));
  S.Read(SEnd, SizeOf(SEnd));
  S.Read(Cur, SizeOf(Cur));
  if IsValid and (SEnd <= BufLen) then
  begin
    SetSelect(SStart, SEnd, Cur = SStart);
    TrackCursor(True);
  end;
  Unlock;
end;

procedure TFileEditor.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(FileName, Length(FileName) + 1);
  S.Write(SelStart, SizeOf(SelStart));
  S.Write(SelEnd, SizeOf(SelEnd));
  S.Write(CurPtr, SizeOf(CurPtr));
end;

procedure TFileEditor.InitBuffer;
begin
  BufSize := 0;
  GetMem(Buffer, 1);
end;

procedure TFileEditor.DoneBuffer;
begin
  inherited DoneBuffer;
end;

{ Grows (or shrinks) in 4 KB steps. }
function TFileEditor.SetBufSize(NewSize: Sw_Word): Boolean;
var
  N: Sw_Word;
begin
  N := (NewSize + $0FFF) and not Sw_Word($0FFF);
  if N < NewSize then
    N := NewSize;
  SetBufSize := GrowBuffer(N);
end;

function TFileEditor.LoadFile: Boolean;
var
  F: File;
  FSize: LongInt;
  Got: LongInt;
begin
  LoadFile := False;
  Assign(F, FileName);
  Reset(F, 1);
  if IOResult <> 0 then
  begin
    { A new file. }
    LoadFile := True;
    Exit;
  end;
  FSize := FileSize(F);
  if not SetBufSize(FSize) then
  begin
    EditorDialog(edOutOfMemory, nil);
    Close(F);
    Exit;
  end;
  Got := 0;
  if FSize > 0 then
    BlockRead(F, Buffer^[BufSize - FSize], FSize, Got);
  Close(F);
  if (IOResult <> 0) or (Got <> FSize) then
  begin
    EditorDialog(edReadError, @FileName);
    Exit;
  end;
  SetBufLen(FSize);
  LoadFile := True;
end;

function TFileEditor.SaveFile: Boolean;
var
  F: File;
  BackupName: FNameStr;
  D: DirStr;
  N: NameStr;
  E: ExtStr;
begin
  SaveFile := False;
  if EditorFlags and efBackupFiles <> 0 then
  begin
    FSplit(FileName, D, N, E);
    BackupName := D + N + '.bak';
    Assign(F, BackupName);
    Erase(F);
    if IOResult <> 0 then;
    Assign(F, FileName);
    Rename(F, BackupName);
    if IOResult <> 0 then;
  end;
  Assign(F, FileName);
  Rewrite(F, 1);
  if IOResult <> 0 then
  begin
    EditorDialog(edCreateError, @FileName);
    Exit;
  end;
  if CurPtr > 0 then
    BlockWrite(F, Buffer^[0], CurPtr);
  if BufLen > CurPtr then
    BlockWrite(F, Buffer^[CurPtr + GapLen], BufLen - CurPtr);
  Close(F);
  if IOResult <> 0 then
  begin
    EditorDialog(edWriteError, @FileName);
    Exit;
  end;
  Modified := False;
  Update(ufUpdate);
  SaveFile := True;
end;

function TFileEditor.Save: Boolean;
begin
  if FileName = '' then
    Save := SaveAs
  else
    Save := SaveFile;
end;

function TFileEditor.SaveAs: Boolean;
begin
  SaveAs := False;
  if EditorDialog(edSaveAs, @FileName) <> cmCancel then
  begin
    FileName := FExpand(FileName);
    Message(Owner, evBroadcast, cmUpdateTitle, nil);
    SaveAs := SaveFile;
    if IsClipboard then
      FileName := '';
  end;
end;

procedure TFileEditor.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evCommand then
    case Event.Command of
      cmSave:
        begin
          Save;
          ClearEvent(Event);
        end;
      cmSaveAs:
        begin
          SaveAs;
          ClearEvent(Event);
        end;
    end;
end;

procedure TFileEditor.UpdateCommands;
begin
  inherited UpdateCommands;
  SetCmdState(cmSave, True);
  SetCmdState(cmSaveAs, True);
end;

function TFileEditor.Valid(Command: Word): Boolean;
var
  D: Integer;
begin
  if Command = cmValid then
    Valid := IsValid
  else
  begin
    Valid := True;
    if Modified then
    begin
      if FileName = '' then
        D := edSaveUntitled
      else
        D := edSaveModify;
      case EditorDialog(D, @FileName) of
        cmYes: Valid := Save;
        cmNo: Modified := False;
        cmCancel: Valid := False;
      end;
    end;
  end;
end;

{ ---- TEditWindow ---------------------------------------------------------------------------------- }

constructor TEditWindow.Init(var Bounds: TRect; FileName: FNameStr; ANumber: Integer);
var
  R: TRect;
  HBar, VBar: PScrollBar;
  Ind: PIndicator;
begin
  inherited Init(Bounds, '', ANumber);
  Options := Options or ofTileable;
  R.Assign(18, Size.Y - 1, Size.X - 2, Size.Y);
  HBar := New(PScrollBar, Init(R));
  HBar^.Hide;
  Insert(HBar);
  R.Assign(Size.X - 1, 1, Size.X, Size.Y - 1);
  VBar := New(PScrollBar, Init(R));
  VBar^.Hide;
  Insert(VBar);
  R.Assign(2, Size.Y - 1, 16, Size.Y);
  Ind := New(PIndicator, Init(R));
  Ind^.Hide;
  Insert(Ind);
  GetExtent(R);
  R.Grow(-1, -1);
  Editor := New(PFileEditor, Init(R, HBar, VBar, Ind, FileName));
  Insert(Editor);
end;

constructor TEditWindow.Load(var S: TStream);
begin
  inherited Load(S);
  GetSubViewPtr(S, Editor);
end;

procedure TEditWindow.Store(var S: TStream);
begin
  inherited Store(S);
  PutSubViewPtr(S, Editor);
end;

procedure TEditWindow.Close;
begin
  if Editor^.IsClipboard then
    Hide
  else
    inherited Close;
end;

function TEditWindow.GetTitle(MaxSize: Sw_Integer): TTitleStr;
var
  S: String;
begin
  if Editor^.IsClipboard then
    S := 'Clipboard'
  else if Editor^.FileName = '' then
    S := 'Untitled'
  else
    S := Editor^.FileName;
  if Length(S) > MaxSize then
    S := '...' + Copy(S, Length(S) - MaxSize + 4, 255);
  GetTitle := S;
end;

procedure TEditWindow.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmUpdateTitle) then
  begin
    if Frame <> nil then
      Frame^.DrawView;
    ClearEvent(Event);
  end;
end;

procedure TEditWindow.SizeLimits(var Min, Max: TPoint);
begin
  inherited SizeLimits(Min, Max);
  Min.X := 23;
end;

{ ---- dialogs ------------------------------------------------------------------------------------ }

function CreateFindDialog: PDialog;
var
  D: PDialog;
  Control: PView;
  R: TRect;
begin
  R.Assign(0, 0, 38, 12);
  D := New(PDialog, Init(R, 'Find'));
  D^.Options := D^.Options or ofCentered;
  R.Assign(3, 3, 32, 4);
  Control := New(PInputLine, Init(R, 80));
  D^.Insert(Control);
  R.Assign(2, 2, 15, 3);
  D^.Insert(New(PLabel, Init(R, '~T~ext to find', Control)));
  R.Assign(32, 3, 35, 4);
  D^.Insert(New(PHistory, Init(R, PInputLine(Control), 10)));
  R.Assign(3, 5, 35, 7);
  D^.Insert(New(PCheckBoxes, Init(R, NewSItem('~C~ase sensitive', NewSItem('~W~hole words only', nil)))));
  R.Assign(14, 9, 24, 11);
  D^.Insert(New(PButton, Init(R, 'O~K~', cmOK, bfDefault)));
  Inc(R.A.X, 12);
  Inc(R.B.X, 12);
  D^.Insert(New(PButton, Init(R, 'Cancel', cmCancel, bfNormal)));
  D^.SelectNext(False);
  CreateFindDialog := D;
end;

function CreateReplaceDialog: PDialog;
var
  D: PDialog;
  Control: PView;
  R: TRect;
begin
  R.Assign(0, 0, 40, 16);
  D := New(PDialog, Init(R, 'Replace'));
  D^.Options := D^.Options or ofCentered;
  R.Assign(3, 3, 34, 4);
  Control := New(PInputLine, Init(R, 80));
  D^.Insert(Control);
  R.Assign(2, 2, 15, 3);
  D^.Insert(New(PLabel, Init(R, '~T~ext to find', Control)));
  R.Assign(34, 3, 37, 4);
  D^.Insert(New(PHistory, Init(R, PInputLine(Control), 10)));
  R.Assign(3, 6, 34, 7);
  Control := New(PInputLine, Init(R, 80));
  D^.Insert(Control);
  R.Assign(2, 5, 12, 6);
  D^.Insert(New(PLabel, Init(R, '~N~ew text', Control)));
  R.Assign(34, 6, 37, 7);
  D^.Insert(New(PHistory, Init(R, PInputLine(Control), 11)));
  R.Assign(3, 8, 37, 12);
  D^.Insert(New(PCheckBoxes, Init(R, NewSItem('~C~ase sensitive', NewSItem('~W~hole words only',
    NewSItem('~P~rompt on replace', NewSItem('~R~eplace all', nil)))))));
  R.Assign(17, 13, 27, 15);
  D^.Insert(New(PButton, Init(R, 'O~K~', cmOK, bfDefault)));
  R.Assign(28, 13, 38, 15);
  D^.Insert(New(PButton, Init(R, 'Cancel', cmCancel, bfNormal)));
  D^.SelectNext(False);
  CreateReplaceDialog := D;
end;

function StdEditorDialog(Dialog: Integer; Info: Pointer): Word;
var
  R: TRect;
  T: TPoint;
  P: PtrInt;
begin
  P := PtrInt(Info);
  case Dialog of
    edOutOfMemory:
      StdEditorDialog := MessageBox('Not enough memory for this operation.', nil, mfError + mfOKButton);
    edReadError:
      StdEditorDialog := MessageBox('Error reading file %s.', @P, mfError + mfOKButton);
    edWriteError:
      StdEditorDialog := MessageBox('Error writing file %s.', @P, mfError + mfOKButton);
    edCreateError:
      StdEditorDialog := MessageBox('Error creating file %s.', @P, mfError + mfOKButton);
    edSaveModify:
      StdEditorDialog := MessageBox('%s has been modified. Save?', @P, mfInformation + mfYesNoCancel);
    edSaveUntitled:
      StdEditorDialog := MessageBox('Save untitled file?', nil, mfInformation + mfYesNoCancel);
    edSaveAs:
      StdEditorDialog := Application^.ExecuteDialog(New(PFileDialog, Init('*', 'Save file as', '~N~ame',
        fdOkButton, 101)), Info);
    edFind:
      StdEditorDialog := Application^.ExecuteDialog(CreateFindDialog, Info);
    edSearchFailed:
      StdEditorDialog := MessageBox('Search string not found.', nil, mfError + mfOKButton);
    edReplace:
      StdEditorDialog := Application^.ExecuteDialog(CreateReplaceDialog, Info);
    edReplacePrompt:
      begin
        { Above the cursor, or below it when the cursor is high up. }
        R.Assign(0, 1, 40, 8);
        R.Move((Desktop^.Size.X - R.B.X) div 2, 0);
        Desktop^.MakeGlobal(R.B, T);
        Inc(T.Y);
        if TPoint(Info^).Y <= T.Y then
          R.Move(0, Desktop^.Size.Y - R.B.Y - 2);
        StdEditorDialog := MessageBoxRect(R, 'Replace this occurrence?', nil, mfYesNoCancel + mfInformation);
      end;
  else
    StdEditorDialog := cmCancel;
  end;
end;

procedure RegisterEditors;
begin
  RegisterType(REditor);
  RegisterType(RMemo);
  RegisterType(RFileEditor);
  RegisterType(RIndicator);
  RegisterType(REditWindow);
end;

end.
