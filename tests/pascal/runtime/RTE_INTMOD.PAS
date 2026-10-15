{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTEINTMOD;
{ Integer mod by zero: runtime error 200. }
var
  I, J: LongInt;
begin
  WriteLn('start');
  J := 0;
  I := 10;
  WriteLn(I mod J);
  WriteLn('not reached');
end.
