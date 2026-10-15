{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit App dari Odin Vision: TBackground, TDesktop, TProgram dan
  TApplication. Implementasi clean-room berdasarkan dokumentasi API Turbo
  Vision TP7. Palet warna aplikasi dirancang sendiri untuk Odin.

  TProgram.GetEvent mengambil event mouse lalu keyboard; bila keduanya
  kosong ia memanggil Idle lalu menunggu input paling lama 50 ms
  (WaitForEvent juga menampilkan perubahan ScreenBuffer ke terminal). }
unit App;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Memory, HistList, Views, Menus, Dialogs;

const
  { Standard application commands }
  cmNew = 30;
  cmOpen = 31;
  cmSave = 32;
  cmSaveAs = 33;
  cmSaveAll = 34;
  cmChangeDir = 35;
  cmDosShell = 36;
  cmCloseAll = 37;

  { Standard application help contexts }
  hcNew = $FF01;
  hcOpen = $FF02;
  hcSave = $FF03;
  hcSaveAs = $FF04;
  hcSaveAll = $FF05;
  hcChangeDir = $FF06;
  hcDosShell = $FF07;
  hcExit = $FF08;
  hcUndo = $FF10;
  hcCut = $FF11;
  hcCopy = $FF12;
  hcPaste = $FF13;
  hcClear = $FF14;
  hcTile = $FF20;
  hcCascade = $FF21;
  hcCloseAll = $FF22;
  hcResize = $FF23;
  hcZoom = $FF24;
  hcNext = $FF25;
  hcPrev = $FF26;
  hcClose = $FF27;

  apColor = 0;
  apBlackWhite = 1;
  apMonochrome = 2;

  CBackground = #1;

  { Application palettes: 1 desktop, 2-7 menus and status line, 8-15 blue,
    16-23 cyan and 24-31 gray windows, 32-63 gray, 64-95 blue and 96-127
    cyan dialogs. }
  CAppColor =
    #19#112#120#116#47#40#46#23#31#26#49#49#30#113#31#55#63#58#19#19#48#47#63#112#127#122#19#19#112 +
    #127#127#112#127#122#19#19#112#112#127#116#32#43#47#120#46#112#48#63#62#31#47#26#32#114#19#19#48 +
    #47#62#49#19#56#112#23#31#26#113#113#30#23#31#30#32#43#47#120#46#16#48#63#62#112#47#122#32#18#49 +
    #49#48#47#62#49#19#56#31#55#63#58#19#19#62#48#63#62#32#43#47#120#46#48#112#127#126#31#47#26#32 +
    #50#49#49#112#47#126#113#19#120#63;
  CAppBlackWhite =
    #7#112#120#112#15#8#15#7#15#15#112#112#15#112#15#112#112#112#7#7#112#15#112#112#112#112#7#7#112 +
    #112#112#112#112#112#7#7#112#112#112#112#15#15#15#120#15#112#112#112#112#15#15#15#15#112#7#7#112 +
    #15#112#112#7#120#112#7#15#15#112#112#15#7#15#15#15#15#15#120#15#7#112#112#112#112#15#112#15#7 +
    #112#112#112#15#112#112#7#120#15#112#112#112#7#7#112#112#112#112#15#15#15#120#15#112#112#112#112 +
    #15#15#15#15#112#112#112#112#15#112#112#7#120#112;
  CAppMonochrome =
    #7#112#112#112#15#7#15#7#15#15#112#112#15#112#15#112#112#112#7#7#112#15#112#112#112#112#7#7#112 +
    #112#112#112#112#112#7#7#112#112#112#112#15#15#15#112#15#112#112#112#112#15#15#15#15#112#7#7#112 +
    #15#112#112#7#112#112#7#15#15#112#112#15#7#15#15#15#15#15#112#15#7#112#112#112#112#15#112#15#7 +
    #112#112#112#15#112#112#7#112#15#112#112#112#7#7#112#112#112#112#15#15#15#112#15#112#112#112#112 +
    #15#15#15#15#112#112#112#112#15#112#112#7#112#112;

