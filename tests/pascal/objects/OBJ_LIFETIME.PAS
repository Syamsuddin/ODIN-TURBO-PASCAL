{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjLifetime;
{ Constructors and destructors: Fail (static call and New), New and
  Dispose with constructor/destructor (procedure and function forms),
  virtual destructors through ancestor pointers, SizeOf of an instance
  read from its VMT, constructors used as Boolean expressions. }
type
  PItem = ^TItem;
  TItem = object
    Id: Integer;
    constructor Init(AId: Integer);
    destructor Done; virtual;
  end;
  PBig = ^TBig;
  TBig = object(TItem)
    Data: array[1..10] of LongInt;
    constructor Init(AId: Integer);
    destructor Done; virtual;
  end;
  PPicky = ^TPicky;
  TPicky = object(TItem)
    constructor Init(AId: Integer);
  end;

var
  Live: Integer;

constructor TItem.Init(AId: Integer);
begin
  Id := AId;
  Inc(Live);
  WriteLn('item ', Id, ' up, live ', Live);
end;

destructor TItem.Done;
begin
  Dec(Live);
  WriteLn('item ', Id, ' down, live ', Live);
end;

constructor TBig.Init(AId: Integer);
var
  I: Integer;
begin
  if not inherited Init(AId) then
    Fail;
  for I := 1 to 10 do
    Data[I] := I * AId;
end;

destructor TBig.Done;
begin
  WriteLn('big ', Id, ' sum ', Data[1] + Data[10]);
  inherited Done;
end;

constructor TPicky.Init(AId: Integer);
begin
  inherited Init(AId);
  if Odd(AId) then
  begin
    WriteLn('picky refuses ', AId);
    Dec(Live);
    Fail;
  end;
end;

var
  P: PItem;
  B: PBig;
  K: PPicky;
  Item: TItem;
  Picky: TPicky;
  Ok: Boolean;
begin
  Live := 0;
  New(P, Init(1));
  WriteLn('sizeof ', SizeOf(P^), ' ', SizeOf(TItem));
  Dispose(P, Done);
  P := New(PBig, Init(2));
  WriteLn('sizeof through PItem ', SizeOf(P^), ' ', SizeOf(TBig));
  Dispose(P, Done);
  B := New(PBig, Init(3));
  Dispose(B, Done);
  New(K, Init(4));
  WriteLn('picky 4 ', K <> nil);
  Dispose(K, Done);
  New(K, Init(5));
  WriteLn('picky 5 nil ', K = nil);
  K := New(PPicky, Init(7));
  WriteLn('picky 7 nil ', K = nil);
  Ok := Picky.Init(9);
  WriteLn('static picky ', Ok, ' id ', Picky.Id);
  WriteLn('static item ', Item.Init(10));
  Item.Done;
  WriteLn('live at end ', Live);
end.
