{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Menus dari Odin Vision: menu bar, menu box (drop-down) dan status
  line. Implementasi clean-room berdasarkan dokumentasi API Turbo Vision
  TP7.

  TMenuView.Execute menjalankan menu secara modal: menu bar memilih item,
  membuka submenu sebagai TMenuBox lewat Owner^.ExecView, dan
  mengembalikan perintah yang dipilih (0 bila batal). Tombol yang bukan
  untuk submenu (Left/Right, Alt+huruf, klik di luar) dikembalikan ke
  menu induk dengan PutEvent. }
unit Menus;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views;

const
  CMenuView = #2#3#4#5#6#7;
  CStatusLine = #2#3#4#5#6#7;

type
  TMenuStr = String[31];

  PMenu = ^TMenu;

  PMenuItem = ^TMenuItem;
  TMenuItem = record
    Next: PMenuItem;
    Name: PString;
    Command: Word;
    Disabled: Boolean;
    KeyCode: Word;
    HelpCtx: Word;
    case Integer of
      0: (Param: PString);
      1: (SubMenu: PMenu);
  end;

  TMenu = record
    Items: PMenuItem;
    Default: PMenuItem;
  end;

  PMenuView = ^TMenuView;
  TMenuView = object(TView)
    ParentMenu: PMenuView;
    Menu: PMenu;
    Current: PMenuItem;
    constructor Init(var Bounds: TRect);
    constructor Load(var S: TStream);
    function Execute: Word; virtual;
    function FindItem(Ch: Char): PMenuItem;
    procedure GetItemRect(Item: PMenuItem; var R: TRect); virtual;
    function GetHelpCtx: Word; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function HotKey(KeyCode: Word): PMenuItem;
    function NewSubView(var Bounds: TRect; AMenu: PMenu; AParentMenu: PMenuView): PMenuView; virtual;
    procedure Store(var S: TStream);
    { Odin: helpers of Execute and Draw. }
    function TopMenu: PMenuView;
    function ItemAt(Where: TPoint): PMenuItem;
    function UpdateMenu(AMenu: PMenu): Boolean;
    procedure DrawItems(Bar: Boolean);
  end;

  PMenuBar = ^TMenuBar;
  TMenuBar = object(TMenuView)
    constructor Init(var Bounds: TRect; AMenu: PMenu);
    destructor Done; virtual;
    procedure Draw; virtual;
    procedure GetItemRect(Item: PMenuItem; var R: TRect); virtual;
  end;

  PMenuBox = ^TMenuBox;
  TMenuBox = object(TMenuView)
    constructor Init(var Bounds: TRect; AMenu: PMenu; AParentMenu: PMenuView);
    procedure Draw; virtual;
    procedure GetItemRect(Item: PMenuItem; var R: TRect); virtual;
  end;

  PMenuPopup = ^TMenuPopup;
  TMenuPopup = object(TMenuBox)
    constructor Init(var Bounds: TRect; AMenu: PMenu);
    destructor Done; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
  end;

  PStatusItem = ^TStatusItem;
  TStatusItem = record
    Next: PStatusItem;
    Text: PString;
    KeyCode: Word;
    Command: Word;
  end;

  PStatusDef = ^TStatusDef;
  TStatusDef = record
    Next: PStatusDef;
    Min, Max: Word;
    Items: PStatusItem;
  end;

  PStatusLine = ^TStatusLine;
  TStatusLine = object(TView)
    Items: PStatusItem;
    Defs: PStatusDef;
    constructor Init(var Bounds: TRect; ADefs: PStatusDef);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function Hint(AHelpCtx: Word): String; virtual;
    procedure Store(var S: TStream);
    procedure Update; virtual;
    { Odin: the item under a point (global coordinates), or nil. }
    function ItemAt(Where: TPoint): PStatusItem;
    procedure DrawSelect(Selected: PStatusItem);
    procedure FindItems;
  end;

function NewItem(Name, Param: TMenuStr; KeyCode: Word; Command: Word; AHelpCtx: Word; Next: PMenuItem): PMenuItem;
function NewLine(Next: PMenuItem): PMenuItem;
function NewSubMenu(Name: TMenuStr; AHelpCtx: Word; SubMenu: PMenu; Next: PMenuItem): PMenuItem;
function NewMenu(Items: PMenuItem): PMenu;
procedure DisposeMenu(Menu: PMenu);
function NewStatusDef(AMin, AMax: Word; AItems: PStatusItem; ANext: PStatusDef): PStatusDef;
function NewStatusKey(const AText: String; AKeyCode: Word; ACommand: Word; ANext: PStatusItem): PStatusItem;
procedure RegisterMenus;

