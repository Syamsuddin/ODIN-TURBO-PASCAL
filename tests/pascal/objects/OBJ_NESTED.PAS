{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjNested;
{ Methods with nested procedures that use fields, parameters and other
  methods; recursion; open array and string parameters; function methods
  returning strings and records. }
type
  TPoint = record
    X, Y: Integer;
  end;
  TStack = object
    Items: array[1..20] of Integer;
    Top: Integer;
    procedure Clear;
    procedure Push(V: Integer);
    function Pop: Integer;
    procedure PushAll(const Values: array of Integer);
    function Dump: String;
    function Sum: LongInt;
    function MinMax: TPoint;
  end;

procedure TStack.Clear;
begin
  Top := 0;
end;

procedure TStack.Push(V: Integer);
begin
  Inc(Top);
  Items[Top] := V;
end;

function TStack.Pop: Integer;
begin
  Pop := Items[Top];
  Dec(Top);
end;

procedure TStack.PushAll(const Values: array of Integer);
var
  I: Integer;
begin
  for I := 0 to High(Values) do
    Push(Values[I]);
end;

function TStack.Dump: String;
var
  S: String;

  procedure Add(I: Integer);
  var
    T: String;
  begin
    Str(Items[I], T);
    if S <> '' then
      S := S + ',';
    S := S + T;
  end;

var
  I: Integer;
begin
  S := '';
  for I := 1 to Top do
    Add(I);
  Dump := '[' + S + ']';
end;

function TStack.Sum: LongInt;

  function From(I: Integer): LongInt;
  begin
    if I > Top then
      From := 0
    else
      From := Items[I] + From(I + 1);
  end;

begin
  Sum := From(1);
end;

function TStack.MinMax: TPoint;
var
  I: Integer;
  R: TPoint;
begin
  R.X := Items[1];
  R.Y := Items[1];
  for I := 2 to Top do
  begin
    if Items[I] < R.X then R.X := Items[I];
    if Items[I] > R.Y then R.Y := Items[I];
  end;
  MinMax := R;
end;

const
  Start: array[1..4] of Integer = (5, 3, 9, 1);
var
  S: TStack;
  P: TPoint;
begin
  S.Clear;
  S.PushAll(Start);
  S.Push(7);
  WriteLn(S.Dump, ' sum ', S.Sum);
  P := S.MinMax;
  WriteLn('min ', P.X, ' max ', P.Y);
  WriteLn('pop ', S.Pop, ' ', S.Pop, ' -> ', S.Dump);
end.
