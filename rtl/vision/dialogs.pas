{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Dialogs dari Odin Vision: TDialog dan kontrolnya (tombol, input
  line, cluster, list box, teks, label, riwayat). Implementasi clean-room
  berdasarkan dokumentasi API Turbo Vision TP7.

  Rekaman data (GetData/SetData) mengikuti urutan penyisipan kontrol.
  Ukurannya mengikuti TP7: cluster 2 byte (Word), TMultiCheckBoxes 4
  byte, input line MaxLen + 1, list box TListBoxRec (pointer + Word, 16
  byte di 64-bit), TParamText satu PtrInt per parameter. }
unit Dialogs;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views, Validate;

const
  { Palettes: indexes into the dialog palette, which maps into the
    application palette (gray 32-63, blue 64-95, cyan 96-127). }
  CGrayDialog = #32#33#34#35#36#37#38#39#40#41#42#43#44#45#46#47 +
    #48#49#50#51#52#53#54#55#56#57#58#59#60#61#62#63;
  CBlueDialog = #64#65#66#67#68#69#70#71#72#73#74#75#76#77#78#79 +
    #80#81#82#83#84#85#86#87#88#89#90#91#92#93#94#95;
  CCyanDialog = #96#97#98#99#100#101#102#103#104#105#106#107#108#109#110#111 +
    #112#113#114#115#116#117#118#119#120#121#122#123#124#125#126#127;
  CDialog = CGrayDialog;
  CStaticText = #6;
  CLabel = #7#8#9#9;
  CButton = #10#11#12#13#14#14#14#15;
  CCluster = #16#17#18#18#31;
  CInputLine = #19#19#20#21;
  CHistory = #22#23;
  CHistoryWindow = #19#19#21#24#25#19#20;
  CHistoryViewer = #6#6#7#6#6;

  dpBlueDialog = 0;
  dpCyanDialog = 1;
  dpGrayDialog = 2;

  bfNormal = $00;
  bfDefault = $01;
  bfLeftJust = $02;
  bfBroadcast = $04;
  bfGrabFocus = $08;

  cfOneBit = $0101;
  cfTwoBits = $0203;
  cfFourBits = $040F;
  cfEightBits = $08FF;

  cmRecordHistory = 60;
  cmGrabDefault = 61;
  cmReleaseDefault = 62;

type
  PDialog = ^TDialog;
  TDialog = object(TWindow)
    constructor Init(var Bounds: TRect; ATitle: TTitleStr);
    constructor Load(var S: TStream);
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function Valid(Command: Word): Boolean; virtual;
  end;

  PSItem = ^TSItem;
  TSItem = record
    Value: PString;
    Next: PSItem;
  end;

  PInputLine = ^TInputLine;
  TInputLine = object(TView)
    Data: PString;
    MaxLen: Sw_Integer;
    CurPos: Sw_Integer;
    FirstPos: Sw_Integer;
    SelStart: Sw_Integer;
    SelEnd: Sw_Integer;
    Validator: PValidator;
    constructor Init(var Bounds: TRect; AMaxLen: Sw_Integer);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    function DataSize: Word; virtual;
    procedure Draw; virtual;
    procedure GetData(var Rec); virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SelectAll(Enable: Boolean);
    procedure SetData(var Rec); virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure SetValidator(AValid: PValidator);
    procedure Store(var S: TStream);
    function Valid(Command: Word): Boolean; virtual;
    { Odin: helpers. }
    function CanScroll(Delta: Sw_Integer): Boolean;
    function MousePos(var Event: TEvent): Sw_Integer;
    procedure DeleteSelect;
  end;

  PButton = ^TButton;
  TButton = object(TView)
    Title: PString;
    Command: Word;
    Flags: Byte;
    AmDefault: Boolean;
    constructor Init(var Bounds: TRect; ATitle: TTitleStr; ACommand: Word; AFlags: Word);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Draw; virtual;
    procedure DrawState(Down: Boolean);
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure MakeDefault(Enable: Boolean);
    procedure Press; virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
  end;

  PCluster = ^TCluster;
  TCluster = object(TView)
    Value: LongInt;
    Sel: Sw_Integer;
    EnableMask: LongInt;
    Strings: TStringCollection;
    constructor Init(var Bounds: TRect; AStrings: PSItem);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    function ButtonState(Item: Sw_Integer): Boolean;
    function DataSize: Word; virtual;
    procedure DrawBox(const Icon: String; Marker: Char);
    procedure DrawMultiBox(const Icon, Marker: String);
    procedure GetData(var Rec); virtual;
    function GetHelpCtx: Word; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function Mark(Item: Sw_Integer): Boolean; virtual;
    function MultiMark(Item: Sw_Integer): Byte; virtual;
    procedure Press(Item: Sw_Integer); virtual;
    procedure MovedTo(Item: Sw_Integer); virtual;
    procedure SetButtonState(AMask: LongInt; Enable: Boolean);
    procedure SetData(var Rec); virtual;
    procedure SetState(AState: Word; Enable: Boolean); virtual;
    procedure Store(var S: TStream);
    { Odin: layout helpers. }
    function Column(Item: Sw_Integer): Sw_Integer;
    function FindSel(P: TPoint): Sw_Integer;
    function Row(Item: Sw_Integer): Sw_Integer;
    function ItemText(Item: Sw_Integer): String;
  end;

  PRadioButtons = ^TRadioButtons;
  TRadioButtons = object(TCluster)
    procedure Draw; virtual;
    function Mark(Item: Sw_Integer): Boolean; virtual;
    procedure MovedTo(Item: Sw_Integer); virtual;
    procedure Press(Item: Sw_Integer); virtual;
    procedure SetData(var Rec); virtual;
  end;

  PCheckBoxes = ^TCheckBoxes;
  TCheckBoxes = object(TCluster)
    procedure Draw; virtual;
    function Mark(Item: Sw_Integer): Boolean; virtual;
    procedure Press(Item: Sw_Integer); virtual;
  end;

  PMultiCheckBoxes = ^TMultiCheckBoxes;
  TMultiCheckBoxes = object(TCluster)
    SelRange: Byte;
    Flags: Word;
    States: PString;
    constructor Init(var Bounds: TRect; AStrings: PSItem; ASelRange: Byte; AFlags: Word; const AStates: String);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    function DataSize: Word; virtual;
    procedure Draw; virtual;
    procedure GetData(var Rec); virtual;
    function MultiMark(Item: Sw_Integer): Byte; virtual;
    procedure Press(Item: Sw_Integer); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
  end;

  TListBoxRec = record
    List: PCollection;
    Selection: Word;
  end;

  PListBox = ^TListBox;
  TListBox = object(TListViewer)
    List: PCollection;
    constructor Init(var Bounds: TRect; ANumCols: Word; AScrollBar: PScrollBar);
    constructor Load(var S: TStream);
    function DataSize: Word; virtual;
    procedure GetData(var Rec); virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    procedure NewList(AList: PCollection); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
  end;

  PStaticText = ^TStaticText;
  TStaticText = object(TView)
    Text: PString;
    constructor Init(var Bounds: TRect; const AText: String);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure GetText(var S: String); virtual;
    procedure Store(var S: TStream);
  end;

  PParamText = ^TParamText;
  TParamText = object(TStaticText)
    ParamCount: Sw_Integer;
    ParamList: Pointer;
    constructor Init(var Bounds: TRect; const AText: String; AParamCount: Sw_Integer);
    constructor Load(var S: TStream);
    function DataSize: Word; virtual;
    procedure GetText(var S: String); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
  end;

  PLabel = ^TLabel;
  TLabel = object(TStaticText)
    Link: PView;
    Light: Boolean;
    constructor Init(var Bounds: TRect; const AText: String; ALink: PView);
    constructor Load(var S: TStream);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure Store(var S: TStream);
  end;

  PHistoryViewer = ^THistoryViewer;
  THistoryViewer = object(TListViewer)
    HistoryId: Word;
    constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; AHistoryId: Word);
    function GetPalette: PPalette; virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function HistoryWidth: Sw_Integer;
  end;

  PHistoryWindow = ^THistoryWindow;
  THistoryWindow = object(TWindow)
    Viewer: PListViewer;
    constructor Init(var Bounds: TRect; HistoryId: Word);
    function GetPalette: PPalette; virtual;
    function GetSelection: String; virtual;
    procedure InitViewer(HistoryId: Word); virtual;
  end;

  PHistory = ^THistory;
  THistory = object(TView)
    Link: PInputLine;
    HistoryId: Word;
    constructor Init(var Bounds: TRect; ALink: PInputLine; AHistoryId: Word);
    constructor Load(var S: TStream);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function InitHistoryWindow(var Bounds: TRect): PHistoryWindow; virtual;
    procedure RecordHistory(const S: String); virtual;
    procedure Store(var S: TStream);
  end;

