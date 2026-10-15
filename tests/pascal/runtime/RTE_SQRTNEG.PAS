{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTESQRTNEG;
{ Square root of a negative number: runtime error 207. }
var
  X: Real;
begin
  WriteLn('start');
  X := -1;
  WriteLn(Sqrt(X));
  WriteLn('not reached');
end.