type
  PBackground = ^TBackground;
  TBackground = object(TView)
    Pattern: Char;
    constructor Init(var Bounds: TRect; APattern: Char);
    constructor Load(var S: TStream);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure Store(var S: TStream);
  end;

  PDesktop = ^TDesktop;
  TDesktop = object(TGroup)
    Background: PBackground;
    TileColumnsFirst: Boolean;
    constructor Init(var Bounds: TRect);
    constructor Load(var S: TStream);
    procedure Cascade(var R: TRect);
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitBackground; virtual;
    procedure Store(var S: TStream);
    procedure Tile(var R: TRect);
    procedure TileError; virtual;
  end;

  PProgram = ^TProgram;
  TProgram = object(TGroup)
    constructor Init;
    destructor Done; virtual;
    function CanMoveFocus: Boolean;
    function ExecuteDialog(P: PDialog; Data: Pointer): Word;
    procedure GetEvent(var Event: TEvent); virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Idle; virtual;
    procedure InitDesktop; virtual;
    procedure InitMenuBar; virtual;
    procedure InitScreen; virtual;
    procedure InitStatusLine; virtual;
    function InsertWindow(P: PWindow): PWindow;
    procedure OutOfMemory; virtual;
    procedure PutEvent(var Event: TEvent); virtual;
    procedure Run; virtual;
    procedure SetScreenMode(Mode: Word);
    function ValidView(P: PView): PView;
  end;

  PApplication = ^TApplication;
  TApplication = object(TProgram)
    constructor Init;
    destructor Done; virtual;
    procedure Cascade;
    procedure DosShell;
    procedure GetTileRect(var R: TRect); virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Tile;
    procedure WriteShellMsg; virtual;
  end;

function StdStatusKeys(Next: PStatusItem): PStatusItem;
function StdFileMenuItems(Next: PMenuItem): PMenuItem;
function StdEditMenuItems(Next: PMenuItem): PMenuItem;
function StdWindowMenuItems(Next: PMenuItem): PMenuItem;
procedure RegisterApp;

const
  AppPalette: Integer = apColor;

  RBackground: TStreamRec = (ObjType: 30; VmtLink: Ofs(TypeOf(TBackground)^); Load: @TBackground.Load;
    Store: @TBackground.Store);
  RDesktop: TStreamRec = (ObjType: 31; VmtLink: Ofs(TypeOf(TDesktop)^); Load: @TDesktop.Load;
    Store: @TDesktop.Store);

var
  Application: PProgram;
  Desktop: PDesktop;
  StatusLine: PStatusLine;
  MenuBar: PMenuView;

implementation

uses Dos;

var
  Pending: TEvent;

{ ---- TBackground ----------------------------------------------------------------- }

constructor TBackground.Init(var Bounds: TRect; APattern: Char);
begin
  inherited Init(Bounds);
  GrowMode := gfGrowHiX + gfGrowHiY;
  Pattern := APattern;
end;

constructor TBackground.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Pattern, SizeOf(Pattern));
end;

procedure TBackground.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Pattern, SizeOf(Pattern));
end;

procedure TBackground.Draw;
var
  B: TDrawBuffer;
begin
  MoveChar(B, Pattern, GetColor(1), Size.X);
  WriteLine(0, 0, Size.X, Size.Y, B);
end;

function TBackground.GetPalette: PPalette;
const
  P: String[Length(CBackground)] = CBackground;
begin
  GetPalette := @P;
end;

{ ---- TDesktop ---------------------------------------------------------------------- }

constructor TDesktop.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  GrowMode := gfGrowHiX + gfGrowHiY;
  InitBackground;
  if Background <> nil then
    Insert(Background);
end;