const
  RMenuBar: TStreamRec = (ObjType: 40; VmtLink: Ofs(TypeOf(TMenuBar)^); Load: @TMenuBar.Load;
    Store: @TMenuBar.Store);
  RMenuBox: TStreamRec = (ObjType: 41; VmtLink: Ofs(TypeOf(TMenuBox)^); Load: @TMenuBox.Load;
    Store: @TMenuBox.Store);
  RStatusLine: TStreamRec = (ObjType: 42; VmtLink: Ofs(TypeOf(TStatusLine)^); Load: @TStatusLine.Load;
    Store: @TStatusLine.Store);
  RMenuPopup: TStreamRec = (ObjType: 43; VmtLink: Ofs(TypeOf(TMenuPopup)^); Load: @TMenuPopup.Load;
    Store: @TMenuPopup.Store);

implementation

var
  { Set by a submenu closed with Esc (or Left in a nested box): the parent
    stays open but stops opening submenus by itself. }
  MenuEscaped: Boolean;

function Enabled(Command: Word): Boolean;
var
  T: TView;
begin
  Enabled := T.CommandEnabled(Command);
end;

function HotChar(const S: String): Char;
var
  I: Integer;
begin
  HotChar := #0;
  I := Pos('~', S);
  if (I > 0) and (I < Length(S)) then
    HotChar := UpCase(S[I + 1]);
end;

{ ---- menu records ------------------------------------------------------------------ }

function NewItem(Name, Param: TMenuStr; KeyCode: Word; Command: Word; AHelpCtx: Word; Next: PMenuItem): PMenuItem;
var
  P: PMenuItem;
begin
  if (Name <> '') and (Command <> 0) then
  begin
    New(P);
    P^.Next := Next;
    P^.Name := NewStr(Name);
    P^.Command := Command;
    P^.Disabled := not Enabled(Command);
    P^.KeyCode := KeyCode;
    P^.HelpCtx := AHelpCtx;
    P^.Param := NewStr(Param);
    NewItem := P;
  end
  else
    NewItem := Next;
end;

function NewLine(Next: PMenuItem): PMenuItem;
var
  P: PMenuItem;
begin
  New(P);
  FillChar(P^, SizeOf(TMenuItem), 0);
  P^.Next := Next;
  NewLine := P;
end;

function NewSubMenu(Name: TMenuStr; AHelpCtx: Word; SubMenu: PMenu; Next: PMenuItem): PMenuItem;
var
  P: PMenuItem;
begin
  if (Name <> '') and (SubMenu <> nil) then
  begin
    New(P);
    P^.Next := Next;
    P^.Name := NewStr(Name);
    P^.Command := 0;
    P^.Disabled := False;
    P^.KeyCode := 0;
    P^.HelpCtx := AHelpCtx;
    P^.SubMenu := SubMenu;
    NewSubMenu := P;
  end
  else
    NewSubMenu := Next;
end;

function NewMenu(Items: PMenuItem): PMenu;
var
  P: PMenu;
begin
  New(P);
  P^.Items := Items;
  P^.Default := Items;
  NewMenu := P;
end;

procedure DisposeMenu(Menu: PMenu);
var
  P, Q: PMenuItem;
begin
  if Menu = nil then
    Exit;
  P := Menu^.Items;
  while P <> nil do
  begin
    Q := P^.Next;
    if P^.Name <> nil then
    begin
      DisposeStr(P^.Name);
      if P^.Command = 0 then
        DisposeMenu(P^.SubMenu)
      else
        DisposeStr(P^.Param);
    end;
    Dispose(P);
    P := Q;
  end;
  Dispose(Menu);
end;

function NewStatusDef(AMin, AMax: Word; AItems: PStatusItem; ANext: PStatusDef): PStatusDef;
var
  P: PStatusDef;
begin
  New(P);
  P^.Next := ANext;
  P^.Min := AMin;
  P^.Max := AMax;
  P^.Items := AItems;
  NewStatusDef := P;
end;

function NewStatusKey(const AText: String; AKeyCode: Word; ACommand: Word; ANext: PStatusItem): PStatusItem;
var
  P: PStatusItem;
begin
  New(P);
  P^.Next := ANext;
  P^.Text := NewStr(AText);
  P^.KeyCode := AKeyCode;
  P^.Command := ACommand;
  NewStatusKey := P;
end;

{ ---- TMenuView ---------------------------------------------------------------------- }

constructor TMenuView.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  EventMask := EventMask or evBroadcast;
end;

function LoadMenu(var S: TStream): PMenu;
var
  Tok: Byte;
  Menu: PMenu;
  Last: ^PMenuItem;
  Item: PMenuItem;
