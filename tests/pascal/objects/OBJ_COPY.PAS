{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjCopy;
{ Objects as values: assignment between instances of the same type and
  from a descendant to an ancestor (the VMT pointer is copied too, so a
  virtual call then runs the descendant's method), value and var
  parameters, objects inside records and arrays, pointer compatibility. }
type
  TBase = object
    X: Integer;
    constructor Init(AX: Integer);
    function Kind: String; virtual;
  end;
  PBase = ^TBase;
  TDerived = object(TBase)
    Y: Integer;
    constructor Init(AX, AY: Integer);
    function Kind: String; virtual;
  end;
  PDerived = ^TDerived;
  TPair = record
    First, Second: TBase;
  end;

constructor TBase.Init(AX: Integer);
begin
  X := AX;
end;

function TBase.Kind: String;
begin
  Kind := 'base';
end;

constructor TDerived.Init(AX, AY: Integer);
begin
  inherited Init(AX);
  Y := AY;
end;

function TDerived.Kind: String;
begin
  Kind := 'derived';
end;

procedure ByValue(B: TBase);
begin
  B.X := B.X + 100;
  WriteLn('by value: ', B.X, ' ', B.Kind);
end;

procedure ByVar(var B: TBase);
begin
  B.X := B.X + 1;
  WriteLn('by var: ', B.X, ' ', B.Kind);
end;

var
  A, B: TBase;
  D: TDerived;
  PB: PBase;
  PD: PDerived;
  Pair: TPair;
  List: array[1..3] of TBase;
  I: Integer;
begin
  A.Init(1);
  D.Init(2, 3);
  B := A;
  WriteLn('copy ', B.X, ' ', B.Kind);
  B := D;
  WriteLn('from derived ', B.X, ' ', B.Kind, ' typeof base ', TypeOf(B) = TypeOf(TBase));
  ByValue(A);
  WriteLn('after by value ', A.X);
  ByVar(A);
  ByVar(D);
  WriteLn('after by var ', A.X, ' ', D.X, ' ', D.Y);
  Pair.First := A;
  Pair.Second := D;
  WriteLn('pair ', Pair.First.Kind, ' ', Pair.Second.Kind, ' ', Pair.Second.X);
  for I := 1 to 3 do
    List[I].Init(I * 10);
  for I := 1 to 3 do
    Write(List[I].X, ' ');
  WriteLn;
  PD := @D;
  PB := PD;
  WriteLn('pointer ', PB^.Kind, ' ', PB^.X, ' same ', Pointer(PB) = Pointer(PD));
end.
