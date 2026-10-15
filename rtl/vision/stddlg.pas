{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit StdDlg dari Odin Vision: dialog berkas (TFileDialog) dan dialog
  ganti direktori (TChDirDialog) di atas Dos.FindFirst. Implementasi
  clean-room berdasarkan dokumentasi API Turbo Vision TP7.

  Path memakai '/' di macOS dan Linux, '\' (dan 'C:\') di Windows. Berkas
  yang namanya diawali titik tidak ditampilkan. Nama di input line boleh
  sampai 255 karakter, jadi data TFileDialog adalah PathStr (256 byte). }
unit StdDlg;

{$R-,Q-,I-,X+}

interface

uses Objects, Drivers, Views, Dialogs, Dos;

const
  cmFileOpen = 800;
  cmFileReplace = 801;
  cmFileClear = 802;
  cmFileInit = 803;
  cmRevert = 805;
  cmFileFocused = 806;
  cmFileDoubleClicked = 807;

  fdOkButton = $0001;
  fdOpenButton = $0002;
  fdReplaceButton = $0004;
  fdClearButton = $0008;
  fdHelpButton = $0010;
  fdNoLoadDir = $0100;

  cdNormal = $0000;
  cdNoLoadDir = $0001;
  cdHelpButton = $0002;

  CInfoPane = #30;

type
  TWildStr = PathStr;

  PSearchRec = ^TSearchRec;
  TSearchRec = packed record
    Attr: Byte;
    Time: LongInt;
    Size: LongInt;
    Name: String;
  end;

  PFileInputLine = ^TFileInputLine;
  TFileInputLine = object(TInputLine)
    constructor Init(var Bounds: TRect; AMaxLen: Sw_Integer);
    procedure HandleEvent(var Event: TEvent); virtual;
  end;

  PFileCollection = ^TFileCollection;
  TFileCollection = object(TSortedCollection)
    function Compare(Key1, Key2: Pointer): Sw_Integer; virtual;
    procedure FreeItem(Item: Pointer); virtual;
    function GetItem(var S: TStream): Pointer; virtual;
    procedure PutItem(var S: TStream; Item: Pointer); virtual;
  end;

  PSortedListBox = ^TSortedListBox;
  TSortedListBox = object(TListBox)
    SearchPos: Word;
    ShiftState: Byte;
    constructor Init(var Bounds: TRect; ANumCols: Word; AScrollBar: PScrollBar);
    procedure HandleEvent(var Event: TEvent); virtual;
    function GetKey(var S: String): Pointer; virtual;
    procedure NewList(AList: PCollection); virtual;
  end;

  PFileList = ^TFileList;
  TFileList = object(TSortedListBox)
    constructor Init(var Bounds: TRect; AScrollBar: PScrollBar);
    destructor Done; virtual;
    function DataSize: Word; virtual;
    procedure FocusItem(Item: Sw_Integer); virtual;
    procedure GetData(var Rec); virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    function GetKey(var S: String): Pointer; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure ReadDirectory(AWildCard: PathStr);
    procedure SetData(var Rec); virtual;
  end;

  PFileInfoPane = ^TFileInfoPane;
  TFileInfoPane = object(TView)
    S: TSearchRec;
    constructor Init(var Bounds: TRect);
    procedure Draw; virtual;
    function GetPalette: PPalette; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
  end;

  PFileDialog = ^TFileDialog;
  TFileDialog = object(TDialog)
    FileName: PFileInputLine;
    FileList: PFileList;
    WildCard: TWildStr;
    Directory: PString;
    constructor Init(AWildCard: TWildStr; const ATitle, InputName: String; AOptions: Word; HistoryId: Byte);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure GetData(var Rec); virtual;
    procedure GetFileName(var S: PathStr);
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
    function Valid(Command: Word): Boolean; virtual;
    procedure ReadDirectory;
  end;

  PDirEntry = ^TDirEntry;
  TDirEntry = record
    DisplayText: PString;
    Directory: PString;
  end;

  PDirCollection = ^TDirCollection;
  TDirCollection = object(TCollection)
    procedure FreeItem(Item: Pointer); virtual;
    function GetItem(var S: TStream): Pointer; virtual;
    procedure PutItem(var S: TStream; Item: Pointer); virtual;
  end;

  PDirListBox = ^TDirListBox;
  TDirListBox = object(TListBox)
    Dir: DirStr;
    Cur: Word;
    constructor Init(var Bounds: TRect; AScrollBar: PScrollBar);
    destructor Done; virtual;
    function GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    function IsSelected(Item: Sw_Integer): Boolean; virtual;
    procedure NewDirectory(var ADir: DirStr);
    procedure SetState(AState: Word; Enable: Boolean); virtual;
  end;

  PChDirDialog = ^TChDirDialog;
  TChDirDialog = object(TDialog)
    DirInput: PInputLine;
    DirList: PDirListBox;
    OkButton: PButton;
    ChDirButton: PButton;
    constructor Init(AOptions: Word; HistoryId: Sw_Word);
    constructor Load(var S: TStream);
    function DataSize: Word; virtual;
    procedure GetData(var Rec); virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure SetData(var Rec); virtual;
    procedure Store(var S: TStream);
    function Valid(Command: Word): Boolean; virtual;
    procedure SetUpDialog;
  end;

