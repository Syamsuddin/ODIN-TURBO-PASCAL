{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngLoops;
{ Break and Continue in repeat and while loops, nested loops, inside
  case and with, conditions re-evaluated after Continue. }
type
  TRec = record
    N: Integer;
  end;
var
  I, J, K, Total, Evals: Integer;
  S: String;
  R: TRec;

function Check(Value, Limit: Integer): Boolean;
begin
  Inc(Evals);
  Check := Value < Limit;
end;

begin
  I := 0;
  S := '';
  repeat
    Inc(I);
    if I = 3 then Continue;
    S := S + Chr(Ord('0') + I);
  until I >= 3;
  WriteLn('repeat continue tests until: ', S, ' I=', I);
  I := 0;
  S := '';
  repeat
    Inc(I);
    if Odd(I) then Continue;
    if I > 10 then Break;
    S := S + Chr(Ord('a') + I);
  until False;
  WriteLn('repeat break: ', S, ' I=', I);
  I := 0;
  Evals := 0;
  S := '';
  while Check(I, 8) do
  begin
    Inc(I);
    if I mod 3 = 0 then Continue;
    S := S + Chr(Ord('0') + I);
  end;
  WriteLn('while continue: ', S, ' evals=', Evals);
  I := 0;
  Evals := 0;
  while Check(I, 100) do
  begin
    Inc(I, 7);
    if I > 30 then Break;
  end;
  WriteLn('while break I=', I, ' evals=', Evals);
  Total := 0;
  for I := 1 to 4 do
  begin
    J := 0;
    while True do
    begin
      Inc(J);
      if J > I then Break;
      K := 0;
      repeat
        Inc(K);
        if K = 2 then Continue;
        Inc(Total, K);
      until K >= J;
    end;
  end;
  WriteLn('nested total=', Total, ' I=', I);
  S := '';
  for I := 1 to 10 do
  begin
    case I mod 4 of
      0: Continue;
      3: if I > 6 then Break;
    end;
    S := S + Chr(Ord('A') + I);
  end;
  WriteLn('case in loop: ', S, ' stopped I=', I);
  R.N := 0;
  with R do
    while N < 50 do
    begin
      Inc(N, 9);
      if N = 27 then Continue;
      if N > 40 then Break;
      Write(N, ' ');
    end;
  WriteLn('with loop N=', R.N);
  I := 10;
  while I > 0 do
  begin
    Dec(I);
    repeat
      Dec(I, 2);
      if I < 5 then Break;
    until I mod 2 = 0;
    if I < 0 then Break;
    Write(I, ' ');
  end;
  WriteLn('mixed I=', I);
  Total := 0;
  I := 0;
  repeat
    J := 0;
    repeat
      Inc(J);
      if J = 3 then Break;
      Inc(Total);
    until J = 10;
    Inc(I);
  until I = 5;
  WriteLn('repeat in repeat total=', Total);
end.
