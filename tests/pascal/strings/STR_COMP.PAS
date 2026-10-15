{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrComps;
{ StrComp and StrLComp. FPC returns the difference of the first pair of
  bytes that differ, compared as unsigned values (0..255). }
uses Strings;
type
  TBuf = array[0..15] of Char;
var
  A, B: TBuf;
  P, Q: PChar;
  R: LongInt;

procedure Sign(const Lbl: String; V: LongInt);
begin
  Write(Lbl, ' ');
  if V < 0 then WriteLn('<') else if V > 0 then WriteLn('>') else WriteLn('=');
end;

begin
  WriteLn('comp equal ', StrComp('abc', 'abc'));
  WriteLn('comp a c ', StrComp('a', 'c'));
  WriteLn('comp c a ', StrComp('c', 'a'));
  WriteLn('comp first diff ', StrComp('abcx', 'abdy'));
  WriteLn('comp prefix ', StrComp('ab', 'abc'));
  WriteLn('comp longer ', StrComp('abc', 'ab'));
  WriteLn('comp empty empty ', StrComp('', ''));
  WriteLn('comp empty a ', StrComp('', 'a'));
  WriteLn('comp a empty ', StrComp('a', ''));
  WriteLn('comp case ', StrComp('a', 'A'), ' ', StrComp('ABC', 'abc'));
  WriteLn('comp digits ', StrComp('10', '9'));
  WriteLn('comp space ', StrComp('a b', 'ab'));
  WriteLn('comp after null ', StrComp('ab'#0'x', 'ab'#0'y'));
  WriteLn('comp high vs a ', StrComp(#200, 'a'));
  WriteLn('comp a vs high ', StrComp('a', #200));
  WriteLn('comp 255 vs 1 ', StrComp(#255, #1));
  WriteLn('comp 128 vs 127 ', StrComp(#128, #127));
  WriteLn('comp high prefix ', StrComp(#200#201, #200));

  StrCopy(A, 'pascal');
  StrCopy(B, 'pascal');
  WriteLn('comp arrays ', StrComp(A, B));
  B[3] := 'k';
  WriteLn('comp arrays differ ', StrComp(A, B));
  P := A;
  Q := 'pas';
  WriteLn('comp pchar ', StrComp(P, Q), ' ', StrComp(P + 3, 'cal'));
  R := StrComp('apple', 'banana');
  Sign('sign apple banana', R);
  Sign('sign zoo zebra', StrComp('zoo', 'zebra'));
  WriteLn('comp equal test ', StrComp('same', 'same') = 0);

  WriteLn('lcomp 0 ', StrLComp('abc', 'xyz', 0));
  WriteLn('lcomp before diff ', StrLComp('abc', 'abz', 2));
  WriteLn('lcomp at diff ', StrLComp('abc', 'abz', 3));
  WriteLn('lcomp past diff ', StrLComp('abc', 'abz', 50));
  WriteLn('lcomp equal long max ', StrLComp('abc', 'abc', 100));
  WriteLn('lcomp prefix ', StrLComp('ab', 'abc', 3));
  WriteLn('lcomp prefix short max ', StrLComp('ab', 'abc', 2));
  WriteLn('lcomp longer ', StrLComp('abcd', 'ab', 4));
  WriteLn('lcomp empty ', StrLComp('', '', 5), ' ', StrLComp('', 'q', 5), ' ', StrLComp('', 'q', 0));
  WriteLn('lcomp high ', StrLComp(#250'a', #5'a', 1));
  WriteLn('lcomp 1 ', StrLComp('ax', 'ay', 1), ' ', StrLComp('ax', 'by', 1));
  WriteLn('lcomp case ', StrLComp('Hello', 'hello', 5));
  StrCopy(A, 'prefix-one');
  StrCopy(B, 'prefix-two');
  WriteLn('lcomp arrays ', StrLComp(A, B, 7), ' ', StrLComp(A, B, 8));
end.
