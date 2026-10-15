{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Outline dari Odin Vision: TOutlineViewer (pohon yang bisa dibuka
  dan ditutup) dan TOutline di atas simpul TNode. Implementasi clean-room
  berdasarkan dokumentasi API Turbo Vision TP7.

  Baris yang tampil adalah akar lalu anak dari setiap simpul yang terbuka,
  dinomori dari 0. Tombol: panah, PgUp/PgDn, Home/End, '+' buka, '-'
  tutup, '*' buka semua, Right/Left buka/tutup, Enter pilih. Klik pada
  gambar cabang membuka atau menutup simpul; klik ganda memilih. }
unit Outline;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views;

const
  ovExpanded = $01;
  ovChildren = $02;
  ovLast = $04;

  cmOutlineItemSelected = 301;

  COutlineViewer = #6#7#3#8;

type
  PNode = ^TNode;
  TNode = record
    Next: PNode;
    Text: PString;
    ChildList: PNode;
    Expanded: Boolean;
  end;

  POutlineViewer = ^TOutlineViewer;
  TOutlineViewer = object(TScroller)
    Foc: Sw_Integer;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
    constructor Load(var S: TStream);
    procedure Adjust(Node: Pointer; Expand: Boolean); virtual;
    function CreateGraph(Level: Integer; Lines: LongInt; Flags: Word; LevWidth, EndWidth: Integer;
      const Chars: String): String;
    procedure Draw; virtual;
    procedure ExpandAll(Node: Pointer);
    function FirstThat(Test: Pointer): Pointer;
    procedure Focused(I: Sw_Integer); virtual;
    function ForEach(Action: Pointer): Pointer;
    function GetChild(Node: Pointer; I: Sw_Integer): Pointer; virtual;
    function GetGraph(Level: Integer; Lines: LongInt; Flags: Word): String; virtual;
    function GetNode(I: Sw_Integer): Pointer;
    function GetNumChildren(Node: Pointer): Sw_Integer; virtual;
    function GetPalette: PPalette; virtual;
    function GetRoot: Pointer; virtual;
    function GetText(Node: Pointer): String; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function HasChildren(Node: Pointer): Boolean; virtual;
    function IsExpanded(Node: Pointer): Boolean; virtual;
    function IsSelected(I: Sw_Integer): Boolean; virtual;
    procedure Selected(I: Sw_Integer); virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
    procedure Update;
    { Odin: walks the visible nodes, calling Code (a routine nested in the
      routine whose frame is Frame) with the node, level, position, lines
      and flags; with CheckResult it stops at the first True. }
    function Iterate(Code, Frame: Pointer; CheckResult: Boolean): Pointer;
    procedure FocusLine(I: Sw_Integer);
  end;

  POutline = ^TOutline;
  TOutline = object(TOutlineViewer)
    Root: PNode;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; ARoot: PNode);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Adjust(Node: Pointer; Expand: Boolean); virtual;
    function GetChild(Node: Pointer; I: Sw_Integer): Pointer; virtual;
    function GetNumChildren(Node: Pointer): Sw_Integer; virtual;
    function GetRoot: Pointer; virtual;
    function GetText(Node: Pointer): String; virtual;
    function HasChildren(Node: Pointer): Boolean; virtual;
    function IsExpanded(Node: Pointer): Boolean; virtual;
    procedure Store(var S: TStream);
  end;

function NewNode(const AText: String; AChildren, ANext: PNode): PNode;
procedure DisposeNode(Node: PNode);
procedure RegisterOutline;

const
  ROutline: TStreamRec = (ObjType: 91; VmtLink: Ofs(TypeOf(TOutline)^); Load: @TOutline.Load;
    Store: @TOutline.Store);

implementation

function CallerFrame: Pointer; external 'odinrtl' name 'ODIN_CALLERFRAME';
function CallLocal5(Code, Frame, Node: Pointer; Level, Position: Integer; Lines: LongInt; Flags: Word): Boolean;
  external 'odinrtl' name 'ODIN_CALLLOCAL5';