begin
  New(Menu);
  Menu^.Items := nil;
  Last := @Menu^.Items;
  Tok := 0;
  S.Read(Tok, 1);
  while Tok <> 0 do
  begin
    New(Item);
    FillChar(Item^, SizeOf(TMenuItem), 0);
    Last^ := Item;
    Last := @Item^.Next;
    Item^.Name := S.ReadStr;
    S.Read(Item^.Command, 2);
    S.Read(Item^.Disabled, 1);
    S.Read(Item^.KeyCode, 2);
    S.Read(Item^.HelpCtx, 2);
    if Item^.Name <> nil then
      if Item^.Command = 0 then
        Item^.SubMenu := LoadMenu(S)
      else
        Item^.Param := S.ReadStr;
    S.Read(Tok, 1);
  end;
  Menu^.Default := Menu^.Items;
  LoadMenu := Menu;
end;

procedure StoreMenu(var S: TStream; Menu: PMenu);
var
  Tok: Byte;
  Item: PMenuItem;
begin
  Tok := $FF;
  Item := Menu^.Items;
  while Item <> nil do
  begin
    S.Write(Tok, 1);
    S.WriteStr(Item^.Name);
    S.Write(Item^.Command, 2);
    S.Write(Item^.Disabled, 1);
    S.Write(Item^.KeyCode, 2);
    S.Write(Item^.HelpCtx, 2);
    if Item^.Name <> nil then
      if Item^.Command = 0 then
        StoreMenu(S, Item^.SubMenu)
      else
        S.WriteStr(Item^.Param);
    Item := Item^.Next;
  end;
  Tok := 0;
  S.Write(Tok, 1);
end;

constructor TMenuView.Load(var S: TStream);
begin
  inherited Load(S);
  Menu := LoadMenu(S);
end;

procedure TMenuView.Store(var S: TStream);
begin
  inherited Store(S);
  StoreMenu(S, Menu);
end;

function TMenuView.TopMenu: PMenuView;
var
  P: PMenuView;
begin
  P := @Self;
  while P^.ParentMenu <> nil do
    P := P^.ParentMenu;
  TopMenu := P;
end;

{ The named item under a point given in global coordinates. }
function TMenuView.ItemAt(Where: TPoint): PMenuItem;
var
  P: PMenuItem;
  R: TRect;
  Mouse: TPoint;
begin
  ItemAt := nil;
  if Menu = nil then
    Exit;
  MakeLocal(Where, Mouse);
  P := Menu^.Items;
  while P <> nil do
  begin
    if P^.Name <> nil then
    begin
      GetItemRect(P, R);
      if R.Contains(Mouse) then
      begin
        ItemAt := P;
        Exit;
      end;
    end;
    P := P^.Next;
  end;
end;

function TMenuView.Execute: Word;
type
  TAction = (DoNothing, DoSelect, DoReturn);
var
  Action: TAction;
  AutoSelect, MouseActive: Boolean;
  Result: Word;
  E: TEvent;
  ItemShown, P: PMenuItem;
  Target, Sub: PMenuView;
  R: TRect;
  Ch: Char;
  Key: Word;

  function InParentItem: Boolean;
  var
    PR: TRect;
    Mouse: TPoint;
  begin
    InParentItem := False;
    if (ParentMenu <> nil) and (ParentMenu^.Current <> nil) then
    begin
      ParentMenu^.GetItemRect(ParentMenu^.Current, PR);
      ParentMenu^.MakeLocal(E.Where, Mouse);
      InParentItem := PR.Contains(Mouse);
    end;
  end;

  function InParentMenus: Boolean;
  var
    M: PMenuView;
  begin
    InParentMenus := False;
    M := ParentMenu;
    while M <> nil do
    begin
      if M^.MouseInView(E.Where) then
      begin
        InParentMenus := True;
        Exit;
      end;
      M := M^.ParentMenu;
    end;
  end;

  procedure TrackMouse;
  begin
    if MouseInView(E.Where) then
    begin
      MouseActive := True;
      Current := ItemAt(E.Where);
    end;
  end;

  procedure TrackKey(Forwards: Boolean);
  var
    Start, Q, Prev: PMenuItem;
  begin
    if Menu^.Items = nil then
      Exit;
    if Current = nil then
    begin
      Current := Menu^.Items;
      if Current^.Name <> nil then
        Exit;
    end;
    Start := Current;
    repeat
      if Forwards then
      begin
        Current := Current^.Next;
        if Current = nil then
          Current := Menu^.Items;
      end
      else
      begin
        { The item before Current, wrapping to the last one. }
        Prev := nil;
        Q := Menu^.Items;
        while (Q <> nil) and (Q <> Current) do
        begin
          Prev := Q;
          Q := Q^.Next;
        end;
        if Prev = nil then
        begin
          Prev := Menu^.Items;
          while Prev^.Next <> nil do
            Prev := Prev^.Next;
        end;
        Current := Prev;
      end;
    until (Current^.Name <> nil) or (Current = Start);
  end;