function IsWild(const S: String): Boolean;
function IsDir(const S: String): Boolean;
function GetCurDir: DirStr;
function PathValid(var Path: PathStr): Boolean;
function ValidFileName(var FileName: PathStr): Boolean;
procedure RegisterStdDlg;

const
  RFileInputLine: TStreamRec = (ObjType: 60; VmtLink: Ofs(TypeOf(TFileInputLine)^); Load: @TFileInputLine.Load;
    Store: @TFileInputLine.Store);
  RFileCollection: TStreamRec = (ObjType: 61; VmtLink: Ofs(TypeOf(TFileCollection)^);
    Load: @TFileCollection.Load; Store: @TFileCollection.Store);
  RFileList: TStreamRec = (ObjType: 62; VmtLink: Ofs(TypeOf(TFileList)^); Load: @TFileList.Load;
    Store: @TFileList.Store);
  RFileInfoPane: TStreamRec = (ObjType: 63; VmtLink: Ofs(TypeOf(TFileInfoPane)^); Load: @TFileInfoPane.Load;
    Store: @TFileInfoPane.Store);
  RFileDialog: TStreamRec = (ObjType: 64; VmtLink: Ofs(TypeOf(TFileDialog)^); Load: @TFileDialog.Load;
    Store: @TFileDialog.Store);
  RDirCollection: TStreamRec = (ObjType: 65; VmtLink: Ofs(TypeOf(TDirCollection)^); Load: @TDirCollection.Load;
    Store: @TDirCollection.Store);
  RDirListBox: TStreamRec = (ObjType: 66; VmtLink: Ofs(TypeOf(TDirListBox)^); Load: @TDirListBox.Load;
    Store: @TDirListBox.Store);
  RChDirDialog: TStreamRec = (ObjType: 67; VmtLink: Ofs(TypeOf(TChDirDialog)^); Load: @TChDirDialog.Load;
    Store: @TChDirDialog.Store);
  RSortedListBox: TStreamRec = (ObjType: 68; VmtLink: Ofs(TypeOf(TSortedListBox)^); Load: @TSortedListBox.Load;
    Store: @TSortedListBox.Store);

implementation

uses MsgBox;

const
  cmDirChange = 804;

{ ---- path helpers ------------------------------------------------------------------ }

const
{$IFDEF WINDOWS}
  Sep = '\';
{$ELSE}
  Sep = '/';
{$ENDIF}

