{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngGoto;
{ goto out of nested loops (numeric and identifier labels), Exit from
  inside for, while, repeat, case and with, Exit in nested routines and
  in the main program. }
label
  1, 99, Again;
type
  TRec = record
    V: Integer;
  end;
var
  I, J, K, N: Integer;
  Steps: Integer;
  S, T: String;
  Rec: TRec;

procedure Search(Target: Integer);
label
  Found, Done;
var
  I, J: Integer;
begin
  for I := 1 to 5 do
    for J := 1 to 5 do
      if I * J = Target then goto Found;
  WriteLn('not found ', Target);
  goto Done;
Found:
  WriteLn('found ', Target, ' at ', I, ',', J);
Done:
end;

function FirstMultiple(Step, Limit: Integer): Integer;
var
  K: Integer;
begin
  FirstMultiple := -1;
  K := 0;
  while True do
  begin
    Inc(K);
    if K > 1000 then Exit;
    repeat
      if K * Step > Limit then
      begin
        FirstMultiple := K * Step;
        Exit;
      end;
    until True;
  end;
end;

function Classify(N: Integer): String;
var
  I: Integer;
begin
  Classify := 'prima';
  if N < 2 then
  begin
    Classify := 'bukan';
    Exit;
  end;
  for I := 2 to N - 1 do
    case N mod I of
      0:
        begin
          Classify := 'komposit';
          Exit;
        end;
    end;
end;

procedure Inner;
var
  K: Integer;

  procedure Leave;
  begin
    Write('leave ');
    Exit;
    Write('never ');
  end;

begin
  for K := 1 to 3 do
  begin
    Leave;
    Write(K, ' ');
  end;
  WriteLn('inner done');
end;

procedure WithExit(var R: TRec);
begin
  with R do
    while V < 100 do
    begin
      V := V * 2;
      if V > 20 then Exit;
    end;
  R.V := -1;
end;

begin
  Search(12);
  Search(7);
  Search(25);
  WriteLn('first ', FirstMultiple(7, 50), ' ', FirstMultiple(1, 5000));
  S := '';
  for I := 0 to 12 do
  begin
    T := Classify(I);
    S := S + T[1];
  end;
  WriteLn('classify ', S);
  Inner;
  Rec.V := 3;
  WithExit(Rec);
  WriteLn('with exit ', Rec.V);
  Rec.V := 200;
  WithExit(Rec);
  WriteLn('with exit ', Rec.V);
  Steps := 0;
  for I := 1 to 10 do
    for J := 1 to 10 do
    begin
      K := 0;
      while K < 10 do
      begin
        Inc(K);
        Inc(Steps);
        if (I = 2) and (J = 3) and (K = 4) then goto 1;
      end;
    end;
1:
  WriteLn('escaped at ', I, ' ', J, ' ', K, ' steps ', Steps);
  N := 0;
Again:
  Inc(N);
  if N < 4 then
  begin
    Write('again', N, ' ');
    goto Again;
  end;
  WriteLn;
  I := 0;
  repeat
    Inc(I);
    for J := 1 to 3 do
      if I * J = 6 then goto 99;
  until I > 10;
  WriteLn('not reached');
99:
  WriteLn('label 99 with I=', I, ' J=', J);
  for I := 1 to 3 do
  begin
    Write('main ', I, ' ');
    if I = 2 then
    begin
      WriteLn('exit main');
      Exit;
    end;
  end;
  WriteLn('never printed');
end.
