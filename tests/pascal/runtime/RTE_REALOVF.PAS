{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTEREALOVF;
{ Real overflow: runtime error 205. Underflow is silent and gives 0. }
var
  X, Y: Real;
begin
  WriteLn('start');
  Y := 1e-300;
  Y := Y * Y;
  WriteLn(Y);
  X := 1e300;
  X := X * X;
  WriteLn(X);
  WriteLn('not reached');
end.
