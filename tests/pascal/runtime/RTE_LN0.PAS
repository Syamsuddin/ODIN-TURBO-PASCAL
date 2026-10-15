{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTELN0;
{ Ln(0) divides by zero: runtime error 200. }
var
  X: Real;
begin
  WriteLn('start');
  X := 0;
  WriteLn(Ln(X));
  WriteLn('not reached');
end.
