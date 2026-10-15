{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrCases;
{ StrUpper and StrLower convert in place, return their argument, and
  change only 'a'..'z' / 'A'..'Z'. Every byte from #1 to #255 is
  checked, and changed bytes are listed. }
uses Strings;
type
  TAll = array[0..255] of Char;
  TBuf = array[0..15] of Char;
var
  All: TAll;
  A: TBuf;
  Base, P: PChar;
  i, Changed: Integer;

procedure FillAll;
var k: Integer;
begin
  for k := 1 to 255 do All[k - 1] := Chr(k);
  All[255] := #0;
end;

begin
  StrCopy(A, 'Hello, World 42');
  Base := A;
  P := StrUpper(A);
  WriteLn('upper ', A, ' ', P = Base);
  P := StrLower(A);
  WriteLn('lower ', A, ' ', P = Base);
  StrCopy(A, 'mIxEd');
  WriteLn('upper as value ', StrUpper(A));
  WriteLn('lower as value ', StrLower(A));
  A[0] := #0;
  P := StrUpper(A);
  WriteLn('upper empty ', StrLen(P), ' ', P = Base);
  StrCopy(A, 'abcdef');
  StrUpper(Base + 3);
  WriteLn('upper tail ', A);
  StrCopy(A, 'ab');
  A[3] := 'c';
  A[4] := #0;
  StrUpper(A);
  WriteLn('upper stops at null ', A, ' ', A[3]);
  StrCopy(A, 'ZY');
  A[3] := 'X';
  A[4] := #0;
  StrLower(A);
  WriteLn('lower stops at null ', A, ' ', A[3]);

  FillAll;
  StrUpper(All);
  WriteLn('upper length ', StrLen(All));
  Changed := 0;
  Write('upper changed');
  for i := 1 to 255 do
    if All[i - 1] <> Chr(i) then
    begin
      Inc(Changed);
      if Changed <= 3 then Write(' ', i, '>', Ord(All[i - 1]));
    end;
  WriteLn(' total ', Changed);
  for i := 1 to 255 do
    if (All[i - 1] <> Chr(i)) and (All[i - 1] <> UpCase(Chr(i))) then
      WriteLn('upper wrong ', i);

  FillAll;
  StrLower(All);
  WriteLn('lower length ', StrLen(All));
  Changed := 0;
  Write('lower changed');
  for i := 1 to 255 do
    if All[i - 1] <> Chr(i) then
    begin
      Inc(Changed);
      if Changed <= 3 then Write(' ', i, '>', Ord(All[i - 1]));
    end;
  WriteLn(' total ', Changed);
  for i := 1 to 255 do
    if (All[i - 1] <> Chr(i)) and ((i < 65) or (i > 90) or (Ord(All[i - 1]) <> i + 32)) then
      WriteLn('lower wrong ', i);

  StrCopy(A, #224#196'x'#233);
  StrUpper(A);
  WriteLn('upper high ', Ord(A[0]), ' ', Ord(A[1]), ' ', A[2], ' ', Ord(A[3]));
  StrLower(A);
  WriteLn('lower high ', Ord(A[0]), ' ', Ord(A[1]), ' ', A[2], ' ', Ord(A[3]));
end.
