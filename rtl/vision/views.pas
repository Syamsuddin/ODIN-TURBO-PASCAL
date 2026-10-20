{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Views dari Odin Vision: TView, TGroup, TFrame, TScrollBar, TScroller,
  TListViewer, TWindow. Implementasi clean-room berdasarkan dokumentasi API
  Turbo Vision TP7.

  Menggambar: setiap view menulis sel langsung ke Drivers.ScreenBuffer.
  WriteBuf memotong per sel: hanya sel di dalam semua owner yang tidak
  tertutup view di depannya (atau di depan owner-nya) yang ditulis; sel
  di bayangan view di depan memakai ShadowAttr. Karena itu urutan
  menggambar tidak penting, dan menyembunyikan atau memindah view cukup
  menggambar ulang owner-nya.

  Urutan-z: daftar subview melingkar; Last^.Next adalah First, view paling
  atas. Insert menaruh view di paling atas. }
unit Views;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers;

const
  { State }
  sfVisible = $0001;
  sfCursorVis = $0002;
  sfCursorIns = $0004;
  sfShadow = $0008;
  sfActive = $0010;
  sfSelected = $0020;
  sfFocused = $0040;
  sfDragging = $0080;
  sfDisabled = $0100;
  sfModal = $0200;
  sfDefault = $0400;
  sfExposed = $0800;

  { Options }
  ofSelectable = $0001;
  ofTopSelect = $0002;
  ofFirstClick = $0004;
  ofFramed = $0008;
  ofPreProcess = $0010;
  ofPostProcess = $0020;
  ofBuffered = $0040;
  ofTileable = $0080;
  ofCenterX = $0100;
  ofCenterY = $0200;
  ofCentered = $0300;
  ofValidate = $0400;

  { GrowMode }
  gfGrowLoX = $01;
  gfGrowLoY = $02;
  gfGrowHiX = $04;
  gfGrowHiY = $08;
  gfGrowAll = $0F;
  gfGrowRel = $10;

  { DragMode }
  dmDragMove = $01;
  dmDragGrow = $02;
  dmLimitLoX = $10;
  dmLimitLoY = $20;
  dmLimitHiX = $40;
  dmLimitHiY = $80;
  dmLimitAll = $F0;

  { Help contexts }
  hcNoContext = 0;
  hcDragging = 1;

  { Scroll bar parts and options }
  sbLeftArrow = 0;
  sbRightArrow = 1;
  sbPageLeft = 2;
  sbPageRight = 3;
  sbUpArrow = 4;
  sbDownArrow = 5;
  sbPageUp = 6;
  sbPageDown = 7;
  sbIndicator = 8;
  sbHorizontal = $0000;
  sbVertical = $0001;
  sbHandleKeyboard = $0002;

  { Window flags and palettes }
  wfMove = $01;
  wfGrow = $02;
  wfClose = $04;
  wfZoom = $08;
  wnNoNumber = 0;
  wpBlueWindow = 0;
  wpCyanWindow = 1;
  wpGrayWindow = 2;

  { Standard commands }
  cmValid = 0;
  cmQuit = 1;
  cmError = 2;
  cmMenu = 3;
  cmClose = 4;
  cmZoom = 5;
  cmResize = 6;
  cmNext = 7;
  cmPrev = 8;
  cmHelp = 9;
  cmOK = 10;
  cmCancel = 11;
  cmYes = 12;
  cmNo = 13;
  cmDefault = 14;
  cmCut = 20;
  cmCopy = 21;
  cmPaste = 22;
  cmUndo = 23;
  cmClear = 24;
  cmTile = 25;
  cmCascade = 26;
  cmReceivedFocus = 50;
  cmReleasedFocus = 51;
  cmCommandSetChanged = 52;
  cmScrollBarChanged = 53;
  cmScrollBarClicked = 54;
  cmSelectWindowNum = 55;
  cmListItemSelected = 56;

  MaxViewWidth = 255;

  { Palette layouts (indexes into the owner's palette) }
  CFrame = #1#1#2#2#3;
  CScrollBar = #4#5#5;
  CScroller = #6#7;
  CListViewer = #26#26#27#28#29;
  CBlueWindow = #8#9#10#11#12#13#14#15;
  CCyanWindow = #16#17#18#19#20#21#22#23;
  CGrayWindow = #24#25#26#27#28#29#30#31;

type
  TCommandSet = set of Byte;
  PPalette = ^TPalette;
  TPalette = String;
  TDrawBuffer = array[0..MaxViewWidth - 1] of Word;
  TTitleStr = String[80];
  TScrollChars = array[0..4] of Char;
  TFrameChars = array[0..7] of Char;
  TSelectMode = (NormalSelect, EnterSelect, LeaveSelect);
  TPhase = (phFocused, phPreProcess, phPostProcess);

  PView = ^TView;
  PGroup = ^TGroup;
  PWindow = ^TWindow;

  TView = object(TObject)
    Owner: PGroup;
    Next: PView;
    Origin: TPoint;
    Size: TPoint;
    Cursor: TPoint;
    GrowMode: Byte;
    DragMode: Byte;
    HelpCtx: Word;
    State: Word;
    Options: Word;
    EventMask: Word;
    constructor Init(var Bounds: TRect);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Awaken; virtual;
    procedure BlockCursor;
    procedure CalcBounds(var Bounds: TRect; Delta: TPoint); virtual;
    procedure ChangeBounds(var Bounds: TRect); virtual;
    procedure ClearEvent(var Event: TEvent);
    function CommandEnabled(Command: Word): Boolean;
    function DataSize: Word; virtual;
    procedure DisableCommands(Commands: TCommandSet);
    procedure DragView(Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint);
    procedure Draw; virtual;
    procedure DrawView;
    procedure EnableCommands(Commands: TCommandSet);
    procedure EndModal(Command: Word); virtual;
    function EventAvail: Boolean;
    function Execute: Word; virtual;
    function Exposed: Boolean;
    function Focus: Boolean;
    procedure GetBounds(var Bounds: TRect);
    procedure GetClipRect(var Clip: TRect);
    function GetColor(Color: Word): Word;
    procedure GetCommands(var Commands: TCommandSet);
    procedure GetData(var Rec); virtual;
    procedure GetEvent(var Event: TEvent); virtual;
    procedure GetExtent(var Extent: TRect);
    function GetHelpCtx: Word; virtual;
    function GetPalette: PPalette; virtual;
    procedure GetPeerViewPtr(var S: TStream; var P);
    function GetState(AState: Word): Boolean;
    procedure GrowTo(X, Y: Sw_Integer);
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Hide;
    procedure HideCursor;
    procedure KeyEvent(var Event: TEvent);
    procedure Locate(var Bounds: TRect);
    procedure MakeFirst;
    procedure MakeGlobal(Source: TPoint; var Dest: TPoint);
    procedure MakeLocal(Source: TPoint; var Dest: TPoint);
    function MapColor(Index: Byte): Byte;
    function MouseEvent(var Event: TEvent; Mask: Word): Boolean;
    function MouseInView(Mouse: TPoint): Boolean;
    procedure MoveTo(X, Y: Sw_Integer);
    function NextView: PView;
    procedure NormalCursor;
    function Prev: PView;
    function PrevView: PView;
    procedure PutEvent(var Event: TEvent); virtual;
    procedure PutInFrontOf(Target: PView);
    procedure PutPeerViewPtr(var S: TStream; P: PView);
    procedure ResetCursor; virtual;
    procedure Select;
    procedure SetBounds(var Bounds: TRect);
    procedure SetCmdState(Commands: TCommandSet; Enable: Boolean);
    procedure SetCommands(Commands: TCommandSet);
    procedure SetCursor(X, Y: Sw_Integer);
    procedure SetData(var Rec); virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Show;
    procedure ShowCursor;
    procedure SizeLimits(var Min, Max: TPoint); virtual;
    procedure Store(var S: TStream);
    function TopView: PView;
    function Valid(Command: Word): Boolean; virtual;
    procedure WriteBuf(X, Y, W, H: Sw_Integer; var Buf);
    procedure WriteChar(X, Y: Sw_Integer; C: Char; Color: Byte; Count: Sw_Integer);
    procedure WriteLine(X, Y, W, H: Sw_Integer; var Buf);
    procedure WriteStr(X, Y: Sw_Integer; const Str: String; Color: Byte);
    { Odin: the cells of a view row or block, clipped (see the unit comment). }
    procedure WriteCells(X, Y, W, H: Sw_Integer; var Buf; Stride: Sw_Integer);
    procedure DrawCursor;
    procedure DrawHide(LastView: PView);
    procedure DrawShow(LastView: PView);
    procedure DrawUnderView(DoShadow: Boolean; LastView: PView);
  end;

  PFrame = ^TFrame;
  TFrame = object(TView)
    constructor Init(var Bounds: TRect);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
  end;

  PScrollBar = ^TScrollBar;
  TScrollBar = object(TView)
    Value: Sw_Integer;
    Min: Sw_Integer;
    Max: Sw_Integer;
    PgStep: Sw_Integer;
    ArStep: Sw_Integer;
    Chars: TScrollChars;
    constructor Init(var Bounds: TRect);
    constructor Load(var S: TStream);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure ScrollDraw; virtual;
    function ScrollStep(Part: Sw_Integer): Sw_Integer; virtual;
    procedure SetParams(AValue, AMin, AMax, APgStep, AArStep: Sw_Integer);
    procedure SetRange(AMin, AMax: Sw_Integer);
    procedure SetStep(APgStep, AArStep: Sw_Integer);
    procedure SetValue(AValue: Sw_Integer);
    procedure Store(var S: TStream);
    function GetPos: Sw_Integer;
    function GetSize: Sw_Integer;
  end;

  PScroller = ^TScroller;
  TScroller = object(TView)
    HScrollBar: PScrollBar;
    VScrollBar: PScrollBar;
    Delta: TPoint;
    Limit: TPoint;
    DrawLock: Byte;
    DrawFlag: Boolean;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
    constructor Load(var S: TStream);
    procedure ChangeBounds(var Bounds: TRect); virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure ScrollDraw; virtual;
    procedure ScrollTo(X, Y: Sw_Integer);
    procedure SetLimit(X, Y: Sw_Integer);
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
    procedure CheckDraw;
  end;

  PListViewer = ^TListViewer;
  TListViewer = object(TView)
    HScrollBar: PScrollBar;
    VScrollBar: PScrollBar;
    NumCols: Sw_Integer;
    TopItem: Sw_Integer;
    Focused: Sw_Integer;
    Range: Sw_Integer;
    constructor Init(var Bounds: TRect; ANumCols: Sw_Word; AHScrollBar, AVScrollBar: PScrollBar);
    constructor Load(var S: TStream);
    procedure ChangeBounds(var Bounds: TRect); virtual;
    procedure Draw; virtual;
    procedure FocusItem(Item: Sw_Integer); virtual;
    function GetPalette: PPalette; virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    function IsSelected(Item: Sw_Integer): Boolean; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SelectItem(Item: Sw_Integer); virtual;
    procedure SetRange(ARange: Sw_Integer);
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
    procedure FocusItemNum(Item: Sw_Integer); virtual;
  end;

  TGroup = object(TView)
    Last: PView;
    Current: PView;
    Phase: TPhase;
    Buffer: PVideoBuf;
    EndState: Word;
    LockFlag: Byte;
    constructor Init(var Bounds: TRect);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Awaken; virtual;
    procedure ChangeBounds(var Bounds: TRect); virtual;
    function DataSize: Word; virtual;
    procedure Delete(P: PView);
    procedure Draw; virtual;
    procedure EndModal(Command: Word); virtual;
    procedure EventError(var Event: TEvent); virtual;
    function ExecView(P: PView): Word;
    function Execute: Word; virtual;
    function First: PView;
    function FirstThat(P: Pointer): PView;
    function FocusNext(Forwards: Boolean): Boolean;
    procedure ForEach(P: Pointer);
    procedure GetData(var Rec); virtual;
    function GetHelpCtx: Word; virtual;
    procedure GetSubViewPtr(var S: TStream; var P);
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Insert(P: PView);
    procedure InsertBefore(P, Target: PView);
    procedure Lock;
    procedure PutSubViewPtr(var S: TStream; P: PView);
    procedure Redraw;
    procedure SelectNext(Forwards: Boolean);
    procedure SetData(var Rec); virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
    procedure Unlock;
    function Valid(Command: Word): Boolean; virtual;
    { Odin and TP internals used across units. }
    procedure InsertView(P, Target: PView);
    procedure RemoveView(P: PView);
    procedure ResetCurrent;
    procedure SetCurrent(P: PView; Mode: TSelectMode);
    function FirstMatch(AState: Word; AOptions: Word): PView;
    function FindNext(Forwards: Boolean): PView;
    function IndexOf(P: PView): Sw_Integer;
    function At(Index: Sw_Integer): PView;
  end;

  TWindow = object(TGroup)
    Flags: Byte;
    ZoomRect: TRect;
    Number: Sw_Integer;
    Palette: Sw_Integer;
    Frame: PFrame;
    Title: PString;
    constructor Init(var Bounds: TRect; ATitle: TTitleStr; ANumber: Sw_Integer);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Close; virtual;
    function GetPalette: PPalette; virtual;
    function GetTitle(MaxSize: Sw_Integer): TTitleStr; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitFrame; virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure SizeLimits(var Min, Max: TPoint); virtual;
    function StandardScrollBar(AOptions: Word): PScrollBar;
    procedure Store(var S: TStream);
    procedure Zoom; virtual;
  end;

function Message(Receiver: PView; What, Command: Word; InfoPtr: Pointer): Pointer;
procedure RegisterViews;

const
  ErrorAttr: Byte = $CF;
  CommandSetChanged: Boolean = False;
  ShowMarkers: Boolean = False;
  PositionalEvents: Word = evMouse;
  FocusedEvents: Word = evKeyboard + evCommand;
  MinWinSize: TPoint = (X: 16; Y: 6);
  ShadowSize: TPoint = (X: 2; Y: 1);
  ShadowAttr: Byte = $08;
  { Frame characters: single (passive) and double (active) lines. }
  FramePassive: TFrameChars = #218#196#191#179#179#192#196#217;
  FrameActive: TFrameChars = #201#205#187#186#186#200#205#188;

  RView: TStreamRec = (ObjType: 1; VmtLink: Ofs(TypeOf(TView)^); Load: @TView.Load; Store: @TView.Store);
  RFrame: TStreamRec = (ObjType: 2; VmtLink: Ofs(TypeOf(TFrame)^); Load: @TFrame.Load; Store: @TFrame.Store);
  RScrollBar: TStreamRec = (ObjType: 3; VmtLink: Ofs(TypeOf(TScrollBar)^); Load: @TScrollBar.Load;
    Store: @TScrollBar.Store);
  RScroller: TStreamRec = (ObjType: 4; VmtLink: Ofs(TypeOf(TScroller)^); Load: @TScroller.Load;
    Store: @TScroller.Store);
  RListViewer: TStreamRec = (ObjType: 5; VmtLink: Ofs(TypeOf(TListViewer)^); Load: @TListViewer.Load;
    Store: @TListViewer.Store);
  RGroup: TStreamRec = (ObjType: 6; VmtLink: Ofs(TypeOf(TGroup)^); Load: @TGroup.Load; Store: @TGroup.Store);
  RWindow: TStreamRec = (ObjType: 7; VmtLink: Ofs(TypeOf(TWindow)^); Load: @TWindow.Load; Store: @TWindow.Store);

var
  { Odin: the modal view ExecView runs (see TopView). }
  TheTopView: PView;
  CurCommandSet: TCommandSet;

implementation

function CallerFrame: Pointer; external 'odinrtl' name 'ODIN_CALLERFRAME';
procedure CallLocal(Code, Frame, Item: Pointer); external 'odinrtl' name 'ODIN_CALLLOCAL';
function CallLocalTest(Code, Frame, Item: Pointer): Boolean; external 'odinrtl' name 'ODIN_CALLLOCAL';

const
  CScrollChars: array[0..1] of TScrollChars = (#17#16#177#254#178, #30#31#177#254#178);

var
  { Load: the group being loaded and the subview references to fix. }
  OwnerGroup: PGroup;
  FixupCount: Sw_Integer;
  FixupPtr: array[0..255] of Pointer;
  FixupIndex: array[0..255] of Sw_Integer;

function Min(A, B: Sw_Integer): Sw_Integer;
begin
  if A < B then Min := A else Min := B;
end;

function Max(A, B: Sw_Integer): Sw_Integer;
begin
  if A > B then Max := A else Max := B;
end;

function Range(V, Lo, Hi: Sw_Integer): Sw_Integer;
begin
  if V < Lo then
    V := Lo;
  if V > Hi then
    V := Hi;
  Range := V;
end;

function Message(Receiver: PView; What, Command: Word; InfoPtr: Pointer): Pointer;
var
  Event: TEvent;
begin
  Message := nil;
  if Receiver = nil then
    Exit;
  Event.What := What;
  Event.Command := Command;
  Event.InfoPtr := InfoPtr;
  Receiver^.HandleEvent(Event);
  if Event.What = evNothing then
    Message := Event.InfoPtr;
end;

{ ---- TView --------------------------------------------------------------------- }

constructor TView.Init(var Bounds: TRect);
begin
  inherited Init;
  SetBounds(Bounds);
  State := sfVisible;
  DragMode := dmLimitLoY;
  HelpCtx := hcNoContext;
  EventMask := evMouseDown + evKeyDown + evCommand;
end;

constructor TView.Load(var S: TStream);
begin
  inherited Init;
  S.Read(Origin, SizeOf(TPoint));
  S.Read(Size, SizeOf(TPoint));
  S.Read(Cursor, SizeOf(TPoint));
  S.Read(GrowMode, 1);
  S.Read(DragMode, 1);
  S.Read(HelpCtx, 2);
  S.Read(State, 2);
  S.Read(Options, 2);
  S.Read(EventMask, 2);
  State := State and not (sfActive or sfSelected or sfFocused or sfExposed or sfModal);
end;

procedure TView.Store(var S: TStream);
var
  SaveState: Word;
begin
  SaveState := State and not (sfActive or sfSelected or sfFocused or sfExposed or sfModal);
  S.Write(Origin, SizeOf(TPoint));
  S.Write(Size, SizeOf(TPoint));
  S.Write(Cursor, SizeOf(TPoint));
  S.Write(GrowMode, 1);
  S.Write(DragMode, 1);
  S.Write(HelpCtx, 2);
  S.Write(SaveState, 2);
  S.Write(Options, 2);
  S.Write(EventMask, 2);
end;

destructor TView.Done;
begin
  Hide;
  if Owner <> nil then
    Owner^.Delete(@Self);
end;

procedure TView.Awaken;
begin
end;

procedure TView.BlockCursor;
begin
  SetState(sfCursorIns, True);
end;

procedure TView.NormalCursor;
begin
  SetState(sfCursorIns, False);
end;

procedure TView.CalcBounds(var Bounds: TRect; Delta: TPoint);
var
  S, D: Sw_Integer;
  MinS, MaxS: TPoint;

  procedure Grow(var I: Sw_Integer);
  begin
    if GrowMode and gfGrowRel = 0 then
      Inc(I, D)
    else if S - D <> 0 then
      I := (I * S + (S - D) div 2) div (S - D);
  end;

begin
  GetBounds(Bounds);
  S := Owner^.Size.X;
  D := Delta.X;
  if GrowMode and gfGrowLoX <> 0 then
    Grow(Bounds.A.X);
  if GrowMode and gfGrowHiX <> 0 then
    Grow(Bounds.B.X);
  S := Owner^.Size.Y;
  D := Delta.Y;
  if GrowMode and gfGrowLoY <> 0 then
    Grow(Bounds.A.Y);
  if GrowMode and gfGrowHiY <> 0 then
    Grow(Bounds.B.Y);
  SizeLimits(MinS, MaxS);
  Bounds.B.X := Bounds.A.X + Range(Bounds.B.X - Bounds.A.X, MinS.X, MaxS.X);
  Bounds.B.Y := Bounds.A.Y + Range(Bounds.B.Y - Bounds.A.Y, MinS.Y, MaxS.Y);
end;

procedure TView.ChangeBounds(var Bounds: TRect);
begin
  SetBounds(Bounds);
  DrawView;
end;

procedure TView.ClearEvent(var Event: TEvent);
begin
  Event.What := evNothing;
  Event.InfoPtr := @Self;
end;

function TView.CommandEnabled(Command: Word): Boolean;
begin
  CommandEnabled := (Command > 255) or (Command in CurCommandSet);
end;

function TView.DataSize: Word;
begin
  DataSize := 0;
end;

procedure TView.DisableCommands(Commands: TCommandSet);
begin
  CommandSetChanged := CommandSetChanged or (CurCommandSet * Commands <> []);
  CurCommandSet := CurCommandSet - Commands;
end;

procedure TView.EnableCommands(Commands: TCommandSet);
begin
  CommandSetChanged := CommandSetChanged or (CurCommandSet * Commands <> Commands);
  CurCommandSet := CurCommandSet + Commands;
end;

procedure TView.GetCommands(var Commands: TCommandSet);
begin
  Commands := CurCommandSet;
end;

procedure TView.SetCommands(Commands: TCommandSet);
begin
  CommandSetChanged := CommandSetChanged or (CurCommandSet <> Commands);
  CurCommandSet := Commands;
end;

procedure TView.SetCmdState(Commands: TCommandSet; Enable: Boolean);
begin
  if Enable then
    EnableCommands(Commands)
  else
    DisableCommands(Commands);
end;

{ Moves or resizes the view with the mouse (while a button is down) or the
  keyboard (arrows; Shift or Ctrl+arrows to resize, Enter to accept, Esc
  to cancel). }
procedure TView.DragView(Event: TEvent; Mode: Byte; var Limits: TRect; MinSize, MaxSize: TPoint);
var
  P, S, Start: TPoint;
  SaveBounds, R: TRect;

  procedure MoveGrow(P, S: TPoint);
  var
    R: TRect;
  begin
    S.X := Range(S.X, MinSize.X, MaxSize.X);
    S.Y := Range(S.Y, MinSize.Y, MaxSize.Y);
    P.X := Range(P.X, Limits.A.X - S.X + 1, Limits.B.X - 1);
    P.Y := Range(P.Y, Limits.A.Y - S.Y + 1, Limits.B.Y - 1);
    if Mode and dmLimitLoX <> 0 then
      P.X := Max(P.X, Limits.A.X);
    if Mode and dmLimitLoY <> 0 then
      P.Y := Max(P.Y, Limits.A.Y);
    if Mode and dmLimitHiX <> 0 then
      P.X := Min(P.X, Limits.B.X - S.X);
    if Mode and dmLimitHiY <> 0 then
      P.Y := Min(P.Y, Limits.B.Y - S.Y);
    R.Assign(P.X, P.Y, P.X + S.X, P.Y + S.Y);
    Locate(R);
  end;

  procedure Change(DX, DY: Sw_Integer);
  begin
    if (Mode and dmDragMove <> 0) and (GetShiftState and (kbLeftShift or kbRightShift or kbCtrlShift) = 0) then
    begin
      Inc(P.X, DX);
      Inc(P.Y, DY);
    end
    else if Mode and dmDragGrow <> 0 then
    begin
      Inc(S.X, DX);
      Inc(S.Y, DY);
    end;
  end;

begin
  SetState(sfDragging, True);
  GetBounds(SaveBounds);
  if Event.What = evMouseDown then
  begin
    if Mode and dmDragMove <> 0 then
    begin
      P.X := Origin.X - Event.Where.X;
      P.Y := Origin.Y - Event.Where.Y;
      repeat
        Inc(Event.Where.X, P.X);
        Inc(Event.Where.Y, P.Y);
        MoveGrow(Event.Where, Size);
        Dec(Event.Where.X, P.X);
        Dec(Event.Where.Y, P.Y);
      until not MouseEvent(Event, evMouseMove);
    end
    else
    begin
      P.X := Size.X - Event.Where.X;
      P.Y := Size.Y - Event.Where.Y;
      repeat
        Inc(Event.Where.X, P.X);
        Inc(Event.Where.Y, P.Y);
        MoveGrow(Origin, Event.Where);
        Dec(Event.Where.X, P.X);
        Dec(Event.Where.Y, P.Y);
      until not MouseEvent(Event, evMouseMove);
    end;
  end
  else
  begin
    GetBounds(R);
    repeat
      P := Origin;
      S := Size;
      KeyEvent(Event);
      case Event.KeyCode and $FF00 of
        $4B00: Change(-1, 0);
        $4D00: Change(1, 0);
        $4800: Change(0, -1);
        $5000: Change(0, 1);
        $7300: Change(-8, 0);
        $7400: Change(8, 0);
        $4700: P.X := Limits.A.X;
        $4F00: P.X := Limits.B.X - S.X;
        $4900: P.Y := Limits.A.Y;
        $5100: P.Y := Limits.B.Y - S.Y;
      end;
      MoveGrow(P, S);
    until (Event.KeyCode = kbEnter) or (Event.KeyCode = kbEsc);
    if Event.KeyCode = kbEsc then
      Locate(SaveBounds);
  end;
  Start := Origin;
  SetState(sfDragging, False);
end;

procedure TView.Draw;
var
  B: TDrawBuffer;
begin
  MoveChar(B, ' ', GetColor(1), Size.X);
  WriteLine(0, 0, Size.X, Size.Y, B);
end;

procedure TView.DrawView;
begin
  if Exposed then
  begin
    Draw;
    DrawCursor;
  end;
end;

procedure TView.DrawCursor;
begin
  if State and sfFocused <> 0 then
    ResetCursor;
end;

procedure TView.DrawHide(LastView: PView);
begin
  DrawCursor;
  DrawUnderView(State and sfShadow <> 0, LastView);
end;

procedure TView.DrawShow(LastView: PView);
begin
  DrawView;
  if State and sfShadow <> 0 then
    DrawUnderView(True, LastView);
end;

{ What lies under (and, with DoShadow, beside) the view must show again:
  with per-cell clipping, redrawing the owner does it. }
procedure TView.DrawUnderView(DoShadow: Boolean; LastView: PView);
begin
  if Owner <> nil then
    Owner^.Redraw;
end;

procedure TView.EndModal(Command: Word);
var
  P: PView;
begin
  P := TopView;
  if (P <> nil) and (P <> @Self) then
    P^.EndModal(Command);
end;

function TView.EventAvail: Boolean;
var
  Event: TEvent;
begin
  GetEvent(Event);
  if Event.What <> evNothing then
    PutEvent(Event);
  EventAvail := Event.What <> evNothing;
end;

function TView.Execute: Word;
begin
  Execute := cmCancel;
end;

function TView.Exposed: Boolean;
begin
  Exposed := (State and sfExposed <> 0) and (Size.X > 0) and (Size.Y > 0) and (ScreenBuffer <> nil);
end;

function TView.Focus: Boolean;
var
  Result: Boolean;
begin
  Result := True;
  if State and (sfSelected or sfModal) = 0 then
  begin
    if Owner <> nil then
    begin
      Result := Owner^.Focus;
      if Result then
        if (Owner^.Current = nil) or (Owner^.Current^.Options and ofValidate = 0) or
          Owner^.Current^.Valid(cmReleasedFocus) then
          Select
        else
          Result := False;
    end;
  end;
  Focus := Result;
end;

procedure TView.GetBounds(var Bounds: TRect);
begin
  Bounds.A := Origin;
  Bounds.B.X := Origin.X + Size.X;
  Bounds.B.Y := Origin.Y + Size.Y;
end;

procedure TView.GetClipRect(var Clip: TRect);
var
  R: TRect;
begin
  GetBounds(Clip);
  if Owner <> nil then
  begin
    R.Assign(0, 0, Owner^.Size.X, Owner^.Size.Y);
    Clip.Intersect(R);
  end;
  Clip.Move(-Origin.X, -Origin.Y);
end;

function TView.GetColor(Color: Word): Word;
begin
  GetColor := (Word(MapColor(Hi(Color))) shl 8 * Ord(Hi(Color) <> 0)) or MapColor(Lo(Color));
end;

procedure TView.GetData(var Rec);
begin
end;

procedure TView.GetEvent(var Event: TEvent);
begin
  if Owner <> nil then
    Owner^.GetEvent(Event)
  else
    Event.What := evNothing;
end;

procedure TView.GetExtent(var Extent: TRect);
begin
  Extent.Assign(0, 0, Size.X, Size.Y);
end;

function TView.GetHelpCtx: Word;
begin
  if State and sfDragging <> 0 then
    GetHelpCtx := hcDragging
  else
    GetHelpCtx := HelpCtx;
end;

function TView.GetPalette: PPalette;
begin
  GetPalette := nil;
end;

procedure TView.GetPeerViewPtr(var S: TStream; var P);
var
  Index: Sw_Integer;
begin
  Index := 0;
  S.Read(Index, SizeOf(Index));
  Pointer(P) := nil;
  if (Index > 0) and (OwnerGroup <> nil) and (FixupCount < 256) then
  begin
    FixupPtr[FixupCount] := @P;
    FixupIndex[FixupCount] := Index;
    Inc(FixupCount);
  end;
end;

procedure TView.PutPeerViewPtr(var S: TStream; P: PView);
var
  Index: Sw_Integer;
begin
  if (P = nil) or (Owner = nil) then
    Index := 0
  else
    Index := Owner^.IndexOf(P);
  S.Write(Index, SizeOf(Index));
end;

function TView.GetState(AState: Word): Boolean;
begin
  GetState := State and AState = AState;
end;

procedure TView.GrowTo(X, Y: Sw_Integer);
var
  R: TRect;
begin
  R.Assign(Origin.X, Origin.Y, Origin.X + X, Origin.Y + Y);
  Locate(R);
end;

procedure TView.HandleEvent(var Event: TEvent);
begin
  if Event.What = evMouseDown then
    if (State and (sfSelected or sfDisabled) = 0) and (Options and ofSelectable <> 0) then
      if not Focus or (Options and ofFirstClick = 0) then
        ClearEvent(Event);
end;

procedure TView.Hide;
begin
  if State and sfVisible <> 0 then
    SetState(sfVisible, False);
end;

procedure TView.HideCursor;
begin
  SetState(sfCursorVis, False);
end;

procedure TView.KeyEvent(var Event: TEvent);
begin
  repeat
    GetEvent(Event);
  until Event.What = evKeyDown;
end;

procedure TView.Locate(var Bounds: TRect);
var
  MinS, MaxS: TPoint;
  R: TRect;
begin
  SizeLimits(MinS, MaxS);
  Bounds.B.X := Bounds.A.X + Range(Bounds.B.X - Bounds.A.X, MinS.X, MaxS.X);
  Bounds.B.Y := Bounds.A.Y + Range(Bounds.B.Y - Bounds.A.Y, MinS.Y, MaxS.Y);
  GetBounds(R);
  if not Bounds.Equals(R) then
  begin
    ChangeBounds(Bounds);
    if (Owner <> nil) and (State and sfVisible <> 0) then
      DrawUnderView(State and sfShadow <> 0, nil);
  end;
end;

procedure TView.MakeFirst;
begin
  if Owner <> nil then
    PutInFrontOf(Owner^.First);
end;

procedure TView.MakeGlobal(Source: TPoint; var Dest: TPoint);
var
  V: PView;
begin
  Dest := Source;
  V := @Self;
  while V <> nil do
  begin
    Inc(Dest.X, V^.Origin.X);
    Inc(Dest.Y, V^.Origin.Y);
    V := V^.Owner;
  end;
end;

procedure TView.MakeLocal(Source: TPoint; var Dest: TPoint);
var
  V: PView;
begin
  Dest := Source;
  V := @Self;
  while V <> nil do
  begin
    Dec(Dest.X, V^.Origin.X);
    Dec(Dest.Y, V^.Origin.Y);
    V := V^.Owner;
  end;
end;

{ A palette index through this view's palette and its owners' (up to the
  application, whose palette gives the attribute). }
function TView.MapColor(Index: Byte): Byte;
var
  P: PPalette;
  V: PView;
begin
  MapColor := ErrorAttr;
  if Index = 0 then
    Exit;
  V := @Self;
  while V <> nil do
  begin
    P := V^.GetPalette;
    if P <> nil then
    begin
      if Index > Length(P^) then
        Exit;
      Index := Ord(P^[Index]);
      if Index = 0 then
        Exit;
    end;
    V := V^.Owner;
  end;
  MapColor := Index;
end;

function TView.MouseEvent(var Event: TEvent; Mask: Word): Boolean;
begin
  repeat
    GetEvent(Event);
  until Event.What and (Mask or evMouseUp) <> 0;
  MouseEvent := Event.What <> evMouseUp;
end;

function TView.MouseInView(Mouse: TPoint): Boolean;
var
  Extent: TRect;
begin
  MakeLocal(Mouse, Mouse);
  GetExtent(Extent);
  MouseInView := Extent.Contains(Mouse);
end;

procedure TView.MoveTo(X, Y: Sw_Integer);
var
  R: TRect;
begin
  R.Assign(X, Y, X + Size.X, Y + Size.Y);
  Locate(R);
end;

function TView.NextView: PView;
begin
  if (Owner = nil) or (@Self = Owner^.Last) then
    NextView := nil
  else
    NextView := Next;
end;

function TView.Prev: PView;
var
  P: PView;
begin
  P := @Self;
  while P^.Next <> @Self do
    P := P^.Next;
  Prev := P;
end;

function TView.PrevView: PView;
begin
  if (Owner = nil) or (@Self = Owner^.First) then
    PrevView := nil
  else
    PrevView := Prev;
end;

procedure TView.PutEvent(var Event: TEvent);
begin
  if Owner <> nil then
    Owner^.PutEvent(Event);
end;

procedure TView.PutInFrontOf(Target: PView);
begin
  if (Owner = nil) or (Target = @Self) or (Target = NextView) or ((Target <> nil) and (Target^.Owner <> Owner)) then
    Exit;
  Owner^.RemoveView(@Self);
  Owner^.InsertView(@Self, Target);
  if State and sfVisible <> 0 then
  begin
    Owner^.Redraw;
    if Options and ofSelectable <> 0 then
      Owner^.ResetCurrent;
  end;
end;

{ The hardware cursor follows the focused view, when its cursor is on and
  the cell is not covered by another view. }
procedure TView.ResetCursor;
var
  P: TPoint;
  V: PView;
  Visible: Boolean;
begin
  if State and sfFocused = 0 then
    Exit;
  Visible := (State and (sfVisible or sfCursorVis or sfExposed) = sfVisible or sfCursorVis or sfExposed) and
    (Cursor.X >= 0) and (Cursor.Y >= 0) and (Cursor.X < Size.X) and (Cursor.Y < Size.Y);
  if Visible then
  begin
    V := @Self;
    while (V^.Owner <> nil) and Visible do
    begin
      if V^.Owner^.State and sfVisible = 0 then
        Visible := False;
      V := V^.Owner;
    end;
  end;
  MakeGlobal(Cursor, P);
  SetCursorState(P.X, P.Y, Visible, State and sfCursorIns <> 0);
end;

procedure TView.Select;
begin
  if Options and ofSelectable = 0 then
    Exit;
  if Options and ofTopSelect <> 0 then
    MakeFirst
  else if Owner <> nil then
    Owner^.SetCurrent(@Self, NormalSelect);
end;

procedure TView.SetBounds(var Bounds: TRect);
begin
  Origin := Bounds.A;
  Size.X := Bounds.B.X - Bounds.A.X;
  Size.Y := Bounds.B.Y - Bounds.A.Y;
end;

procedure TView.SetCursor(X, Y: Sw_Integer);
begin
  Cursor.X := X;
  Cursor.Y := Y;
  DrawCursor;
end;

procedure TView.SetData(var Rec);
begin
end;

procedure TView.SetState(AState: Word; Enable: Boolean);
var
  Command: Word;
begin
  if Enable then
    State := State or AState
  else
    State := State and not AState;
  if Owner = nil then
    Exit;
  case AState of
    sfVisible:
      begin
        if Owner^.State and sfExposed <> 0 then
          SetState(sfExposed, Enable);
        if Enable then
          DrawShow(nil)
        else
          DrawHide(nil);
        if Options and ofSelectable <> 0 then
          Owner^.ResetCurrent;
      end;
    sfCursorVis, sfCursorIns:
      DrawCursor;
    sfShadow:
      DrawUnderView(True, nil);
    sfFocused:
      begin
        ResetCursor;
        if Enable then
          Command := cmReceivedFocus
        else
          Command := cmReleasedFocus;
        Message(Owner, evBroadcast, Command, @Self);
      end;
  end;
end;

procedure TView.Show;
begin
  if State and sfVisible = 0 then
    SetState(sfVisible, True);
end;

procedure TView.ShowCursor;
begin
  SetState(sfCursorVis, True);
end;

procedure TView.SizeLimits(var Min, Max: TPoint);
begin
  Min.X := 0;
  Min.Y := 0;
  if Owner <> nil then
    Max := Owner^.Size
  else
  begin
    Max.X := MaxInt;
    Max.Y := MaxInt;
  end;
end;

function TView.TopView: PView;
var
  P: PView;
begin
  if TheTopView <> nil then
  begin
    TopView := TheTopView;
    Exit;
  end;
  P := @Self;
  while (P <> nil) and (P^.State and sfModal = 0) do
    P := P^.Owner;
  TopView := P;
end;

function TView.Valid(Command: Word): Boolean;
begin
  Valid := True;
end;

procedure TView.WriteCells(X, Y, W, H: Sw_Integer; var Buf; Stride: Sw_Integer);
type
  TCells = array[0..32767] of Word;
const
  MaxRects = 64;
var
  G: TPoint;
  Clip, R: TRect;
  Covers, Shades: array[0..MaxRects - 1] of TRect;
  NCovers, NShades, I, Row, Col, GX, GY: Sw_Integer;
  V, F: PView;
  O: PGroup;
  Cell: Word;
  Hidden, Shaded: Boolean;
begin
  if (ScreenBuffer = nil) or (State and (sfVisible or sfExposed) <> sfVisible or sfExposed) then
    Exit;
  if (W <= 0) or (H <= 0) then
    Exit;
  G.X := 0;
  G.Y := 0;
  MakeGlobal(G, G);
  Clip.Assign(G.X, G.Y, G.X + Size.X, G.Y + Size.Y);
  R.Assign(0, 0, ScreenWidth, ScreenHeight);
  Clip.Intersect(R);
  NCovers := 0;
  NShades := 0;
  V := @Self;
  while V^.Owner <> nil do
  begin
    O := V^.Owner;
    if O^.State and sfVisible = 0 then
      Exit;
    R.Assign(0, 0, 0, 0);
    R.B := O^.Size;
    O^.MakeGlobal(R.A, R.A);
    R.B.X := R.A.X + O^.Size.X;
    R.B.Y := R.A.Y + O^.Size.Y;
    Clip.Intersect(R);
    F := O^.First;
    while (F <> nil) and (F <> V) do
    begin
      if F^.State and sfVisible <> 0 then
      begin
        F^.GetBounds(R);
        O^.MakeGlobal(R.A, R.A);
        R.B.X := R.A.X + F^.Size.X;
        R.B.Y := R.A.Y + F^.Size.Y;
        if NCovers < MaxRects then
        begin
          Covers[NCovers] := R;
          Inc(NCovers);
        end;
        if (F^.State and sfShadow <> 0) and (NShades < MaxRects - 1) then
        begin
          Shades[NShades].Assign(R.B.X, R.A.Y + ShadowSize.Y, R.B.X + ShadowSize.X, R.B.Y + ShadowSize.Y);
          Shades[NShades + 1].Assign(R.A.X + ShadowSize.X, R.B.Y, R.B.X, R.B.Y + ShadowSize.Y);
          Inc(NShades, 2);
        end;
      end;
      F := F^.NextView;
    end;
    V := O;
  end;
  if Clip.Empty then
    Exit;
  for Row := 0 to H - 1 do
  begin
    GY := G.Y + Y + Row;
    if (GY < Clip.A.Y) or (GY >= Clip.B.Y) then
      Continue;
    for Col := 0 to W - 1 do
    begin
      GX := G.X + X + Col;
      if (GX < Clip.A.X) or (GX >= Clip.B.X) then
        Continue;
      Hidden := False;
      for I := 0 to NCovers - 1 do
        if (GX >= Covers[I].A.X) and (GX < Covers[I].B.X) and (GY >= Covers[I].A.Y) and (GY < Covers[I].B.Y) then
        begin
          Hidden := True;
          Break;
        end;
      if Hidden then
        Continue;
      Cell := TCells(Buf)[Row * Stride + Col];
      Shaded := False;
      for I := 0 to NShades - 1 do
        if (GX >= Shades[I].A.X) and (GX < Shades[I].B.X) and (GY >= Shades[I].A.Y) and (GY < Shades[I].B.Y) then
          Shaded := True;
      if Shaded then
        Cell := (Cell and $FF) or (Word(ShadowAttr) shl 8);
      ScreenBuffer^[GY * ScreenWidth + GX] := Cell;
    end;
  end;
end;

procedure TView.WriteBuf(X, Y, W, H: Sw_Integer; var Buf);
begin
  WriteCells(X, Y, W, H, Buf, W);
end;

procedure TView.WriteLine(X, Y, W, H: Sw_Integer; var Buf);
begin
  WriteCells(X, Y, W, H, Buf, 0);
end;

procedure TView.WriteChar(X, Y: Sw_Integer; C: Char; Color: Byte; Count: Sw_Integer);
var
  B: TDrawBuffer;
begin
  if Count <= 0 then
    Exit;
  if Count > MaxViewWidth then
    Count := MaxViewWidth;
  MoveChar(B, C, MapColor(Color), Count);
  WriteCells(X, Y, Count, 1, B, Count);
end;

procedure TView.WriteStr(X, Y: Sw_Integer; const Str: String; Color: Byte);
var
  B: TDrawBuffer;
begin
  if Length(Str) = 0 then
    Exit;
  MoveStr(B, Str, MapColor(Color));
  WriteCells(X, Y, Length(Str), 1, B, Length(Str));
end;

{ ---- TFrame -------------------------------------------------------------------- }

constructor TFrame.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  GrowMode := gfGrowHiX + gfGrowHiY;
  EventMask := EventMask or evBroadcast;
end;

procedure TFrame.Draw;
var
  B: TDrawBuffer;
  Chars: TFrameChars;
  CFrame, CTitle, CIcon: Word;
  W, I, L: Sw_Integer;
  Title: TTitleStr;
  Win: PWindow;
  N: String;
begin
  Win := PWindow(Owner);
  if State and sfDragging <> 0 then
  begin
    CFrame := GetColor(5);
    CTitle := GetColor(5);
    CIcon := GetColor(5);
    Chars := FramePassive;
  end
  else if State and sfActive <> 0 then
  begin
    CFrame := GetColor(3);
    CTitle := GetColor(4);
    CIcon := GetColor(5);
    Chars := FrameActive;
  end
  else
  begin
    CFrame := GetColor(1);
    CTitle := GetColor(2);
    CIcon := GetColor(1);
    Chars := FramePassive;
  end;
  W := Size.X;
  { Top line: corners, title, close and zoom icons, window number. }
  MoveChar(B, Chars[1], Lo(CFrame), W);
  MoveChar(B[0], Chars[0], Lo(CFrame), 1);
  MoveChar(B[W - 1], Chars[2], Lo(CFrame), 1);
  if Win <> nil then
  begin
    { The title stays clear of the close icon (columns 1-4) and of the
      number and zoom icon at the right. }
    L := W - 12;
    if (Win^.Number <> wnNoNumber) and (Win^.Number < 10) then
      Dec(L, 4);
    if Win^.Flags and wfZoom <> 0 then
      Dec(L, 2);
    if L > 0 then
      Title := Win^.GetTitle(L)
    else
      Title := '';
    L := Length(Title);
    if L > 0 then
    begin
      I := (W - L - 2) div 2;
      if I < 5 then
        I := 5;
      MoveStr(B[I], ' ' + Title + ' ', Lo(CTitle));
    end;
    if (Win^.Number <> wnNoNumber) and (Win^.Number < 10) then
    begin
      Str(Win^.Number, N);
      I := W - 4;
      if Win^.Flags and wfZoom <> 0 then
        Dec(I, 4);
      MoveChar(B[I], N[1], Lo(CFrame), 1);
    end;
    if State and sfActive <> 0 then
    begin
      if Win^.Flags and wfClose <> 0 then
        MoveCStr(B[2], '[~'#254'~]', (Lo(CIcon) shl 8) or Lo(CFrame));
      if Win^.Flags and wfZoom <> 0 then
      begin
        if (Owner^.Owner <> nil) and (Owner^.Size.X = Owner^.Owner^.Size.X) and
          (Owner^.Size.Y = Owner^.Owner^.Size.Y) then
          MoveCStr(B[W - 5], '[~'#18'~]', (Lo(CIcon) shl 8) or Lo(CFrame))
        else
          MoveCStr(B[W - 5], '[~'#24'~]', (Lo(CIcon) shl 8) or Lo(CFrame));
      end;
    end;
  end;
  WriteLine(0, 0, W, 1, B);
  { Sides and the window's background: the frame is the window's bottom
  subview, so the views inserted later cover its inside. }
  MoveChar(B, ' ', Lo(CFrame), W);
  MoveChar(B[0], Chars[3], Lo(CFrame), 1);
  MoveChar(B[W - 1], Chars[4], Lo(CFrame), 1);
  WriteLine(0, 1, W, Size.Y - 2, B);
  { Bottom line, with a resize corner when the window can grow. }
  MoveChar(B, Chars[6], Lo(CFrame), W);
  MoveChar(B[0], Chars[5], Lo(CFrame), 1);
  MoveChar(B[W - 1], Chars[7], Lo(CFrame), 1);
  if (Win <> nil) and (State and sfActive <> 0) and (Win^.Flags and wfGrow <> 0) then
    MoveCStr(B[W - 2], '~'#196#217'~', (Lo(CIcon) shl 8) or Lo(CFrame));
  WriteLine(0, Size.Y - 1, W, 1, B);
end;

function TFrame.GetPalette: PPalette;
const
  P: String[Length(CFrame)] = CFrame;
begin
  GetPalette := @P;
end;

procedure TFrame.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  Win: PWindow;
  Limits: TRect;
  MinS, MaxS: TPoint;
begin
  inherited HandleEvent(Event);
  Win := PWindow(Owner);
  if (Event.What = evMouseDown) and (Win <> nil) then
  begin
    MakeLocal(Event.Where, Mouse);
    if Mouse.Y = 0 then
    begin
      if (Win^.Flags and wfClose <> 0) and (State and sfActive <> 0) and (Mouse.X >= 2) and (Mouse.X <= 4) then
      begin
        Event.What := evCommand;
        Event.Command := cmClose;
        Event.InfoPtr := Owner;
        PutEvent(Event);
        ClearEvent(Event);
      end
      else if (Win^.Flags and wfZoom <> 0) and (State and sfActive <> 0) and
        ((Mouse.X >= Size.X - 5) and (Mouse.X <= Size.X - 3) or Event.Double) then
      begin
        Event.What := evCommand;
        Event.Command := cmZoom;
        Event.InfoPtr := Owner;
        PutEvent(Event);
        ClearEvent(Event);
      end
      else if Win^.Flags and wfMove <> 0 then
      begin
        Owner^.Owner^.GetExtent(Limits);
        Win^.SizeLimits(MinS, MaxS);
        Owner^.DragView(Event, Owner^.DragMode or dmDragMove, Limits, MinS, MaxS);
        ClearEvent(Event);
      end;
    end
    else if (Mouse.X >= Size.X - 2) and (Mouse.Y >= Size.Y - 1) and (Win^.Flags and wfGrow <> 0) then
    begin
      Owner^.Owner^.GetExtent(Limits);
      Win^.SizeLimits(MinS, MaxS);
      Owner^.DragView(Event, Owner^.DragMode or dmDragGrow, Limits, MinS, MaxS);
      ClearEvent(Event);
    end;
  end;
end;

procedure TFrame.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState and (sfActive or sfDragging) <> 0 then
    DrawView;
end;

{ ---- TScrollBar ------------------------------------------------------------------ }

constructor TScrollBar.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  Value := 0;
  Min := 0;
  Max := 0;
  PgStep := 1;
  ArStep := 1;
  if Size.X = 1 then
  begin
    GrowMode := gfGrowLoX + gfGrowHiX + gfGrowHiY;
    Chars := CScrollChars[1];
  end
  else
  begin
    GrowMode := gfGrowLoY + gfGrowHiX + gfGrowHiY;
    Chars := CScrollChars[0];
  end;
end;

constructor TScrollBar.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Value, SizeOf(Sw_Integer) * 5);
  S.Read(Chars, SizeOf(Chars));
end;

procedure TScrollBar.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Value, SizeOf(Sw_Integer) * 5);
  S.Write(Chars, SizeOf(Chars));
end;

{ Length of the bar between the arrows. }
function TScrollBar.GetSize: Sw_Integer;
begin
  if Size.X = 1 then
    GetSize := Size.Y
  else
    GetSize := Size.X;
end;

{ Position of the indicator between the arrows (1..GetSize - 2). }
function TScrollBar.GetPos: Sw_Integer;
var
  R: Sw_Integer;
begin
  R := Max - Min;
  if R = 0 then
    GetPos := 1
  else
    GetPos := ((Value - Min) * (GetSize - 3) + R div 2) div R + 1;
end;

procedure TScrollBar.Draw;
var
  B: TDrawBuffer;
  S, P, I: Sw_Integer;
begin
  S := GetSize;
  if S < 2 then
    Exit;
  MoveChar(B[0], Chars[0], GetColor(2), 1);
  if Max = Min then
    MoveChar(B[1], Chars[4], GetColor(1), S - 2)
  else
  begin
    MoveChar(B[1], Chars[2], GetColor(1), S - 2);
    P := GetPos;
    MoveChar(B[P], Chars[3], GetColor(3), 1);
  end;
  MoveChar(B[S - 1], Chars[1], GetColor(2), 1);
  if Size.X = 1 then
    for I := 0 to S - 1 do
      WriteCells(0, I, 1, 1, B[I], 1)
  else
    WriteBuf(0, 0, S, 1, B);
end;

function TScrollBar.GetPalette: PPalette;
const
  P: String[Length(CScrollBar)] = CScrollBar;
begin
  GetPalette := @P;
end;

procedure TScrollBar.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  Part, Pos, S, Step: Sw_Integer;
  Extent: TRect;
  Tracking: Boolean;

  function PartAt(M: TPoint): Sw_Integer;
  var
    Mark: Sw_Integer;
  begin
    if Size.X = 1 then
      Mark := M.Y
    else
      Mark := M.X;
    if Mark = 0 then
      PartAt := 0
    else if Mark = S - 1 then
      PartAt := 1
    else if Mark < GetPos then
      PartAt := 2
    else if Mark > GetPos then
      PartAt := 3
    else
      PartAt := 8;
  end;

begin
  inherited HandleEvent(Event);
  S := GetSize;
  case Event.What of
    evMouseDown:
      begin
        Message(Owner, evBroadcast, cmScrollBarClicked, @Self);
        MakeLocal(Event.Where, Mouse);
        Part := PartAt(Mouse);
        if Size.X = 1 then
          Inc(Part, 4);
        if Part = 12 then
          Part := sbIndicator;
        if Part = sbIndicator then
        begin
          GetExtent(Extent);
          repeat
            MakeLocal(Event.Where, Mouse);
            if Size.X = 1 then
              Pos := Mouse.Y
            else
              Pos := Mouse.X;
            Pos := Range(Pos, 1, S - 2);
            if S > 3 then
              SetValue(Min + ((Pos - 1) * (Max - Min) + (S - 3) div 2) div (S - 3));
            Tracking := MouseEvent(Event, evMouseMove + evMouseAuto);
          until not Tracking;
        end
        else
          repeat
            MakeLocal(Event.Where, Mouse);
            Step := PartAt(Mouse);
            if Size.X = 1 then
              Inc(Step, 4);
            if Step = Part then
              SetValue(Value + ScrollStep(Part));
          until not MouseEvent(Event, evMouseAuto);
        ClearEvent(Event);
      end;
    evKeyDown:
      if State and sfVisible <> 0 then
      begin
        Step := 0;
        if Size.X = 1 then
          case CtrlToArrow(Event.KeyCode) of
            kbUp: Step := ScrollStep(sbUpArrow);
            kbDown: Step := ScrollStep(sbDownArrow);
            kbPgUp: Step := ScrollStep(sbPageUp);
            kbPgDn: Step := ScrollStep(sbPageDown);
            kbCtrlPgUp: Step := Min - Value;
            kbCtrlPgDn: Step := Max - Value;
          else
            Exit;
          end
        else
          case CtrlToArrow(Event.KeyCode) of
            kbLeft: Step := ScrollStep(sbLeftArrow);
            kbRight: Step := ScrollStep(sbRightArrow);
            kbCtrlLeft: Step := ScrollStep(sbPageLeft);
            kbCtrlRight: Step := ScrollStep(sbPageRight);
            kbHome: Step := Min - Value;
            kbEnd: Step := Max - Value;
          else
            Exit;
          end;
        SetValue(Value + Step);
        ClearEvent(Event);
      end;
  end;
end;

procedure TScrollBar.ScrollDraw;
begin
  Message(Owner, evBroadcast, cmScrollBarChanged, @Self);
end;

function TScrollBar.ScrollStep(Part: Sw_Integer): Sw_Integer;
var
  Step: Sw_Integer;
begin
  if Part and 2 = 0 then
    Step := ArStep
  else
    Step := PgStep;
  if Part and 1 = 0 then
    ScrollStep := -Step
  else
    ScrollStep := Step;
end;

procedure TScrollBar.SetParams(AValue, AMin, AMax, APgStep, AArStep: Sw_Integer);
var
  SValue: Sw_Integer;
begin
  if AMax < AMin then
    AMax := AMin;
  AValue := Range(AValue, AMin, AMax);
  SValue := Value;
  if (SValue <> AValue) or (Min <> AMin) or (Max <> AMax) then
  begin
    Value := AValue;
    Min := AMin;
    Max := AMax;
    DrawView;
    if SValue <> AValue then
      ScrollDraw;
  end;
  PgStep := APgStep;
  ArStep := AArStep;
end;

procedure TScrollBar.SetRange(AMin, AMax: Sw_Integer);
begin
  SetParams(Value, AMin, AMax, PgStep, ArStep);
end;

procedure TScrollBar.SetStep(APgStep, AArStep: Sw_Integer);
begin
  SetParams(Value, Min, Max, APgStep, AArStep);
end;

procedure TScrollBar.SetValue(AValue: Sw_Integer);
begin
  SetParams(AValue, Min, Max, PgStep, ArStep);
end;

{ ---- TScroller ----------------------------------------------------------------------- }

constructor TScroller.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
begin
  inherited Init(Bounds);
  Options := Options or ofSelectable;
  EventMask := EventMask or evBroadcast;
  HScrollBar := AHScrollBar;
  VScrollBar := AVScrollBar;
end;

constructor TScroller.Load(var S: TStream);
begin
  inherited Load(S);
  GetPeerViewPtr(S, HScrollBar);
  GetPeerViewPtr(S, VScrollBar);
  S.Read(Delta, SizeOf(TPoint) * 2);
end;

procedure TScroller.Store(var S: TStream);
begin
  inherited Store(S);
  PutPeerViewPtr(S, HScrollBar);
  PutPeerViewPtr(S, VScrollBar);
  S.Write(Delta, SizeOf(TPoint) * 2);
end;

procedure TScroller.ChangeBounds(var Bounds: TRect);
begin
  SetBounds(Bounds);
  Inc(DrawLock);
  SetLimit(Limit.X, Limit.Y);
  Dec(DrawLock);
  DrawFlag := False;
  DrawView;
end;

procedure TScroller.CheckDraw;
begin
  if (DrawLock = 0) and DrawFlag then
  begin
    DrawFlag := False;
    DrawView;
  end;
end;

function TScroller.GetPalette: PPalette;
const
  P: String[Length(CScroller)] = CScroller;
begin
  GetPalette := @P;
end;

procedure TScroller.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmScrollBarChanged) and
    ((Event.InfoPtr = HScrollBar) or (Event.InfoPtr = VScrollBar)) then
    ScrollDraw;
end;

procedure TScroller.ScrollDraw;
var
  D: TPoint;
begin
  if HScrollBar <> nil then
    D.X := HScrollBar^.Value
  else
    D.X := 0;
  if VScrollBar <> nil then
    D.Y := VScrollBar^.Value
  else
    D.Y := 0;
  if (D.X <> Delta.X) or (D.Y <> Delta.Y) then
  begin
    SetCursor(Cursor.X + Delta.X - D.X, Cursor.Y + Delta.Y - D.Y);
    Delta := D;
    if DrawLock <> 0 then
      DrawFlag := True
    else
      DrawView;
  end;
end;

procedure TScroller.ScrollTo(X, Y: Sw_Integer);
begin
  Inc(DrawLock);
  if HScrollBar <> nil then
    HScrollBar^.SetValue(X);
  if VScrollBar <> nil then
    VScrollBar^.SetValue(Y);
  Dec(DrawLock);
  CheckDraw;
end;

procedure TScroller.SetLimit(X, Y: Sw_Integer);
begin
  Limit.X := X;
  Limit.Y := Y;
  Inc(DrawLock);
  if HScrollBar <> nil then
    HScrollBar^.SetParams(HScrollBar^.Value, 0, X - Size.X, Size.X - 1, HScrollBar^.ArStep);
  if VScrollBar <> nil then
    VScrollBar^.SetParams(VScrollBar^.Value, 0, Y - Size.Y, Size.Y - 1, VScrollBar^.ArStep);
  Dec(DrawLock);
  CheckDraw;
end;

procedure TScroller.SetState(AState: Word; Enable: Boolean);

  procedure ShowSBar(SBar: PScrollBar);
  begin
    if SBar <> nil then
      if GetState(sfActive + sfSelected) then
        SBar^.Show
      else
        SBar^.Hide;
  end;

begin
  inherited SetState(AState, Enable);
  if AState and (sfActive + sfSelected) <> 0 then
  begin
    ShowSBar(HScrollBar);
    ShowSBar(VScrollBar);
  end;
end;

{ ---- TListViewer ------------------------------------------------------------------------- }

constructor TListViewer.Init(var Bounds: TRect; ANumCols: Sw_Word; AHScrollBar, AVScrollBar: PScrollBar);
var
  ArStep, PgStep: Sw_Integer;
begin
  inherited Init(Bounds);
  Options := Options or (ofFirstClick + ofSelectable);
  EventMask := EventMask or evBroadcast;
  Range := 0;
  NumCols := ANumCols;
  Focused := 0;
  if AVScrollBar <> nil then
  begin
    if NumCols = 1 then
    begin
      PgStep := Size.Y - 1;
      ArStep := 1;
    end
    else
    begin
      PgStep := Size.Y * NumCols;
      ArStep := Size.Y;
    end;
    AVScrollBar^.SetStep(PgStep, ArStep);
  end;
  if AHScrollBar <> nil then
    AHScrollBar^.SetStep(Size.X div NumCols, 1);
  HScrollBar := AHScrollBar;
  VScrollBar := AVScrollBar;
end;

constructor TListViewer.Load(var S: TStream);
begin
  inherited Load(S);
  GetPeerViewPtr(S, HScrollBar);
  GetPeerViewPtr(S, VScrollBar);
  S.Read(NumCols, SizeOf(Sw_Integer) * 4);
end;

procedure TListViewer.Store(var S: TStream);
begin
  inherited Store(S);
  PutPeerViewPtr(S, HScrollBar);
  PutPeerViewPtr(S, VScrollBar);
  S.Write(NumCols, SizeOf(Sw_Integer) * 4);
end;

procedure TListViewer.ChangeBounds(var Bounds: TRect);
begin
  inherited ChangeBounds(Bounds);
  if HScrollBar <> nil then
    HScrollBar^.SetStep(Size.X div NumCols, HScrollBar^.ArStep);
  if VScrollBar <> nil then
    VScrollBar^.SetStep(Size.Y, VScrollBar^.ArStep);
end;

procedure TListViewer.Draw;
var
  I, J, Item, ColWidth, CurCol, Indent: Sw_Integer;
  NormalColor, SelectedColor, FocusedColor, Color: Word;
  B: TDrawBuffer;
  Text: String;
  SCOff: Byte;
begin
  if State and (sfSelected + sfActive) = sfSelected + sfActive then
  begin
    NormalColor := GetColor(1);
    FocusedColor := GetColor(3);
    SelectedColor := GetColor(4);
  end
  else
  begin
    NormalColor := GetColor(2);
    SelectedColor := GetColor(4);
    FocusedColor := GetColor(4);
  end;
  if HScrollBar <> nil then
    Indent := HScrollBar^.Value
  else
    Indent := 0;
  if NumCols < 1 then
    NumCols := 1;
  ColWidth := Size.X div NumCols + 1;
  for I := 0 to Size.Y - 1 do
  begin
    for J := 0 to NumCols - 1 do
    begin
      Item := J * Size.Y + I + TopItem;
      CurCol := J * ColWidth;
      if (State and (sfSelected + sfActive) = sfSelected + sfActive) and (Focused = Item) and (Range > 0) then
      begin
        Color := FocusedColor;
        SetCursor(CurCol + 1, I);
        SCOff := 0;
      end
      else if (Item < Range) and IsSelected(Item) then
      begin
        Color := SelectedColor;
        SCOff := 2;
      end
      else
      begin
        Color := NormalColor;
        SCOff := 4;
      end;
      MoveChar(B[CurCol], ' ', Color, ColWidth);
      if Item < Range then
      begin
        Text := GetText(Item, ColWidth + Indent);
        Text := Copy(Text, Indent + 1, ColWidth);
        MoveStr(B[CurCol + 1], Text, Color);
        if ShowMarkers then
        begin
          MoveChar(B[CurCol], '[', 0, 1);
          MoveChar(B[CurCol + ColWidth - 2], ']', 0, 1);
        end;
      end
      else if (I = 0) and (J = 0) then
        MoveStr(B[CurCol + 1], '<empty>', GetColor(1));
      if SCOff = 255 then
        Color := 0;
      MoveChar(B[CurCol + ColWidth - 1], #179, GetColor(5), 1);
    end;
    WriteLine(0, I, Size.X, 1, B);
  end;
end;

procedure TListViewer.FocusItem(Item: Sw_Integer);
begin
  Focused := Item;
  if VScrollBar <> nil then
    VScrollBar^.SetValue(Item);
  if Item < TopItem then
    if NumCols = 1 then
      TopItem := Item
    else
      TopItem := Item - Item mod Size.Y
  else if Item >= TopItem + (Size.Y * NumCols) then
    if NumCols = 1 then
      TopItem := Item - Size.Y + 1
    else
      TopItem := Item - Item mod Size.Y - (Size.Y * (NumCols - 1));
end;

procedure TListViewer.FocusItemNum(Item: Sw_Integer);
begin
  if Item < 0 then
    Item := 0
  else if (Item >= Range) and (Range > 0) then
    Item := Range - 1;
  if Range <> 0 then
    FocusItem(Item);
end;

function TListViewer.GetPalette: PPalette;
const
  P: String[Length(CListViewer)] = CListViewer;
begin
  GetPalette := @P;
end;

function TListViewer.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
begin
  Abstract;
  GetText := '';
end;

function TListViewer.IsSelected(Item: Sw_Integer): Boolean;
begin
  IsSelected := Item = Focused;
end;

procedure TListViewer.HandleEvent(var Event: TEvent);
const
  MouseAutosToSkip = 4;
var
  Mouse: TPoint;
  ColWidth, OldItem, NewItem, Count: Sw_Integer;
begin
  inherited HandleEvent(Event);
  if Event.What = evMouseDown then
  begin
    if NumCols < 1 then
      NumCols := 1;
    ColWidth := Size.X div NumCols + 1;
    OldItem := Focused;
    MakeLocal(Event.Where, Mouse);
    if MouseInView(Event.Where) then
      NewItem := Mouse.Y + (Size.Y * (Mouse.X div ColWidth)) + TopItem
    else
      NewItem := OldItem;
    Count := 0;
    repeat
      if NewItem <> OldItem then
      begin
        FocusItemNum(NewItem);
        DrawView;
      end;
      OldItem := NewItem;
      MakeLocal(Event.Where, Mouse);
      if MouseInView(Event.Where) then
        NewItem := Mouse.Y + (Size.Y * (Mouse.X div ColWidth)) + TopItem
      else if NumCols = 1 then
      begin
        if Event.What = evMouseAuto then
          Inc(Count);
        if Count = MouseAutosToSkip then
        begin
          Count := 0;
          if Mouse.Y < 0 then
            NewItem := Focused - 1
          else if Mouse.Y >= Size.Y then
            NewItem := Focused + 1;
        end;
      end;
      if Event.Double then
        Break;
    until not MouseEvent(Event, evMouseMove + evMouseAuto);
    FocusItemNum(NewItem);
    DrawView;
    if Event.Double and (Range > Focused) then
      SelectItem(Focused);
    ClearEvent(Event);
  end
  else if Event.What = evKeyDown then
  begin
    if (Event.CharCode = ' ') and (Focused < Range) then
    begin
      SelectItem(Focused);
      NewItem := Focused;
    end
    else
      case CtrlToArrow(Event.KeyCode) of
        kbUp: NewItem := Focused - 1;
        kbDown: NewItem := Focused + 1;
        kbRight: if NumCols > 1 then NewItem := Focused + Size.Y else Exit;
        kbLeft: if NumCols > 1 then NewItem := Focused - Size.Y else Exit;
        kbPgDn: NewItem := Focused + Size.Y * NumCols;
        kbPgUp: NewItem := Focused - Size.Y * NumCols;
        kbHome: NewItem := TopItem;
        kbEnd: NewItem := TopItem + (Size.Y * NumCols) - 1;
        kbCtrlPgDn: NewItem := Range - 1;
        kbCtrlPgUp: NewItem := 0;
      else
        Exit;
      end;
    FocusItemNum(NewItem);
    DrawView;
    ClearEvent(Event);
  end
  else if Event.What = evBroadcast then
    if Options and ofSelectable <> 0 then
      if (Event.Command = cmScrollBarClicked) and ((Event.InfoPtr = HScrollBar) or (Event.InfoPtr = VScrollBar)) then
        Select
      else if Event.Command = cmScrollBarChanged then
      begin
        if VScrollBar = Event.InfoPtr then
        begin
          FocusItemNum(VScrollBar^.Value);
          DrawView;
        end
        else if HScrollBar = Event.InfoPtr then
          DrawView;
      end;
end;

procedure TListViewer.SelectItem(Item: Sw_Integer);
begin
  Message(Owner, evBroadcast, cmListItemSelected, @Self);
end;

procedure TListViewer.SetRange(ARange: Sw_Integer);
begin
  Range := ARange;
  if Focused >= ARange then
    Focused := 0;
  if VScrollBar <> nil then
  begin
    if Focused > ARange - 1 then
      Focused := 0;
    VScrollBar^.SetParams(Focused, 0, ARange - 1, VScrollBar^.PgStep, VScrollBar^.ArStep);
  end
  else
    DrawView;
end;

procedure TListViewer.SetState(AState: Word; Enable: Boolean);

  procedure ShowSBar(SBar: PScrollBar);
  begin
    if SBar <> nil then
      if GetState(sfActive) and GetState(sfVisible) then
        SBar^.Show
      else
        SBar^.Hide;
  end;

begin
  inherited SetState(AState, Enable);
  if AState and (sfSelected + sfActive + sfVisible) <> 0 then
  begin
    ShowSBar(HScrollBar);
    ShowSBar(VScrollBar);
    DrawView;
  end;
end;

{ ---- TGroup ------------------------------------------------------------------------------- }

constructor TGroup.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  Options := Options or (ofSelectable + ofBuffered);
  EventMask := $FFFF;
end;

constructor TGroup.Load(var S: TStream);
var
  Count, I: Sw_Integer;
  P: PView;
  SaveOwner: PGroup;
  SaveCount: Sw_Integer;
begin
  inherited Load(S);
  SaveOwner := OwnerGroup;
  SaveCount := FixupCount;
  OwnerGroup := @Self;
  Count := 0;
  S.Read(Count, SizeOf(Count));
  for I := 1 to Count do
  begin
    P := PView(S.Get);
    if P <> nil then
      InsertView(P, nil);
  end;
  GetSubViewPtr(S, Current);
  { Peer references of the subviews just loaded. }
  for I := SaveCount to FixupCount - 1 do
    PPointer(FixupPtr[I])^ := At(FixupIndex[I]);
  FixupCount := SaveCount;
  OwnerGroup := SaveOwner;
end;

procedure TGroup.Store(var S: TStream);
var
  Count: Sw_Integer;
  P: PView;
begin
  inherited Store(S);
  { The number of subviews: they are numbered from Last (1) to First. }
  Count := IndexOf(First);
  S.Write(Count, SizeOf(Count));
  if Last <> nil then
  begin
    P := Last;
    repeat
      P := P^.Next;
      S.Put(P);
    until P = Last;
  end;
  PutSubViewPtr(S, Current);
end;

destructor TGroup.Done;
var
  P, T: PView;
begin
  Hide;
  P := Last;
  if P <> nil then
  begin
    repeat
      P^.Hide;
      P := P^.Prev;
    until P = Last;
    repeat
      T := P^.Prev;
      Dispose(P, Done);
      P := T;
    until Last = nil;
  end;
  inherited Done;
end;

procedure TGroup.Awaken;
var
  P: PView;
begin
  P := First;
  while P <> nil do
  begin
    P^.Awaken;
    P := P^.NextView;
  end;
end;

procedure TGroup.ChangeBounds(var Bounds: TRect);
var
  D: TPoint;
  P, N: PView;
  R: TRect;
begin
  D.X := Bounds.B.X - Bounds.A.X - Size.X;
  D.Y := Bounds.B.Y - Bounds.A.Y - Size.Y;
  if (D.X = 0) and (D.Y = 0) then
  begin
    SetBounds(Bounds);
    DrawView;
    Exit;
  end;
  SetBounds(Bounds);
  Lock;
  P := First;
  while P <> nil do
  begin
    N := P^.NextView;
    P^.CalcBounds(R, D);
    P^.ChangeBounds(R);
    P := N;
  end;
  Unlock;
end;

function TGroup.DataSize: Word;
var
  P: PView;
  T: Word;
begin
  T := 0;
  if Last <> nil then
  begin
    P := Last;
    repeat
      Inc(T, P^.DataSize);
      P := P^.Prev;
    until P = Last;
  end;
  DataSize := T;
end;

procedure TGroup.Delete(P: PView);
var
  SaveState: Word;
begin
  if (P = nil) or (P^.Owner <> @Self) then
    Exit;
  SaveState := P^.State;
  P^.Hide;
  RemoveView(P);
  P^.Owner := nil;
  P^.Next := nil;
  if P = Current then
    Current := nil;
  if SaveState and sfVisible <> 0 then
    P^.State := P^.State or sfVisible;
end;

procedure TGroup.Draw;
begin
  Redraw;
end;

procedure TGroup.EndModal(Command: Word);
begin
  if State and sfModal <> 0 then
    EndState := Command
  else
    inherited EndModal(Command);
end;

procedure TGroup.EventError(var Event: TEvent);
begin
  if Owner <> nil then
    Owner^.EventError(Event);
end;

function TGroup.ExecView(P: PView): Word;
var
  SaveOptions: Word;
  SaveOwner: PGroup;
  SaveTopView, SaveCurrent: PView;
  SaveCommands: TCommandSet;
begin
  if P = nil then
  begin
    ExecView := cmCancel;
    Exit;
  end;
  SaveOptions := P^.Options;
  SaveOwner := P^.Owner;
  SaveTopView := TheTopView;
  SaveCurrent := Current;
  GetCommands(SaveCommands);
  TheTopView := P;
  P^.Options := P^.Options and not ofSelectable;
  P^.SetState(sfModal, True);
  SetCurrent(P, EnterSelect);
  if SaveOwner = nil then
    Insert(P);
  ExecView := P^.Execute;
  if SaveOwner = nil then
    Delete(P);
  SetCurrent(SaveCurrent, LeaveSelect);
  P^.SetState(sfModal, False);
  P^.Options := SaveOptions;
  TheTopView := SaveTopView;
  SetCommands(SaveCommands);
end;

function TGroup.Execute: Word;
var
  E: TEvent;
begin
  repeat
    EndState := 0;
    repeat
      GetEvent(E);
      HandleEvent(E);
      if E.What <> evNothing then
        EventError(E);
    until EndState <> 0;
  until Valid(EndState);
  Execute := EndState;
end;

function TGroup.First: PView;
begin
  if Last = nil then
    First := nil
  else
    First := Last^.Next;
end;

{ P is a function nested in the caller (TP convention). }
function TGroup.FirstThat(P: Pointer): PView;
var
  Frame: Pointer;
  V, N: PView;
  Stop: Boolean;
begin
  Frame := CallerFrame;
  FirstThat := nil;
  if Last = nil then
    Exit;
  V := Last^.Next;
  repeat
    N := V^.Next;
    Stop := V = Last;
    if CallLocalTest(P, Frame, V) then
    begin
      FirstThat := V;
      Exit;
    end;
    V := N;
  until Stop or (Last = nil);
end;

procedure TGroup.ForEach(P: Pointer);
var
  Frame: Pointer;
  V, N, L: PView;
  Stop: Boolean;
begin
  Frame := CallerFrame;
  if Last = nil then
    Exit;
  L := Last;
  V := L^.Next;
  repeat
    N := V^.Next;
    Stop := V = L;
    CallLocal(P, Frame, V);
    V := N;
  until Stop or (Last = nil);
end;

function TGroup.FindNext(Forwards: Boolean): PView;
var
  P: PView;
begin
  FindNext := nil;
  if Current = nil then
    Exit;
  P := Current;
  repeat
    if Forwards then
      P := P^.Next
    else
      P := P^.Prev;
  until ((P^.State and (sfVisible + sfDisabled) = sfVisible) and (P^.Options and ofSelectable <> 0)) or (P = Current);
  if P <> Current then
    FindNext := P;
end;

function TGroup.FocusNext(Forwards: Boolean): Boolean;
var
  P: PView;
begin
  P := FindNext(Forwards);
  FocusNext := True;
  if P <> nil then
    FocusNext := P^.Focus;
end;

function TGroup.FirstMatch(AState: Word; AOptions: Word): PView;
var
  P: PView;
begin
  FirstMatch := nil;
  P := First;
  while P <> nil do
  begin
    if (P^.State and AState = AState) and (P^.Options and AOptions = AOptions) then
    begin
      FirstMatch := P;
      Exit;
    end;
    P := P^.NextView;
  end;
end;

procedure TGroup.GetData(var Rec);
var
  I: Word;
  P: PView;
begin
  I := 0;
  if Last = nil then
    Exit;
  P := Last;
  repeat
    P^.GetData(PByteArray(@Rec)^[I]);
    Inc(I, P^.DataSize);
    P := P^.Prev;
  until P = Last;
end;

function TGroup.GetHelpCtx: Word;
var
  H: Word;
begin
  H := hcNoContext;
  if Current <> nil then
    H := Current^.GetHelpCtx;
  if H = hcNoContext then
    H := inherited GetHelpCtx;
  GetHelpCtx := H;
end;

{ Subviews are numbered from 1 in insertion order (Last is the first). }
function TGroup.IndexOf(P: PView): Sw_Integer;
var
  Q: PView;
  I: Sw_Integer;
begin
  IndexOf := 0;
  if (P = nil) or (Last = nil) then
    Exit;
  Q := Last;
  I := 0;
  repeat
    Inc(I);
    if Q = P then
    begin
      IndexOf := I;
      Exit;
    end;
    Q := Q^.Prev;
  until Q = Last;
end;

function TGroup.At(Index: Sw_Integer): PView;
var
  Q: PView;
begin
  At := nil;
  if (Last = nil) or (Index < 1) then
    Exit;
  Q := Last;
  while Index > 1 do
  begin
    Q := Q^.Prev;
    if Q = Last then
      Exit;
    Dec(Index);
  end;
  At := Q;
end;

procedure TGroup.GetSubViewPtr(var S: TStream; var P);
var
  Index: Sw_Integer;
begin
  Index := 0;
  S.Read(Index, SizeOf(Index));
  Pointer(P) := At(Index);
end;

procedure TGroup.PutSubViewPtr(var S: TStream; P: PView);
var
  Index: Sw_Integer;
begin
  Index := IndexOf(P);
  S.Write(Index, SizeOf(Index));
end;

procedure TGroup.HandleEvent(var Event: TEvent);

  procedure DoHandle(P: PView);
  begin
    if P = nil then
      Exit;
    if (P^.State and sfDisabled <> 0) and (Event.What and (PositionalEvents or FocusedEvents) <> 0) then
      Exit;
    case Phase of
      phPreProcess: if P^.Options and ofPreProcess = 0 then Exit;
      phPostProcess: if P^.Options and ofPostProcess = 0 then Exit;
    end;
    if Event.What and P^.EventMask <> 0 then
      P^.HandleEvent(Event);
  end;

  procedure ForAll;
  var
    V, N, L: PView;
    Stop: Boolean;
  begin
    if Last = nil then
      Exit;
    L := Last;
    V := L^.Next;
    repeat
      N := V^.Next;
      Stop := V = L;
      DoHandle(V);
      V := N;
    until Stop or (Last = nil);
  end;

  function UnderMouse: PView;
  var
    V: PView;
  begin
    UnderMouse := nil;
    V := First;
    while V <> nil do
    begin
      if (V^.State and sfVisible <> 0) and V^.MouseInView(Event.Where) then
      begin
        UnderMouse := V;
        Exit;
      end;
      V := V^.NextView;
    end;
  end;

begin
  inherited HandleEvent(Event);
  if Event.What and FocusedEvents <> 0 then
  begin
    Phase := phPreProcess;
    ForAll;
    Phase := phFocused;
    DoHandle(Current);
    Phase := phPostProcess;
    ForAll;
  end
  else
  begin
    Phase := phFocused;
    if Event.What and PositionalEvents <> 0 then
      DoHandle(UnderMouse)
    else
      ForAll;
  end;
end;

procedure TGroup.Insert(P: PView);
begin
  InsertBefore(P, First);
end;

procedure TGroup.InsertBefore(P, Target: PView);
var
  SaveState: Word;
begin
  if (P = nil) or (P^.Owner <> nil) or ((Target <> nil) and (Target^.Owner <> @Self)) then
    Exit;
  if P^.Options and ofCenterX <> 0 then
    P^.Origin.X := (Size.X - P^.Size.X) div 2;
  if P^.Options and ofCenterY <> 0 then
    P^.Origin.Y := (Size.Y - P^.Size.Y) div 2;
  SaveState := P^.State;
  P^.State := P^.State and not sfVisible;
  InsertView(P, Target);
  if SaveState and sfVisible <> 0 then
    P^.Show;
  if State and sfActive <> 0 then
    P^.SetState(sfActive, True);
end;

procedure TGroup.InsertView(P, Target: PView);
begin
  P^.Owner := @Self;
  if Target <> nil then
  begin
    Target := Target^.Prev;
    P^.Next := Target^.Next;
    Target^.Next := P;
  end
  else
  begin
    if Last = nil then
      P^.Next := P
    else
    begin
      P^.Next := Last^.Next;
      Last^.Next := P;
    end;
    Last := P;
  end;
end;

procedure TGroup.RemoveView(P: PView);
var
  Q: PView;
begin
  if Last = nil then
    Exit;
  Q := Last;
  while (Q^.Next <> P) and (Q^.Next <> Last) do
    Q := Q^.Next;
  if Q^.Next <> P then
    Exit;
  if Q = P then
    Last := nil
  else
  begin
    Q^.Next := P^.Next;
    if P = Last then
      Last := Q;
  end;
end;

procedure TGroup.Lock;
begin
  Inc(LockFlag);
end;

procedure TGroup.Unlock;
begin
  if LockFlag > 0 then
  begin
    Dec(LockFlag);
    if LockFlag = 0 then
      DrawView;
  end;
end;

{ Draws every subview (bottom first; clipping hides covered cells). }
procedure TGroup.Redraw;
var
  P: PView;
begin
  if (LockFlag > 0) or not Exposed then
    Exit;
  P := Last;
  if P = nil then
    Exit;
  repeat
    if P^.State and sfVisible <> 0 then
      P^.DrawView;
    P := P^.Prev;
  until P = Last;
end;

procedure TGroup.ResetCurrent;
begin
  SetCurrent(FirstMatch(sfVisible, ofSelectable), NormalSelect);
end;

procedure TGroup.SelectNext(Forwards: Boolean);
var
  P: PView;
begin
  P := FindNext(Forwards);
  if P <> nil then
    P^.Select;
end;

procedure TGroup.SetCurrent(P: PView; Mode: TSelectMode);
begin
  if Current = P then
    Exit;
  Lock;
  if (State and sfFocused <> 0) and (Current <> nil) then
    Current^.SetState(sfFocused, False);
  if (Mode <> EnterSelect) and (Current <> nil) then
    Current^.SetState(sfSelected, False);
  if (Mode <> LeaveSelect) and (P <> nil) then
    P^.SetState(sfSelected, True);
  if (State and sfFocused <> 0) and (P <> nil) then
    P^.SetState(sfFocused, True);
  Current := P;
  Unlock;
end;

procedure TGroup.SetData(var Rec);
var
  I: Word;
  P: PView;
begin
  I := 0;
  if Last = nil then
    Exit;
  P := Last;
  repeat
    P^.SetData(PByteArray(@Rec)^[I]);
    Inc(I, P^.DataSize);
    P := P^.Prev;
  until P = Last;
end;

procedure TGroup.SetState(AState: Word; Enable: Boolean);
var
  P, N: PView;
begin
  inherited SetState(AState, Enable);
  case AState of
    sfActive, sfDragging:
      begin
        Lock;
        P := First;
        while P <> nil do
        begin
          N := P^.NextView;
          P^.SetState(AState, Enable);
          P := N;
        end;
        Unlock;
      end;
    sfFocused:
      if Current <> nil then
        Current^.SetState(sfFocused, Enable);
    sfExposed:
      begin
        P := First;
        while P <> nil do
        begin
          N := P^.NextView;
          if P^.State and sfVisible <> 0 then
            P^.SetState(sfExposed, Enable);
          P := N;
        end;
      end;
  end;
end;

function TGroup.Valid(Command: Word): Boolean;
var
  P: PView;
begin
  Valid := True;
  if Command = cmReleasedFocus then
  begin
    if (Current <> nil) and (Current^.Options and ofValidate <> 0) then
      Valid := Current^.Valid(Command);
    Exit;
  end;
  P := First;
  while P <> nil do
  begin
    if not P^.Valid(Command) then
    begin
      Valid := False;
      Exit;
    end;
    P := P^.NextView;
  end;
end;

{ ---- TWindow ------------------------------------------------------------------------------- }

constructor TWindow.Init(var Bounds: TRect; ATitle: TTitleStr; ANumber: Sw_Integer);
begin
  inherited Init(Bounds);
  State := State or sfShadow;
  Options := Options or (ofSelectable + ofTopSelect);
  GrowMode := gfGrowAll + gfGrowRel;
  Flags := wfMove + wfGrow + wfClose + wfZoom;
  Title := NewStr(ATitle);
  Number := ANumber;
  Palette := wpBlueWindow;
  InitFrame;
  if Frame <> nil then
    Insert(Frame);
  GetBounds(ZoomRect);
end;

constructor TWindow.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Flags, 1);
  S.Read(ZoomRect, SizeOf(TRect));
  S.Read(Number, SizeOf(Sw_Integer));
  S.Read(Palette, SizeOf(Sw_Integer));
  GetSubViewPtr(S, Frame);
  Title := S.ReadStr;
end;

procedure TWindow.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Flags, 1);
  S.Write(ZoomRect, SizeOf(TRect));
  S.Write(Number, SizeOf(Sw_Integer));
  S.Write(Palette, SizeOf(Sw_Integer));
  PutSubViewPtr(S, Frame);
  S.WriteStr(Title);
end;

destructor TWindow.Done;
begin
  inherited Done;
  DisposeStr(Title);
end;

procedure TWindow.Close;
var
  P: PObject;
begin
  if Valid(cmClose) then
  begin
    P := @Self;
    Dispose(P, Done);
  end;
end;

function TWindow.GetPalette: PPalette;
const
  P: array[wpBlueWindow..wpGrayWindow] of String[Length(CBlueWindow)] = (CBlueWindow, CCyanWindow, CGrayWindow);
begin
  GetPalette := @P[Palette];
end;

function TWindow.GetTitle(MaxSize: Sw_Integer): TTitleStr;
begin
  if Title = nil then
    GetTitle := ''
  else
    GetTitle := Copy(Title^, 1, MaxSize);
end;

procedure TWindow.HandleEvent(var Event: TEvent);
var
  Limits: TRect;
  MinS, MaxS: TPoint;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evCommand:
      case Event.Command of
        cmResize:
          if Flags and (wfMove + wfGrow) <> 0 then
          begin
            Owner^.GetExtent(Limits);
            SizeLimits(MinS, MaxS);
            DragView(Event, DragMode or (Flags and (wfMove + wfGrow)), Limits, MinS, MaxS);
            ClearEvent(Event);
          end;
        cmClose:
          if (Flags and wfClose <> 0) and ((Event.InfoPtr = nil) or (Event.InfoPtr = @Self)) then
          begin
            ClearEvent(Event);
            if State and sfModal = 0 then
              Close
            else
            begin
              Event.What := evCommand;
              Event.Command := cmCancel;
              PutEvent(Event);
              ClearEvent(Event);
            end;
          end;
        cmZoom:
          if (Flags and wfZoom <> 0) and ((Event.InfoPtr = nil) or (Event.InfoPtr = @Self)) then
          begin
            Zoom;
            ClearEvent(Event);
          end;
      end;
    evKeyDown:
      case Event.KeyCode of
        kbTab:
          begin
            FocusNext(False);
            ClearEvent(Event);
          end;
        kbShiftTab:
          begin
            FocusNext(True);
            ClearEvent(Event);
          end;
      end;
    evBroadcast:
      if (Event.Command = cmSelectWindowNum) and (Event.InfoInt = Number) and (Options and ofSelectable <> 0) then
      begin
        Select;
        ClearEvent(Event);
      end;
  end;
end;

procedure TWindow.InitFrame;
var
  R: TRect;
begin
  GetExtent(R);
  Frame := New(PFrame, Init(R));
end;

procedure TWindow.SetState(AState: Word; Enable: Boolean);
var
  WindowCommands: TCommandSet;
begin
  inherited SetState(AState, Enable);
  if AState = sfSelected then
    SetState(sfActive, Enable);
  if (AState = sfSelected) or ((AState = sfExposed) and (State and sfSelected <> 0)) then
  begin
    WindowCommands := [cmNext, cmPrev];
    if Flags and (wfGrow + wfMove) <> 0 then
      WindowCommands := WindowCommands + [cmResize];
    if Flags and wfClose <> 0 then
      WindowCommands := WindowCommands + [cmClose];
    if Flags and wfZoom <> 0 then
      WindowCommands := WindowCommands + [cmZoom];
    if Enable then
      EnableCommands(WindowCommands)
    else
      DisableCommands(WindowCommands);
  end;
end;

procedure TWindow.SizeLimits(var Min, Max: TPoint);
begin
  inherited SizeLimits(Min, Max);
  Min := MinWinSize;
end;

function TWindow.StandardScrollBar(AOptions: Word): PScrollBar;
var
  R: TRect;
  S: PScrollBar;
begin
  GetExtent(R);
  if AOptions and sbVertical = 0 then
    R.Assign(R.A.X + 2, R.B.Y - 1, R.B.X - 2, R.B.Y)
  else
    R.Assign(R.B.X - 1, R.A.Y + 1, R.B.X, R.B.Y - 1);
  S := New(PScrollBar, Init(R));
  Insert(S);
  if AOptions and sbHandleKeyboard <> 0 then
    S^.Options := S^.Options or ofPostProcess;
  StandardScrollBar := S;
end;

procedure TWindow.Zoom;
var
  R: TRect;
  MaxS, MinS: TPoint;
begin
  SizeLimits(MinS, MaxS);
  if (Size.X <> MaxS.X) or (Size.Y <> MaxS.Y) then
  begin
    GetBounds(ZoomRect);
    R.Assign(0, 0, MaxS.X, MaxS.Y);
    Locate(R);
  end
  else
    Locate(ZoomRect);
end;

procedure RegisterViews;
begin
  RegisterType(RView);
  RegisterType(RFrame);
  RegisterType(RScrollBar);
  RegisterType(RScroller);
  RegisterType(RListViewer);
  RegisterType(RGroup);
  RegisterType(RWindow);
end;

begin
  CurCommandSet := [0..255] - [cmZoom, cmClose, cmResize, cmNext, cmPrev];
end.
