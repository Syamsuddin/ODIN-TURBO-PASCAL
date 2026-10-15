{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngNest;
{ Nested procedures three levels deep: outer locals, value and var
  parameters, globals, recursion through static links. }
var
  G: Integer;
  X: Integer;
  Even: Boolean;

procedure Level1(var V: Integer; P: Integer);
var
  A: Integer;
  S: String[20];

  procedure Sibling(K: Integer);
  begin
    A := A * K;
    S := S + '*';
  end;

  procedure Level2(var W: Integer);
  var
    B: Integer;

    procedure Level3(C: Integer);
    var
      D: Integer;
    begin
      D := C * 2;
      A := A + D;
      B := B + 1;
      V := V + 100;
      W := W + 1000;
      P := P - 1;
      G := G + 1;
      S := S + Chr(Ord('a') + C);
      if C = 2 then Sibling(3);
      WriteLn('    L3 C=', C, ' D=', D, ' A=', A, ' B=', B, ' P=', P, ' V=', V, ' W=', W);
    end;

  begin
    B := 10;
    Level3(1);
    Level3(2);
    WriteLn('  L2 B=', B, ' W=', W);
  end;

begin
  A := 5;
  S := '';
  Level2(V);
  WriteLn(' L1 A=', A, ' P=', P, ' V=', V, ' S=', S);
  Level2(A);
  WriteLn(' L1 A=', A, ' P=', P, ' V=', V, ' S=', S);
end;

function SumDigits(N: LongInt): Integer;
var
  Calls: Integer;

  function Rec(M: LongInt): Integer;
  var
    Here: Integer;
  begin
    Inc(Calls);
    Here := M mod 10;
    if M < 10 then
      Rec := Here
    else
      Rec := Here + Rec(M div 10);
    Write(Here);
  end;

begin
  Calls := 0;
  SumDigits := Rec(N);
  Write(' calls=', Calls);
end;

procedure Outer(N: Integer);
var
  L: Integer;

  procedure Show;
  begin
    Write('[', N, ':', L, ']');
  end;

begin
  L := N * 10;
  if N > 0 then
  begin
    Show;
    Outer(N - 1);
    Show;
  end;
end;

procedure Towers(N: Integer);
var
  Moves: Integer;
  Log: String;

  procedure Solve(K: Integer; From, Dest, Via: Char);

    procedure Move(F, T: Char);
    begin
      Inc(Moves);
      if Moves <= 7 then Log := Log + F + T + ' ';
    end;

  begin
    if K = 0 then Exit;
    Solve(K - 1, From, Via, Dest);
    Move(From, Dest);
    Solve(K - 1, Via, Dest, From);
  end;

begin
  Moves := 0;
  Log := '';
  Solve(N, 'A', 'C', 'B');
  WriteLn('towers ', N, ' moves=', Moves, ' log=', Log);
end;

function Parity(N: Integer; var Trace: String): Boolean;

  function IsOdd(K: Integer): Boolean; forward;

  function IsEven(K: Integer): Boolean;
  begin
    Trace := Trace + 'e';
    if K = 0 then IsEven := True else IsEven := IsOdd(K - 1);
  end;

  function IsOdd(K: Integer): Boolean;
  begin
    Trace := Trace + 'o';
    if K = 0 then IsOdd := False else IsOdd := IsEven(K - 1);
  end;

begin
  Trace := '';
  Parity := IsEven(N);
end;

function Triple(N: Integer): Integer;
var
  Local: Integer;

  procedure SetResult(K: Integer);
  begin
    Triple := K * 3;
    Local := K;
  end;

begin
  Local := 0;
  Triple := -1;
  SetResult(N);
  if Local <> N then Triple := -2;
end;

function Depth(N: Integer): Integer;
var
  Mine: Integer;

  function Inner(K: Integer): Integer;
  begin
    if K = 0 then Inner := Mine
    else Inner := Depth(K - 1) + Mine;
  end;

begin
  Mine := N + 1;
  Depth := Inner(N);
end;

var
  T: String;
  V: Integer;
  Sum: Integer;
begin
  G := 0;
  X := 7;
  Level1(X, 50);
  WriteLn('X=', X, ' G=', G);
  Sum := SumDigits(12345);
  WriteLn(' sum=', Sum);
  Sum := SumDigits(7);
  WriteLn(' sum=', Sum);
  Outer(3);
  WriteLn;
  Towers(3);
  Towers(5);
  Even := Parity(5, T);
  WriteLn('even(5)=', Even, ' trace=', T);
  Even := Parity(4, T);
  WriteLn('even(4)=', Even, ' trace=', T);
  WriteLn('triple ', Triple(14));
  V := Depth(4);
  WriteLn('depth ', V);
end.
