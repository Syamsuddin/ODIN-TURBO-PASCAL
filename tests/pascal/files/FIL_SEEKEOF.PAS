{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program FilSeekEof;
{ SeekEof skips blanks, tabs and line breaks; SeekEoln skips blanks and
  tabs up to the end of the line. }
var
  F: Text;
  I, Sum, Count, Line: Integer;
  C: Char;
begin
  Assign(F, 'seek.txt');
  Rewrite(F);
  WriteLn(F, ' 1 2  ');
  WriteLn(F, #9'3   ');
  WriteLn(F);
  WriteLn(F, '   ');
  WriteLn(F, '4'#9'5'#9);
  Write(F, '  '#9);
  Close(F);

  Reset(F);
  Sum := 0;
  while not SeekEof(F) do
  begin
    Read(F, I);
    Sum := Sum + I;
    WriteLn('got ', I, ' seekeoln=', SeekEoln(F), ' eoln=', Eoln(F));
  end;
  WriteLn('sum=', Sum, ' eof=', Eof(F), ' seekeof again=', SeekEof(F));
  Close(F);

  Reset(F);
  Line := 0;
  while not SeekEof(F) do
  begin
    Line := Line + 1;
    Count := 0;
    while not SeekEoln(F) do
    begin
      Read(F, I);
      Count := Count + 1;
    end;
    ReadLn(F);
    WriteLn('line ', Line, ' numbers=', Count);
  end;
  Close(F);

  Reset(F);
  WriteLn('start: seekeoln=', SeekEoln(F));
  Read(F, C);
  WriteLn('seekeoln skipped the blank, char=', C);
  Read(F, I);
  WriteLn('after 2: eoln=', Eoln(F), ' seekeoln=', SeekEoln(F), ' eoln=', Eoln(F));
  Read(F, C);
  WriteLn('next char code=', Ord(C));
  Close(F);

  Rewrite(F);
  Close(F);
  Reset(F);
  WriteLn('empty: seekeof=', SeekEof(F), ' seekeoln=', SeekEoln(F));
  Close(F);
end.