const
  GraphChars = ' '#179#195#192#196#196'+'#196;
  LevelWidth = 3;
  EndWidth = 3;

{ The frame of the routine calling this function. }
function MyFrame: Pointer;
begin
  MyFrame := CallerFrame;
end;

function NewNode(const AText: String; AChildren, ANext: PNode): PNode;
var
  P: PNode;
begin
  New(P);
  P^.Next := ANext;
  P^.Text := NewStr(AText);
  P^.ChildList := AChildren;
  P^.Expanded := True;
  NewNode := P;
end;

procedure DisposeNode(Node: PNode);
begin
  if Node = nil then
    Exit;
  DisposeNode(Node^.ChildList);
  DisposeNode(Node^.Next);
  DisposeStr(Node^.Text);
  Dispose(Node);
end;

{ ---- TOutlineViewer ------------------------------------------------------------------ }

constructor TOutlineViewer.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
begin
  inherited Init(Bounds, AHScrollBar, AVScrollBar);
  GrowMode := gfGrowHiX + gfGrowHiY;
  Foc := 0;
end;

constructor TOutlineViewer.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Foc, SizeOf(Foc));
end;

procedure TOutlineViewer.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Foc, SizeOf(Foc));
end;

procedure TOutlineViewer.Adjust(Node: Pointer; Expand: Boolean);
begin
  Abstract;
end;

function TOutlineViewer.GetChild(Node: Pointer; I: Sw_Integer): Pointer;
begin
  Abstract;
  GetChild := nil;
end;

function TOutlineViewer.GetNumChildren(Node: Pointer): Sw_Integer;
begin
  Abstract;
  GetNumChildren := 0;
end;

function TOutlineViewer.GetRoot: Pointer;
begin
  Abstract;
  GetRoot := nil;
end;

function TOutlineViewer.GetText(Node: Pointer): String;
begin
  Abstract;
  GetText := '';
end;

function TOutlineViewer.HasChildren(Node: Pointer): Boolean;
begin
  Abstract;
  HasChildren := False;
end;

function TOutlineViewer.IsExpanded(Node: Pointer): Boolean;
begin
  Abstract;
  IsExpanded := False;
end;

function TOutlineViewer.IsSelected(I: Sw_Integer): Boolean;
begin
  IsSelected := Foc = I;
end;

procedure TOutlineViewer.Focused(I: Sw_Integer);
begin
  Foc := I;
end;

procedure TOutlineViewer.Selected(I: Sw_Integer);
begin
  Message(Owner, evBroadcast, cmOutlineItemSelected, @Self);
end;

function TOutlineViewer.CreateGraph(Level: Integer; Lines: LongInt; Flags: Word; LevWidth, EndWidth: Integer;
  const Chars: String): String;
var
  S: String;
  I, J: Integer;
begin
  S := '';
  for I := 0 to Level - 1 do
  begin
    if Lines and (LongInt(1) shl I) <> 0 then
      S := S + Chars[2]
    else
      S := S + Chars[1];
    for J := 2 to LevWidth do
      S := S + Chars[1];
  end;
  if EndWidth > 0 then
  begin
    if Flags and ovLast <> 0 then
      S := S + Chars[4]
    else
      S := S + Chars[3];
    for J := 3 to EndWidth do
      S := S + Chars[5];
    if Flags and ovChildren <> 0 then
    begin
      if Flags and ovExpanded <> 0 then
        S := S + Chars[8]
      else
        S := S + Chars[7];
    end
    else
      S := S + Chars[6];
  end;
  CreateGraph := S;
end;

function TOutlineViewer.GetGraph(Level: Integer; Lines: LongInt; Flags: Word): String;
begin
  GetGraph := CreateGraph(Level, Lines, Flags, LevelWidth, EndWidth, GraphChars);
