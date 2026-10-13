{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Rekursi;

function Faktorial(N: Integer): LongInt;
begin
  if N <= 1 then
    Faktorial := 1
  else
    Faktorial := N * Faktorial(N - 1);
end;

var I: Integer;
begin
  for I := 0 to 10 do
    WriteLn(I:2, '! = ', Faktorial(I):8);
end.
