{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Control;
label 10, 20;
var
  i, j, n: Integer;
  total: LongInt;

function Fib(N: Integer): LongInt;
begin
  if N < 2 then Fib := N else Fib := Fib(N - 1) + Fib(N - 2);
end;

procedure Outer(K: Integer);
var
  Acc: Integer;

  procedure Inner(D: Integer);
  begin
    Acc := Acc + D * K;
  end;

begin
  Acc := 0;
  Inner(1); Inner(2); Inner(3);
  WriteLn('outer ', K, ' acc ', Acc);
end;

function Classify(X: Integer): String;
begin
  case X of
    0: Classify := 'nol';
    1..9: Classify := 'satuan';
    10, 20, 30: Classify := 'puluhan bulat';
    -5..-1: Classify := 'negatif kecil';
  else
    Classify := 'lain';
  end;
end;

function FirstOver(Limit: Integer): Integer;
var K: Integer;
begin
  FirstOver := -1;
  for K := 1 to 100 do
    if K * K > Limit then
    begin
      FirstOver := K;
      Exit;
    end;
end;

procedure Later; forward;

procedure Earlier;
begin
  Write('earlier ');
  Later;
end;

procedure Later;
begin
  WriteLn('later');
end;

begin
  for i := 0 to 10 do Write(Fib(i), ' ');
  WriteLn;
  Outer(10);
  for i := -6 to 31 do
    if (i mod 7 = 0) or (i < 0) then Write(Classify(i), ';');
  WriteLn;
  WriteLn('firstover ', FirstOver(50));
  total := 0;
  for i := 10 downto 1 do total := total + i;
  WriteLn('sum ', total);
  i := 0;
  repeat Inc(i, 3) until i > 10;
  WriteLn('repeat ', i);
  n := 0;
  while True do
  begin
    Inc(n);
    if n mod 2 = 0 then Continue;
    if n > 9 then Break;
    Write(n, ' ');
  end;
  WriteLn;
  for i := 1 to 3 do
    for j := 1 to 3 do
    begin
      if j = 2 then Continue;
      Write(i * 10 + j, ' ');
    end;
  WriteLn;
  i := 0;
10:
  Inc(i);
  if i < 5 then goto 10;
  WriteLn('goto ', i);
  goto 20;
  WriteLn('tidak tercetak');
20:
  Earlier;
  i := 5;
  for j := i to 3 do WriteLn('tidak');
  for j := 3 downto i do WriteLn('tidak');
  WriteLn('selesai');
end.
