{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTEINTDIV;
{ Integer division by zero: runtime error 200. }
var
  I, J: Integer;
begin
  WriteLn('start');
  J := 0;
  I := 10;
  WriteLn(I div J);
  WriteLn('not reached');
end.