constructor TDesktop.Load(var S: TStream);
begin
  inherited Load(S);
  GetSubViewPtr(S, Background);
  S.Read(TileColumnsFirst, SizeOf(TileColumnsFirst));
end;

procedure TDesktop.Store(var S: TStream);
begin
  inherited Store(S);
  PutSubViewPtr(S, Background);
  S.Write(TileColumnsFirst, SizeOf(TileColumnsFirst));
end;

procedure TDesktop.InitBackground;
var
  R: TRect;
begin
  GetExtent(R);
  Background := New(PBackground, Init(R, #176));
end;

function Tileable(P: PView): Boolean;
begin
  Tileable := (P^.Options and ofTileable <> 0) and (P^.State and sfVisible <> 0);
end;

{ Windows overlap down and to the right; the front window is the last
  one, at the largest offset. }
procedure TDesktop.Cascade(var R: TRect);
var
  N, I: Sw_Integer;
  P: PView;
  NR: TRect;
  MinS, MaxS: TPoint;
begin
  N := 0;
  P := First;
  while P <> nil do
  begin
    if Tileable(P) then
      Inc(N);
    P := P^.NextView;
  end;
  if N = 0 then
    Exit;
  MinS := MinWinSize;
  if (R.B.X - R.A.X - (N - 1) < MinS.X) or (R.B.Y - R.A.Y - (N - 1) < MinS.Y) then
  begin
    TileError;
    Exit;
  end;
  Lock;
  I := N - 1;
  P := First;
  while P <> nil do
  begin
    if Tileable(P) then
    begin
      NR.Assign(R.A.X + I, R.A.Y + I, R.B.X, R.B.Y);
      P^.Locate(NR);
      Dec(I);
    end;
    P := P^.NextView;
  end;
  Unlock;
end;

{ A grid of about Sqrt(N) columns; the last column takes what is left, so
  its windows are taller. The front window is at the top left. }
procedure TDesktop.Tile(var R: TRect);
var
  N, Cols, Rows, I, Col, Row, InCol, W, H, T: Sw_Integer;
  P: PView;
  NR: TRect;
begin
  N := 0;
  P := First;
  while P <> nil do
  begin
    if Tileable(P) then
      Inc(N);
    P := P^.NextView;
  end;
  if N = 0 then
    Exit;
  Cols := 1;
  while Cols * Cols < N do
    Inc(Cols);
  Rows := (N + Cols - 1) div Cols;
  if TileColumnsFirst then
  begin
    T := Cols;
    Cols := Rows;
    Rows := T;
  end;
  W := R.B.X - R.A.X;
  H := R.B.Y - R.A.Y;
  if (W div Cols < MinWinSize.X) or (H div Rows < MinWinSize.Y) then
  begin
    TileError;
    Exit;
  end;
  Lock;
  I := 0;
  P := First;
  while P <> nil do
  begin
    if Tileable(P) then
    begin
      Col := I div Rows;
      Row := I mod Rows;
      if Col = Cols - 1 then
        InCol := N - Rows * (Cols - 1)
      else
        InCol := Rows;
      if InCol < 1 then
        InCol := 1;
      NR.Assign(R.A.X + W * Col div Cols, R.A.Y + H * Row div InCol,
        R.A.X + W * (Col + 1) div Cols, R.A.Y + H * (Row + 1) div InCol);
      P^.Locate(NR);
      Inc(I);
    end;
    P := P^.NextView;
  end;
  Unlock;
end;

procedure TDesktop.TileError;
begin
end;

procedure TDesktop.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evCommand then
  begin
    case Event.Command of
      cmNext:
        if Valid(cmReleasedFocus) then
          SelectNext(False);
      cmPrev:
        if Valid(cmReleasedFocus) and (Current <> nil) then
          Current^.PutInFrontOf(Background);
    else
      Exit;
    end;
    ClearEvent(Event);
  end;
end;

{ ---- TProgram ------------------------------------------------------------------------ }

constructor TProgram.Init;
var
  R: TRect;
begin
  Application := @Self;
  InitScreen;
  R.Assign(0, 0, ScreenWidth, ScreenHeight);
  inherited Init(R);
  State := sfVisible + sfSelected + sfFocused + sfModal + sfExposed;
  Options := 0;
  Buffer := ScreenBuffer;
  InitDesktop;
  InitStatusLine;
  InitMenuBar;
  if Desktop <> nil then
    Insert(Desktop);
  if StatusLine <> nil then
    Insert(StatusLine);
  if MenuBar <> nil then
    Insert(MenuBar);
end;

destructor TProgram.Done;
begin
  { Nothing needs drawing any more. }
  State := State and not sfExposed;
  if Desktop <> nil then
    Dispose(Desktop, Done);
  if StatusLine <> nil then
    Dispose(StatusLine, Done);
  if MenuBar <> nil then
    Dispose(MenuBar, Done);
  Desktop := nil;
  StatusLine := nil;
  MenuBar := nil;
  Application := nil;
  inherited Done;
end;

function TProgram.CanMoveFocus: Boolean;
begin
  CanMoveFocus := (Desktop = nil) or Desktop^.Valid(cmReleasedFocus);
end;

{ Runs a modal dialog on the desktop; Data (when not nil) fills the
  controls before and receives their values after, unless cancelled. }
function TProgram.ExecuteDialog(P: PDialog; Data: Pointer): Word;
var
  C: Word;
begin
  ExecuteDialog := cmCancel;
  if ValidView(P) = nil then
    Exit;
  if Data <> nil then
    P^.SetData(Data^);
  C := Desktop^.ExecView(P);
  if (C <> cmCancel) and (Data <> nil) then
    P^.GetData(Data^);
  Dispose(P, Done);
  ExecuteDialog := C;
end;

procedure TProgram.GetEvent(var Event: TEvent);
var
  P: PView;
begin
  if Pending.What <> evNothing then
  begin
    Event := Pending;
    Pending.What := evNothing;
  end
  else
  begin
    GetMouseEvent(Event);
    if Event.What = evNothing then
      GetKeyEvent(Event);
    if Event.What = evNothing then
    begin
      Idle;
      WaitForEvent(50);
      GetMouseEvent(Event);
      if Event.What = evNothing then
        GetKeyEvent(Event);
    end;
  end;
  if StatusLine <> nil then
    if Event.What and evKeyDown <> 0 then
      StatusLine^.HandleEvent(Event)
    else if Event.What and evMouseDown <> 0 then
    begin
      { Only when the status line is the top view under the mouse. }
      P := First;
      while (P <> nil) and not ((P^.State and sfVisible <> 0) and P^.MouseInView(Event.Where)) do
        P := P^.NextView;
      if P = PView(StatusLine) then
        StatusLine^.HandleEvent(Event);
    end;
end;

function TProgram.GetPalette: PPalette;
const
  P: array[apColor..apMonochrome] of String[Length(CAppColor)] = (CAppColor, CAppBlackWhite, CAppMonochrome);
begin
  GetPalette := @P[AppPalette];
end;

procedure TProgram.HandleEvent(var Event: TEvent);
var
  C: Char;
begin
  if Event.What = evKeyDown then
  begin
    C := GetAltChar(Event.KeyCode);
    if (C >= '1') and (C <= '9') then
      if Message(Desktop, evBroadcast, cmSelectWindowNum, Pointer(PtrUInt(Ord(C) - Ord('0')))) <> nil then
        ClearEvent(Event);
  end;
  inherited HandleEvent(Event);
  if Event.What = evCommand then
    if Event.Command = cmQuit then
    begin
      EndModal(cmQuit);
      ClearEvent(Event);
    end;
end;

procedure TProgram.Idle;
begin
  if StatusLine <> nil then
    StatusLine^.Update;
  if CommandSetChanged then
  begin
    Message(@Self, evBroadcast, cmCommandSetChanged, nil);
    CommandSetChanged := False;
  end;
end;

procedure TProgram.InitDesktop;
var
  R: TRect;
begin
  GetExtent(R);
  Inc(R.A.Y);
  Dec(R.B.Y);
  Desktop := New(PDesktop, Init(R));
end;

procedure TProgram.InitMenuBar;
var
  R: TRect;
begin
  GetExtent(R);
  R.B.Y := R.A.Y + 1;
  MenuBar := New(PMenuBar, Init(R, nil));
end;

procedure TProgram.InitScreen;
begin
  if ScreenMode and $FF <> smMono then
  begin
    if ScreenMode and smFont8x8 <> 0 then
      ShadowSize.X := 1
    else
      ShadowSize.X := 2;
    ShadowSize.Y := 1;
    ShowMarkers := False;
    if ScreenMode and $FF = smBW80 then
      AppPalette := apBlackWhite
    else
      AppPalette := apColor;
  end
  else
  begin
    ShadowSize.X := 0;
    ShadowSize.Y := 0;
    ShowMarkers := True;
    AppPalette := apMonochrome;
  end;
end;

procedure TProgram.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  StatusLine := New(PStatusLine, Init(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~Alt-X~ Exit', kbAltX, cmQuit,
      StdStatusKeys(nil)), nil)));
