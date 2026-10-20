{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit ColorSel dari Odin Vision: dialog pemilih warna palet aplikasi
  (TColorDialog) dan kontrol-kontrolnya. Implementasi clean-room
  berdasarkan dokumentasi API Turbo Vision TP7.

  Dialog menyunting salinan palet (Pal). Contoh teks (TColorDisplay)
  menunjuk ke satu byte Pal, dan selector warna depan dan latar mengubah
  byte itu lewat broadcast. Data dialog adalah TPalette (256 byte), jadi
  ExecuteDialog(D, Application^.GetPalette) langsung mengganti palet
  aplikasi. }
unit ColorSel;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views, Dialogs;

const
  cmColorForegroundChanged = 71;
  cmColorBackgroundChanged = 72;
  cmColorSet = 73;
  cmNewColorItem = 74;
  cmNewColorIndex = 75;
  cmSaveColorIndex = 76;

type
  TColorSel = (csBackground, csForeground);

  PColorItem = ^TColorItem;
  TColorItem = record
    Name: PString;
    Index: Byte;
    Next: PColorItem;
  end;

  PColorGroup = ^TColorGroup;
  TColorGroup = record
    Name: PString;
    Index: Byte;
    Items: PColorItem;
    Next: PColorGroup;
  end;

  PColorIndex = ^TColorIndex;
  TColorIndex = record
    GroupIndex: Byte;
    ColorSize: Byte;
    ColorIndex: array[0..255] of Byte;
  end;

  PColorSelector = ^TColorSelector;
  TColorSelector = object(TView)
    Color: Byte;
    SelType: TColorSel;
    constructor Init(var Bounds: TRect; ASelType: TColorSel);
    constructor Load(var S: TStream);
    procedure Draw; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Store(var S: TStream);
    { Odin: the number of colors (16 or 8) and choosing one. }
    function ColorCount: Integer;
    procedure SelectColor(AColor: Integer);
  end;

  PMonoSelector = ^TMonoSelector;
  TMonoSelector = object(TCluster)
    constructor Init(var Bounds: TRect);
    procedure Draw; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function Mark(Item: Sw_Integer): Boolean; virtual;
    procedure NewColor;
    procedure Press(Item: Sw_Integer); virtual;
    procedure MovedTo(Item: Sw_Integer); virtual;
  end;

  PColorDisplay = ^TColorDisplay;
  TColorDisplay = object(TView)
    Color: PByte;
    Text: PString;
    constructor Init(var Bounds: TRect; AText: PString);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Draw; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SetColor(var AColor: Byte); virtual;
    procedure Store(var S: TStream);
  end;

  PColorGroupList = ^TColorGroupList;
  TColorGroupList = object(TListViewer)
    Groups: PColorGroup;
    constructor Init(var Bounds: TRect; AScrollBar: PScrollBar; AGroups: PColorGroup);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure FocusItem(Item: Sw_Integer); virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Store(var S: TStream);
    procedure SetGroupIndex(GroupNum, ItemNum: Byte);
    function GetGroup(GroupNum: Byte): PColorGroup;
    function GetGroupIndex(GroupNum: Byte): Byte;
    function GetNumGroups: Byte;
  end;

  PColorItemList = ^TColorItemList;
  TColorItemList = object(TListViewer)
    Items: PColorItem;
    constructor Init(var Bounds: TRect; AScrollBar: PScrollBar; AItems: PColorItem);
    constructor Load(var S: TStream);
    procedure FocusItem(Item: Sw_Integer); virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
  end;

  PColorDialog = ^TColorDialog;
  TColorDialog = object(TDialog)
    GroupIndex: Byte;
    Display: PColorDisplay;
    Groups: PColorGroupList;
    ForLabel: PLabel;
    ForSel: PColorSelector;
    BakLabel: PLabel;
    BakSel: PColorSelector;
    MonoLabel: PLabel;
    MonoSel: PMonoSelector;
    Pal: TPalette;
    constructor Init(APalette: TPalette; AGroups: PColorGroup);
    constructor Load(var S: TStream);
    function DataSize: Word; virtual;
    procedure GetData(var Rec); virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
    procedure GetIndexes(var Colors: PColorIndex);
    procedure SetIndexes(var Colors: PColorIndex);
  end;