function NewSItem(const Str: String; ANext: PSItem): PSItem;
procedure RegisterDialogs;

const
  RDialog: TStreamRec = (ObjType: 10; VmtLink: Ofs(TypeOf(TDialog)^); Load: @TDialog.Load; Store: @TDialog.Store);
  RInputLine: TStreamRec = (ObjType: 11; VmtLink: Ofs(TypeOf(TInputLine)^); Load: @TInputLine.Load;
    Store: @TInputLine.Store);
  RButton: TStreamRec = (ObjType: 12; VmtLink: Ofs(TypeOf(TButton)^); Load: @TButton.Load; Store: @TButton.Store);
  RCluster: TStreamRec = (ObjType: 13; VmtLink: Ofs(TypeOf(TCluster)^); Load: @TCluster.Load;
    Store: @TCluster.Store);
  RRadioButtons: TStreamRec = (ObjType: 14; VmtLink: Ofs(TypeOf(TRadioButtons)^); Load: @TRadioButtons.Load;
    Store: @TRadioButtons.Store);
  RCheckBoxes: TStreamRec = (ObjType: 15; VmtLink: Ofs(TypeOf(TCheckBoxes)^); Load: @TCheckBoxes.Load;
    Store: @TCheckBoxes.Store);
  RListBox: TStreamRec = (ObjType: 16; VmtLink: Ofs(TypeOf(TListBox)^); Load: @TListBox.Load;
    Store: @TListBox.Store);
  RStaticText: TStreamRec = (ObjType: 17; VmtLink: Ofs(TypeOf(TStaticText)^); Load: @TStaticText.Load;
    Store: @TStaticText.Store);
  RLabel: TStreamRec = (ObjType: 18; VmtLink: Ofs(TypeOf(TLabel)^); Load: @TLabel.Load; Store: @TLabel.Store);
  RHistory: TStreamRec = (ObjType: 19; VmtLink: Ofs(TypeOf(THistory)^); Load: @THistory.Load;
    Store: @THistory.Store);
  RParamText: TStreamRec = (ObjType: 20; VmtLink: Ofs(TypeOf(TParamText)^); Load: @TParamText.Load;
    Store: @TParamText.Store);
  RMultiCheckBoxes: TStreamRec = (ObjType: 27; VmtLink: Ofs(TypeOf(TMultiCheckBoxes)^);
    Load: @TMultiCheckBoxes.Load; Store: @TMultiCheckBoxes.Store);

implementation

uses HistList;

