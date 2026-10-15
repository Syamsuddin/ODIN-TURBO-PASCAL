{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTERUNERROR;
{ RunError(N) ends the program with exit code N. }

begin
  WriteLn('start');
  RunError(123);
  WriteLn('not reached');
end.