function ColorItem(const Name: String; Index: Byte; Next: PColorItem): PColorItem;
function ColorGroup(const Name: String; Items: PColorItem; Next: PColorGroup): PColorGroup;
function DesktopColorItems(Next: PColorItem): PColorItem;
function MenuColorItems(Next: PColorItem): PColorItem;
function DialogColorItems(Palette: Word; Next: PColorItem): PColorItem;
function WindowColorItems(Palette: Word; Next: PColorItem): PColorItem;
procedure LoadIndexes(var S: TStream);
procedure StoreIndexes(var S: TStream);
procedure RegisterColorSel;

const
  { The group and item chosen last in each group, kept between dialogs. }
  ColorIndexes: PColorIndex = nil;

  RColorSelector: TStreamRec = (ObjType: 21; VmtLink: Ofs(TypeOf(TColorSelector)^); Load: @TColorSelector.Load;
    Store: @TColorSelector.Store);
  RMonoSelector: TStreamRec = (ObjType: 22; VmtLink: Ofs(TypeOf(TMonoSelector)^); Load: @TMonoSelector.Load;
    Store: @TMonoSelector.Store);
  RColorDisplay: TStreamRec = (ObjType: 23; VmtLink: Ofs(TypeOf(TColorDisplay)^); Load: @TColorDisplay.Load;
    Store: @TColorDisplay.Store);
  RColorGroupList: TStreamRec = (ObjType: 24; VmtLink: Ofs(TypeOf(TColorGroupList)^); Load: @TColorGroupList.Load;
    Store: @TColorGroupList.Store);
  RColorItemList: TStreamRec = (ObjType: 25; VmtLink: Ofs(TypeOf(TColorItemList)^); Load: @TColorItemList.Load;
    Store: @TColorItemList.Store);
  RColorDialog: TStreamRec = (ObjType: 26; VmtLink: Ofs(TypeOf(TColorDialog)^); Load: @TColorDialog.Load;
    Store: @TColorDialog.Store);

implementation

const
  { Width of one color in a selector, and colors per row. }
  CellWidth = 3;
  RowColors = 4;
  { Attributes of the monochrome choices: normal, highlight, underline,
    inverse. }
  MonoColors: array[0..3] of Byte = ($07, $0F, $01, $70);
  { Item names of a dialog palette (entries 1-31) and a window palette
    (entries 1-7), in the order of SPEC.md section 7. }
  DialogNames: array[0..30] of String[17] = (
    'Frame passive', 'Frame active', 'Frame icons', 'Scroll bar page', 'Scroll bar icons', 'Static text',
    'Label normal', 'Label selected', 'Label shortcut', 'Button normal', 'Button default', 'Button selected',
    'Button disabled', 'Button shortcut', 'Button shadow', 'Cluster normal', 'Cluster selected',
    'Cluster shortcut', 'Input normal', 'Input selected', 'Input arrow', 'History button', 'History sides',
    'History bar page', 'History bar icons', 'List normal', 'List focused', 'List selected', 'List divider',
    'Information pane', 'Cluster disabled');
  WindowNames: array[0..6] of String[16] = (
    'Frame passive', 'Frame active', 'Frame icons', 'Scroll bar page', 'Scroll bar icons', 'Normal text',
    'Selected text');

function CountGroups(P: PColorGroup): Sw_Integer;
var
  N: Sw_Integer;
begin
  N := 0;
  while P <> nil do
  begin
    Inc(N);
    P := P^.Next;
  end;
  CountGroups := N;
end;

function CountItems(P: PColorItem): Sw_Integer;
var
  N: Sw_Integer;
begin
  N := 0;
  while P <> nil do
  begin
    Inc(N);
    P := P^.Next;
  end;
  CountItems := N;
end;

