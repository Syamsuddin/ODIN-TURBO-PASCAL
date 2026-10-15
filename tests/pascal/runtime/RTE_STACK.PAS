{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RteStack;
{ Endless recursion overflows the stack. FPC 3.2.2 dies from SIGSEGV
  (exit 139) and loses buffered output; Odin ends with runtime error 202
  after flushing it (see DEVIATIONS.md, expectations written by hand). }
function Down(N: LongInt): LongInt;
var
  Pad: array[1..64] of LongInt;
begin
  Pad[1] := N;
  Down := Down(N + 1) + Pad[1];
end;

begin
  WriteLn('start');
  WriteLn(Down(1));
  WriteLn('not reached');
end.