end;

function TOutlineViewer.Iterate(Code, Frame: Pointer; CheckResult: Boolean): Pointer;
var
  Position: Sw_Integer;

  function Traverse(Cur: Pointer; Level: Integer; Lines: LongInt; LastChild: Boolean): Pointer;
  var
    J, Count: Sw_Integer;
    Flags: Word;
    Children, Open: Boolean;
    Ret: Pointer;
  begin
    Traverse := nil;
    Flags := 0;
    if LastChild then
      Flags := ovLast;
    Children := HasChildren(Cur);
    Open := Children and IsExpanded(Cur);
    if Children then
      Flags := Flags or ovChildren;
    if not Children or Open then
      Flags := Flags or ovExpanded;
    Inc(Position);
    if CallLocal5(Code, Frame, Cur, Level, Position, Lines, Flags) and CheckResult then
    begin
      Traverse := Cur;
      Exit;
    end;
    if Open then
    begin
      Count := GetNumChildren(Cur);
      if not LastChild then
        Lines := Lines or (LongInt(1) shl Level);
      for J := 0 to Count - 1 do
      begin
        Ret := Traverse(GetChild(Cur, J), Level + 1, Lines, J = Count - 1);
        if Ret <> nil then
        begin
          Traverse := Ret;
          Exit;
        end;
      end;
    end;
  end;

var
  Root: Pointer;
begin
  Iterate := nil;
  Position := -1;
  Root := GetRoot;
  if Root <> nil then
    Iterate := Traverse(Root, 0, 0, True);
end;

{ Test is a function nested in the caller (TP convention):
  function(Node: Pointer; Level, Position: Integer; Lines: LongInt; Flags: Word): Boolean. }
function TOutlineViewer.FirstThat(Test: Pointer): Pointer;
begin
  FirstThat := Iterate(Test, CallerFrame, True);
end;

function TOutlineViewer.ForEach(Action: Pointer): Pointer;
begin
  ForEach := Iterate(Action, CallerFrame, False);
end;

function TOutlineViewer.GetNode(I: Sw_Integer): Pointer;

  function IsNode(Node: Pointer; Level, Position: Integer; Lines: LongInt; Flags: Word): Boolean;
  begin
    IsNode := Position = I;
  end;

begin
  GetNode := Iterate(@IsNode, MyFrame, True);
end;

procedure TOutlineViewer.Draw;
var
  B: TDrawBuffer;
  NormalColor, FocusColor, SelectColor, ClosedColor: Word;
  Y: Sw_Integer;

  function DrawNode(Node: Pointer; Level, Position: Integer; Lines: LongInt; Flags: Word): Boolean;
  var
    S: String;
    Color: Word;
    Past: Boolean;
  begin
    Past := Position >= Delta.Y + Size.Y;
    DrawNode := Past;
    if (Position < Delta.Y) or Past then
      Exit;
    if (Position = Foc) and (State and sfFocused <> 0) then
      Color := FocusColor
    else if IsSelected(Position) then
      Color := SelectColor
    else
      Color := NormalColor;
    MoveChar(B, ' ', Byte(Color), Size.X);
    S := GetGraph(Level, Lines, Flags);
    if Flags and ovExpanded = 0 then
      S := S + '~' + GetText(Node) + '~'
    else
      S := S + GetText(Node);
    MoveCStr(B, Copy(S, Delta.X + 1, 255), (ClosedColor shl 8) or Byte(Color));
    WriteLine(0, Position - Delta.Y, Size.X, 1, B);
    Y := Position - Delta.Y + 1;
  end;

begin
  NormalColor := GetColor(1);
  FocusColor := GetColor(2);
  SelectColor := GetColor(3);
  ClosedColor := GetColor(4);
  Y := 0;
  Iterate(@DrawNode, MyFrame, True);
  MoveChar(B, ' ', Byte(NormalColor), Size.X);
  while Y < Size.Y do
  begin
    WriteLine(0, Y, Size.X, 1, B);
    Inc(Y);
  end;
