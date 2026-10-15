{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngWith;
{ with statements: nesting, with lists, scope and shadowing, pointer
  dereferences, array elements, address evaluated once. }
type
  PNode = ^TNode;
  TInner = record
    A, B: Integer;
  end;
  TNode = record
    Name: String[10];
    Inner: TInner;
    Next: PNode;
    X: Integer;
  end;
  TPair = record
    X, Y: Integer;
  end;

var
  N1, N2: TNode;
  P, Q, Q0: PNode;
  Arr: array[1..3] of TNode;
  Pairs: array[1..2] of TPair;
  Grid: array[1..2, 1..2] of TPair;
  X, I, J: Integer;
  Name: String;

procedure ShowGlobalX;
begin
  Write('[global X=', X, ']');
end;

procedure UseLocal;
var
  X: Integer;
begin
  X := 1;
  with Pairs[2] do
  begin
    X := 500;
    Y := X + 1;
  end;
  WriteLn('local X=', X, ' pair2 ', Pairs[2].X, ' ', Pairs[2].Y);
end;

begin
  X := 5;
  Name := 'global';
  with N1, Inner do
  begin
    A := 1;
    B := 2;
    Name := 'one';
    X := 10;
    ShowGlobalX;
  end;
  WriteLn(' N1 ', N1.Name, ' ', N1.Inner.A, ' ', N1.Inner.B, ' ', N1.X, ' X=', X, ' Name=', Name);
  with N2 do
    with Inner do
    begin
      A := 3;
      B := A * 10;
      X := A + B;
      Name := 'two';
    end;
  WriteLn('N2 ', N2.Name, ' ', N2.Inner.A, ' ', N2.Inner.B, ' ', N2.X);
  Pairs[1].X := 0; Pairs[1].Y := 0;
  with Pairs[1] do
    with N1 do X := 99;
  WriteLn('inner wins ', N1.X, ' ', Pairs[1].X);
  with N1 do
    with Pairs[1] do X := 7;
  WriteLn('inner wins ', N1.X, ' ', Pairs[1].X);
  with N1 do
    with N2 do Inner.A := X;
  WriteLn('same type ', N1.Inner.A, ' ', N2.Inner.A);
  New(P);
  with P^ do
  begin
    Name := 'heap';
    Inner.A := 3;
    Next := nil;
    X := 30;
  end;
  New(Q);
  Q^.Next := P;
  with Q^, Next^ do
  begin
    Name := 'chain';
    Inner.B := -4;
  end;
  WriteLn('heap ', P^.Name, ' ', P^.Inner.A, ' ', P^.Inner.B, ' ', P^.X, ' ', Q^.Next = P);
  with Q^.Next^.Inner do A := A + 100;
  WriteLn('deref chain ', P^.Inner.A);
  Q^.X := 1;
  Q0 := Q;
  with Q^ do
  begin
    Q := Next;
    X := 77;
  end;
  WriteLn('evaluated once ', Q = P, ' ', Q0^.X, ' ', P^.X);
  for I := 1 to 3 do Arr[I].X := I;
  I := 2;
  with Arr[I] do
  begin
    I := 3;
    X := 50;
  end;
  WriteLn('array once ', Arr[1].X, ' ', Arr[2].X, ' ', Arr[3].X, ' I=', I);
  for I := 1 to 2 do
    for J := 1 to 2 do
      with Grid[I, J] do
      begin
        X := I;
        Y := J;
      end;
  with Grid[2, 1] do WriteLn('grid ', X, Y, ' ', Grid[1, 2].X, Grid[1, 2].Y);
  UseLocal;
  with Arr[1], Inner do
  begin
    A := 8;
    with Pairs[1] do
    begin
      Y := A;
      X := Inner.A + 1;
    end;
  end;
  WriteLn('mixed ', Pairs[1].X, ' ', Pairs[1].Y, ' ', Arr[1].X);
  Dispose(P);
  Dispose(Q0);
  WriteLn('end X=', X);
end.
