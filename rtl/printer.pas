{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Printer dari runtime library Odin: Lst adalah berkas teks yang
  diteruskan ke /usr/bin/lpr (printer default macOS) saat program selesai. }
unit Printer;

{$R-,Q-,I-,X+}

interface

var
  Lst: Text;

implementation

function c_mkstemp(Template: PChar): LongInt; cdecl; external 'c' name 'mkstemp';
function c_system(Command: PChar): LongInt; cdecl; external 'c' name 'system';
function c_unlink(Path: PChar): LongInt; cdecl; external 'c' name 'unlink';
function c_lseek(Fd: LongInt; Offset: Int64; Whence: LongInt): Int64; cdecl; external 'c' name 'lseek';

var
  SpoolName: array[0..63] of Char;
  Spooling: Boolean;
  OldExitProc: Pointer;

{ Sends the spooled text to lpr, if the program printed anything, and
  removes the spool file. }
procedure PrinterExit;
const
  SEEK_END = 2;
var
  Cmd: array[0..127] of Char;
  S: String;
  I: Integer;
  Size: Int64;
begin
  ExitProc := OldExitProc;
  if not Spooling then
    Exit;
  Flush(Lst);
  Size := c_lseek(TextRec(Lst).Handle, 0, SEEK_END);
  Close(Lst);
  if IOResult = 0 then;
  if Size <= 0 then
  begin
    c_unlink(@SpoolName);
    Exit;
  end;
  S := '/usr/bin/lpr ''';
  I := 0;
  while SpoolName[I] <> #0 do
  begin
    S := S + SpoolName[I];
    Inc(I);
  end;
  S := S + ''' 2>/dev/null';
  for I := 1 to Length(S) do
    Cmd[I - 1] := S[I];
  Cmd[Length(S)] := #0;
  c_system(@Cmd);
  c_unlink(@SpoolName);
end;

procedure Init;
const
  Template = '/tmp/odin-lst-XXXXXX';
var
  I, Fd: Integer;
  Name: String;
begin
  for I := 1 to Length(Template) do
    SpoolName[I - 1] := Template[I];
  SpoolName[Length(Template)] := #0;
  Fd := c_mkstemp(@SpoolName);
  Spooling := Fd >= 0;
  if not Spooling then
    Exit;
  Name := '';
  I := 0;
  while SpoolName[I] <> #0 do
  begin
    Name := Name + SpoolName[I];
    Inc(I);
  end;
  Assign(Lst, Name);
  Rewrite(Lst);
  if IOResult <> 0 then
    Spooling := False;
  OldExitProc := ExitProc;
  ExitProc := @PrinterExit;
end;

begin
  Init;
end.