end;

procedure TOutlineViewer.ExpandAll(Node: Pointer);
var
  I, N: Sw_Integer;
begin
  if (Node <> nil) and HasChildren(Node) then
  begin
    Adjust(Node, True);
    N := GetNumChildren(Node);
    for I := 0 to N - 1 do
      ExpandAll(GetChild(Node, I));
  end;
end;

function TOutlineViewer.GetPalette: PPalette;
const
  P: String[Length(COutlineViewer)] = COutlineViewer;
begin
  GetPalette := @P;
end;

{ Counts the visible lines and their width, then fixes the scroll limits
  and the focused line. }
procedure TOutlineViewer.Update;
var
  Count, MaxX: Sw_Integer;

  function CountNode(Node: Pointer; Level, Position: Integer; Lines: LongInt; Flags: Word): Boolean;
  var
    L: Sw_Integer;
  begin
    Inc(Count);
    L := Length(GetGraph(Level, Lines, Flags)) + Length(GetText(Node));
    if L > MaxX then
      MaxX := L;
    CountNode := False;
  end;

begin
  Count := 0;
  MaxX := 0;
  Iterate(@CountNode, MyFrame, False);
  SetLimit(MaxX, Count);
  if Foc >= Count then
    Foc := Count - 1;
  if Foc < 0 then
    Foc := 0;
  DrawView;
end;

procedure TOutlineViewer.FocusLine(I: Sw_Integer);
begin
  if I >= Limit.Y then
    I := Limit.Y - 1;
  if I < 0 then
    I := 0;
  Focused(I);
  if Foc < Delta.Y then
    ScrollTo(Delta.X, Foc)
  else if Foc >= Delta.Y + Size.Y then
    ScrollTo(Delta.X, Foc - Size.Y + 1);
  DrawView;
end;

procedure TOutlineViewer.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  Node: Pointer;
  Line, GraphLen: Sw_Integer;
  NewFoc: Sw_Integer;

  function FindGraph(N: Pointer; Level, Position: Integer; Lines: LongInt; Flags: Word): Boolean;
  begin
    FindGraph := Position = Line;
    if Position = Line then
      GraphLen := Length(GetGraph(Level, Lines, Flags));
  end;

  procedure Toggle(Expand: Boolean);
  begin
    Node := GetNode(Foc);
    if (Node <> nil) and HasChildren(Node) and (IsExpanded(Node) <> Expand) then
    begin
      Adjust(Node, Expand);
      Update;
    end;
  end;

begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      begin
        MakeLocal(Event.Where, Mouse);
        Line := Mouse.Y + Delta.Y;
        if (Line >= 0) and (Line < Limit.Y) then
        begin
          GraphLen := 0;
          Node := Iterate(@FindGraph, MyFrame, True);
          FocusLine(Line);
          if Event.Double then
            Selected(Foc)
          else if (Node <> nil) and (Mouse.X + Delta.X < GraphLen) and HasChildren(Node) then
          begin
            Adjust(Node, not IsExpanded(Node));
            Update;
          end;
        end;
        repeat
        until not MouseEvent(Event, evMouseMove);
        ClearEvent(Event);
      end;
    evKeyDown:
      begin
        NewFoc := Foc;
        case CtrlToArrow(Event.KeyCode) of
          kbUp: Dec(NewFoc);
          kbDown: Inc(NewFoc);
          kbPgUp: Dec(NewFoc, Size.Y - 1);
          kbPgDn: Inc(NewFoc, Size.Y - 1);
          kbHome: NewFoc := Delta.Y;
          kbEnd: NewFoc := Delta.Y + Size.Y - 1;
          kbCtrlPgUp: NewFoc := 0;
          kbCtrlPgDn: NewFoc := Limit.Y - 1;
          kbRight: Toggle(True);
          kbLeft: Toggle(False);
          kbEnter: Selected(Foc);
        else
          case Event.CharCode of
            '+': Toggle(True);
            '-': Toggle(False);
            '*':
              begin
                ExpandAll(GetNode(Foc));
                Update;
              end;
          else
            Exit;
          end;
        end;
        if NewFoc <> Foc then
          FocusLine(NewFoc);
        ClearEvent(Event);
      end;
  end;