function ItemAt(P: PColorItem; I: Sw_Integer): PColorItem;
begin
  while (P <> nil) and (I > 0) do
  begin
    P := P^.Next;
    Dec(I);
  end;
  if I < 0 then
    P := nil;
  ItemAt := P;
end;

function GroupAt(P: PColorGroup; I: Sw_Integer): PColorGroup;
begin
  while (P <> nil) and (I > 0) do
  begin
    P := P^.Next;
    Dec(I);
  end;
  if I < 0 then
    P := nil;
  GroupAt := P;
end;

function NameOf(P: PString; MaxLen: Sw_Integer): String;
begin
  if P = nil then
    NameOf := ''
  else
    NameOf := Copy(P^, 1, MaxLen);
end;

{ ---- builders --------------------------------------------------------------------------- }

function ColorItem(const Name: String; Index: Byte; Next: PColorItem): PColorItem;
var
  P: PColorItem;
begin
  New(P);
  P^.Name := NewStr(Name);
  P^.Index := Index;
  P^.Next := Next;
  ColorItem := P;
end;

function ColorGroup(const Name: String; Items: PColorItem; Next: PColorGroup): PColorGroup;
var
  P: PColorGroup;
begin
  New(P);
  P^.Name := NewStr(Name);
  P^.Index := 0;
  P^.Items := Items;
  P^.Next := Next;
  ColorGroup := P;
end;

function DesktopColorItems(Next: PColorItem): PColorItem;
begin
  DesktopColorItems := ColorItem('Color', 1, Next);
end;

function MenuColorItems(Next: PColorItem): PColorItem;
begin
  MenuColorItems :=
    ColorItem('Normal', 2,
    ColorItem('Disabled', 3,
    ColorItem('Shortcut', 4,
    ColorItem('Selected', 5,
    ColorItem('Selected disabled', 6,
    ColorItem('Shortcut selected', 7, Next))))));
end;

function DialogColorItems(Palette: Word; Next: PColorItem): PColorItem;
var
  Base, I: Integer;
  P: PColorItem;
begin
  case Palette of
    dpBlueDialog: Base := 64;
    dpCyanDialog: Base := 96;
  else
    Base := 32;
  end;
  P := Next;
  for I := 30 downto 0 do
    P := ColorItem(DialogNames[I], Base + I, P);
  DialogColorItems := P;
end;

function WindowColorItems(Palette: Word; Next: PColorItem): PColorItem;
var
  Base, I: Integer;
  P: PColorItem;
begin
  case Palette of
    wpCyanWindow: Base := 16;
    wpGrayWindow: Base := 24;
  else
    Base := 8;
  end;
  P := Next;
  for I := 6 downto 0 do
    P := ColorItem(WindowNames[I], Base + I, P);
  WindowColorItems := P;
end;

{ ---- TColorSelector -------------------------------------------------------------------- }

constructor TColorSelector.Init(var Bounds: TRect; ASelType: TColorSel);
begin
  inherited Init(Bounds);
  Options := Options or (ofSelectable + ofFirstClick + ofFramed);
  EventMask := EventMask or evBroadcast;
  SelType := ASelType;
  Color := 0;
  ShowCursor;
end;

constructor TColorSelector.Load(var S: TStream);
var
  B: Byte;
begin
  inherited Load(S);
  S.Read(Color, 1);
  B := 0;
  S.Read(B, 1);
  if B = Ord(csBackground) then
    SelType := csBackground
  else
    SelType := csForeground;
end;

procedure TColorSelector.Store(var S: TStream);
var
  B: Byte;
begin
  inherited Store(S);
  S.Write(Color, 1);
  B := Ord(SelType);
  S.Write(B, 1);
end;

function TColorSelector.ColorCount: Integer;
begin
  if SelType = csBackground then
    ColorCount := 8
  else
    ColorCount := 16;
end;

procedure TColorSelector.Draw;
var
  B: TDrawBuffer;
  Back: Byte;
  Y, I, C, X: Integer;
