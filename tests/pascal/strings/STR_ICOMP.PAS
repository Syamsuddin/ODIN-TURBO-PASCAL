{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrIComps;
{ StrIComp and StrLIComp. FPC folds 'A'..'Z' to lower case before
  comparing, so characters between 'Z' and 'a' ('[', '_', '`') sort
  below letters. Bytes >= #128 are not folded. }
uses Strings;
type
  TBuf = array[0..15] of Char;
var
  A, B: TBuf;
  P: PChar;
  C: Char;
  Folded: Integer;
begin
  WriteLn('icomp equal ', StrIComp('abc', 'abc'));
  WriteLn('icomp mixed equal ', StrIComp('PaScAl', 'pAsCaL'));
  WriteLn('icomp ABC abd ', StrIComp('ABC', 'abd'));
  WriteLn('icomp a B ', StrIComp('a', 'B'), ' ', StrIComp('B', 'a'));
  WriteLn('icomp underscore ', StrIComp('_', 'a'), ' ', StrIComp('a', '_'));
  WriteLn('icomp bracket ', StrIComp('[', 'a'), ' ', StrIComp('Z', '['));
  WriteLn('icomp backquote ', StrIComp('@', '`'), ' ', StrIComp('z', '{'));
  WriteLn('icomp prefix ', StrIComp('abc', 'ABCD'), ' ', StrIComp('ABCD', 'abc'));
  WriteLn('icomp empty ', StrIComp('', ''), ' ', StrIComp('', 'Q'), ' ', StrIComp('q', ''));
  WriteLn('icomp digits ', StrIComp('A1', 'a2'));
  WriteLn('icomp high not folded ', StrIComp(#228, #196), ' ', StrIComp(#196, #228));
  WriteLn('icomp high vs letter ', StrIComp(#200, 'A'));
  WriteLn('icomp after null ', StrIComp('ab'#0'x', 'AB'#0'y'));

  StrCopy(A, 'Hello World');
  StrCopy(B, 'hELLO wORLD');
  WriteLn('icomp arrays ', StrIComp(A, B));
  P := A;
  WriteLn('icomp pchar ', StrIComp(P + 6, 'WORLD'), ' ', StrIComp(P + 6, 'WORLDS'));

  Folded := 0;
  for C := 'A' to 'Z' do
  begin
    A[0] := C; A[1] := #0;
    B[0] := Chr(Ord(C) + 32); B[1] := #0;
    if StrIComp(A, B) = 0 then Inc(Folded);
  end;
  WriteLn('icomp letters folded ', Folded);
  Folded := 0;
  for C := #1 to #255 do
  begin
    A[0] := C; A[1] := #0;
    if StrIComp(A, 'a') = 0 then Inc(Folded);
  end;
  WriteLn('icomp chars equal to a ', Folded);

  WriteLn('licomp 0 ', StrLIComp('abc', 'XYZ', 0));
  WriteLn('licomp before diff ', StrLIComp('ABx', 'abY', 2));
  WriteLn('licomp at diff ', StrLIComp('ABx', 'abY', 3));
  WriteLn('licomp equal long max ', StrLIComp('Abc', 'aBC', 100));
  WriteLn('licomp prefix ', StrLIComp('ab', 'ABC', 3), ' ', StrLIComp('ab', 'ABC', 2));
  WriteLn('licomp underscore ', StrLIComp('x_', 'XA', 2));
  WriteLn('licomp high ', StrLIComp(#233'a', #201'a', 2));
  WriteLn('licomp empty ', StrLIComp('', '', 3), ' ', StrLIComp('', 'b', 3));
end.