{ '/' everywhere, and '\' on Windows. }
function IsSep(C: Char): Boolean;
begin
{$IFDEF WINDOWS}
  IsSep := (C = '/') or (C = '\');
{$ELSE}
  IsSep := C = '/';
{$ENDIF}
end;

{ The length of the root at the start of S: '/' (or '\'), or 'C:\' on
  Windows; 0 for a relative path. }
function RootLength(const S: String): Integer;
begin
  RootLength := 0;
{$IFDEF WINDOWS}
  if (Length(S) >= 3) and (S[2] = ':') and IsSep(S[3]) then
    RootLength := 3
  else if (Length(S) = 2) and (S[2] = ':') then
    RootLength := 2
  else
{$ENDIF}
  if (S <> '') and IsSep(S[1]) then
    RootLength := 1;
end;

{ S without its last separator, unless S is a root. }
function NoSlash(const S: String): String;
var
  T: String;
begin
  T := S;
  while (Length(T) > RootLength(T)) and IsSep(T[Length(T)]) do
    Dec(T[0]);
  NoSlash := T;
end;

function IsWild(const S: String): Boolean;
begin
  IsWild := (Pos('*', S) > 0) or (Pos('?', S) > 0);
end;

function IsDir(const S: String): Boolean;
var
  F: SearchRec;
  T: String;
begin
  T := NoSlash(S);
  if (T <> '') and (RootLength(T) = Length(T)) then
  begin
    IsDir := True;
    Exit;
  end;
  FindFirst(T, Directory + Hidden + ReadOnly + SysFile + Archive, F);
  IsDir := (DosError = 0) and (F.Attr and Directory <> 0);
  FindClose(F);
end;

function GetCurDir: DirStr;
var
  S: String;
begin
  GetDir(0, S);
  if (S = '') or not IsSep(S[Length(S)]) then
    S := S + Sep;
  GetCurDir := S;
end;

function PathValid(var Path: PathStr): Boolean;
var
  S: PathStr;
begin
  S := FExpand(Path);
  PathValid := IsDir(S);
end;

{ A name whose directory exists and that has no wildcard. }
function ValidFileName(var FileName: PathStr): Boolean;
var
  D: DirStr;
  N: NameStr;
  E: ExtStr;
begin
  FSplit(FExpand(FileName), D, N, E);
  ValidFileName := (N + E <> '') and not IsWild(N + E) and IsDir(D);
end;

function WithSlash(const S: String): String;
begin
  if (S <> '') and IsSep(S[Length(S)]) then
    WithSlash := S
  else
    WithSlash := S + Sep;
end;

{ ---- TFileInputLine ------------------------------------------------------------------ }

constructor TFileInputLine.Init(var Bounds: TRect; AMaxLen: Sw_Integer);
begin
  inherited Init(Bounds, AMaxLen);
  EventMask := EventMask or evBroadcast;
end;

procedure TFileInputLine.HandleEvent(var Event: TEvent);
var
  R: PSearchRec;
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmFileFocused) and (State and sfSelected = 0) and
    (Event.InfoPtr <> nil) then
  begin
    R := PSearchRec(Event.InfoPtr);
    if R^.Attr and Directory <> 0 then
      Data^ := Copy(R^.Name + Sep + PFileDialog(Owner)^.WildCard, 1, MaxLen)
    else
      Data^ := Copy(R^.Name, 1, MaxLen);
    DrawView;
  end;
end;

{ ---- TFileCollection ------------------------------------------------------------------- }

{ Files first, then directories, '..' last; names ignore case first. }
function TFileCollection.Compare(Key1, Key2: Pointer): Sw_Integer;
var
  A, B: PSearchRec;
  SA, SB: String;
  I: Integer;
begin
  A := PSearchRec(Key1);
  B := PSearchRec(Key2);
  if (A^.Attr and Directory) <> (B^.Attr and Directory) then
  begin
    if A^.Attr and Directory <> 0 then
      Compare := 1
    else
      Compare := -1;
    Exit;
  end;
  if A^.Name = B^.Name then
  begin
    Compare := 0;
    Exit;
  end;
  if A^.Name = '..' then
  begin
    Compare := 1;
    Exit;
  end;
  if B^.Name = '..' then
  begin
    Compare := -1;
    Exit;
  end;
  SA := A^.Name;
  SB := B^.Name;
  for I := 1 to Length(SA) do
    SA[I] := UpCase(SA[I]);
  for I := 1 to Length(SB) do
    SB[I] := UpCase(SB[I]);
  if SA = SB then
  begin
    SA := A^.Name;
    SB := B^.Name;
  end;
  if SA < SB then
    Compare := -1
  else
    Compare := 1;
end;

procedure TFileCollection.FreeItem(Item: Pointer);
begin
  if Item <> nil then
    Dispose(PSearchRec(Item));
end;

function TFileCollection.GetItem(var S: TStream): Pointer;
var
  P: PSearchRec;
begin
  New(P);
  S.Read(P^.Attr, SizeOf(P^.Attr));
  S.Read(P^.Time, SizeOf(P^.Time));
  S.Read(P^.Size, SizeOf(P^.Size));
  S.Read(P^.Name[0], 1);
  S.Read(P^.Name[1], Length(P^.Name));
  GetItem := P;
end;

procedure TFileCollection.PutItem(var S: TStream; Item: Pointer);
var
  P: PSearchRec;
begin
  P := PSearchRec(Item);
  S.Write(P^.Attr, SizeOf(P^.Attr));
  S.Write(P^.Time, SizeOf(P^.Time));
  S.Write(P^.Size, SizeOf(P^.Size));
  S.Write(P^.Name, Length(P^.Name) + 1);
end;

{ ---- TSortedListBox ----------------------------------------------------------------------- }

constructor TSortedListBox.Init(var Bounds: TRect; ANumCols: Word; AScrollBar: PScrollBar);
begin
  inherited Init(Bounds, ANumCols, AScrollBar);
  SearchPos := 0;
  ShowCursor;
  SetCursor(1, 0);
end;

function TSortedListBox.GetKey(var S: String): Pointer;
begin
  GetKey := @S;
end;

procedure TSortedListBox.NewList(AList: PCollection);
begin
  inherited NewList(AList);
  SearchPos := 0;
end;

{ Typing letters focuses the first item that starts with them. }
procedure TSortedListBox.HandleEvent(var Event: TEvent);
var
  OldFocused, I, J: Sw_Integer;
  Prefix, T: String;
  Found: Boolean;
begin
  OldFocused := Focused;
  if (Event.What = evKeyDown) and (Range > 0) and
    ((Event.CharCode > ' ') or ((Event.KeyCode = kbBack) and (SearchPos > 0))) then
  begin
    if (OldFocused >= 0) and (OldFocused < Range) then
      Prefix := Copy(GetText(OldFocused, 255), 1, SearchPos)
    else
      Prefix := '';
    if Event.KeyCode = kbBack then
      Dec(Prefix[0])
    else
      Prefix := Prefix + Event.CharCode;
    for J := 1 to Length(Prefix) do
      Prefix[J] := UpCase(Prefix[J]);
    Found := False;
    I := 0;
    while (I < Range) and not Found do
    begin
      T := Copy(GetText(I, 255), 1, Length(Prefix));
      for J := 1 to Length(T) do
        T[J] := UpCase(T[J]);
      if T = Prefix then
        Found := True
      else
        Inc(I);
    end;
    if Found then
    begin
      SearchPos := Length(Prefix);
      if I <> Focused then
        FocusItem(I);
      DrawView;
    end;
    ClearEvent(Event);
    Exit;
  end;
  inherited HandleEvent(Event);
  if Focused <> OldFocused then
    SearchPos := 0;
end;

{ ---- TFileList ------------------------------------------------------------------------------ }

constructor TFileList.Init(var Bounds: TRect; AScrollBar: PScrollBar);
begin
  inherited Init(Bounds, 2, AScrollBar);
end;

destructor TFileList.Done;
begin
  if List <> nil then
    Dispose(List, Done);
  List := nil;
  inherited Done;
end;

function TFileList.DataSize: Word;
begin
  DataSize := 0;
end;

procedure TFileList.GetData(var Rec);
begin
end;

procedure TFileList.SetData(var Rec);
begin
end;

procedure TFileList.FocusItem(Item: Sw_Integer);
begin
  inherited FocusItem(Item);
  if (List <> nil) and (Item >= 0) and (Item < List^.Count) then
    Message(Owner, evBroadcast, cmFileFocused, List^.At(Item));
end;

function TFileList.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
var
  P: PSearchRec;
  S: String;
begin
  GetText := '';
  if (List = nil) or (Item < 0) or (Item >= List^.Count) then
    Exit;
  P := PSearchRec(List^.At(Item));
  S := P^.Name;
  if P^.Attr and Directory <> 0 then
    S := S + Sep;
  GetText := Copy(S, 1, MaxLen);
end;

function TFileList.GetKey(var S: String): Pointer;
const
  Key: TSearchRec = (Attr: 0; Time: 0; Size: 0; Name: '');
begin
  Key.Name := S;
  GetKey := @Key;
end;

procedure TFileList.HandleEvent(var Event: TEvent);
begin
  if (Event.What = evMouseDown) and Event.Double then
  begin
    inherited HandleEvent(Event);
    if (List <> nil) and (Focused < List^.Count) then
      Message(Owner, evBroadcast, cmFileDoubleClicked, List^.At(Focused));
    ClearEvent(Event);
  end
  else
    inherited HandleEvent(Event);
end;

procedure TFileList.ReadDirectory(AWildCard: PathStr);
var
  F: SearchRec;
  P: PSearchRec;
  Files: PFileCollection;
  D: DirStr;
  N: NameStr;
  E: ExtStr;

  procedure Add(var F: SearchRec);
  begin
    New(P);
    P^.Attr := F.Attr;
    P^.Time := F.Time;
    P^.Size := F.Size;
    P^.Name := F.Name;
    Files^.Insert(P);
  end;

begin
  AWildCard := FExpand(AWildCard);
  FSplit(AWildCard, D, N, E);
  Files := New(PFileCollection, Init(16, 16));
  FindFirst(AWildCard, ReadOnly + Archive, F);
  while DosError = 0 do
  begin
    if (F.Attr and Directory = 0) and (F.Name <> '') and (F.Name[1] <> '.') then
      Add(F);
    FindNext(F);
  end;
  FindClose(F);
  FindFirst(D + '*', Directory + ReadOnly + Archive, F);
  while DosError = 0 do
  begin
    if (F.Attr and Directory <> 0) and (F.Name <> '') and (F.Name[1] <> '.') then
      Add(F);
    FindNext(F);
  end;
  FindClose(F);
  if RootLength(D) <> Length(D) then
  begin
    F.Attr := Directory;
    F.Time := 0;
    F.Size := 0;
    F.Name := '..';
    Add(F);
  end;
  NewList(Files);
  if List^.Count = 0 then
    Message(Owner, evBroadcast, cmFileFocused, nil);
end;

{ ---- TFileInfoPane ---------------------------------------------------------------------------- }

constructor TFileInfoPane.Init(var Bounds: TRect);
begin
  inherited Init(Bounds);
  EventMask := EventMask or evBroadcast;
  FillChar(S, SizeOf(S), 0);
end;

procedure TFileInfoPane.Draw;
const
  Months: array[1..12] of String[3] = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec');
var
  B: TDrawBuffer;
  Color: Byte;
  T: DateTime;
  Line, Num: String;
  D: PFileDialog;
  Hour: Word;
  AmPm: String[2];
  Y: Sw_Integer;
begin
  Color := GetColor(1);
  D := PFileDialog(Owner);
  MoveChar(B, ' ', Color, Size.X);
  if (D <> nil) and (D^.Directory <> nil) then
  begin
    Line := D^.Directory^ + D^.WildCard;
    if Length(Line) > Size.X - 2 then
      Line := '...' + Copy(Line, Length(Line) - Size.X + 6, 255);
    MoveStr(B[1], Line, Color);
  end;
  WriteLine(0, 0, Size.X, 1, B);
  MoveChar(B, ' ', Color, Size.X);
  if S.Name <> '' then
  begin
    Line := S.Name;
    if S.Attr and Directory <> 0 then
      Line := Line + Sep;
    MoveStr(B[1], Copy(Line, 1, Size.X - 28), Color);
    if S.Attr and Directory = 0 then
    begin
      Str(S.Size, Num);
      MoveStr(B[Size.X - 26 - Length(Num)], Num, Color);
    end;
    if S.Time <> 0 then
    begin
      UnpackTime(S.Time, T);
      if (T.Month >= 1) and (T.Month <= 12) then
      begin
        Hour := T.Hour mod 12;
        if Hour = 0 then
          Hour := 12;
        if T.Hour >= 12 then
          AmPm := 'pm'
        else
          AmPm := 'am';
        Str(T.Day, Num);
        Line := Months[T.Month] + ' ' + Num + ', ';
        Str(T.Year, Num);
        Line := Line + Num + '  ';
        Str(Hour, Num);
        Line := Line + Num + ':';
        Str(T.Min, Num);
        if Length(Num) < 2 then
          Num := '0' + Num;
        Line := Line + Num + AmPm;
        MoveStr(B[Size.X - 23], Line, Color);
      end;
    end;
  end;
  WriteLine(0, 1, Size.X, 1, B);
  MoveChar(B, ' ', Color, Size.X);
  for Y := 2 to Size.Y - 1 do
    WriteLine(0, Y, Size.X, 1, B);
end;

function TFileInfoPane.GetPalette: PPalette;
const
  P: String[Length(CInfoPane)] = CInfoPane;
begin
  GetPalette := @P;
end;

procedure TFileInfoPane.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evBroadcast) and (Event.Command = cmFileFocused) then
  begin
    if Event.InfoPtr = nil then
      FillChar(S, SizeOf(S), 0)
    else
      S := PSearchRec(Event.InfoPtr)^;
    DrawView;
  end;
end;

{ ---- TFileDialog -------------------------------------------------------------------------------- }

constructor TFileDialog.Init(AWildCard: TWildStr; const ATitle, InputName: String; AOptions: Word;
  HistoryId: Byte);
var
  R: TRect;
  Bar: PScrollBar;
  D: DirStr;
  N: NameStr;
  E: ExtStr;
  Opt: Word;

  procedure AddButton(const Title: String; Command: Word);
  begin
    Insert(New(PButton, Init(R, Title, Command, Opt)));
    Opt := bfNormal;
    Inc(R.A.Y, 3);
    Inc(R.B.Y, 3);
  end;

begin
  R.Assign(15, 1, 64, 21);
  inherited Init(R, ATitle);
  Options := Options or ofCentered;
  if AWildCard = '' then
    AWildCard := '*';
  FSplit(FExpand(AWildCard), D, N, E);
  Directory := NewStr(D);
  WildCard := N + E;

  R.Assign(3, 3, 31, 4);
  FileName := New(PFileInputLine, Init(R, 255));
  FileName^.Data^ := WildCard;
  Insert(FileName);
  R.Assign(2, 2, 3 + CStrLen(InputName), 3);
  Insert(New(PLabel, Init(R, InputName, FileName)));
  R.Assign(31, 3, 34, 4);
  Insert(New(PHistory, Init(R, FileName, HistoryId)));

  R.Assign(3, 14, 34, 15);
  Bar := New(PScrollBar, Init(R));
  Insert(Bar);
  R.Assign(3, 6, 34, 14);
  FileList := New(PFileList, Init(R, Bar));
  Insert(FileList);
  R.Assign(2, 5, 8, 6);
  Insert(New(PLabel, Init(R, '~F~iles', FileList)));

  R.Assign(35, 3, 46, 5);
  Opt := bfDefault;
  if AOptions and fdOpenButton <> 0 then
    AddButton('~O~pen', cmFileOpen);
  if AOptions and fdOkButton <> 0 then
    AddButton('O~K~', cmFileOpen);
  if AOptions and fdReplaceButton <> 0 then
    AddButton('~R~eplace', cmFileReplace);
  if AOptions and fdClearButton <> 0 then
    AddButton('~C~lear', cmFileClear);
  AddButton('Cancel', cmCancel);
  if AOptions and fdHelpButton <> 0 then
    AddButton('Help', cmHelp);

  R.Assign(1, 16, 48, 18);
  Insert(New(PFileInfoPane, Init(R)));
  SelectNext(False);
  if AOptions and fdNoLoadDir = 0 then
    ReadDirectory;
end;

constructor TFileDialog.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(WildCard, SizeOf(TWildStr));
  GetSubViewPtr(S, FileName);
  GetSubViewPtr(S, FileList);
  Directory := NewStr(GetCurDir);
  ReadDirectory;
end;

procedure TFileDialog.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(WildCard, SizeOf(TWildStr));
  PutSubViewPtr(S, FileName);
  PutSubViewPtr(S, FileList);
end;

destructor TFileDialog.Done;
begin
  DisposeStr(Directory);
  inherited Done;
end;

procedure TFileDialog.GetData(var Rec);
begin
  GetFileName(PathStr(Rec));
end;

{ The input line as a full path: relative names start at Directory, and a
  name without extension takes the extension of the wildcard. }
procedure TFileDialog.GetFileName(var S: PathStr);
var
  T: PathStr;
  D, WD: DirStr;
  N, WN: NameStr;
  E, WE: ExtStr;
begin
  T := FileName^.Data^;
  while (Length(T) > 0) and (T[Length(T)] = ' ') do
    Dec(T[0]);
  while (Length(T) > 0) and (T[1] = ' ') do
    System.Delete(T, 1, 1);
  if (T <> '') and (RootLength(T) = 0) and (T[1] <> '~') and (Directory <> nil) then
    T := Directory^ + T;
  T := FExpand(T);
  FSplit(T, D, N, E);
  if (E = '') and not IsWild(N) and not IsDir(T) then
  begin
    FSplit(WildCard, WD, WN, WE);
    if (WE <> '') and not IsWild(WE) then
      E := WE;
  end;
  S := D + N + E;
end;

procedure TFileDialog.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  case Event.What of
    evCommand:
      case Event.Command of
        cmFileOpen, cmFileReplace, cmFileClear:
          if State and sfModal <> 0 then
          begin
            EndModal(Event.Command);
            ClearEvent(Event);
          end;
      end;
    evBroadcast:
      if Event.Command = cmFileDoubleClicked then
      begin
        Event.What := evBroadcast;
        Event.Command := cmDefault;
        Event.InfoPtr := nil;
        PutEvent(Event);
        ClearEvent(Event);
      end;
  end;
end;

procedure TFileDialog.ReadDirectory;
begin
  if Directory = nil then
    Directory := NewStr(GetCurDir);
  FileList^.ReadDirectory(Directory^ + WildCard);
end;

procedure TFileDialog.SetData(var Rec);
begin
  inherited SetData(Rec);
  if (PathStr(Rec) <> '') and IsWild(PathStr(Rec)) then
  begin
    Valid(cmFileInit);
    FileName^.Select;
  end;
end;

function TFileDialog.Valid(Command: Word): Boolean;
var
  FName: PathStr;
  D: DirStr;
  N: NameStr;
  E: ExtStr;
begin
  Valid := True;
  if (Command = cmValid) or (Command = cmCancel) or (Command = cmFileClear) then
    Exit;
  if not inherited Valid(Command) then
  begin
    Valid := False;
    Exit;
  end;
  GetFileName(FName);
  if IsWild(FName) then
  begin
    FSplit(FName, D, N, E);
    if IsDir(D) then
    begin
      DisposeStr(Directory);
      Directory := NewStr(D);
      WildCard := N + E;
      if Command <> cmFileInit then
        FileList^.Select;
      ReadDirectory;
    end
    else
      MessageBox('Invalid drive or directory.', nil, mfError + mfOKButton);
    Valid := False;
  end
  else if IsDir(FName) then
  begin
    DisposeStr(Directory);
    Directory := NewStr(WithSlash(FName));
    if Command <> cmFileInit then
      FileList^.Select;
    ReadDirectory;
    FileName^.Data^ := WildCard;
    FileName^.DrawView;
    Valid := False;
  end
  else if not ValidFileName(FName) then
  begin
    MessageBox('Invalid file name.', nil, mfError + mfOKButton);
    Valid := False;
  end;
end;

{ ---- TDirCollection / TDirListBox --------------------------------------------------------------- }

procedure TDirCollection.FreeItem(Item: Pointer);
var
  P: PDirEntry;
begin
  P := PDirEntry(Item);
  if P <> nil then
  begin
    DisposeStr(P^.DisplayText);
    DisposeStr(P^.Directory);
    Dispose(P);
  end;
end;

function TDirCollection.GetItem(var S: TStream): Pointer;
var
  P: PDirEntry;
begin
  New(P);
  P^.DisplayText := S.ReadStr;
  P^.Directory := S.ReadStr;
  GetItem := P;
end;

procedure TDirCollection.PutItem(var S: TStream; Item: Pointer);
begin
  S.WriteStr(PDirEntry(Item)^.DisplayText);
  S.WriteStr(PDirEntry(Item)^.Directory);
end;

constructor TDirListBox.Init(var Bounds: TRect; AScrollBar: PScrollBar);
begin
  inherited Init(Bounds, 1, AScrollBar);
  Dir := '';
  Cur := 0;
end;

destructor TDirListBox.Done;
begin
  if List <> nil then
    Dispose(List, Done);
  List := nil;
  inherited Done;
end;

function TDirListBox.GetText(Item: Sw_Integer; MaxLen: Sw_Integer): String;
var
  P: PDirEntry;
begin
  GetText := '';
  if (List <> nil) and (Item >= 0) and (Item < List^.Count) then
  begin
    P := PDirEntry(List^.At(Item));
    if P^.DisplayText <> nil then
      GetText := Copy(P^.DisplayText^, 1, MaxLen);
  end;
end;

procedure TDirListBox.HandleEvent(var Event: TEvent);
var
  E: TEvent;
begin
  if (Event.What = evMouseDown) and Event.Double then
  begin
    inherited HandleEvent(Event);
    E.What := evCommand;
    E.Command := cmDirChange;
    E.InfoPtr := nil;
    PutEvent(E);
    ClearEvent(Event);
  end
  else
    inherited HandleEvent(Event);
end;

function TDirListBox.IsSelected(Item: Sw_Integer): Boolean;
begin
  IsSelected := Item = Cur;
end;

{ The path from the root (/ or C:\) to ADir, one level per line, then the subdirectories of
  ADir:
    /
    └─┬Users
      └─┬name
        ├──sub1
        └──sub2 }
procedure TDirListBox.NewDirectory(var ADir: DirStr);
var
  Dirs: PDirCollection;
  Path, Part, Indent: String;
  I, Start, Level: Integer;
  F: SearchRec;
  Subs: PStringCollection;
  Name: PString;

  procedure AddEntry(const Text, Directory: String);
  var
    P: PDirEntry;
  begin
    New(P);
    P^.DisplayText := NewStr(Text);
    P^.Directory := NewStr(Directory);
    Dirs^.Insert(P);
  end;

begin
  Dir := WithSlash(FExpand(ADir));
  Dirs := New(PDirCollection, Init(16, 16));
  Subs := New(PStringCollection, Init(16, 16));
  FindFirst(Dir + '*', Directory + ReadOnly + Archive, F);
  while DosError = 0 do
  begin
    if (F.Attr and Directory <> 0) and (F.Name <> '') and (F.Name[1] <> '.') then
      Subs^.Insert(NewStr(F.Name));
    FindNext(F);
  end;
  FindClose(F);
  Path := Copy(Dir, 1, RootLength(Dir));
  AddEntry(Path, Path);
  Indent := '';
  Level := 0;
  I := Length(Path) + 1;
  while I <= Length(Dir) do
  begin
    Start := I;
    while (I <= Length(Dir)) and not IsSep(Dir[I]) do
      Inc(I);
    Part := Copy(Dir, Start, I - Start);
    Inc(I);
    if Part = '' then
      Continue;
    Path := Path + Part + Sep;
    Inc(Level);
    if (I > Length(Dir)) and (Subs^.Count = 0) then
      AddEntry(Indent + #192#196#196 + Part, Path)
    else
      AddEntry(Indent + #192#196#194 + Part, Path);
    Indent := Indent + '  ';
  end;
  Cur := Dirs^.Count - 1;
  for I := 0 to Subs^.Count - 1 do
  begin
    Name := PString(Subs^.At(I));
    if I = Subs^.Count - 1 then
      AddEntry(Indent + #192#196#196 + Name^, Path + Name^ + Sep)
    else
      AddEntry(Indent + #195#196#196 + Name^, Path + Name^ + Sep);
  end;
  Dispose(Subs, Done);
  NewList(Dirs);
  FocusItem(Cur);
end;

procedure TDirListBox.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if (AState and sfFocused <> 0) and (Owner <> nil) and (PChDirDialog(Owner)^.ChDirButton <> nil) then
    PChDirDialog(Owner)^.ChDirButton^.MakeDefault(Enable);
end;

{ ---- TChDirDialog -------------------------------------------------------------------------------- }

constructor TChDirDialog.Init(AOptions: Word; HistoryId: Sw_Word);
var
  R: TRect;
  Bar: PScrollBar;
begin
  R.Assign(16, 2, 64, 20);
  inherited Init(R, 'Change Directory');
  Options := Options or ofCentered;
  R.Assign(3, 3, 30, 4);
  DirInput := New(PInputLine, Init(R, 255));
  Insert(DirInput);
  R.Assign(2, 2, 17, 3);
  Insert(New(PLabel, Init(R, 'Directory ~n~ame', DirInput)));
  R.Assign(30, 3, 33, 4);
  Insert(New(PHistory, Init(R, DirInput, HistoryId)));
  R.Assign(32, 6, 33, 16);
  Bar := New(PScrollBar, Init(R));
  Insert(Bar);
  R.Assign(3, 6, 32, 16);
  DirList := New(PDirListBox, Init(R, Bar));
  Insert(DirList);
  R.Assign(2, 5, 17, 6);
  Insert(New(PLabel, Init(R, 'Directory ~t~ree', DirList)));
  R.Assign(35, 6, 45, 8);
  OkButton := New(PButton, Init(R, 'O~K~', cmOK, bfDefault));
  Insert(OkButton);
  Inc(R.A.Y, 3);
  Inc(R.B.Y, 3);
  ChDirButton := New(PButton, Init(R, '~C~hdir', cmDirChange, bfNormal));
  Insert(ChDirButton);
  Inc(R.A.Y, 3);
  Inc(R.B.Y, 3);
  Insert(New(PButton, Init(R, '~R~evert', cmRevert, bfNormal)));
  if AOptions and cdHelpButton <> 0 then
  begin
    Inc(R.A.Y, 3);
    Inc(R.B.Y, 3);
    Insert(New(PButton, Init(R, 'Help', cmHelp, bfNormal)));
  end;
  if AOptions and cdNoLoadDir = 0 then
    SetUpDialog;
  SelectNext(False);
end;

constructor TChDirDialog.Load(var S: TStream);
begin
  inherited Load(S);
  GetSubViewPtr(S, DirList);
  GetSubViewPtr(S, DirInput);
  GetSubViewPtr(S, OkButton);
  GetSubViewPtr(S, ChDirButton);
  SetUpDialog;
end;

procedure TChDirDialog.Store(var S: TStream);
begin
  inherited Store(S);
  PutSubViewPtr(S, DirList);
  PutSubViewPtr(S, DirInput);
  PutSubViewPtr(S, OkButton);
  PutSubViewPtr(S, ChDirButton);
end;

function TChDirDialog.DataSize: Word;
begin
  DataSize := 0;
end;

procedure TChDirDialog.GetData(var Rec);
begin
end;

procedure TChDirDialog.SetData(var Rec);
begin
end;

function ShownDir(const D: String): String;
begin
  ShownDir := NoSlash(D);
end;

procedure TChDirDialog.SetUpDialog;
var
  CurDir: DirStr;
begin
  if DirList <> nil then
  begin
    CurDir := GetCurDir;
    DirList^.NewDirectory(CurDir);
    if DirInput <> nil then
    begin
      DirInput^.Data^ := Copy(ShownDir(CurDir), 1, DirInput^.MaxLen);
      DirInput^.DrawView;
    end;
    DirList^.DrawView;
  end;
end;

procedure TChDirDialog.HandleEvent(var Event: TEvent);
var
  CurDir: DirStr;
  P: PDirEntry;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  case Event.Command of
    cmRevert:
      CurDir := GetCurDir;
    cmDirChange:
      begin
        if (DirList^.List = nil) or (DirList^.Focused >= DirList^.List^.Count) then
          Exit;
        P := PDirEntry(DirList^.List^.At(DirList^.Focused));
        CurDir := P^.Directory^;
      end;
  else
    Exit;
  end;
  DirList^.NewDirectory(CurDir);
  DirInput^.Data^ := Copy(ShownDir(CurDir), 1, DirInput^.MaxLen);
  DirInput^.DrawView;
  DirList^.Select;
  ClearEvent(Event);
end;

function TChDirDialog.Valid(Command: Word): Boolean;
var
  P: PathStr;
begin
  Valid := True;
  if Command <> cmOK then
    Exit;
  P := NoSlash(FExpand(DirInput^.Data^));
  ChDir(P);
  if IOResult <> 0 then
  begin
    MessageBox('Invalid directory.', nil, mfError + mfOKButton);
    Valid := False;
  end;
end;

procedure RegisterStdDlg;
begin
  RegisterType(RFileInputLine);
  RegisterType(RFileCollection);
  RegisterType(RFileList);
  RegisterType(RFileInfoPane);
  RegisterType(RFileDialog);
  RegisterType(RDirCollection);
  RegisterType(RDirListBox);
  RegisterType(RChDirDialog);
  RegisterType(RSortedListBox);
end;

end.
