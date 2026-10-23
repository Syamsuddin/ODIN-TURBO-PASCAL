{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Classes dari runtime library Odin. Bukan unit Turbo Pascal 7,
  tetapi subset dari Classes Free Pascal/Delphi yang ditulis dengan class:
  TList (daftar pointer) dan TStringList (daftar string, bisa diurutkan,
  dimuat dari dan disimpan ke berkas teks, dengan objek pendamping).

  Odin belum punya exception, jadi indeks di luar daftar menjadi runtime
  error 201 (di Free Pascal: EListError), dan galat berkas di LoadFromFile
  dan SaveToFile menjadi runtime error I/O biasa. String tetap String 255
  karakter; Text dan CommaText tidak ada karena melewati batas itu.
  TObjectList ada di unit Contnrs. }
unit Classes;

{$R-,Q-,X+}

interface

const
  MaxListSize = 134217727;

type
  PPointerList = ^TPointerList;
  TPointerList = array[0..MaxListSize - 1] of Pointer;
  TListSortCompare = function(Item1, Item2: Pointer): Integer;
  TListNotification = (lnAdded, lnExtracted, lnDeleted);

  TList = class
  private
    FList: PPointerList;
    FCount: Integer;
    FCapacity: Integer;
    function Get(Index: Integer): Pointer;
    procedure Put(Index: Integer; Item: Pointer);
    procedure SetCapacity(NewCapacity: Integer);
    procedure SetCount(NewCount: Integer);
    procedure Grow;
  protected
    { Called for every item added to or taken from the list. }
    procedure Notify(Ptr: Pointer; Action: TListNotification); virtual;
  public
    destructor Destroy; override;
    function Add(Item: Pointer): Integer;
    procedure Insert(Index: Integer; Item: Pointer);
    procedure Delete(Index: Integer);
    function Extract(Item: Pointer): Pointer;
    function Remove(Item: Pointer): Integer;
    function IndexOf(Item: Pointer): Integer;
    procedure Clear; virtual;
    procedure Exchange(Index1, Index2: Integer);
    procedure Move(CurIndex, NewIndex: Integer);
    procedure Pack;
    procedure Sort(Compare: TListSortCompare);
    function First: Pointer;
    function Last: Pointer;
    property Capacity: Integer read FCapacity write SetCapacity;
    property Count: Integer read FCount write SetCount;
    property Items[Index: Integer]: Pointer read Get write Put; default;
    property List: PPointerList read FList;
  end;

  TStringList = class
  private
    FStrings: TList;
    FObjects: TList;
    FSorted: Boolean;
    FCaseSensitive: Boolean;
    function Get(Index: Integer): String;
    procedure Put(Index: Integer; const S: String);
    function GetObject(Index: Integer): TObject;
    procedure PutObject(Index: Integer; AObject: TObject);
    function GetCount: Integer;
    procedure SetSorted(Value: Boolean);
    procedure SetCaseSensitive(Value: Boolean);
    function Compare(const S1, S2: String): Integer;
    procedure InsertItem(Index: Integer; const S: String; AObject: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const S: String): Integer;
    function AddObject(const S: String; AObject: TObject): Integer;
    procedure Insert(Index: Integer; const S: String);
    procedure Delete(Index: Integer);
    procedure Clear;
    procedure Exchange(Index1, Index2: Integer);
    function IndexOf(const S: String): Integer;
    function IndexOfObject(AObject: TObject): Integer;
    { Binary search of a sorted list: True when S is there; Index is where
      it is, or where it would go. }
    function Find(const S: String; var Index: Integer): Boolean;
    procedure Sort;
    procedure LoadFromFile(const FileName: String);
    procedure SaveToFile(const FileName: String);
    property Count: Integer read GetCount;
    property Strings[Index: Integer]: String read Get write Put; default;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property Sorted: Boolean read FSorted write SetSorted;
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
  end;

implementation

{ ---- TList ---------------------------------------------------------------- }

{ A bad index: runtime error 201 at the caller of the list method. }
procedure IndexError;
begin
  RunError(201);
