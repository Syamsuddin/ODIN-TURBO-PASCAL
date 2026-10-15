{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VFiles;
{ Odin Vision StdDlg check: a file dialog over the current directory, then
  the change-directory dialog. Prints the chosen file and the new
  directory. Driven by tests/test_vision.py. }
uses Objects, Drivers, Views, Dialogs, App, StdDlg;

var
  A: TApplication;
  S: FNameStr;
  Dir: String;
  C: Word;
begin
  A.Init;
  S := '*.PAS';
  C := A.ExecuteDialog(New(PFileDialog, Init('*.PAS', 'Open a file', '~N~ame', fdOpenButton, 100)), @S);
  if C <> cmCancel then
    A.ExecuteDialog(New(PChDirDialog, Init(cdNormal, 101)), nil);
  A.Done;
  WriteLn('FILE ', C, ' ', S);
  GetDir(0, Dir);
  WriteLn('DIR ', Dir);
end.
