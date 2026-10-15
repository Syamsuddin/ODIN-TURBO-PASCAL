{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RTERANGE;
{ Array index out of range with range checks on ($R+): runtime error 201. }
{$R+}
var
  A: array[1..5] of Integer;
  I: Integer;
begin
  WriteLn('start');
  I := 6;
  A[I] := 1;
  WriteLn('not reached');
end.