begin
  Result := 0;
  AutoSelect := False;
  MouseActive := False;
  ItemShown := nil;
  if Menu <> nil then
    Current := Menu^.Default
  else
    Current := nil;
  if (Current <> nil) and (Current^.Name = nil) then
    TrackKey(True);
  repeat
    Action := DoNothing;
    GetEvent(E);
    case E.What of
      evMouseDown:
        if MouseInView(E.Where) or InParentItem then
        begin
          TrackMouse;
          if Size.Y = 1 then
            AutoSelect := True;
        end
        else
          Action := DoReturn;
      evMouseUp:
        begin
          TrackMouse;
          if InParentItem then
          begin
            if Size.Y <> 1 then
            begin
              Current := Menu^.Default;
              if (Current <> nil) and (Current^.Name = nil) then
                TrackKey(True);
            end;
          end
          else if (Current <> nil) and MouseInView(E.Where) then
            Action := DoSelect
          else if (Size.Y <> 1) or not MouseInView(E.Where) then
            Action := DoReturn;
        end;
      evMouseMove:
        if E.Buttons <> 0 then
        begin
          TrackMouse;
          if not (MouseInView(E.Where) or InParentItem) and InParentMenus then
            Action := DoReturn;
        end;
      evKeyDown:
        begin
          Key := CtrlToArrow(E.KeyCode);
          if (Key = kbUp) or (Key = kbDown) then
          begin
            if Size.Y <> 1 then
              TrackKey(Key = kbDown)
            else if Key = kbDown then
              AutoSelect := True;
          end
          else if (Key = kbLeft) or (Key = kbRight) then
          begin
            if ParentMenu = nil then
              TrackKey(Key = kbRight)
            else if ParentMenu^.Size.Y = 1 then
              Action := DoReturn
            else if Key = kbLeft then
            begin
              Action := DoReturn;
              MenuEscaped := True;
              ClearEvent(E);
            end
            else if (Current <> nil) and (Current^.Command = 0) then
              Action := DoSelect;
          end
          else if (Key = kbHome) or (Key = kbEnd) then
          begin
            if Size.Y <> 1 then
            begin
              Current := Menu^.Items;
              if Key = kbEnd then
                TrackKey(False)
              else if Current^.Name = nil then
                TrackKey(True);
            end;
          end
          else if Key = kbEnter then
          begin
            if Size.Y = 1 then
              AutoSelect := True;
            Action := DoSelect;
          end
          else if Key = kbEsc then
          begin
            Action := DoReturn;
            if ParentMenu <> nil then
              MenuEscaped := True;
            ClearEvent(E);
          end
          else
          begin
            Target := @Self;
            Ch := GetAltChar(E.KeyCode);
            if Ch = #0 then
              Ch := E.CharCode
            else
              Target := TopMenu;
            P := Target^.FindItem(Ch);
            if P = nil then
            begin
              P := TopMenu^.HotKey(E.KeyCode);
              if (P <> nil) and CommandEnabled(P^.Command) then
              begin
                Result := P^.Command;
                Action := DoReturn;
              end;
            end
            else if Target = @Self then
            begin
              if Size.Y = 1 then
                AutoSelect := True;
              Action := DoSelect;
              Current := P;
            end
            else if (ParentMenu <> Target) or (ParentMenu^.Current <> P) then
              Action := DoReturn;
          end;
        end;
      evCommand:
        if E.Command = cmMenu then
        begin
          AutoSelect := False;
          if ParentMenu <> nil then
            Action := DoReturn;
        end
        else
          Action := DoReturn;
    end;
    if ItemShown <> Current then
    begin
      ItemShown := Current;
      DrawView;
    end;
    if (Action = DoSelect) or ((Action = DoNothing) and AutoSelect) then
      if (Current <> nil) and (Current^.Name <> nil) then
        if Current^.Command = 0 then
        begin
          if E.What and (evMouseDown + evMouseMove) <> 0 then
            PutEvent(E);
          GetItemRect(Current, R);
          R.A.X := R.A.X + Origin.X;
          R.A.Y := R.B.Y + Origin.Y;
          R.B := Owner^.Size;
          if Size.Y = 1 then
            Dec(R.A.X);
          Sub := TopMenu^.NewSubView(R, Current^.SubMenu, @Self);
          MenuEscaped := False;
          Result := Owner^.ExecView(Sub);
          Dispose(Sub, Done);
          if MenuEscaped then
          begin
            AutoSelect := False;
            MenuEscaped := False;
          end;
        end
        else if (Action = DoSelect) and not Current^.Disabled then
          Result := Current^.Command;
    if (Result <> 0) and CommandEnabled(Result) then
    begin
      Action := DoReturn;
      ClearEvent(E);
    end
    else
      Result := 0;
  until Action = DoReturn;
  if E.What <> evNothing then
    if (ParentMenu <> nil) or (E.What = evCommand) then
      PutEvent(E);
  if Current <> nil then
  begin
    Menu^.Default := Current;
    Current := nil;
    DrawView;
  end;
  Execute := Result;