{ The highlighted (~X~) character of a title, upper case, or #0. }
function HotKey(const S: String): Char;
var
  I: Integer;
begin
  HotKey := #0;
  I := Pos('~', S);
  if (I > 0) and (I < Length(S)) then
    HotKey := UpCase(S[I + 1]);
end;

function NewSItem(const Str: String; ANext: PSItem): PSItem;
var
  Item: PSItem;
begin
  New(Item);
  Item^.Value := NewStr(Str);
  Item^.Next := ANext;
  NewSItem := Item;
end;

{ ---- TDialog ---------------------------------------------------------------------- }

constructor TDialog.Init(var Bounds: TRect; ATitle: TTitleStr);
begin
  inherited Init(Bounds, ATitle, wnNoNumber);
  GrowMode := 0;
  Flags := wfMove + wfClose;
  Palette := dpGrayDialog;
end;

constructor TDialog.Load(var S: TStream);
begin
  inherited Load(S);
end;

function TDialog.GetPalette: PPalette;
const
  P: array[dpBlueDialog..dpGrayDialog] of String[Length(CBlueDialog)] = (CBlueDialog, CCyanDialog, CGrayDialog);
begin
  GetPalette := @P[Palette];
end;

procedure TDialog.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  case Event.What of
    evKeyDown:
      case Event.KeyCode of
        kbEsc:
          begin
            Event.What := evCommand;
            Event.Command := cmCancel;
            Event.InfoPtr := nil;
            PutEvent(Event);
            ClearEvent(Event);
          end;
        kbEnter:
          begin
            Event.What := evBroadcast;
            Event.Command := cmDefault;
            Event.InfoPtr := nil;
            PutEvent(Event);
            ClearEvent(Event);
          end;
      end;
    evCommand:
      case Event.Command of
        cmOK, cmCancel, cmYes, cmNo:
          if State and sfModal <> 0 then
          begin
            EndModal(Event.Command);
            ClearEvent(Event);
          end;
      end;
  end;
end;

function TDialog.Valid(Command: Word): Boolean;
begin
  if Command = cmCancel then
    Valid := True
  else
    Valid := inherited Valid(Command);
end;

{ ---- TInputLine -------------------------------------------------------------------- }

constructor TInputLine.Init(var Bounds: TRect; AMaxLen: Sw_Integer);
begin
  inherited Init(Bounds);
  State := State or sfCursorVis;
  Options := Options or (ofSelectable + ofFirstClick);
  if AMaxLen > 255 then
    AMaxLen := 255;
  if AMaxLen < 0 then
    AMaxLen := 0;
  GetMem(Data, AMaxLen + 1);
  Data^ := '';
  MaxLen := AMaxLen;
end;

constructor TInputLine.Load(var S: TStream);
var
  T: PString;
begin
  inherited Load(S);
  S.Read(MaxLen, SizeOf(Sw_Integer) * 5);
  GetMem(Data, MaxLen + 1);
  T := S.ReadStr;
  if T <> nil then
  begin
    Data^ := Copy(T^, 1, MaxLen);
    DisposeStr(T);
  end
  else
    Data^ := '';
  Validator := PValidator(S.Get);
end;

procedure TInputLine.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(MaxLen, SizeOf(Sw_Integer) * 5);
  S.WriteStr(Data);
  S.Put(Validator);
end;

destructor TInputLine.Done;
begin
  FreeMem(Data, MaxLen + 1);
  SetValidator(nil);
  inherited Done;
end;

function TInputLine.CanScroll(Delta: Sw_Integer): Boolean;
begin
  if Delta < 0 then
    CanScroll := FirstPos > 0
  else if Delta > 0 then
    CanScroll := Length(Data^) - FirstPos + 2 > Size.X
  else
    CanScroll := False;
end;

function TInputLine.DataSize: Word;
var
  N: Word;
  S: String;
begin
  N := 0;
  if Validator <> nil then
  begin
    S := Data^;
    N := Validator^.Transfer(S, nil, vtDataSize);
  end;
  if N = 0 then
    N := MaxLen + 1;
  DataSize := N;
end;

procedure TInputLine.Draw;
var
  B: TDrawBuffer;
  Color: Byte;
  L, R: Sw_Integer;
begin
  if State and sfFocused = 0 then
    Color := GetColor(1)
  else
    Color := GetColor(2);
  MoveChar(B, ' ', Color, Size.X);
  MoveStr(B[1], Copy(Data^, FirstPos + 1, Size.X - 2), Color);
  if CanScroll(1) then
    MoveChar(B[Size.X - 1], #16, GetColor(4), 1);
  if State and sfFocused <> 0 then
  begin
    if CanScroll(-1) then
      MoveChar(B[0], #17, GetColor(4), 1);
    L := SelStart - FirstPos;
    R := SelEnd - FirstPos;
    if L < 0 then
      L := 0;
    if R > Size.X - 2 then
      R := Size.X - 2;
    if L < R then
      MoveChar(B[L + 1], #0, GetColor(3), R - L);
  end;
  WriteLine(0, 0, Size.X, Size.Y, B);
  SetCursor(CurPos - FirstPos + 1, 0);
end;

procedure TInputLine.GetData(var Rec);
var
  S: String;
begin
  S := Data^;
  if (Validator = nil) or (Validator^.Transfer(S, @Rec, vtGetData) = 0) then
    Move(Data^, Rec, DataSize);
end;

function TInputLine.GetPalette: PPalette;
const
  P: String[Length(CInputLine)] = CInputLine;
begin
  GetPalette := @P;
end;

function TInputLine.MousePos(var Event: TEvent): Sw_Integer;
var
  Mouse: TPoint;
  Pos: Sw_Integer;
begin
  MakeLocal(Event.Where, Mouse);
  if Mouse.X < 1 then
    Mouse.X := 1;
  Pos := Mouse.X + FirstPos - 1;
  if Pos < 0 then
    Pos := 0;
  if Pos > Length(Data^) then
    Pos := Length(Data^);
  MousePos := Pos;
end;

procedure TInputLine.DeleteSelect;
begin
  if SelStart < SelEnd then
  begin
    Delete(Data^, SelStart + 1, SelEnd - SelStart);
    CurPos := SelStart;
  end;
end;

procedure TInputLine.HandleEvent(var Event: TEvent);
const
  PadKeys = [$47, $4B, $4D, $4F, $73, $74];
var
  Delta, Anchor, OldCurPos, OldFirstPos, OldSelStart, OldSelEnd: Sw_Integer;
  ExtendBlock, WasAppending, Rejected: Boolean;
  OldData: String;
  Key: Word;

  procedure SaveState;
  begin
    if Validator <> nil then
    begin
      OldData := Data^;
      OldCurPos := CurPos;
      OldFirstPos := FirstPos;
      OldSelStart := SelStart;
      OldSelEnd := SelEnd;
      WasAppending := Length(Data^) = CurPos;
    end;
  end;

  procedure RestoreState;
  begin
    if Validator <> nil then
    begin
      Data^ := OldData;
      CurPos := OldCurPos;
      FirstPos := OldFirstPos;
      SelStart := OldSelStart;
      SelEnd := OldSelEnd;
      Rejected := True;
    end;
  end;

  function CheckValid(NoAutoFill: Boolean): Boolean;
  var
    NewData: String;
    OldLen: Sw_Integer;
  begin
    CheckValid := True;
    if Validator = nil then
      Exit;
    OldLen := Length(Data^);
    if (Validator^.Options and voOnAppend = 0) or (WasAppending and (CurPos = OldLen)) then
    begin
      NewData := Data^;
      if not Validator^.IsValidInput(NewData, NoAutoFill) then
      begin
        RestoreState;
        CheckValid := False;
      end
      else
      begin
        if Length(NewData) > MaxLen then
          NewData[0] := Chr(MaxLen);
        Data^ := NewData;
        if (CurPos >= OldLen) and (Length(Data^) > OldLen) then
          CurPos := Length(Data^);
      end;
    end;
  end;

  procedure AdjustSelectBlock;
  begin
    if CurPos < Anchor then
    begin
      SelStart := CurPos;
      SelEnd := Anchor;
    end
    else
    begin
      SelStart := Anchor;
      SelEnd := CurPos;
    end;
  end;

begin
  inherited HandleEvent(Event);
  if State and sfSelected = 0 then
    Exit;
  case Event.What of
    evMouseDown:
      begin
        Delta := 0;
        if CanScroll(-1) and (Event.Where.X <= Origin.X) then
          Delta := -1;
        if Event.Double then
          SelectAll(True)
        else
        begin
          Anchor := MousePos(Event);
          repeat
            if Event.What = evMouseAuto then
            begin
              MakeLocal(Event.Where, Event.Where);
              if (Event.Where.X <= 0) and CanScroll(-1) then
                Dec(FirstPos)
              else if (Event.Where.X >= Size.X - 1) and CanScroll(1) then
                Inc(FirstPos);
              MakeGlobal(Event.Where, Event.Where);
            end;
            CurPos := MousePos(Event);
            AdjustSelectBlock;
            DrawView;
          until not MouseEvent(Event, evMouseMove + evMouseAuto);
        end;
        ClearEvent(Event);
      end;
    evKeyDown:
      begin
        SaveState;
        Rejected := False;
        Key := CtrlToArrow(Event.KeyCode);
        ExtendBlock := False;
        if (Event.ScanCode in PadKeys) and (GetShiftState and (kbRightShift + kbLeftShift) <> 0) then
        begin
          Event.CharCode := #0;
          if CurPos = SelEnd then
            Anchor := SelStart
          else
            Anchor := SelEnd;
          ExtendBlock := True;
        end;
        case Key of
          kbLeft:
            if CurPos > 0 then
              Dec(CurPos);
          kbRight:
            if CurPos < Length(Data^) then
              Inc(CurPos);
          kbHome:
            CurPos := 0;
          kbEnd:
            CurPos := Length(Data^);
          kbBack:
            if CurPos > 0 then
            begin
              if SelStart < SelEnd then
                DeleteSelect
              else
              begin
                Delete(Data^, CurPos, 1);
                Dec(CurPos);
              end;
              if FirstPos > 0 then
                Dec(FirstPos);
              CheckValid(True);
            end
            else if SelStart < SelEnd then
            begin
              DeleteSelect;
              CheckValid(True);
            end;
          kbDel:
            begin
              if SelStart = SelEnd then
                if CurPos < Length(Data^) then
                begin
                  SelStart := CurPos;
                  SelEnd := CurPos + 1;
                end;
              DeleteSelect;
              CheckValid(True);
            end;
          kbIns:
            SetState(sfCursorIns, State and sfCursorIns = 0);
        else
          if Event.CharCode >= ' ' then
          begin
            DeleteSelect;
            { Typing over a selection that reaches the end appends. }
            WasAppending := CurPos = Length(Data^);
            if State and sfCursorIns <> 0 then
              Delete(Data^, CurPos + 1, 1);
            if CheckValid(True) then
            begin
              if Length(Data^) < MaxLen then
              begin
                if FirstPos > CurPos then
                  FirstPos := CurPos;
                Inc(CurPos);
                Insert(Event.CharCode, Data^, CurPos);
              end;
              CheckValid(False);
            end;
          end
          else if Event.CharCode = ^Y then
          begin
            Data^ := '';
            CurPos := 0;
          end
          else
            Exit;
        end;
        if Rejected then
          { The validator refused the key: the line stays as it was. }
        else if ExtendBlock then
          AdjustSelectBlock
        else
        begin
          SelStart := CurPos;
          SelEnd := CurPos;
        end;
        if FirstPos > CurPos then
          FirstPos := CurPos;
        if CurPos - FirstPos > Size.X - 2 then
          FirstPos := CurPos - Size.X + 2;
        if FirstPos < 0 then
          FirstPos := 0;
        DrawView;
        ClearEvent(Event);
      end;
  end;
end;

procedure TInputLine.SelectAll(Enable: Boolean);
begin
  CurPos := 0;
  FirstPos := 0;
  SelStart := 0;
  if Enable then
    SelEnd := Length(Data^)
  else
    SelEnd := 0;
  DrawView;
end;

procedure TInputLine.SetData(var Rec);
var
  S: String;
begin
  if (Validator = nil) or (Validator^.Transfer(S, @Rec, vtSetData) = 0) then
  begin
    Move(Rec, Data^, DataSize);
    if Length(Data^) > MaxLen then
      Data^[0] := Chr(MaxLen);
  end
  else
    Data^ := Copy(S, 1, MaxLen);
  SelectAll(True);
end;

procedure TInputLine.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if (AState = sfSelected) or ((AState = sfActive) and (State and sfSelected <> 0)) then
    SelectAll(Enable)
  else if AState = sfFocused then
    DrawView;
end;

procedure TInputLine.SetValidator(AValid: PValidator);
begin
  if Validator <> nil then
    Dispose(Validator, Done);
  Validator := AValid;
end;

function TInputLine.Valid(Command: Word): Boolean;
begin
  Valid := inherited Valid(Command);
  if (Validator <> nil) and (State and sfDisabled = 0) then
    if Command = cmValid then
      Valid := Validator^.Status = vsOk
    else if Command <> cmCancel then
      if not Validator^.Valid(Data^) then
      begin
        Select;
        Valid := False;
      end;
end;

{ ---- TButton ----------------------------------------------------------------------- }

constructor TButton.Init(var Bounds: TRect; ATitle: TTitleStr; ACommand: Word; AFlags: Word);
begin
  inherited Init(Bounds);
  Options := Options or (ofSelectable + ofFirstClick + ofPreProcess + ofPostProcess);
  EventMask := EventMask or evBroadcast;
  if not CommandEnabled(ACommand) then
    State := State or sfDisabled;
  Flags := AFlags;
  AmDefault := AFlags and bfDefault <> 0;
  Title := NewStr(ATitle);
  Command := ACommand;
end;

constructor TButton.Load(var S: TStream);
begin
  inherited Load(S);
  Title := S.ReadStr;
  S.Read(Command, SizeOf(Command));
  S.Read(Flags, SizeOf(Flags));
  S.Read(AmDefault, SizeOf(AmDefault));
  if not CommandEnabled(Command) then
    State := State or sfDisabled
  else
    State := State and not sfDisabled;
end;

procedure TButton.Store(var S: TStream);
begin
  inherited Store(S);
  S.WriteStr(Title);
  S.Write(Command, SizeOf(Command));
  S.Write(Flags, SizeOf(Flags));
  S.Write(AmDefault, SizeOf(AmDefault));
end;

destructor TButton.Done;
begin
  DisposeStr(Title);
  inherited Done;
end;

procedure TButton.Draw;
begin
  DrawState(False);
end;

{ The face takes all but the last column and row; the shadow fills the
  rest. A pressed button moves one cell right and loses its shadow. }
procedure TButton.DrawState(Down: Boolean);
var
  B: TDrawBuffer;
  CButton, CShadow: Word;
  W, Y, Mid, X, L, I: Sw_Integer;
begin
  if State and sfDisabled <> 0 then
    CButton := GetColor($0404)
  else
  begin
    CButton := GetColor($0501);
    if State and sfActive <> 0 then
      if State and sfSelected <> 0 then
        CButton := GetColor($0703)
      else if AmDefault then
        CButton := GetColor($0602);
  end;
  CShadow := GetColor(8);
  W := Size.X;
  if Down then
    I := 1
  else
    I := 0;
  Mid := (Size.Y - 1) div 2;
  if Size.Y = 1 then
    Mid := 0;
  for Y := 0 to Size.Y - 1 do
  begin
    MoveChar(B, ' ', Byte(CShadow), W);
    if (Y < Size.Y - 1) or (Size.Y = 1) then
    begin
      MoveChar(B[I], ' ', Byte(CButton), W - 1);
      if not Down then
        if Y = 0 then
          MoveChar(B[W - 1], #220, Byte(CShadow), 1)
        else
          MoveChar(B[W - 1], #219, Byte(CShadow), 1);
      if (Y = Mid) and (Title <> nil) then
      begin
        L := CStrLen(Title^);
        if Flags and bfLeftJust <> 0 then
          X := I + 1
        else
          X := I + (W - 1 - L) div 2;
        if X < I then
          X := I;
        MoveCStr(B[X], Title^, CButton);
        if ShowMarkers and (State and sfSelected <> 0) then
        begin
          MoveChar(B[I], #16, 0, 1);
          MoveChar(B[I + W - 2], #17, 0, 1);
        end;
      end;
    end
    else if not Down then
      MoveChar(B[1], #223, Byte(CShadow), W - 1);
    WriteLine(0, Y, W, 1, B);
  end;
end;

function TButton.GetPalette: PPalette;
const
  P: String[Length(CButton)] = CButton;
begin
  GetPalette := @P;
end;

procedure TButton.HandleEvent(var Event: TEvent);
var
  Down: Boolean;
  C: Char;
  Mouse: TPoint;
  ClickRect: TRect;
begin
  GetExtent(ClickRect);
  Inc(ClickRect.A.X);
  Dec(ClickRect.B.X);
  Dec(ClickRect.B.Y);
  if Event.What = evMouseDown then
  begin
    MakeLocal(Event.Where, Mouse);
    if not ClickRect.Contains(Mouse) then
      ClearEvent(Event);
  end;
  if Flags and bfGrabFocus <> 0 then
    inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      begin
        if State and sfDisabled = 0 then
        begin
          Down := False;
          repeat
            MakeLocal(Event.Where, Mouse);
            if Down <> ClickRect.Contains(Mouse) then
            begin
              Down := not Down;
              DrawState(Down);
            end;
          until not MouseEvent(Event, evMouseMove);
          if Down then
          begin
            Press;
            DrawState(False);
          end;
        end;
        ClearEvent(Event);
      end;
    evKeyDown:
      begin
        if Title <> nil then
          C := HotKey(Title^)
        else
          C := #0;
        if ((C <> #0) and (Event.KeyCode = GetAltCode(C))) or
          ((Owner^.Phase = phPostProcess) and (C <> #0) and (UpCase(Event.CharCode) = C)) or
          ((State and sfFocused <> 0) and (Event.CharCode = ' ')) then
        begin
          if State and sfDisabled = 0 then
            Press;
          ClearEvent(Event);
        end;
      end;
    evBroadcast:
      case Event.Command of
        cmDefault:
          if AmDefault and (State and sfDisabled = 0) then
          begin
            Press;
            ClearEvent(Event);
          end;
        cmGrabDefault, cmReleaseDefault:
          if Flags and bfDefault <> 0 then
          begin
            AmDefault := Event.Command = cmReleaseDefault;
            DrawView;
          end;
        cmCommandSetChanged:
          if ((State and sfDisabled <> 0) and CommandEnabled(Command)) or
            ((State and sfDisabled = 0) and not CommandEnabled(Command)) then
          begin
            SetState(sfDisabled, not CommandEnabled(Command));
            DrawView;
          end;
      end;
  end;
end;

procedure TButton.MakeDefault(Enable: Boolean);
var
  C: Word;
begin
  if Flags and bfDefault = 0 then
  begin
    if Enable then
      C := cmGrabDefault
    else
      C := cmReleaseDefault;
    Message(Owner, evBroadcast, C, @Self);
    AmDefault := Enable;
    DrawView;
  end;
end;

procedure TButton.Press;
var
  E: TEvent;
begin
  Message(Owner, evBroadcast, cmRecordHistory, nil);
  if Flags and bfBroadcast <> 0 then
    Message(Owner, evBroadcast, Command, @Self)
  else
  begin
    E.What := evCommand;
    E.Command := Command;
    E.InfoPtr := @Self;
    PutEvent(E);
  end;
end;

procedure TButton.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState and (sfSelected + sfActive) <> 0 then
    DrawView;
  if AState and sfFocused <> 0 then
    MakeDefault(Enable);
end;

{ ---- TCluster ------------------------------------------------------------------------ }

constructor TCluster.Init(var Bounds: TRect; AStrings: PSItem);
var
  I: Sw_Integer;
  P, Q: PSItem;
begin
  inherited Init(Bounds);
  Options := Options or (ofSelectable + ofFirstClick + ofPreProcess + ofPostProcess);
  I := 0;
  P := AStrings;
  while P <> nil do
  begin
    Inc(I);
    P := P^.Next;
  end;
  Strings.Init(I, 0);
  while AStrings <> nil do
  begin
    P := AStrings;
    Strings.AtInsert(Strings.Count, AStrings^.Value);
    AStrings := AStrings^.Next;
    Q := P;
    Dispose(Q);
  end;
  Value := 0;
  Sel := 0;
  EnableMask := -1;
  SetCursor(2, 0);
  ShowCursor;
end;

constructor TCluster.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Value, SizeOf(Value));
  S.Read(Sel, SizeOf(Sel));
  S.Read(EnableMask, SizeOf(EnableMask));
  Strings.Load(S);
  SetButtonState(0, True);
end;

procedure TCluster.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Value, SizeOf(Value));
  S.Write(Sel, SizeOf(Sel));
  S.Write(EnableMask, SizeOf(EnableMask));
  Strings.Store(S);
end;

destructor TCluster.Done;
begin
  Strings.Done;
  inherited Done;
end;

function TCluster.ButtonState(Item: Sw_Integer): Boolean;
begin
  if (Item < 0) or (Item > 31) then
    ButtonState := False
  else
    ButtonState := EnableMask and (LongInt(1) shl Item) <> 0;
end;

function TCluster.DataSize: Word;
begin
  DataSize := SizeOf(Word);
end;

function TCluster.ItemText(Item: Sw_Integer): String;
var
  P: PString;
begin
  P := PString(Strings.At(Item));
  if P = nil then
    ItemText := ''
  else
    ItemText := P^;
end;

{ X of the column holding Item: columns hold Size.Y items each and are as
  wide as their longest text plus the box. }
function TCluster.Column(Item: Sw_Integer): Sw_Integer;
var
  I, Col, Width, L: Sw_Integer;
begin
  if Item < Size.Y then
  begin
    Column := 0;
    Exit;
  end;
  Width := 0;
  Col := -6;
  for I := 0 to Item do
  begin
    if I mod Size.Y = 0 then
    begin
      Inc(Col, Width + 6);
      Width := 0;
    end;
    if I < Strings.Count then
    begin
      L := CStrLen(ItemText(I));
      if L > Width then
        Width := L;
    end;
  end;
  Column := Col;
end;

function TCluster.Row(Item: Sw_Integer): Sw_Integer;
begin
  Row := Item mod Size.Y;
end;

function TCluster.FindSel(P: TPoint): Sw_Integer;
var
  R: TRect;
  I, S: Sw_Integer;
begin
  GetExtent(R);
  FindSel := -1;
  if not R.Contains(P) then
    Exit;
  I := 0;
  while (I < Strings.Count - 1) and (P.X >= Column(I + Size.Y)) do
    Inc(I, Size.Y);
  S := I + P.Y;
  if S < Strings.Count then
    FindSel := S;
end;

procedure TCluster.DrawBox(const Icon: String; Marker: Char);
begin
  DrawMultiBox(Icon, ' ' + Marker);
end;

procedure TCluster.DrawMultiBox(const Icon, Marker: String);
var
  B: TDrawBuffer;
  I, J, Cur, Col, Next: Sw_Integer;
  CNorm, CSel, CDis, Color: Word;
begin
  CNorm := GetColor($0301);
  CSel := GetColor($0402);
  CDis := GetColor($0505);
  for I := 0 to Size.Y - 1 do
  begin
    MoveChar(B, ' ', Byte(CNorm), Size.X);
    for J := 0 to (Strings.Count - 1) div Size.Y do
    begin
      Cur := J * Size.Y + I;
      if Cur < Strings.Count then
      begin
        Col := Column(Cur);
        if Col < Size.X then
        begin
          if not ButtonState(Cur) then
            Color := CDis
          else if (Cur = Sel) and (State and sfFocused <> 0) then
            Color := CSel
          else
            Color := CNorm;
          Next := Column(Cur + Size.Y);
          if (Next > Size.X) or (Cur + Size.Y >= Strings.Count) then
            Next := Size.X;
          MoveChar(B[Col], ' ', Byte(Color), Next - Col);
          MoveStr(B[Col], Icon, Byte(Color));
          MoveChar(B[Col + 2], Marker[MultiMark(Cur) + 1], Byte(Color), 1);
          if Col + 5 < Size.X then
            MoveCStr(B[Col + 5], Copy(ItemText(Cur), 1, Size.X - Col - 5), Color);
          if ShowMarkers and (State and sfFocused <> 0) and (Cur = Sel) then
          begin
            MoveChar(B[Col], #16, 0, 1);
            if Next - 1 > Col then
              MoveChar(B[Next - 1], #17, 0, 1);
          end;
        end;
      end;
    end;
    WriteBuf(0, I, Size.X, 1, B);
  end;
  SetCursor(Column(Sel) + 2, Row(Sel));
end;

procedure TCluster.GetData(var Rec);
begin
  Word(Rec) := Word(Value);
end;

function TCluster.GetHelpCtx: Word;
begin
  if HelpCtx = hcNoContext then
    GetHelpCtx := hcNoContext
  else
    GetHelpCtx := HelpCtx + Sel;
end;

function TCluster.GetPalette: PPalette;
const
  P: String[Length(CCluster)] = CCluster;
begin
  GetPalette := @P;
end;

procedure TCluster.HandleEvent(var Event: TEvent);
var
  Mouse: TPoint;
  I, S: Sw_Integer;
  C: Char;

  procedure MoveSel(NewSel: Sw_Integer);
  begin
    if (NewSel >= 0) and (NewSel < Strings.Count) and ButtonState(NewSel) then
    begin
      Sel := NewSel;
      MovedTo(Sel);
      DrawView;
    end;
  end;

begin
  inherited HandleEvent(Event);
  if Options and ofSelectable = 0 then
    Exit;
  case Event.What of
    evMouseDown:
      begin
        MakeLocal(Event.Where, Mouse);
        I := FindSel(Mouse);
        if (I <> -1) and ButtonState(I) then
          Sel := I;
        DrawView;
        repeat
          MakeLocal(Event.Where, Mouse);
          S := FindSel(Mouse);
          if (S <> -1) and ButtonState(S) and (S <> Sel) then
          begin
            Sel := S;
            DrawView;
          end;
        until not MouseEvent(Event, evMouseMove);
        MakeLocal(Event.Where, Mouse);
        if (FindSel(Mouse) = Sel) and ButtonState(Sel) then
        begin
          Press(Sel);
          DrawView;
        end;
        ClearEvent(Event);
      end;
    evKeyDown:
      begin
        if State and sfFocused <> 0 then
          case CtrlToArrow(Event.KeyCode) of
            kbUp:
              begin
                S := Sel;
                repeat
                  Dec(S);
                  if S < 0 then
                    S := Strings.Count - 1;
                until ButtonState(S) or (S = Sel);
                MoveSel(S);
                ClearEvent(Event);
                Exit;
              end;
            kbDown:
              begin
                S := Sel;
                repeat
                  Inc(S);
                  if S >= Strings.Count then
                    S := 0;
                until ButtonState(S) or (S = Sel);
                MoveSel(S);
                ClearEvent(Event);
                Exit;
              end;
            kbRight:
              begin
                MoveSel(Sel + Size.Y);
                ClearEvent(Event);
                Exit;
              end;
            kbLeft:
              begin
                MoveSel(Sel - Size.Y);
                ClearEvent(Event);
                Exit;
              end;
          end;
        for I := 0 to Strings.Count - 1 do
        begin
          C := HotKey(ItemText(I));
          if (C <> #0) and ((GetAltCode(C) = Event.KeyCode) or
            (((Owner^.Phase = phPostProcess) or (State and sfFocused <> 0)) and (UpCase(Event.CharCode) = C))) then
          begin
            if ButtonState(I) and Focus then
            begin
              Sel := I;
              MovedTo(Sel);
              Press(Sel);
              DrawView;
            end;
            ClearEvent(Event);
            Exit;
          end;
        end;
        if (Event.CharCode = ' ') and (State and sfFocused <> 0) and ButtonState(Sel) then
        begin
          Press(Sel);
          DrawView;
          ClearEvent(Event);
        end;
      end;
  end;
end;

function TCluster.Mark(Item: Sw_Integer): Boolean;
begin
  Mark := False;
end;

function TCluster.MultiMark(Item: Sw_Integer): Byte;
begin
  MultiMark := Ord(Mark(Item));
end;

procedure TCluster.MovedTo(Item: Sw_Integer);
begin
end;

procedure TCluster.Press(Item: Sw_Integer);
begin
end;

procedure TCluster.SetButtonState(AMask: LongInt; Enable: Boolean);
var
  I: Sw_Integer;
  Any: Boolean;
begin
  if Enable then
    EnableMask := EnableMask or AMask
  else
    EnableMask := EnableMask and not AMask;
  Any := False;
  for I := 0 to Strings.Count - 1 do
    if ButtonState(I) then
      Any := True;
  if Any then
    Options := Options or ofSelectable
  else
    Options := Options and not ofSelectable;
  DrawView;
end;

procedure TCluster.SetData(var Rec);
begin
  Value := Word(Rec);
  DrawView;
end;

procedure TCluster.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if AState = sfFocused then
    DrawView;
end;

{ ---- TRadioButtons / TCheckBoxes / TMultiCheckBoxes ----------------------------------- }

procedure TRadioButtons.Draw;
begin
  DrawBox(' ( ) ', #7);
end;

function TRadioButtons.Mark(Item: Sw_Integer): Boolean;
begin
  Mark := Item = Value;
end;

procedure TRadioButtons.MovedTo(Item: Sw_Integer);
begin
  Value := Item;
end;

procedure TRadioButtons.Press(Item: Sw_Integer);
begin
  Value := Item;
end;

procedure TRadioButtons.SetData(var Rec);
begin
  inherited SetData(Rec);
  Sel := Value;
  DrawView;
end;

procedure TCheckBoxes.Draw;
begin
  DrawBox(' [ ] ', 'X');
end;

function TCheckBoxes.Mark(Item: Sw_Integer): Boolean;
begin
  Mark := Value and (LongInt(1) shl Item) <> 0;
end;

procedure TCheckBoxes.Press(Item: Sw_Integer);
begin
  Value := Value xor (LongInt(1) shl Item);
end;

constructor TMultiCheckBoxes.Init(var Bounds: TRect; AStrings: PSItem; ASelRange: Byte; AFlags: Word;
  const AStates: String);
begin
  inherited Init(Bounds, AStrings);
  SelRange := ASelRange;
  Flags := AFlags;
  States := NewStr(AStates);
end;

constructor TMultiCheckBoxes.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(SelRange, SizeOf(SelRange));
  S.Read(Flags, SizeOf(Flags));
  States := S.ReadStr;
end;

procedure TMultiCheckBoxes.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(SelRange, SizeOf(SelRange));
  S.Write(Flags, SizeOf(Flags));
  S.WriteStr(States);
end;

destructor TMultiCheckBoxes.Done;
begin
  DisposeStr(States);
  inherited Done;
end;

function TMultiCheckBoxes.DataSize: Word;
begin
  DataSize := SizeOf(LongInt);
end;

procedure TMultiCheckBoxes.Draw;
begin
  if States <> nil then
    DrawMultiBox(' [ ] ', States^)
  else
    DrawMultiBox(' [ ] ', ' X');
end;

procedure TMultiCheckBoxes.GetData(var Rec);
begin
  LongInt(Rec) := Value;
end;

function TMultiCheckBoxes.MultiMark(Item: Sw_Integer): Byte;
var
  M: Byte;
begin
  M := (Value shr (Item * Hi(Flags))) and Lo(Flags);
  if (States <> nil) and (M >= Length(States^)) then
    M := 0;
  MultiMark := M;
end;

procedure TMultiCheckBoxes.Press(Item: Sw_Integer);
var
  Cur: LongInt;
  Shift: Sw_Integer;
begin
  Shift := Item * Hi(Flags);
  Cur := (Value shr Shift) and Lo(Flags);
  Inc(Cur);
  if Cur >= SelRange then
    Cur := 0;
  Value := (Value and not (LongInt(Lo(Flags)) shl Shift)) or (Cur shl Shift);
end;

procedure TMultiCheckBoxes.SetData(var Rec);
begin
  Value := LongInt(Rec);
  DrawView;
end;

{ ---- TListBox ------------------------------------------------------------------------- }

constructor TListBox.Init(var Bounds: TRect; ANumCols: Word; AScrollBar: PScrollBar);
begin
  inherited Init(Bounds, ANumCols, nil, AScrollBar);
  List := nil;
  SetRange(0);
end;

constructor TListBox.Load(var S: TStream);
begin
  inherited Load(S);
  List := PCollection(S.Get);
end;

procedure TListBox.Store(var S: TStream);
begin
  inherited Store(S);
  S.Put(List);
end;

function TListBox.DataSize: Word;
begin
  DataSize := SizeOf(TListBoxRec);
end;

procedure TListBox.GetData(var Rec);
begin
  TListBoxRec(Rec).List := List;
  TListBoxRec(Rec).Selection := Focused;
end;

function TListBox.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
var
  P: PString;
begin
  GetText := '';
  if (List <> nil) and (Item >= 0) and (Item < List^.Count) then
  begin
    P := PString(List^.At(Item));
    if P <> nil then
      GetText := Copy(P^, 1, MaxLen);
  end;
end;

procedure TListBox.NewList(AList: PCollection);
begin
  if List <> nil then
    Dispose(List, Done);
  List := AList;
  if AList <> nil then
    SetRange(AList^.Count)
  else
    SetRange(0);
  if Range > 0 then
    FocusItem(0);
  DrawView;
end;

procedure TListBox.SetData(var Rec);
begin
  NewList(TListBoxRec(Rec).List);
  if Range > 0 then
    FocusItem(TListBoxRec(Rec).Selection);
  DrawView;
end;

{ ---- TStaticText / TParamText ------------------------------------------------------------ }

constructor TStaticText.Init(var Bounds: TRect; const AText: String);
begin
  inherited Init(Bounds);
  Text := NewStr(AText);
end;

constructor TStaticText.Load(var S: TStream);
begin
  inherited Load(S);
  Text := S.ReadStr;
end;

procedure TStaticText.Store(var S: TStream);
begin
  inherited Store(S);
  S.WriteStr(Text);
end;

destructor TStaticText.Done;
begin
  DisposeStr(Text);
  inherited Done;
end;

{ Word-wrapped text; #13 ends a line and a line starting with #3 is
  centered. }
procedure TStaticText.Draw;
var
  B: TDrawBuffer;
  S: String;
  Color: Byte;
  L, P, Y, Start, Stop, Brk, X: Sw_Integer;
  Center: Boolean;
begin
  Color := GetColor(1);
  GetText(S);
  L := Length(S);
  P := 1;
  Center := False;
  for Y := 0 to Size.Y - 1 do
  begin
    MoveChar(B, ' ', Color, Size.X);
    if P <= L then
    begin
      if S[P] = #3 then
      begin
        Center := True;
        Inc(P);
      end;
      Start := P;
      Brk := 0;
      { Take characters up to the width, remembering the last space. }
      while (P <= L) and (S[P] <> #13) and (P - Start < Size.X) do
      begin
        if S[P] = ' ' then
          Brk := P;
        Inc(P);
      end;
      Stop := P;
      if (P <= L) and (S[P] <> #13) and (S[P] <> ' ') and (Brk > Start) then
        Stop := Brk;
      P := Stop;
      { Trailing spaces of a wrapped line are not shown. }
      while (Stop > Start) and (S[Stop - 1] = ' ') and (P <= L) and (S[P] <> #13) do
        Dec(Stop);
      if Center then
        X := (Size.X - (Stop - Start)) div 2
      else
        X := 0;
      if X < 0 then
        X := 0;
      if Stop > Start then
        MoveBuf(B[X], S[Start], Color, Stop - Start);
      while (P <= L) and (S[P] = ' ') do
        Inc(P);
      if (P <= L) and (S[P] = #13) then
      begin
        Center := False;
        Inc(P);
        if (P <= L) and (S[P] = #10) then
          Inc(P);
      end;
    end;
    WriteLine(0, Y, Size.X, 1, B);
  end;
end;

function TStaticText.GetPalette: PPalette;
const
  P: String[Length(CStaticText)] = CStaticText;
begin
  GetPalette := @P;
end;

procedure TStaticText.GetText(var S: String);
begin
  if Text <> nil then
    S := Text^
  else
    S := '';
end;

constructor TParamText.Init(var Bounds: TRect; const AText: String; AParamCount: Sw_Integer);
begin
  inherited Init(Bounds, AText);
  ParamCount := AParamCount;
end;

constructor TParamText.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(ParamCount, SizeOf(ParamCount));
end;

procedure TParamText.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(ParamCount, SizeOf(ParamCount));
end;

function TParamText.DataSize: Word;
begin
  DataSize := ParamCount * SizeOf(PtrInt);
end;

procedure TParamText.GetText(var S: String);
begin
  if Text = nil then
    S := ''
  else if ParamList = nil then
    S := Text^
  else
    FormatStr(S, Text^, ParamList^);
end;

procedure TParamText.SetData(var Rec);
begin
  ParamList := @Rec;
  DrawView;
end;

{ ---- TLabel ------------------------------------------------------------------------------ }

constructor TLabel.Init(var Bounds: TRect; const AText: String; ALink: PView);
begin
  inherited Init(Bounds, AText);
  Link := ALink;
  Options := Options or (ofPreProcess + ofPostProcess);
  EventMask := EventMask or evBroadcast;
end;

constructor TLabel.Load(var S: TStream);
begin
  inherited Load(S);
  GetPeerViewPtr(S, Link);
end;

procedure TLabel.Store(var S: TStream);
begin
  inherited Store(S);
  PutPeerViewPtr(S, Link);
end;

procedure TLabel.Draw;
var
  B: TDrawBuffer;
  Color: Word;
begin
  if Light then
    Color := GetColor($0402)
  else
    Color := GetColor($0301);
  MoveChar(B, ' ', Byte(Color), Size.X);
  if Text <> nil then
    MoveCStr(B[1], Text^, Color);
  if ShowMarkers and Light then
    MoveChar(B[0], #16, 0, 1);
  WriteLine(0, 0, Size.X, 1, B);
end;

function TLabel.GetPalette: PPalette;
const
  P: String[Length(CLabel)] = CLabel;
begin
  GetPalette := @P;
end;

procedure TLabel.HandleEvent(var Event: TEvent);
var
  C: Char;

  procedure FocusLink;
  begin
    if (Link <> nil) and (Link^.Options and ofSelectable <> 0) then
      Link^.Focus;
    ClearEvent(Event);
  end;

begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      FocusLink;
    evKeyDown:
      begin
        if Text <> nil then
          C := HotKey(Text^)
        else
          C := #0;
        if (C <> #0) and ((GetAltCode(C) = Event.KeyCode) or
          ((Owner^.Phase = phPostProcess) and (UpCase(Event.CharCode) = C))) then
          FocusLink;
      end;
    evBroadcast:
      if ((Event.Command = cmReceivedFocus) or (Event.Command = cmReleasedFocus)) and (Link <> nil) then
      begin
        Light := Link^.State and sfFocused <> 0;
        DrawView;
      end;
  end;
end;

{ ---- THistoryViewer / THistoryWindow / THistory ---------------------------------------------- }

constructor THistoryViewer.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; AHistoryId: Word);
begin
  inherited Init(Bounds, 1, AHScrollBar, AVScrollBar);
  HistoryId := AHistoryId;
  SetRange(HistoryCount(AHistoryId));
  if Range > 1 then
    FocusItem(1);
  if HScrollBar <> nil then
    HScrollBar^.SetRange(0, HistoryWidth - Size.X + 3);
end;

function THistoryViewer.GetPalette: PPalette;
const
  P: String[Length(CHistoryViewer)] = CHistoryViewer;
begin
  GetPalette := @P;
end;

function THistoryViewer.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
begin
  GetText := Copy(HistoryStr(HistoryId, Item), 1, MaxLen);
end;

procedure THistoryViewer.HandleEvent(var Event: TEvent);
begin
  if ((Event.What = evMouseDown) and Event.Double) or
    ((Event.What = evKeyDown) and (Event.KeyCode = kbEnter)) then
  begin
    EndModal(cmOK);
    ClearEvent(Event);
  end
  else if ((Event.What = evKeyDown) and (Event.KeyCode = kbEsc)) or
    ((Event.What = evCommand) and (Event.Command = cmCancel)) then
  begin
    EndModal(cmCancel);
    ClearEvent(Event);
  end
  else
    inherited HandleEvent(Event);
end;

function THistoryViewer.HistoryWidth: Sw_Integer;
var
  I, W, L: Sw_Integer;
begin
  W := 0;
  for I := 0 to HistoryCount(HistoryId) - 1 do
  begin
    L := Length(HistoryStr(HistoryId, I));
    if L > W then
      W := L;
  end;
  HistoryWidth := W;
end;

constructor THistoryWindow.Init(var Bounds: TRect; HistoryId: Word);
begin
  inherited Init(Bounds, '', wnNoNumber);
  Flags := wfClose;
  InitViewer(HistoryId);
end;

function THistoryWindow.GetPalette: PPalette;
const
  P: String[Length(CHistoryWindow)] = CHistoryWindow;
begin
  GetPalette := @P;
end;

function THistoryWindow.GetSelection: String;
begin
  GetSelection := Viewer^.GetText(Viewer^.Focused, 255);
end;

procedure THistoryWindow.InitViewer(HistoryId: Word);
var
  R: TRect;
begin
  GetExtent(R);
  R.Grow(-1, -1);
  Viewer := New(PHistoryViewer, Init(R, StandardScrollBar(sbHorizontal + sbHandleKeyboard),
    StandardScrollBar(sbVertical + sbHandleKeyboard), HistoryId));
  Insert(Viewer);
end;

constructor THistory.Init(var Bounds: TRect; ALink: PInputLine; AHistoryId: Word);
begin
  inherited Init(Bounds);
  Options := Options or ofPostProcess;
  EventMask := EventMask or evBroadcast;
  Link := ALink;
  HistoryId := AHistoryId;
end;

constructor THistory.Load(var S: TStream);
begin
  inherited Load(S);
  GetPeerViewPtr(S, Link);
  S.Read(HistoryId, SizeOf(HistoryId));
end;

procedure THistory.Store(var S: TStream);
begin
  inherited Store(S);
  PutPeerViewPtr(S, Link);
  S.Write(HistoryId, SizeOf(HistoryId));
end;

procedure THistory.Draw;
var
  B: TDrawBuffer;
begin
  MoveCStr(B, #222'~'#25'~'#221, GetColor($0102));
  WriteLine(0, 0, Size.X, Size.Y, B);
end;

function THistory.GetPalette: PPalette;
const
  P: String[Length(CHistory)] = CHistory;
begin
  GetPalette := @P;
end;

procedure THistory.HandleEvent(var Event: TEvent);
var
  W: PHistoryWindow;
  R, P: TRect;
  C: Word;
  S: String;
begin
  inherited HandleEvent(Event);
  if Link = nil then
    Exit;
  if (Event.What = evMouseDown) or
    ((Event.What = evKeyDown) and (CtrlToArrow(Event.KeyCode) = kbDown) and (Link^.State and sfFocused <> 0)) then
  begin
    if not Link^.Focus then
    begin
      ClearEvent(Event);
      Exit;
    end;
    RecordHistory(Link^.Data^);
    Link^.GetBounds(R);
    Dec(R.A.X);
    Inc(R.B.X);
    Inc(R.B.Y, 7);
    Dec(R.A.Y);
    Owner^.GetExtent(P);
    R.Intersect(P);
    Dec(R.B.Y);
    W := InitHistoryWindow(R);
    if W <> nil then
    begin
      C := Owner^.ExecView(W);
      if C = cmOK then
      begin
        S := W^.GetSelection;
        if Length(S) > Link^.MaxLen then
          S[0] := Chr(Link^.MaxLen);
        Link^.Data^ := S;
        Link^.SelectAll(True);
        Link^.DrawView;
      end;
      Dispose(W, Done);
    end;
    ClearEvent(Event);
  end
  else if Event.What = evBroadcast then
    if ((Event.Command = cmReleasedFocus) and (Event.InfoPtr = Link)) or (Event.Command = cmRecordHistory) then
      RecordHistory(Link^.Data^);
end;

function THistory.InitHistoryWindow(var Bounds: TRect): PHistoryWindow;
var
  P: PHistoryWindow;
begin
  P := New(PHistoryWindow, Init(Bounds, HistoryId));
  P^.HelpCtx := Link^.HelpCtx;
  InitHistoryWindow := P;
end;

procedure THistory.RecordHistory(const S: String);
begin
  HistoryAdd(HistoryId, S);
end;

procedure RegisterDialogs;
begin
  RegisterType(RDialog);
  RegisterType(RInputLine);
  RegisterType(RButton);
  RegisterType(RCluster);
  RegisterType(RRadioButtons);
  RegisterType(RCheckBoxes);
  RegisterType(RMultiCheckBoxes);
  RegisterType(RListBox);
  RegisterType(RStaticText);
  RegisterType(RLabel);
  RegisterType(RHistory);
  RegisterType(RParamText);
end;

end.