end;

destructor TList.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TList.Notify(Ptr: Pointer; Action: TListNotification);
begin
end;

function TList.Get(Index: Integer): Pointer;
begin
  if (Index < 0) or (Index >= FCount) then
    IndexError;
  Get := FList^[Index];
end;

procedure TList.Put(Index: Integer; Item: Pointer);
var
  Old: Pointer;
begin
  if (Index < 0) or (Index >= FCount) then
    IndexError;
  Old := FList^[Index];
  if Old = Item then
    Exit;
  FList^[Index] := Item;
  if Old <> nil then
    Notify(Old, lnDeleted);
  if Item <> nil then
    Notify(Item, lnAdded);
end;

procedure TList.SetCapacity(NewCapacity: Integer);
var
  NewList: PPointerList;
begin
  if (NewCapacity < FCount) or (NewCapacity > MaxListSize) then
    IndexError;
  if NewCapacity = FCapacity then
    Exit;
  NewList := nil;
  if NewCapacity > 0 then
  begin
    GetMem(NewList, NewCapacity * SizeOf(Pointer));
    if FCount > 0 then
      System.Move(FList^, NewList^, FCount * SizeOf(Pointer));
  end;
  if FCapacity > 0 then
    FreeMem(FList, FCapacity * SizeOf(Pointer));
  FList := NewList;
  FCapacity := NewCapacity;
end;

procedure TList.SetCount(NewCount: Integer);
var
  I: Integer;
begin
  if NewCount < 0 then
    IndexError;
  if NewCount > FCapacity then
    SetCapacity(NewCount);
  if NewCount > FCount then
    for I := FCount to NewCount - 1 do
      FList^[I] := nil
  else
    for I := FCount - 1 downto NewCount do
      Delete(I);
  FCount := NewCount;
end;

procedure TList.Grow;
begin
  if FCapacity < 8 then
    SetCapacity(8)
  else
    SetCapacity(FCapacity * 2);
end;

function TList.Add(Item: Pointer): Integer;
begin
  if FCount = FCapacity then
    Grow;
  FList^[FCount] := Item;
  Add := FCount;
  Inc(FCount);
  if Item <> nil then
    Notify(Item, lnAdded);
end;

procedure TList.Insert(Index: Integer; Item: Pointer);
begin
  if (Index < 0) or (Index > FCount) then
    IndexError;
  if FCount = FCapacity then
    Grow;
  if Index < FCount then
    System.Move(FList^[Index], FList^[Index + 1], (FCount - Index) * SizeOf(Pointer));
  FList^[Index] := Item;
  Inc(FCount);
  if Item <> nil then
    Notify(Item, lnAdded);
end;

procedure TList.Delete(Index: Integer);
var
  Item: Pointer;
begin
  if (Index < 0) or (Index >= FCount) then
    IndexError;
  Item := FList^[Index];
  Dec(FCount);
  if Index < FCount then
    System.Move(FList^[Index + 1], FList^[Index], (FCount - Index) * SizeOf(Pointer));
  if Item <> nil then
    Notify(Item, lnDeleted);
end;

function TList.Extract(Item: Pointer): Pointer;
var
  I: Integer;
begin
  Extract := nil;
  I := IndexOf(Item);
  if I < 0 then
    Exit;
  Dec(FCount);
  if I < FCount then
    System.Move(FList^[I + 1], FList^[I], (FCount - I) * SizeOf(Pointer));
  Extract := Item;
  Notify(Item, lnExtracted);
end;

function TList.Remove(Item: Pointer): Integer;
var
  I: Integer;
begin
  I := IndexOf(Item);
  if I >= 0 then
    Delete(I);
  Remove := I;
end;

function TList.IndexOf(Item: Pointer): Integer;
var
  I: Integer;
begin
  IndexOf := -1;
  for I := 0 to FCount - 1 do
    if FList^[I] = Item then
    begin
      IndexOf := I;
      Exit;
    end;
end;

procedure TList.Clear;
begin
  SetCount(0);
  SetCapacity(0);
