{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTEZEROZERO;
{ Real 0/0 is an invalid operation: runtime error 207. }
var
  X: Real;
begin
  WriteLn('start');
  X := 0;
  WriteLn(X / X);
  WriteLn('not reached');
end.
