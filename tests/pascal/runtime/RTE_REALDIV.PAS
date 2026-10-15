{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTEREALDIV;
{ Real division by zero: runtime error 200. }
var
  X: Real;
begin
  WriteLn('start');
  X := 0;
  WriteLn(1 / X);
  WriteLn('not reached');
end.
