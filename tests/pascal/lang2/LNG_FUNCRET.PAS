{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngFuncRet;
{ Functions returning records, strings, reals, sets and pointers,
  used directly inside expressions and as arguments. }
type
  TPoint = record
    X, Y: Integer;
  end;
  TBig = record
    Vals: array[1..10] of LongInt;
    Tag: String[5];
  end;
  Str5 = String[5];
  TDigits = set of 0..9;
  PInt = ^Integer;

var
  P, Q: TPoint;
  Pts: array[1..3] of TPoint;
  B: TBig;
  S: String;
  R: Real;
  I: Integer;
  D: TDigits;
  Target: Integer;

function MkPoint(X, Y: Integer): TPoint;
var T: TPoint;
begin
  T.X := X;
  T.Y := Y;
  MkPoint := T;
end;

function AddP(const A, B: TPoint): TPoint;
begin
  AddP.X := A.X + B.X;
  AddP.Y := A.Y + B.Y;
end;

function Dist2(P: TPoint): LongInt;
begin
  Dist2 := LongInt(P.X) * P.X + LongInt(P.Y) * P.Y;
end;

function MkBig(Base: LongInt; const T: String): TBig;
var K: Integer;
begin
  for K := 1 to 10 do MkBig.Vals[K] := Base * K;
  MkBig.Tag := T;
end;

function SumBig(const X: TBig): LongInt;
var K: Integer; T: LongInt;
begin
  T := 0;
  for K := 1 to 10 do T := T + X.Vals[K];
  SumBig := T;
end;

function Rev(const S: String): String;
var K: Integer; T: String;
begin
  T := '';
  for K := Length(S) downto 1 do T := T + S[K];
  Rev := T;
end;

function Repl(C: Char; N: Integer): String;
begin
  if N <= 0 then Repl := '' else Repl := C + Repl(C, N - 1);
end;

function Short(const S: String): Str5;
begin
  Short := S;
end;

function Avg(A, B: Real): Real;
begin
  Avg := (A + B) / 2;
end;

function Poly(X: Real): Real;
begin
  Poly := 2 * X * X - 3 * X + 1;
end;

function Evens(Hi: Integer): TDigits;
var K: Integer; T: TDigits;
begin
  T := [];
  K := 0;
  while K <= Hi do
  begin
    T := T + [K];
    K := K + 2;
  end;
  Evens := T;
end;

function AddrOf(var X: Integer): PInt;
begin
  AddrOf := @X;
end;

function Swapped(P: TPoint): TPoint;
begin
  Swapped := MkPoint(P.Y, P.X);
end;

begin
  P := MkPoint(3, 4);
  WriteLn('mk ', P.X, ' ', P.Y, ' d2=', Dist2(P));
  WriteLn('nested d2=', Dist2(AddP(MkPoint(1, 2), AddP(P, MkPoint(-10, 20)))));
  Q := Swapped(Swapped(Swapped(P)));
  WriteLn('swapped ', Q.X, ' ', Q.Y);
  P := AddP(P, P);
  WriteLn('self ', P.X, ' ', P.Y);
  for I := 1 to 3 do Pts[I] := MkPoint(I, I * I);
  Pts[2] := AddP(Pts[1], Pts[3]);
  WriteLn('pts ', Pts[1].X, ':', Pts[1].Y, ' ', Pts[2].X, ':', Pts[2].Y, ' ', Pts[3].X, ':', Pts[3].Y);
  B := MkBig(7, 'seven-long');
  WriteLn('big ', B.Vals[1], ' ', B.Vals[10], ' ', B.Tag, ' ', SumBig(B), ' ', SumBig(MkBig(-1, '')));
  S := Rev('abc') + '-' + Rev(Rev('def')) + '-' + Repl('x', 3);
  WriteLn(S, ' ', Length(Rev(S)), ' ', Pos('cba', Rev('zabcz')), ' ', Copy(Rev('12345'), 2, 3));
  WriteLn(Rev('level') = 'level', ' ', Rev('ab') < Rev('ba'), ' ', Short('truncated'), ' ', Length(Short('abcdefgh')));
  S := Short(Rev('0123456789')) + Short('xy');
  WriteLn(S);
  R := Avg(1, 2) * 2 + Avg(10, 20) / 5;
  WriteLn('avg ', R:0:3, ' ', Avg(Avg(1, 3), Avg(5, 7)):0:2);
  R := Poly(Avg(2, 4)) - Poly(0);
  WriteLn('poly ', R:0:2, ' ', Round(Poly(2.5)), ' ', Trunc(Poly(-1.5)), ' ', Poly(1) = 0);
  WriteLn('cmp ', Avg(1, 2) > 1.4, ' ', Avg(1, 2) < 1.5, ' ', Sqrt(Avg(8, 10)):0:4);
  D := Evens(9);
  for I := 0 to 9 do if I in D then Write(I);
  WriteLn(' ', 4 in Evens(4), ' ', 6 in Evens(5), ' ', Evens(3) <= Evens(9), ' ', Evens(-1) = []);
  Target := 10;
  AddrOf(Target)^ := 99;
  WriteLn('ptr ', Target, ' ', AddrOf(Target)^ + 1);
end.
