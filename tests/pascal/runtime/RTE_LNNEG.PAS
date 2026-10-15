{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTELNNEG;
{ Ln of a negative number: runtime error 207. }
var
  X: Real;
begin
  WriteLn('start');
  X := -2;
  WriteLn(Ln(X));
  WriteLn('not reached');
end.
