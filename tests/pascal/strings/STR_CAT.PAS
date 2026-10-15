{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrCats;
{ StrCat and StrLCat. For StrLCat, MaxLen is the maximum length of the
  whole result, not of the appended part. '~' shows #0. }
uses Strings;
type
  TBuf = array[0..15] of Char;
var
  A, B: TBuf;
  Base, P: PChar;

procedure Start(var X: TBuf; const S: String);
var k: Integer;
begin
  for k := 0 to 15 do X[k] := '.';
  for k := 1 to Length(S) do X[k - 1] := S[k];
  X[Length(S)] := #0;
end;

procedure Dump(const Lbl: String; var X: TBuf);
var k: Integer;
begin
  Write(Lbl, ' ');
  for k := 0 to 15 do
    if X[k] = #0 then Write('~') else Write(X[k]);
  WriteLn;
end;

begin
  Base := A;

  Start(A, 'abc'); P := StrCat(A, 'def'); Dump('cat', A);
  WriteLn('cat returns dest ', P = Base);
  Start(A, 'abc'); StrCat(A, ''); Dump('cat empty source', A);
  Start(A, ''); StrCat(A, 'xyz'); Dump('cat empty dest', A);
  Start(A, ''); StrCat(A, ''); Dump('cat both empty', A);
  Start(A, 'ab'); StrCat(StrCat(StrCat(A, 'cd'), 'ef'), 'g'); Dump('cat chain', A);
  Start(A, 'ab'); StrCat(A, 'c'#0'd'); Dump('cat stops at null', A);
  Start(A, 'x'); Start(B, 'yz'); StrCat(A, B); Dump('cat array', A);
  Start(A, 'abcdefg'); StrCat(A, 'hijklmno'); Dump('cat to 15', A);
  Start(A, 'hi'); StrCat(A, #200#255); WriteLn('cat high ', Ord(A[2]), ' ', Ord(A[3]), ' ', Ord(A[4]));

  Start(A, 'abc'); P := StrLCat(A, 'defgh', 5); Dump('lcat 5', A);
  WriteLn('lcat returns dest ', P = Base);
  Start(A, 'abc'); StrLCat(A, 'defgh', 8); Dump('lcat 8 exact', A);
  Start(A, 'abc'); StrLCat(A, 'defgh', 12); Dump('lcat 12 room', A);
  Start(A, 'abc'); StrLCat(A, 'defgh', 4); Dump('lcat 4', A);
  Start(A, 'abc'); StrLCat(A, 'defgh', 3); Dump('lcat 3 full', A);
  Start(A, 'abcdef'); StrLCat(A, 'xy', 4); Dump('lcat dest longer', A);
  Start(A, 'abc'); StrLCat(A, 'defgh', 0); Dump('lcat 0', A);
  Start(A, ''); StrLCat(A, 'defgh', 2); Dump('lcat empty dest', A);
  { FPC also clears the byte after the terminator here; not checked. }
  Start(A, 'abc'); StrLCat(A, '', 10); WriteLn('lcat empty source ', StrLen(A), ' ', A[5]);
  Start(A, 'abc'); StrLCat(A, 'de', SizeOf(A) - 1); Dump('lcat sizeof-1', A);
  Start(A, 'abcdefghij'); StrLCat(A, 'klmnopqrstuvwxyz', SizeOf(A) - 1); Dump('lcat fill', A);
end.