end;

procedure TOutlineViewer.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState and sfFocused <> 0 then
    DrawView;
end;

{ ---- TOutline ---------------------------------------------------------------------------- }

constructor TOutline.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; ARoot: PNode);
begin
  inherited Init(Bounds, AHScrollBar, AVScrollBar);
  Root := ARoot;
  Update;
end;

function LoadNode(var S: TStream): PNode;
var
  P: PNode;
  Flags: Byte;
begin
  New(P);
  P^.Text := S.ReadStr;
  Flags := 0;
  S.Read(Flags, 1);
  P^.Expanded := Flags and 1 <> 0;
  if Flags and 2 <> 0 then
    P^.ChildList := LoadNode(S)
  else
    P^.ChildList := nil;
  if Flags and 4 <> 0 then
    P^.Next := LoadNode(S)
  else
    P^.Next := nil;
  LoadNode := P;
end;

procedure StoreNode(var S: TStream; P: PNode);
var
  Flags: Byte;
begin
  S.WriteStr(P^.Text);
  Flags := Ord(P^.Expanded) or (Ord(P^.ChildList <> nil) shl 1) or (Ord(P^.Next <> nil) shl 2);
  S.Write(Flags, 1);
  if P^.ChildList <> nil then
    StoreNode(S, P^.ChildList);
  if P^.Next <> nil then
    StoreNode(S, P^.Next);
end;

constructor TOutline.Load(var S: TStream);
var
  Has: Byte;
begin
  inherited Load(S);
  Has := 0;
  S.Read(Has, 1);
  if Has <> 0 then
    Root := LoadNode(S)
  else
    Root := nil;
end;

procedure TOutline.Store(var S: TStream);
var
  Has: Byte;
begin
  inherited Store(S);
  Has := Ord(Root <> nil);
  S.Write(Has, 1);
  if Root <> nil then
    StoreNode(S, Root);
end;

destructor TOutline.Done;
begin
  DisposeNode(Root);
  inherited Done;
end;

procedure TOutline.Adjust(Node: Pointer; Expand: Boolean);
begin
  PNode(Node)^.Expanded := Expand;
end;

function TOutline.GetChild(Node: Pointer; I: Sw_Integer): Pointer;
var
  P: PNode;
begin
  P := PNode(Node)^.ChildList;
  while (I > 0) and (P <> nil) do
  begin
    P := P^.Next;
    Dec(I);
  end;
  GetChild := P;
end;

function TOutline.GetNumChildren(Node: Pointer): Sw_Integer;
var
  P: PNode;
  N: Sw_Integer;
begin
  N := 0;
  P := PNode(Node)^.ChildList;
  while P <> nil do
  begin
    Inc(N);
    P := P^.Next;
  end;
  GetNumChildren := N;
end;

function TOutline.GetRoot: Pointer;
begin
  GetRoot := Root;
end;

function TOutline.GetText(Node: Pointer): String;
begin
  if PNode(Node)^.Text = nil then
    GetText := ''
  else
    GetText := PNode(Node)^.Text^;
end;

function TOutline.HasChildren(Node: Pointer): Boolean;
begin
  HasChildren := PNode(Node)^.ChildList <> nil;
end;

function TOutline.IsExpanded(Node: Pointer): Boolean;
begin
  IsExpanded := PNode(Node)^.Expanded;
end;

procedure RegisterOutline;
begin
  RegisterType(ROutline);
end;

end.
