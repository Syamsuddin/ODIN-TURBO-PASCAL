{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosExec;
{ TP7 Dos unit on macOS: Exec runs Path directly (no PATH search) with
  ComLine split at blanks; an argument that starts with '"' runs to the
  next '"'. DosExitCode is the low byte of the exit status. When the
  program cannot start, DosError is 8 and DosExitCode 127; a signal gives
  DosError 8 and the negated signal number. Output is flushed before each
  Exec so the order is the same with either compiler. }
uses Dos;

procedure Run(const P, C: String);
begin
  Flush(Output);
  Exec(P, C);
  WriteLn('Exec [', P, '] [', C, '] err ', DosError, ' code ', DosExitCode);
end;

begin
  WriteLn('start');
  Run('/bin/sh', '-c "exit 3"');
  Run('/bin/echo', 'a  b "c d" ''e f'' g\h "x""y" z"w q"');
  Run('/bin/echo', '');
  Run('/no/such/program', 'x');
  Run('/etc/hosts', 'x');
  Run('/bin', 'x');
  Run('/bin/sh', '-c "kill -9 $$"');
  Run('/bin/sh', '-c "exit 300"');
  Run('sh', '-c "exit 4"');
  Run('/bin/sh', '-c "echo $0"');
  Run('/bin/sh', '-c "echo  [$1] [$2]" A  B');
  Run('/bin/sh', '-c "exit 127"');
  Run('/bin/sh', '-c "test -n \"$HOME\""');
end.
