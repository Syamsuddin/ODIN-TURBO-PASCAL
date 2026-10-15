{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjTConst;
{ Typed constants of object type (with and without a VMT), typed constants
  local to same-named methods of different object types, and Dispose of a
  variable typecast. }
type
  TPos = object
    X, Y: Integer;
  end;

  TBase = object
    N: Integer;
    constructor Init;
    function Name: String; virtual;
    function Count: Integer;
  end;

  TDerived = object(TBase)
    function Name: String; virtual;
    function Count: Integer;
  end;

  PRec = ^TRec;
  TRec = record
    A, B: LongInt;
  end;

const
  Origin: TPos = (X: 3; Y: 4);
  Base: TBase = (N: 7);
  Grid: array[1..2] of TPos = ((X: 1; Y: 2), (X: 5; Y: 6));

constructor TBase.Init;
begin
  N := 1;
end;

function TBase.Name: String;
begin
  Name := 'base';
end;

function TBase.Count: Integer;
const
  Calls: Integer = 0;
begin
  Inc(Calls);
  Count := Calls;
end;

function TDerived.Name: String;
begin
  Name := 'derived';
end;

function TDerived.Count: Integer;
const
  Calls: Integer = 100;
begin
  Inc(Calls);
  Count := Calls;
end;

var
  B: TBase;
  D: TDerived;
  P: Pointer;
begin
  WriteLn(Origin.X, ' ', Origin.Y, ' ', Grid[2].X + Grid[1].Y);
  WriteLn(Base.N, ' ', Base.Name);
  B.Init;
  D.Init;
  WriteLn(B.Count, ' ', B.Count, ' ', D.Count, ' ', D.Count, ' ', D.Name);
  GetMem(P, SizeOf(TRec));
  PRec(P)^.A := 5;
  PRec(P)^.B := 6;
  WriteLn(PRec(P)^.A * PRec(P)^.B);
  Dispose(PRec(P));
  WriteLn('done');
end.
