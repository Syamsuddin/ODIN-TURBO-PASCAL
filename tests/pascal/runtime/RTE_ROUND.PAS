{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTEROUND;
{ Round of a real outside Int64: runtime error 207. }
var
  X: Real;
begin
  WriteLn('start');
  X := -1e25;
  WriteLn(Round(X));
  WriteLn('not reached');
end.