end;

function TMenuView.FindItem(Ch: Char): PMenuItem;
var
  P: PMenuItem;
begin
  FindItem := nil;
  if (Ch = #0) or (Menu = nil) then
    Exit;
  Ch := UpCase(Ch);
  P := Menu^.Items;
  while P <> nil do
  begin
    if (P^.Name <> nil) and not P^.Disabled and (HotChar(P^.Name^) = Ch) then
    begin
      FindItem := P;
      Exit;
    end;
    P := P^.Next;
  end;
end;

procedure TMenuView.GetItemRect(Item: PMenuItem; var R: TRect);
begin
  R.Assign(0, 0, 0, 0);
end;

function TMenuView.GetHelpCtx: Word;
var
  C: PMenuView;
begin
  C := @Self;
  while (C <> nil) and ((C^.Current = nil) or (C^.Current^.HelpCtx = hcNoContext) or (C^.Current^.Name = nil)) do
    C := C^.ParentMenu;
  if C <> nil then
    GetHelpCtx := C^.Current^.HelpCtx
  else
    GetHelpCtx := hcNoContext;
end;

function TMenuView.GetPalette: PPalette;
const
  P: String[Length(CMenuView)] = CMenuView;
begin
  GetPalette := @P;
end;

function TMenuView.UpdateMenu(AMenu: PMenu): Boolean;
var
  P: PMenuItem;
  Changed, D: Boolean;
begin
  Changed := False;
  if AMenu <> nil then
  begin
    P := AMenu^.Items;
    while P <> nil do
    begin
      if P^.Name <> nil then
        if P^.Command = 0 then
        begin
          if UpdateMenu(P^.SubMenu) then
            Changed := True;
        end
        else
        begin
          D := not CommandEnabled(P^.Command);
          if D <> P^.Disabled then
          begin
            P^.Disabled := D;
            Changed := True;
          end;
        end;
      P := P^.Next;
    end;
  end;
  UpdateMenu := Changed;
end;

procedure TMenuView.HandleEvent(var Event: TEvent);
var
  Command: Word;
  P: PMenuItem;

  procedure DoSelect;
  begin
    PutEvent(Event);
    Command := Owner^.ExecView(@Self);
    if (Command <> 0) and CommandEnabled(Command) then
    begin
      Event.What := evCommand;
      Event.Command := Command;
      Event.InfoPtr := nil;
      PutEvent(Event);
    end;
    ClearEvent(Event);
  end;

begin
  if Menu = nil then
    Exit;
  case Event.What of
    evMouseDown:
      DoSelect;
    evKeyDown:
      if FindItem(GetAltChar(Event.KeyCode)) <> nil then
        DoSelect
      else
      begin
        P := HotKey(Event.KeyCode);
        if (P <> nil) and CommandEnabled(P^.Command) then
        begin
          Event.What := evCommand;
          Event.Command := P^.Command;
          Event.InfoPtr := nil;
          PutEvent(Event);
          ClearEvent(Event);
        end;
      end;
    evCommand:
      if Event.Command = cmMenu then
        DoSelect;
    evBroadcast:
      if Event.Command = cmCommandSetChanged then
        if UpdateMenu(Menu) then
          DrawView;
  end;
end;

function TMenuView.HotKey(KeyCode: Word): PMenuItem;

  function FindIn(P: PMenuItem): PMenuItem;
  var
    T: PMenuItem;
  begin
    FindIn := nil;
    while P <> nil do
    begin
      if P^.Name <> nil then
        if P^.Command = 0 then
        begin
          if P^.SubMenu <> nil then
          begin
            T := FindIn(P^.SubMenu^.Items);
            if T <> nil then
            begin
              FindIn := T;
              Exit;
            end;
          end;
        end
        else if not P^.Disabled and (P^.KeyCode <> kbNoKey) and (P^.KeyCode = KeyCode) then
        begin
          FindIn := P;
          Exit;
        end;
      P := P^.Next;
    end;
  end;

begin
  HotKey := nil;
  if Menu <> nil then
    HotKey := FindIn(Menu^.Items);
end;

function TMenuView.NewSubView(var Bounds: TRect; AMenu: PMenu; AParentMenu: PMenuView): PMenuView;
begin
  NewSubView := New(PMenuBox, Init(Bounds, AMenu, AParentMenu));
end;

{ Draws the items of a bar (one line) or a box (framed column). }
procedure TMenuView.DrawItems(Bar: Boolean);
var
  B: TDrawBuffer;
  P: PMenuItem;
  CNormal, CSelect, CNormDisabled, CSelDisabled, Color: Word;
  X, Y, L: Sw_Integer;

  procedure Line(Left, Fill, Right: Char);
  begin
    MoveChar(B, Fill, Byte(CNormal), Size.X);
    MoveChar(B[0], Left, Byte(CNormal), 1);
    MoveChar(B[Size.X - 1], Right, Byte(CNormal), 1);
  end;

begin
  CNormal := GetColor($0301);
  CSelect := GetColor($0604);
  CNormDisabled := GetColor($0202);
  CSelDisabled := GetColor($0505);
  if Menu <> nil then
    P := Menu^.Items
  else
    P := nil;
  if Bar then
  begin
    MoveChar(B, ' ', Byte(CNormal), Size.X);
    X := 1;
    while P <> nil do
    begin
      if P^.Name <> nil then
      begin
        L := CStrLen(P^.Name^);
        if X + L + 2 <= Size.X then
        begin
          if P^.Disabled then
            if P = Current then Color := CSelDisabled else Color := CNormDisabled
          else if P = Current then
            Color := CSelect
          else
            Color := CNormal;
          MoveChar(B[X], ' ', Byte(Color), L + 2);
          MoveCStr(B[X + 1], P^.Name^, Color);
        end;
        Inc(X, L + 2);
      end;
      P := P^.Next;
    end;
    WriteBuf(0, 0, Size.X, 1, B);
    Exit;
  end;
  Line(#218, #196, #191);
  WriteBuf(0, 0, Size.X, 1, B);
  Y := 1;
  while (P <> nil) and (Y < Size.Y - 1) do
  begin
    if P^.Name = nil then
      Line(#195, #196, #180)
    else
    begin
      if P^.Disabled then
        if P = Current then Color := CSelDisabled else Color := CNormDisabled
      else if P = Current then
        Color := CSelect
      else
        Color := CNormal;
      Line(#179, ' ', #179);
      MoveChar(B[1], ' ', Byte(Color), Size.X - 2);
      MoveCStr(B[3], P^.Name^, Color);
      if P^.Command = 0 then
        MoveChar(B[Size.X - 4], #16, Byte(Color), 1)
      else if P^.Param <> nil then
        MoveStr(B[Size.X - 3 - Length(P^.Param^)], P^.Param^, Byte(Color));
    end;
    WriteBuf(0, Y, Size.X, 1, B);
    Inc(Y);
    P := P^.Next;
  end;
  Line(#192, #196, #217);
  WriteBuf(0, Size.Y - 1, Size.X, 1, B);
end;

{ ---- TMenuBar ------------------------------------------------------------------------ }

constructor TMenuBar.Init(var Bounds: TRect; AMenu: PMenu);
begin
  inherited Init(Bounds);
  GrowMode := gfGrowHiX;
  Menu := AMenu;
  Options := Options or ofPreProcess;
end;

destructor TMenuBar.Done;
begin
  inherited Done;
  DisposeMenu(Menu);
end;

procedure TMenuBar.Draw;
begin
  DrawItems(True);
end;

procedure TMenuBar.GetItemRect(Item: PMenuItem; var R: TRect);
var
  P: PMenuItem;
  X, L: Sw_Integer;
begin
  R.Assign(0, 0, 0, 0);
  if Menu = nil then
    Exit;
  X := 1;
  P := Menu^.Items;
  while P <> nil do
  begin
    if P^.Name <> nil then
    begin
      L := CStrLen(P^.Name^) + 2;
      if P = Item then
      begin
        R.Assign(X, 0, X + L, 1);
        Exit;
      end;
      Inc(X, L);
    end;
    P := P^.Next;
  end;
end;

{ ---- TMenuBox ------------------------------------------------------------------------- }

constructor TMenuBox.Init(var Bounds: TRect; AMenu: PMenu; AParentMenu: PMenuView);
var
  W, H, L: Sw_Integer;
  P: PMenuItem;
  R: TRect;
begin
  W := 10;
  H := 2;
  if AMenu <> nil then
  begin
    P := AMenu^.Items;
    while P <> nil do
    begin
      if P^.Name <> nil then
      begin
        L := CStrLen(P^.Name^) + 6;
        if P^.Command = 0 then
          Inc(L, 3)
        else if P^.Param <> nil then
          Inc(L, CStrLen(P^.Param^) + 2);
        if L > W then
          W := L;
      end;
      Inc(H);
      P := P^.Next;
    end;
  end;
  R := Bounds;
  if R.A.X + W < R.B.X then
    R.B.X := R.A.X + W
  else
    R.A.X := R.B.X - W;
  if R.A.Y + H < R.B.Y then
    R.B.Y := R.A.Y + H
  else
    R.A.Y := R.B.Y - H;
  inherited Init(R);
  State := State or sfShadow;
  Options := Options or ofPreProcess;
  Menu := AMenu;
  ParentMenu := AParentMenu;
end;

procedure TMenuBox.Draw;
begin
  DrawItems(False);
end;

procedure TMenuBox.GetItemRect(Item: PMenuItem; var R: TRect);
var
  P: PMenuItem;
  Y: Sw_Integer;
begin
  R.Assign(0, 0, 0, 0);
  if Menu = nil then
    Exit;
  Y := 1;
  P := Menu^.Items;
  while (P <> nil) and (P <> Item) do
  begin
    Inc(Y);
    P := P^.Next;
  end;
  if P <> nil then
    R.Assign(2, Y, Size.X - 2, Y + 1);
end;

{ ---- TMenuPopup ------------------------------------------------------------------------ }

constructor TMenuPopup.Init(var Bounds: TRect; AMenu: PMenu);
begin
  inherited Init(Bounds, AMenu, nil);
end;

destructor TMenuPopup.Done;
begin
  inherited Done;
  DisposeMenu(Menu);
end;

procedure TMenuPopup.HandleEvent(var Event: TEvent);
var
  P: PMenuItem;
begin
  case Event.What of
    evKeyDown:
      begin
        P := FindItem(GetCtrlChar(Event.KeyCode));
        if P = nil then
          P := HotKey(Event.KeyCode);
        if (P <> nil) and CommandEnabled(P^.Command) then
        begin
          Event.What := evCommand;
          Event.Command := P^.Command;
          Event.InfoPtr := nil;
          PutEvent(Event);
          ClearEvent(Event);
        end
        else if GetAltChar(Event.KeyCode) <> #0 then
          ClearEvent(Event);
      end;
  end;
  inherited HandleEvent(Event);
end;

{ ---- TStatusLine --------------------------------------------------------------------------- }

constructor TStatusLine.Init(var Bounds: TRect; ADefs: PStatusDef);
begin
  inherited Init(Bounds);
  Options := Options or ofPreProcess;
  EventMask := EventMask or evBroadcast;
  GrowMode := gfGrowLoY + gfGrowHiX + gfGrowHiY;
  Defs := ADefs;
  FindItems;
end;

function LoadItems(var S: TStream): PStatusItem;
var
  Count: Sw_Integer;
  First: PStatusItem;
  Last: ^PStatusItem;
  P: PStatusItem;
begin
  First := nil;
  Last := @First;
  Count := 0;
  S.Read(Count, SizeOf(Count));
  while Count > 0 do
  begin
    New(P);
    P^.Next := nil;
    P^.Text := S.ReadStr;
    S.Read(P^.KeyCode, 2);
    S.Read(P^.Command, 2);
    Last^ := P;
    Last := @P^.Next;
    Dec(Count);
  end;
  LoadItems := First;
end;

constructor TStatusLine.Load(var S: TStream);
var
  Count: Sw_Integer;
  Last: ^PStatusDef;
  D: PStatusDef;
begin
  inherited Load(S);
  Defs := nil;
  Last := @Defs;
  Count := 0;
  S.Read(Count, SizeOf(Count));
  while Count > 0 do
  begin
    New(D);
    D^.Next := nil;
    S.Read(D^.Min, 2);
    S.Read(D^.Max, 2);
    D^.Items := LoadItems(S);
    Last^ := D;
    Last := @D^.Next;
    Dec(Count);
  end;
  FindItems;
end;

procedure TStatusLine.Store(var S: TStream);
var
  Count: Sw_Integer;
  D: PStatusDef;
  P: PStatusItem;
begin
  inherited Store(S);
  Count := 0;
  D := Defs;
  while D <> nil do
  begin
    Inc(Count);
    D := D^.Next;
  end;
  S.Write(Count, SizeOf(Count));
  D := Defs;
  while D <> nil do
  begin
    S.Write(D^.Min, 2);
    S.Write(D^.Max, 2);
    Count := 0;
    P := D^.Items;
    while P <> nil do
    begin
      Inc(Count);
      P := P^.Next;
    end;
    S.Write(Count, SizeOf(Count));
    P := D^.Items;
    while P <> nil do
    begin
      S.WriteStr(P^.Text);
      S.Write(P^.KeyCode, 2);
      S.Write(P^.Command, 2);
      P := P^.Next;
    end;
    D := D^.Next;
  end;
end;

destructor TStatusLine.Done;
var
  D, ND: PStatusDef;
  P, NP: PStatusItem;
begin
  D := Defs;
  while D <> nil do
  begin
    P := D^.Items;
    while P <> nil do
    begin
      NP := P^.Next;
      DisposeStr(P^.Text);
      Dispose(P);
      P := NP;
    end;
    ND := D^.Next;
    Dispose(D);
    D := ND;
  end;
  inherited Done;
end;

procedure TStatusLine.FindItems;
var
  D: PStatusDef;
  H: Word;
begin
  H := HelpCtx;
  D := Defs;
  while (D <> nil) and ((H < D^.Min) or (H > D^.Max)) do
    D := D^.Next;
  if D = nil then
    Items := nil
  else
    Items := D^.Items;
end;

procedure TStatusLine.Draw;
begin
  DrawSelect(nil);
end;

procedure TStatusLine.DrawSelect(Selected: PStatusItem);
var
  B: TDrawBuffer;
  T: PStatusItem;
  CNormal, CSelect, CNormDisabled, CSelDisabled, Color: Word;
  I, L: Sw_Integer;
  HintBuf: String;
begin
  CNormal := GetColor($0301);
  CSelect := GetColor($0604);
  CNormDisabled := GetColor($0202);
  CSelDisabled := GetColor($0505);
  MoveChar(B, ' ', Byte(CNormal), Size.X);
  T := Items;
  I := 0;
  while T <> nil do
  begin
    if T^.Text <> nil then
    begin
      L := CStrLen(T^.Text^);
      if I + L < Size.X then
      begin
        if CommandEnabled(T^.Command) then
          if T = Selected then Color := CSelect else Color := CNormal
        else if T = Selected then
          Color := CSelDisabled
        else
          Color := CNormDisabled;
        MoveChar(B[I], ' ', Byte(Color), 1);
        MoveCStr(B[I + 1], T^.Text^, Color);
        MoveChar(B[I + L + 1], ' ', Byte(Color), 1);
      end;
      Inc(I, L + 2);
    end;
    T := T^.Next;
  end;
  if I < Size.X - 2 then
  begin
    HintBuf := Hint(HelpCtx);
    if HintBuf <> '' then
    begin
      MoveChar(B[I], #179, Byte(CNormal), 1);
      Inc(I, 2);
      if I + Length(HintBuf) > Size.X then
        HintBuf := Copy(HintBuf, 1, Size.X - I);
      MoveStr(B[I], HintBuf, Byte(CNormal));
    end;
  end;
  WriteLine(0, 0, Size.X, 1, B);
end;

function TStatusLine.GetPalette: PPalette;
const
  P: String[Length(CStatusLine)] = CStatusLine;
begin
  GetPalette := @P;
end;

function TStatusLine.ItemAt(Where: TPoint): PStatusItem;
var
  T: PStatusItem;
  I, K: Sw_Integer;
  Mouse: TPoint;
begin
  ItemAt := nil;
  MakeLocal(Where, Mouse);
  if (Mouse.Y <> 0) or (Mouse.X < 0) then
    Exit;
  I := 0;
  T := Items;
  while T <> nil do
  begin
    if T^.Text <> nil then
    begin
      K := I + CStrLen(T^.Text^) + 2;
      if (Mouse.X >= I) and (Mouse.X < K) then
      begin
        ItemAt := T;
        Exit;
      end;
      I := K;
    end;
    T := T^.Next;
  end;
end;

procedure TStatusLine.HandleEvent(var Event: TEvent);
var
  T: PStatusItem;
  Mouse: TPoint;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      begin
        T := nil;
        repeat
          if MouseInView(Event.Where) then
            T := ItemAt(Event.Where)
          else
            T := nil;
          DrawSelect(T);
        until not MouseEvent(Event, evMouseMove);
        MakeLocal(Event.Where, Mouse);
        if (T <> nil) and CommandEnabled(T^.Command) then
        begin
          Event.What := evCommand;
          Event.Command := T^.Command;
          Event.InfoPtr := nil;
          PutEvent(Event);
        end;
        ClearEvent(Event);
        DrawView;
      end;
    evKeyDown:
      begin
        T := Items;
        while T <> nil do
        begin
          if (Event.KeyCode = T^.KeyCode) and CommandEnabled(T^.Command) then
          begin
            Event.What := evCommand;
            Event.Command := T^.Command;
            Event.InfoPtr := nil;
            Exit;
          end;
          T := T^.Next;
        end;
      end;
    evBroadcast:
      if Event.Command = cmCommandSetChanged then
        DrawView;
  end;
end;

function TStatusLine.Hint(AHelpCtx: Word): String;
begin
  Hint := '';
end;

{ Called from TProgram.Idle: follows the help context of the modal view. }
procedure TStatusLine.Update;
var
  P: PView;
  H: Word;
  D: PStatusDef;
  NewItems: PStatusItem;
begin
  P := TopView;
  if P <> nil then
    H := P^.GetHelpCtx
  else
    H := hcNoContext;
  if HelpCtx <> H then
  begin
    HelpCtx := H;
    D := Defs;
    while (D <> nil) and ((H < D^.Min) or (H > D^.Max)) do
      D := D^.Next;
    if D = nil then
      NewItems := nil
    else
      NewItems := D^.Items;
    Items := NewItems;
    DrawView;
  end;
end;

procedure RegisterMenus;
begin
  RegisterType(RMenuBar);
  RegisterType(RMenuBox);
  RegisterType(RStatusLine);
  RegisterType(RMenuPopup);
end;

end.
