{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RteExitProc;
{ A runtime error from a processor fault still runs the ExitProc chain,
  which sees ExitCode and ErrorAddr. Clearing ErrorAddr there removes the
  message; the exit code stays. }
var
  OldExit: Pointer;
  P: ^Integer;

procedure Bye;
begin
  ExitProc := OldExit;
  WriteLn('exitproc code ', ExitCode, ' addr set ', ErrorAddr <> nil);
  ErrorAddr := nil;
end;

begin
  OldExit := ExitProc;
  ExitProc := @Bye;
  WriteLn('start');
  P := nil;
  P^ := 1;
  WriteLn('not reached');
end.
