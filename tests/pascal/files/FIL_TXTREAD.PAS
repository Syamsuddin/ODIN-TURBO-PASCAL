{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program FilTxtRead;
{ Read and ReadLn of integers, reals, chars and strings from a text file:
  several values per line, values spread over lines, blank lines. }
var
  F: Text;
  S, T: String;
  S5: String[5];
  I, J, K: Integer;
  L: LongInt;
  B: Byte;
  W: Word;
  R1, R2: Real;
  C, D: Char;
begin
  Assign(F, 'mixed.txt');
  Rewrite(F);
  WriteLn(F, '10 20 30');
  WriteLn(F, '  -7   8');
  WriteLn(F);
  WriteLn(F, '3.25 -1.5e2 7');
  WriteLn(F, '42 hello world');
  WriteLn(F, 'ab');
  WriteLn(F, 'abcdefghij');
  WriteLn(F, '$1F 0');
  WriteLn(F, '255 65535 -2000000000');
  WriteLn(F);
  WriteLn(F);
  WriteLn(F, '   5');
  WriteLn(F, '6 x');
  WriteLn(F, 'long line that is cut');
  WriteLn(F, 'after');
  Close(F);

  Reset(F);
  Read(F, I, J);
  WriteLn('two ints: ', I, ' ', J, ' eoln=', Eoln(F));
  Read(F, K);
  WriteLn('third: ', K, ' eoln=', Eoln(F));
  Read(F, I);
  WriteLn('on next line: ', I, ' eoln=', Eoln(F));
  ReadLn(F, J);
  WriteLn('readln: ', J, ' eoln=', Eoln(F));
  ReadLn(F, S);
  WriteLn('blank line: [', S, '] len=', Length(S));
  Read(F, R1, R2, L);
  WriteLn('reals: ', R1:0:3, ' ', R2:0:3, ' longint: ', L);
  ReadLn(F);
  Read(F, I, S);
  WriteLn('int then string: ', I, ' [', S, ']');
  ReadLn(F);
  Read(F, C, D);
  WriteLn('chars: ', C, D, ' eoln=', Eoln(F));
  Read(F, C);
  WriteLn('char at eoln: ', Ord(C), ' eoln=', Eoln(F));
  Read(F, S5);
  WriteLn('short 1: [', S5, ']');
  Read(F, S5);
  WriteLn('short 2: [', S5, ']');
  Read(F, S5);
  WriteLn('short 3: [', S5, '] eoln=', Eoln(F));
  Read(F, T);
  WriteLn('string at eoln: [', T, ']');
  ReadLn(F);
  ReadLn(F, I, J);
  WriteLn('hex: ', I, ' ', J);
  ReadLn(F, B, W, L);
  WriteLn('byte word longint: ', B, ' ', W, ' ', L);
  Read(F, I);
  WriteLn('int after blank lines: ', I);
  Read(F, J, C, D);
  WriteLn('int then chars: ', J, ' [', C, '] [', D, ']');
  ReadLn(F);
  ReadLn(F, S5);
  WriteLn('readln short: [', S5, ']');
  ReadLn(F, S);
  WriteLn('next line: [', S, '] eof=', Eof(F));
  Close(F);
end.