begin
  Back := Byte(GetColor(6));
  for Y := 0 to Size.Y - 1 do
  begin
    MoveChar(B, ' ', Back, Size.X);
    for I := 0 to RowColors - 1 do
    begin
      C := Y * RowColors + I;
      if C < ColorCount then
      begin
        X := I * CellWidth;
        { Attribute C: the color on black. Written directly, because
          MoveChar keeps the attribute when it is 0 (black). }
        B[X] := (Word(C) shl 8) or 219;
        B[X + 1] := (Word(C) shl 8) or 219;
        B[X + 2] := (Word(C) shl 8) or 219;
        if C = Color then
          if C = 0 then
            B[X + 1] := ($70 shl 8) or 8
          else
            B[X + 1] := (Word(C) shl 8) or 8;
      end;
    end;
    WriteLine(0, Y, Size.X, 1, B);
  end;
  SetCursor((Color mod RowColors) * CellWidth + 1, Color div RowColors);
end;

procedure TColorSelector.SelectColor(AColor: Integer);
var
  Command: Word;
begin
  if (AColor < 0) or (AColor >= ColorCount) or (AColor = Color) then
    Exit;
  Color := AColor;
  DrawView;
  if SelType = csBackground then
    Command := cmColorBackgroundChanged
  else
    Command := cmColorForegroundChanged;
  Message(Owner, evBroadcast, Command, Pointer(PtrUInt(Color)));
end;

procedure TColorSelector.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  C, N: Integer;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      begin
        repeat
          if MouseInView(Event.Where) then
          begin
            MakeLocal(Event.Where, Mouse);
            if Mouse.X < RowColors * CellWidth then
              SelectColor(Mouse.Y * RowColors + Mouse.X div CellWidth);
          end;
        until not MouseEvent(Event, evMouseMove);
        ClearEvent(Event);
      end;
    evKeyDown:
      begin
        N := ColorCount;
        C := Color;
        case CtrlToArrow(Event.KeyCode) of
          kbLeft:
            if C > 0 then
              Dec(C)
            else
              C := N - 1;
          kbRight:
            if C < N - 1 then
              Inc(C)
            else
              C := 0;
          kbUp:
            if C >= RowColors then
              Dec(C, RowColors)
            else
              Inc(C, N - RowColors);
          kbDown:
            if C < N - RowColors then
              Inc(C, RowColors)
            else
              Dec(C, N - RowColors);
        else
          Exit;
        end;
        SelectColor(C);
        ClearEvent(Event);
      end;
    evBroadcast:
      if Event.Command = cmColorSet then
      begin
        if SelType = csBackground then
          Color := (Event.InfoByte shr 4) and $07
        else
          Color := Event.InfoByte and $0F;
        DrawView;
      end;
  end;
end;

{ ---- TMonoSelector --------------------------------------------------------------------- }

constructor TMonoSelector.Init(var Bounds: TRect);
begin
  inherited Init(Bounds, NewSItem('Normal', NewSItem('Highlight', NewSItem('Underline',
    NewSItem('Inverse', nil)))));
  EventMask := EventMask or evBroadcast;
end;

procedure TMonoSelector.Draw;
begin
  DrawBox(' ( ) ', #7);
end;

procedure TMonoSelector.HandleEvent(var Event: TEvent);
var
  I: Integer;
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmColorSet) then
  begin
    Value := Event.InfoByte;
    for I := 0 to 3 do
      if MonoColors[I] = Value then
        Sel := I;
    DrawView;
  end;
end;

function TMonoSelector.Mark(Item: Sw_Integer): Boolean;
begin
  Mark := (Item >= 0) and (Item <= 3) and (MonoColors[Item] = Value);
end;

procedure TMonoSelector.NewColor;
begin
  Message(Owner, evBroadcast, cmColorForegroundChanged, Pointer(PtrUInt(Value and $0F)));
  Message(Owner, evBroadcast, cmColorBackgroundChanged, Pointer(PtrUInt((Value shr 4) and $0F)));
end;

procedure TMonoSelector.Press(Item: Sw_Integer);
begin
  if (Item < 0) or (Item > 3) then
    Exit;
  Value := MonoColors[Item];
  NewColor;