end;

function TProgram.InsertWindow(P: PWindow): PWindow;
begin
  InsertWindow := nil;
  if ValidView(P) <> nil then
    if CanMoveFocus then
    begin
      Desktop^.Insert(P);
      InsertWindow := P;
    end
    else
      Dispose(P, Done);
end;

procedure TProgram.OutOfMemory;
begin
end;

procedure TProgram.PutEvent(var Event: TEvent);
begin
  Pending := Event;
end;

procedure TProgram.Run;
begin
  Execute;
end;

procedure TProgram.SetScreenMode(Mode: Word);
var
  R: TRect;
begin
  SetVideoMode(Mode);
  InitScreen;
  Buffer := ScreenBuffer;
  R.Assign(0, 0, ScreenWidth, ScreenHeight);
  ChangeBounds(R);
  Redraw;
end;

function TProgram.ValidView(P: PView): PView;
begin
  ValidView := nil;
  if P = nil then
    Exit;
  if LowMemory then
  begin
    Dispose(P, Done);
    OutOfMemory;
    Exit;
  end;
  if not P^.Valid(cmValid) then
  begin
    Dispose(P, Done);
    Exit;
  end;
  ValidView := P;
end;

{ ---- TApplication ------------------------------------------------------------------- }

constructor TApplication.Init;
begin
  InitMemory;
  InitVideo;
  InitEvents;
  InitSysError;
  InitHistory;
  inherited Init;