end;

procedure TList.Exchange(Index1, Index2: Integer);
var
  T: Pointer;
begin
  if (Index1 < 0) or (Index1 >= FCount) or (Index2 < 0) or (Index2 >= FCount) then
    IndexError;
  T := FList^[Index1];
  FList^[Index1] := FList^[Index2];
  FList^[Index2] := T;
end;

procedure TList.Move(CurIndex, NewIndex: Integer);
var
  Item: Pointer;
begin
  if CurIndex = NewIndex then
    Exit;
  if (NewIndex < 0) or (NewIndex >= FCount) then
    IndexError;
  Item := Get(CurIndex);
  FList^[CurIndex] := nil;
  Delete(CurIndex);
  Insert(NewIndex, nil);
  FList^[NewIndex] := Item;
end;

procedure TList.Pack;
var
  I, J: Integer;
begin
  J := 0;
  for I := 0 to FCount - 1 do
    if FList^[I] <> nil then
    begin
      FList^[J] := FList^[I];
      Inc(J);
    end;
  FCount := J;
end;

{ Insertion sort: stable, and quick enough for the lists of exercises. }
procedure TList.Sort(Compare: TListSortCompare);
var
  I, J: Integer;
  Item: Pointer;
begin
  for I := 1 to FCount - 1 do
  begin
    Item := FList^[I];
    J := I - 1;
    while (J >= 0) and (Compare(FList^[J], Item) > 0) do
    begin
      FList^[J + 1] := FList^[J];
      Dec(J);
    end;
    FList^[J + 1] := Item;
  end;
end;

function TList.First: Pointer;
begin
  First := Get(0);
end;

function TList.Last: Pointer;
begin
  Last := Get(FCount - 1);
end;

{ ---- TStringList ---------------------------------------------------------- }

{ Strings live on the heap: length byte and characters only. }
function NewString(const S: String): PString;
var
  P: PString;
begin
  GetMem(P, Length(S) + 1);
  System.Move(S, P^, Length(S) + 1);
  NewString := P;
end;

procedure DisposeString(P: PString);
begin
  if P <> nil then
    FreeMem(P, Length(P^) + 1);
end;

constructor TStringList.Create;
begin
  inherited Create;
  FStrings := TList.Create;
  FObjects := TList.Create;
end;

destructor TStringList.Destroy;
begin
  Clear;
  FStrings.Free;
  FObjects.Free;
  inherited Destroy;
end;

function TStringList.GetCount: Integer;
begin
  GetCount := FStrings.Count;
end;

function TStringList.Get(Index: Integer): String;
begin
  Get := PString(FStrings[Index])^;
end;

procedure TStringList.Put(Index: Integer; const S: String);
var
  Old: PString;
begin
  Old := PString(FStrings[Index]);
  FStrings[Index] := NewString(S);
  DisposeString(Old);
end;

function TStringList.GetObject(Index: Integer): TObject;
begin
  GetObject := TObject(FObjects[Index]);
end;

procedure TStringList.PutObject(Index: Integer; AObject: TObject);
begin
  FObjects[Index] := AObject;
end;

function TStringList.Compare(const S1, S2: String): Integer;
var
  I, N: Integer;
  A, B: Char;
begin
  N := Length(S1);
  if Length(S2) < N then
    N := Length(S2);
  for I := 1 to N do
  begin
    A := S1[I];
    B := S2[I];
    if not FCaseSensitive then
    begin
      A := UpCase(A);
      B := UpCase(B);
    end;
    if A < B then
    begin
      Compare := -1;
      Exit;
    end;
    if A > B then
    begin
      Compare := 1;
      Exit;
    end;
  end;
  if Length(S1) < Length(S2) then
    Compare := -1
  else if Length(S1) > Length(S2) then
    Compare := 1
  else
    Compare := 0;
end;

procedure TStringList.InsertItem(Index: Integer; const S: String; AObject: TObject);
begin
  FStrings.Insert(Index, NewString(S));
  FObjects.Insert(Index, AObject);