end;

procedure TMonoSelector.MovedTo(Item: Sw_Integer);
begin
  Press(Item);
end;

{ ---- TColorDisplay --------------------------------------------------------------------- }

constructor TColorDisplay.Init(var Bounds: TRect; AText: PString);
begin
  inherited Init(Bounds);
  EventMask := EventMask or evBroadcast;
  Text := AText;
  Color := nil;
end;

constructor TColorDisplay.Load(var S: TStream);
begin
  inherited Load(S);
  Text := S.ReadStr;
  Color := nil;
end;

procedure TColorDisplay.Store(var S: TStream);
begin
  inherited Store(S);
  S.WriteStr(Text);
end;

destructor TColorDisplay.Done;
begin
  DisposeStr(Text);
  inherited Done;
end;

procedure TColorDisplay.Draw;
var
  B: TDrawBuffer;
  Attr: Byte;
  S: String;
  I, L: Integer;
begin
  if Color <> nil then
    Attr := Color^
  else
    Attr := Byte(GetColor(6));
  if Text <> nil then
    S := Text^
  else
    S := '';
  L := Length(S);
  for I := 0 to Size.X - 1 do
    if L > 0 then
      B[I] := (Word(Attr) shl 8) or Ord(S[I mod L + 1])
    else
      B[I] := (Word(Attr) shl 8) or Ord(' ');
  WriteLine(0, 0, Size.X, Size.Y, B);
end;

procedure TColorDisplay.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Color <> nil) then
    case Event.Command of
      cmColorForegroundChanged:
        begin
          Color^ := (Color^ and $F0) or (Event.InfoByte and $0F);
          DrawView;
        end;
      cmColorBackgroundChanged:
        begin
          Color^ := (Color^ and $0F) or ((Event.InfoByte and $0F) shl 4);
          DrawView;
        end;
    end;
end;

procedure TColorDisplay.SetColor(var AColor: Byte);
begin
  Color := @AColor;
  Message(Owner, evBroadcast, cmColorSet, Pointer(PtrUInt(AColor)));
  DrawView;
end;

{ ---- TColorGroupList ------------------------------------------------------------------- }

constructor TColorGroupList.Init(var Bounds: TRect; AScrollBar: PScrollBar; AGroups: PColorGroup);
begin
  inherited Init(Bounds, 1, nil, AScrollBar);
  Groups := AGroups;
  SetRange(CountGroups(AGroups));
end;

constructor TColorGroupList.Load(var S: TStream);
var
  GroupCount, ItemCount, I, J: Sw_Integer;
  G, LastG: PColorGroup;
  P, LastP: PColorItem;
begin
  inherited Load(S);
  Groups := nil;
  LastG := nil;
  GroupCount := 0;
  S.Read(GroupCount, SizeOf(GroupCount));
  I := 0;
  while (I < GroupCount) and (S.Status = stOk) do
  begin
    New(G);
    G^.Name := S.ReadStr;
    G^.Index := 0;
    S.Read(G^.Index, 1);
    G^.Items := nil;
    G^.Next := nil;
    ItemCount := 0;
    S.Read(ItemCount, SizeOf(ItemCount));
    LastP := nil;
    J := 0;
    while (J < ItemCount) and (S.Status = stOk) do
    begin
      New(P);
      P^.Name := S.ReadStr;
      P^.Index := 0;
      S.Read(P^.Index, 1);
      P^.Next := nil;
      if LastP = nil then
        G^.Items := P
      else
        LastP^.Next := P;
      LastP := P;
      Inc(J);
    end;
    if LastG = nil then
      Groups := G
    else
      LastG^.Next := G;
    LastG := G;
    Inc(I);
  end;
end;

procedure TColorGroupList.Store(var S: TStream);
var
  N: Sw_Integer;
  G: PColorGroup;
  P: PColorItem;