end;

destructor TApplication.Done;
begin
  inherited Done;
  DoneHistory;
  DoneSysError;
  DoneEvents;
  DoneVideo;
  DoneMemory;
end;

procedure TApplication.Cascade;
var
  R: TRect;
begin
  GetTileRect(R);
  if Desktop <> nil then
    Desktop^.Cascade(R);
end;

procedure TApplication.Tile;
var
  R: TRect;
begin
  GetTileRect(R);
  if Desktop <> nil then
    Desktop^.Tile(R);
end;

{ Runs the user's shell ($SHELL, else /bin/sh) on the normal screen. }
procedure TApplication.DosShell;
var
  Shell: String;
begin
  DoneSysError;
  DoneEvents;
  DoneVideo;
  DoneDosMem;
  WriteShellMsg;
  Shell := GetEnv('SHELL');
  if Shell = '' then
    Shell := '/bin/sh';
  SwapVectors;
  Exec(Shell, '');
  SwapVectors;
  InitDosMem;
  InitVideo;
  InitEvents;
  InitSysError;
  Buffer := ScreenBuffer;
  Redraw;
end;

procedure TApplication.GetTileRect(var R: TRect);
begin
  if Desktop <> nil then
    Desktop^.GetExtent(R)
  else
    GetExtent(R);
end;

procedure TApplication.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evCommand then
  begin
    case Event.Command of
      cmTile: Tile;
      cmCascade: Cascade;
      cmDosShell: DosShell;
    else
      Exit;
    end;
    ClearEvent(Event);
  end;
end;

procedure TApplication.WriteShellMsg;
begin
  WriteLn('Ketik EXIT untuk kembali...');
end;

{ ---- standard menus and status keys -------------------------------------------------- }

function StdStatusKeys(Next: PStatusItem): PStatusItem;
begin
  StdStatusKeys :=
    NewStatusKey('', kbAltX, cmQuit,
    NewStatusKey('', kbF10, cmMenu,
    NewStatusKey('', kbAltF3, cmClose,
    NewStatusKey('', kbF5, cmZoom,
    NewStatusKey('', kbCtrlF5, cmResize,
    NewStatusKey('', kbF6, cmNext,
    NewStatusKey('', kbShiftF6, cmPrev,
    Next)))))));
end;

function StdFileMenuItems(Next: PMenuItem): PMenuItem;
begin
  StdFileMenuItems :=
    NewItem('~N~ew', '', kbNoKey, cmNew, hcNew,
    NewItem('~O~pen...', 'F3', kbF3, cmOpen, hcOpen,
    NewItem('~S~ave', 'F2', kbF2, cmSave, hcSave,
    NewItem('S~a~ve as...', '', kbNoKey, cmSaveAs, hcSaveAs,
    NewItem('Save a~l~l', '', kbNoKey, cmSaveAll, hcSaveAll,
    NewLine(
    NewItem('~C~hange dir...', '', kbNoKey, cmChangeDir, hcChangeDir,
    NewItem('OS shel~l~', '', kbNoKey, cmDosShell, hcDosShell,
    NewItem('E~x~it', 'Alt+X', kbAltX, cmQuit, hcExit,
    Next)))))))));
end;

function StdEditMenuItems(Next: PMenuItem): PMenuItem;
begin
  StdEditMenuItems :=
    NewItem('~U~ndo', '', kbAltBack, cmUndo, hcUndo,
    NewLine(
    NewItem('Cu~t~', 'Shift+Del', kbShiftDel, cmCut, hcCut,
    NewItem('~C~opy', 'Ctrl+Ins', kbCtrlIns, cmCopy, hcCopy,
    NewItem('~P~aste', 'Shift+Ins', kbShiftIns, cmPaste, hcPaste,
    NewItem('C~l~ear', 'Ctrl+Del', kbCtrlDel, cmClear, hcClear,
    Next))))));
end;

function StdWindowMenuItems(Next: PMenuItem): PMenuItem;
begin
  StdWindowMenuItems :=
    NewItem('~T~ile', '', kbNoKey, cmTile, hcTile,
    NewItem('C~a~scade', '', kbNoKey, cmCascade, hcCascade,
    NewItem('Cl~o~se all', '', kbNoKey, cmCloseAll, hcCloseAll,
    NewLine(
    NewItem('~S~ize/Move', 'Ctrl+F5', kbCtrlF5, cmResize, hcResize,
    NewItem('~Z~oom', 'F5', kbF5, cmZoom, hcZoom,
    NewItem('~N~ext', 'F6', kbF6, cmNext, hcNext,
    NewItem('~P~revious', 'Shift+F6', kbShiftF6, cmPrev, hcPrev,
    NewItem('~C~lose', 'Alt+F3', kbAltF3, cmClose, hcClose,
    Next)))))))));
end;

procedure RegisterApp;
begin
  RegisterType(RBackground);
  RegisterType(RDesktop);
end;

end.
