{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTENIL;
{ Reading through a nil pointer: runtime error 216, output written before it still appears. }
var
  P: ^LongInt;
begin
  WriteLn('start');
  P := nil;
  WriteLn(P^);
  WriteLn('not reached');
end.
