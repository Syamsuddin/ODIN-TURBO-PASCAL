{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program FilTxtBasic;
{ Text files: Assign, Rewrite, Reset, Append, Close, opening an open file
  again, Text as a var parameter and several files open at the same time. }
var
  F: Text;
  Many: array[1..3] of Text;
  S, Num: String;
  I, N: Integer;

procedure Dump(var T: Text; const Title: String);
var
  Line: String;
  Count: Integer;
begin
  Reset(T);
  Count := 0;
  while not Eof(T) do
  begin
    ReadLn(T, Line);
    Count := Count + 1;
    WriteLn(Title, ' ', Count, ': [', Line, ']');
  end;
  Close(T);
  WriteLn(Title, ' lines=', Count);
end;

begin
  Assign(F, 'basic.txt');
  Rewrite(F);
  WriteLn(F, 'alpha');
  WriteLn(F, 'beta');
  Write(F, 'gam');
  Write(F, 'ma');
  WriteLn(F);
  Close(F);
  Dump(F, 'new');

  { Rewrite of an existing file empties it }
  Rewrite(F);
  WriteLn(F, 'only');
  Close(F);
  Dump(F, 'rewritten');

  { Append writes at the end, also onto a last line without a line break }
  Append(F);
  Write(F, 'tail');
  Close(F);
  Append(F);
  WriteLn(F, '-joined');
  WriteLn(F, 'last');
  Close(F);
  Dump(F, 'appended');

  { Reset of a file that is already open starts again at the beginning }
  Reset(F);
  ReadLn(F, S);
  ReadLn(F, S);
  WriteLn('second line [', S, ']');
  Reset(F);
  ReadLn(F, S);
  WriteLn('after reset again [', S, ']');
  { Rewrite of a file that is open for reading empties it }
  Rewrite(F);
  WriteLn(F, 'replaced');
  Close(F);
  Dump(F, 'reopened');

  { Several files open at once }
  for I := 1 to 3 do
  begin
    Str(I, Num);
    Assign(Many[I], 'many' + Num + '.txt');
    Rewrite(Many[I]);
  end;
  for N := 1 to 4 do
    for I := 1 to 3 do
      WriteLn(Many[I], 'file ', I, ' row ', N);
  for I := 1 to 3 do
    Close(Many[I]);
  for I := 3 downto 1 do
    Reset(Many[I]);
  ReadLn(Many[2], S);
  WriteLn('many2 first [', S, ']');
  ReadLn(Many[3], S);
  ReadLn(Many[3], S);
  WriteLn('many3 second [', S, ']');
  ReadLn(Many[1], S);
  WriteLn('many1 first [', S, ']');
  N := 0;
  while not Eof(Many[3]) do
  begin
    ReadLn(Many[3], S);
    N := N + 1;
  end;
  WriteLn('many3 remaining=', N);
  for I := 1 to 3 do
    Close(Many[I]);

  { Assign only stores the name; a closed variable can be assigned again }
  Assign(F, 'many1.txt');
  Reset(F);
  ReadLn(F, S);
  Close(F);
  WriteLn('reassigned [', S, ']');
end.
