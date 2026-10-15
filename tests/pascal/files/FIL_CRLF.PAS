{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program FilCrLf;
{ Reading text files whose lines end in CR LF or in a lone CR. }
var
  F: Text;
  S: String;
  I, J, N: Integer;
  C: Char;
begin
  Assign(F, 'crlf.txt');
  Rewrite(F);
  Write(F, 'one'#13#10'two'#13#10#13#10'5 6'#13#10'x'#13#10);
  Write(F, 'lone'#13'cr'#13#10'end');
  Close(F);

  Reset(F);
  ReadLn(F, S);
  WriteLn('[', S, '] len=', Length(S));
  Read(F, S);
  WriteLn('[', S, '] len=', Length(S), ' eoln=', Eoln(F));
  ReadLn(F);
  ReadLn(F, S);
  WriteLn('blank [', S, '] len=', Length(S));
  Read(F, I, J);
  WriteLn('ints ', I, ' ', J, ' eoln=', Eoln(F));
  ReadLn(F);
  Read(F, C);
  WriteLn('char ', Ord(C), ' eoln=', Eoln(F));
  Read(F, C);
  WriteLn('char ', Ord(C), ' eoln=', Eoln(F));
  Read(F, C);
  WriteLn('char ', Ord(C), ' eoln=', Eoln(F));
  ReadLn(F, S);
  WriteLn('[', S, '] len=', Length(S));
  ReadLn(F, S);
  WriteLn('[', S, '] len=', Length(S));
  ReadLn(F, S);
  WriteLn('[', S, '] len=', Length(S), ' eof=', Eof(F));
  Close(F);

  Reset(F);
  N := 0;
  while not Eof(F) do
  begin
    ReadLn(F, S);
    N := N + 1;
  end;
  WriteLn('lines=', N);
  Close(F);

  Rewrite(F);
  Write(F, '7'#13#10#13#10'  8 '#13#10'9');
  Close(F);
  Reset(F);
  N := 0;
  while not SeekEof(F) do
  begin
    Read(F, I);
    N := N + I;
  end;
  WriteLn('sum over crlf lines=', N);
  Close(F);
end.
