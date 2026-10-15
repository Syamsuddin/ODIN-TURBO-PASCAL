{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program FilTxtEof;
{ Eof and Eoln on text files: empty file, a file with only a line break,
  a missing final line break, and reading at the end of the file. }
var
  F: Text;
  S: String;
  I, N, R: Integer;
  X: Real;
  C: Char;

procedure Make(const Content: String);
begin
  Rewrite(F);
  Write(F, Content);
  Close(F);
  Reset(F);
end;

begin
  Assign(F, 'eof.txt');
  Make('');
  WriteLn('empty: eof=', Eof(F), ' eoln=', Eoln(F));
  S := 'old';
  ReadLn(F, S);
  WriteLn('readln at eof: [', S, ']');
  I := 99;
  Read(F, I);
  WriteLn('integer at eof: ', I);
  C := 'q';
  Read(F, C);
  WriteLn('char at eof: ', Ord(C));
  {$I-}
  X := 9;
  Read(F, X);
  R := IOResult;
  {$I+}
  WriteLn('real at eof: io=', R, ' value=', X:0:1);
  Close(F);

  Make(#10);
  WriteLn('one line break: eof=', Eof(F), ' eoln=', Eoln(F));
  ReadLn(F);
  WriteLn('after readln: eof=', Eof(F), ' eoln=', Eoln(F));
  Close(F);

  Make('ab'#10'cd');
  Read(F, C);
  WriteLn('first ', C, ' eoln=', Eoln(F));
  Read(F, C);
  WriteLn('second ', C, ' eoln=', Eoln(F), ' eof=', Eof(F));
  Read(F, C);
  WriteLn('line break read as char: ', Ord(C), ' eoln=', Eoln(F));
  Read(F, C, C);
  WriteLn('last char ', C, ' eoln=', Eoln(F), ' eof=', Eof(F));
  Read(F, C);
  WriteLn('char past the end: ', Ord(C), ' eof=', Eof(F));
  Close(F);

  Make('first'#10'second'#10'third');
  N := 0;
  while not Eof(F) do
  begin
    ReadLn(F, S);
    N := N + 1;
    WriteLn('line ', N, ' [', S, '] eof=', Eof(F));
  end;
  Close(F);

  Make('x'#10#10#10);
  N := 0;
  while not Eof(F) do
  begin
    ReadLn(F, S);
    N := N + 1;
  end;
  WriteLn('lines with trailing blank lines: ', N);
  Close(F);

  Make('12 34');
  Read(F, I);
  WriteLn('read ', I, ' eoln=', Eoln(F), ' eof=', Eof(F));
  Read(F, I);
  WriteLn('read ', I, ' eoln=', Eoln(F), ' eof=', Eof(F));
  Close(F);
end.