begin
  inherited Store(S);
  N := CountGroups(Groups);
  S.Write(N, SizeOf(N));
  G := Groups;
  while G <> nil do
  begin
    S.WriteStr(G^.Name);
    S.Write(G^.Index, 1);
    N := CountItems(G^.Items);
    S.Write(N, SizeOf(N));
    P := G^.Items;
    while P <> nil do
    begin
      S.WriteStr(P^.Name);
      S.Write(P^.Index, 1);
      P := P^.Next;
    end;
    G := G^.Next;
  end;
end;

destructor TColorGroupList.Done;
var
  G, NextG: PColorGroup;
  P, NextP: PColorItem;
begin
  G := Groups;
  while G <> nil do
  begin
    P := G^.Items;
    while P <> nil do
    begin
      NextP := P^.Next;
      DisposeStr(P^.Name);
      Dispose(P);
      P := NextP;
    end;
    NextG := G^.Next;
    DisposeStr(G^.Name);
    Dispose(G);
    G := NextG;
  end;
  Groups := nil;
  inherited Done;
end;

procedure TColorGroupList.FocusItem(Item: Sw_Integer);
begin
  inherited FocusItem(Item);
  Message(Owner, evBroadcast, cmNewColorItem, GroupAt(Groups, Item));
end;

function TColorGroupList.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
var
  G: PColorGroup;
begin
  G := GroupAt(Groups, Item);
  if G = nil then
    GetText := ''
  else
    GetText := NameOf(G^.Name, MaxLen);
end;

procedure TColorGroupList.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmSaveColorIndex) then
    SetGroupIndex(Focused, Event.InfoByte);
end;

procedure TColorGroupList.SetGroupIndex(GroupNum, ItemNum: Byte);
var
  G: PColorGroup;
begin
  G := GroupAt(Groups, GroupNum);
  if G <> nil then
    G^.Index := ItemNum;
end;

function TColorGroupList.GetGroup(GroupNum: Byte): PColorGroup;
begin
  GetGroup := GroupAt(Groups, GroupNum);
end;

function TColorGroupList.GetGroupIndex(GroupNum: Byte): Byte;
var
  G: PColorGroup;
begin
  G := GroupAt(Groups, GroupNum);
  if G = nil then
    GetGroupIndex := 0
  else
    GetGroupIndex := G^.Index;
end;

function TColorGroupList.GetNumGroups: Byte;
begin
  GetNumGroups := CountGroups(Groups);
end;

{ ---- TColorItemList -------------------------------------------------------------------- }

constructor TColorItemList.Init(var Bounds: TRect; AScrollBar: PScrollBar; AItems: PColorItem);
begin
  inherited Init(Bounds, 1, nil, AScrollBar);
  EventMask := EventMask or evBroadcast;
  Items := AItems;
  SetRange(CountItems(AItems));
end;

constructor TColorItemList.Load(var S: TStream);
begin
  inherited Load(S);
  Items := nil;
end;

procedure TColorItemList.FocusItem(Item: Sw_Integer);
var
  P: PColorItem;
begin
  inherited FocusItem(Item);
  Message(Owner, evBroadcast, cmSaveColorIndex, Pointer(PtrUInt(Item)));
  P := ItemAt(Items, Item);
  if P <> nil then
    Message(Owner, evBroadcast, cmNewColorIndex, Pointer(PtrUInt(P^.Index)));
end;

function TColorItemList.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
var
  P: PColorItem;
begin
  P := ItemAt(Items, Item);
  if P = nil then
    GetText := ''
  else
    GetText := NameOf(P^.Name, MaxLen);
end;

procedure TColorItemList.HandleEvent(var Event: TEvent);
var
  G: PColorGroup;
  Saved: Sw_Integer;
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmNewColorItem) then
  begin
    G := PColorGroup(Event.InfoPtr);
    if G = nil then
    begin
      Items := nil;
      SetRange(0);
    end
    else
    begin
      { SetRange can move the focus (and so save a new index for the group)
        through the scroll bar: read the saved item first. }
      Saved := G^.Index;
      Items := G^.Items;
      SetRange(CountItems(Items));
      if Saved >= Range then
        Saved := 0;
      if Range > 0 then
        FocusItem(Saved);
    end;
    DrawView;
  end;