end;

function TStringList.Add(const S: String): Integer;
begin
  Add := AddObject(S, nil);
end;

function TStringList.AddObject(const S: String; AObject: TObject): Integer;
var
  I: Integer;
begin
  if FSorted then
  begin
    { After any equal strings, so equal ones keep their order. }
    Find(S, I);
    while (I < Count) and (Compare(Get(I), S) = 0) do
      Inc(I);
  end
  else
    I := Count;
  InsertItem(I, S, AObject);
  AddObject := I;
end;

{ In a sorted list the string goes where it belongs, not at Index. }
procedure TStringList.Insert(Index: Integer; const S: String);
begin
  if FSorted then
    Add(S)
  else
  begin
    if (Index < 0) or (Index > Count) then
      IndexError;
    InsertItem(Index, S, nil);
  end;
end;

procedure TStringList.Delete(Index: Integer);
begin
  DisposeString(PString(FStrings[Index]));
  FStrings.Delete(Index);
  FObjects.Delete(Index);
end;

procedure TStringList.Clear;
var
  I: Integer;
begin
  for I := 0 to FStrings.Count - 1 do
    DisposeString(PString(FStrings[I]));
  FStrings.Clear;
  FObjects.Clear;
end;

procedure TStringList.Exchange(Index1, Index2: Integer);
begin
  FStrings.Exchange(Index1, Index2);
  FObjects.Exchange(Index1, Index2);
end;

function TStringList.IndexOf(const S: String): Integer;
var
  I: Integer;
begin
  if FSorted then
  begin
    if Find(S, I) then
      IndexOf := I
    else
      IndexOf := -1;
    Exit;
  end;
  IndexOf := -1;
  for I := 0 to Count - 1 do
    if Compare(Get(I), S) = 0 then
    begin
      IndexOf := I;
      Exit;
    end;
end;

function TStringList.IndexOfObject(AObject: TObject): Integer;
begin
  IndexOfObject := FObjects.IndexOf(AObject);
end;

function TStringList.Find(const S: String; var Index: Integer): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Find := False;
  Lo := 0;
  Hi := Count - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := Compare(Get(Mid), S);
    if C < 0 then
      Lo := Mid + 1
    else
    begin
      if C = 0 then
        Find := True;
      Hi := Mid - 1;
    end;
  end;
  Index := Lo;
end;

{ Insertion sort, stable like the sorted inserts of Add. }
procedure TStringList.Sort;
var
  I, J: Integer;
  S, O: Pointer;
begin
  for I := 1 to Count - 1 do
  begin
    S := FStrings[I];
    O := FObjects[I];
    J := I - 1;
    while (J >= 0) and (Compare(PString(FStrings[J])^, PString(S)^) > 0) do
    begin
      FStrings[J + 1] := FStrings[J];
      FObjects[J + 1] := FObjects[J];
      Dec(J);
    end;
    FStrings[J + 1] := S;
    FObjects[J + 1] := O;
  end;
end;

procedure TStringList.SetSorted(Value: Boolean);
begin
  if Value and not FSorted then
  begin
    FSorted := True;
    Sort;
  end
  else
    FSorted := Value;
end;

procedure TStringList.SetCaseSensitive(Value: Boolean);
begin
  if Value = FCaseSensitive then
    Exit;
  FCaseSensitive := Value;
  if FSorted then
    Sort;
end;

{ One string per line; an I/O error is a runtime error ($I+). }
procedure TStringList.LoadFromFile(const FileName: String);
var
  F: Text;
  Line: String;
begin
  Assign(F, FileName);
  Reset(F);
  Clear;
  while not Eof(F) do
  begin
    ReadLn(F, Line);
    Add(Line);
  end;
  Close(F);
end;

procedure TStringList.SaveToFile(const FileName: String);
var
  F: Text;
  I: Integer;
begin
  Assign(F, FileName);
  Rewrite(F);
  for I := 0 to Count - 1 do
    WriteLn(F, Get(I));
  Close(F);
end;

end.
