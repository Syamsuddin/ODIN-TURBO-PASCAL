{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program FilTxtWrite;
{ Write and WriteLn to a text file with field widths, then read it back. }
var
  F: Text;
  S: String;
  I, N: Integer;
  L: LongInt;
  R, Neg: Real;
  B: Boolean;
  C: Char;
begin
  Assign(F, 'widths.txt');
  Rewrite(F);
  I := 42;
  L := -123456;
  R := 3.14159;
  Neg := -2.5;
  B := True;
  C := 'Z';
  WriteLn(F, I:5, '|', L:10, '|', I:1, '|', L:0, '|');
  WriteLn(F, 'ab':5, '|', 'abcdef':3, '|', C:4, '|', C:0, '|');
  WriteLn(F, B:7, '|', False:2, '|', B, '|');
  WriteLn(F, R:10:3, '|', R:0:2, '|', R:8:0, '|', Neg:9:4, '|');
  WriteLn(F, R);
  WriteLn(F, R:12);
  WriteLn(F, Neg:15);
  WriteLn(F, I:-5, '|', 'x':-3, '|');
  S := 'pas';
  WriteLn(F, S:6, '|', S:1, '|', '':3, '|');
  Write(F, 'no', 'newline', 7);
  WriteLn(F);
  WriteLn(F, '');
  Write(F, I, L, C, B);
  Close(F);

  Reset(F);
  N := 0;
  while not Eof(F) do
  begin
    ReadLn(F, S);
    N := N + 1;
    WriteLn(N:2, ' [', S, ']');
  end;
  Close(F);
end.