end;

{ ---- TColorDialog ---------------------------------------------------------------------- }

constructor TColorDialog.Init(APalette: TPalette; AGroups: PColorGroup);
var
  R: TRect;
  Bar: PScrollBar;
  List: PColorItemList;
begin
  R.Assign(0, 0, 62, 18);
  inherited Init(R, 'Colors');
  Options := Options or ofCentered;
  Pal := APalette;
  GroupIndex := 0;

  R.Assign(16, 3, 17, 14);
  Bar := New(PScrollBar, Init(R));
  Insert(Bar);
  R.Assign(3, 3, 16, 14);
  Groups := New(PColorGroupList, Init(R, Bar, AGroups));
  Insert(Groups);
  R.Assign(2, 2, 9, 3);
  Insert(New(PLabel, Init(R, '~G~roup', Groups)));

  R.Assign(37, 3, 38, 14);
  Bar := New(PScrollBar, Init(R));
  Insert(Bar);
  R.Assign(19, 3, 37, 14);
  List := New(PColorItemList, Init(R, Bar, nil));
  Insert(List);
  R.Assign(18, 2, 24, 3);
  Insert(New(PLabel, Init(R, '~I~tem', List)));

  R.Assign(41, 3, 53, 7);
  ForSel := New(PColorSelector, Init(R, csForeground));
  Insert(ForSel);
  R.Assign(40, 2, 53, 3);
  ForLabel := New(PLabel, Init(R, '~F~oreground', ForSel));
  Insert(ForLabel);

  R.Assign(41, 9, 53, 11);
  BakSel := New(PColorSelector, Init(R, csBackground));
  Insert(BakSel);
  R.Assign(40, 8, 53, 9);
  BakLabel := New(PLabel, Init(R, '~B~ackground', BakSel));
  Insert(BakLabel);

  R.Assign(41, 12, 53, 14);
  Display := New(PColorDisplay, Init(R, NewStr('Text ')));
  Insert(Display);

  R.Assign(40, 3, 58, 7);
  MonoSel := New(PMonoSelector, Init(R));
  Insert(MonoSel);
  R.Assign(39, 2, 47, 3);
  MonoLabel := New(PLabel, Init(R, '~C~olor', MonoSel));
  Insert(MonoLabel);

  if ScreenMode and $FF = smMono then
  begin
    ForLabel^.Hide;
    ForSel^.Hide;
    BakLabel^.Hide;
    BakSel^.Hide;
  end
  else
  begin
    MonoLabel^.Hide;
    MonoSel^.Hide;
  end;

  R.Assign(39, 15, 49, 17);
  Insert(New(PButton, Init(R, 'O~K~', cmOK, bfDefault)));
  R.Assign(50, 15, 60, 17);
  Insert(New(PButton, Init(R, 'Cancel', cmCancel, bfNormal)));
  SelectNext(False);
  { Fills the item list and points the sample at the first item. }
  Groups^.FocusItemNum(0);
end;

constructor TColorDialog.Load(var S: TStream);
begin
  inherited Load(S);
  GetSubViewPtr(S, Display);
  GetSubViewPtr(S, Groups);
  GetSubViewPtr(S, ForLabel);
  GetSubViewPtr(S, ForSel);
  GetSubViewPtr(S, BakLabel);
  GetSubViewPtr(S, BakSel);
  GetSubViewPtr(S, MonoLabel);
  GetSubViewPtr(S, MonoSel);
  GroupIndex := 0;
  S.Read(GroupIndex, 1);
  Pal := '';
  S.Read(Pal, 1);
  S.Read(Pal[1], Length(Pal));
  { The item list and the sample are not stored: link them again. }
  if Groups <> nil then
    Groups^.FocusItemNum(Groups^.Focused);
end;

procedure TColorDialog.Store(var S: TStream);
begin
  inherited Store(S);
  PutSubViewPtr(S, Display);
  PutSubViewPtr(S, Groups);
  PutSubViewPtr(S, ForLabel);
  PutSubViewPtr(S, ForSel);
  PutSubViewPtr(S, BakLabel);
  PutSubViewPtr(S, BakSel);
  PutSubViewPtr(S, MonoLabel);
  PutSubViewPtr(S, MonoSel);
  S.Write(GroupIndex, 1);
  S.Write(Pal, Length(Pal) + 1);
end;

function TColorDialog.DataSize: Word;
begin
  DataSize := SizeOf(TPalette);
end;

procedure TColorDialog.GetData(var Rec);
begin
  GetIndexes(ColorIndexes);
  Move(Pal, Rec, Length(Pal) + 1);
end;

procedure TColorDialog.SetData(var Rec);
begin
  Move(Rec, Pal, Byte(Rec) + 1);
  SetIndexes(ColorIndexes);
  if Groups <> nil then
  begin
    Groups^.FocusItemNum(GroupIndex);
    Groups^.DrawView;
  end;
end;

procedure TColorDialog.HandleEvent(var Event: TEvent);
begin
  if (Event.What = evBroadcast) and (Event.Command = cmNewColorItem) and (Groups <> nil) then
    GroupIndex := Groups^.Focused;
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmNewColorIndex) and (Display <> nil) then
    if (Event.InfoByte >= 1) and (Event.InfoByte <= Length(Pal)) then
      Display^.SetColor(PByte(@Pal[Event.InfoByte])^)
    else
    begin
      Display^.Color := nil;
      Display^.DrawView;
    end;
end;

procedure TColorDialog.GetIndexes(var Colors: PColorIndex);
var
  N, I: Integer;
begin
  if Groups = nil then
    Exit;
  N := Groups^.GetNumGroups;
  if (Colors <> nil) and (Colors^.ColorSize <> N) then
  begin
    FreeMem(Colors, 2 + Colors^.ColorSize);
    Colors := nil;
  end;
  if Colors = nil then
    GetMem(Colors, 2 + N);
  Colors^.GroupIndex := Groups^.Focused;
  Colors^.ColorSize := N;
  for I := 0 to N - 1 do
    Colors^.ColorIndex[I] := Groups^.GetGroupIndex(I);
end;

procedure TColorDialog.SetIndexes(var Colors: PColorIndex);
var
  N, I: Integer;
begin
  if (Groups = nil) or (Colors = nil) then
    Exit;
  N := Groups^.GetNumGroups;
  if Colors^.ColorSize <> N then
    Exit;
  for I := 0 to N - 1 do
    Groups^.SetGroupIndex(I, Colors^.ColorIndex[I]);
  GroupIndex := Colors^.GroupIndex;
end;

{ ---- ColorIndexes on a stream ------------------------------------------------------------ }

procedure StoreIndexes(var S: TStream);
var
  N: Byte;
begin
  if ColorIndexes = nil then
    N := 0
  else
    N := ColorIndexes^.ColorSize;
  S.Write(N, 1);
  if N > 0 then
  begin
    S.Write(ColorIndexes^.GroupIndex, 1);
    S.Write(ColorIndexes^.ColorIndex, N);
  end;
end;

procedure LoadIndexes(var S: TStream);
var
  N: Byte;
begin
  if ColorIndexes <> nil then
    FreeMem(ColorIndexes, 2 + ColorIndexes^.ColorSize);
  ColorIndexes := nil;
  N := 0;
  S.Read(N, 1);
  if N > 0 then
  begin
    GetMem(ColorIndexes, 2 + N);
    ColorIndexes^.ColorSize := N;
    ColorIndexes^.GroupIndex := 0;
    S.Read(ColorIndexes^.GroupIndex, 1);
    S.Read(ColorIndexes^.ColorIndex, N);
  end;
end;

procedure RegisterColorSel;
begin
  RegisterType(RColorSelector);
  RegisterType(RMonoSelector);
  RegisterType(RColorDisplay);
  RegisterType(RColorGroupList);
  RegisterType(RColorItemList);
  RegisterType(RColorDialog);
end;

end.
