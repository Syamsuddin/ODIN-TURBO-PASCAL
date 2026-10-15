{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrCopies;
{ StrCopy, StrECopy, StrLCopy and StrPCopy: results, terminators, and
  bytes after the terminator (which must stay untouched). '~' shows #0. }
uses Strings;
type
  TBuf = array[0..15] of Char;
var
  A, B: TBuf;
  Base, P: PChar;
  S: String;
  T: String[5];

procedure Clear(var X: TBuf);
var k: Integer;
begin
  for k := 0 to 15 do X[k] := '.';
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

  Clear(A); P := StrCopy(A, 'hello'); Dump('copy', A);
  WriteLn('copy returns dest ', P = Base);
  Clear(A); StrCopy(A, ''); Dump('copy empty', A);
  Clear(A); StrCopy(A, 'ab'#0'cd'); Dump('copy stops at null', A);
  Clear(A); StrCopy(A, 'fifteen chars!!'); Dump('copy 15', A);
  Clear(A); StrCopy(A, 'abc'); StrCopy(Base + 3, 'def'); Dump('copy at offset', A);
  Clear(A); Clear(B); StrCopy(B, 'array'); StrCopy(A, B); Dump('copy array', A);
  Clear(A); StrCopy(A, #200#255'x'); WriteLn('copy high ', Ord(A[0]), ' ', Ord(A[1]), ' ', A[2], ' ', Ord(A[3]));

  Clear(A); P := StrECopy(A, 'abc'); Dump('ecopy', A);
  WriteLn('ecopy returns end ', P - Base, ' ', Ord(P^));
  Clear(A); P := StrECopy(A, ''); Dump('ecopy empty', A);
  WriteLn('ecopy empty end ', P - Base);
  Clear(A); P := StrECopy(StrECopy(StrECopy(A, 'ab'), 'cd'), 'ef'); Dump('ecopy chain', A);
  WriteLn('ecopy chain end ', P - Base);

  Clear(A); P := StrLCopy(A, 'abcdef', 3); Dump('lcopy 3', A);
  WriteLn('lcopy returns dest ', P = Base);
  Clear(A); StrLCopy(A, 'abc', 3); Dump('lcopy exact', A);
  Clear(A); StrLCopy(A, 'abc', 10); Dump('lcopy no padding', A);
  Clear(A); StrLCopy(A, 'abc', 0); Dump('lcopy 0', A);
  { FPC also clears A[1] for an empty source; only the length is checked. }
  Clear(A); StrLCopy(A, '', 5); WriteLn('lcopy empty ', StrLen(A), ' ', A[2]);
  Clear(A); StrLCopy(A, 'abcdefghijklmnopqrstuvwxyz', SizeOf(A) - 1); Dump('lcopy sizeof-1', A);
  Clear(A); StrLCopy(A, 'ab'#0'cd', 4); Dump('lcopy stops at null', A);

  Clear(A); S := 'pascal'; P := StrPCopy(A, S); Dump('pcopy', A);
  WriteLn('pcopy returns dest ', P = Base);
  Clear(A); S := ''; StrPCopy(A, S); Dump('pcopy empty', A);
  Clear(A); StrPCopy(A, 'literal arg'); Dump('pcopy literal', A);
  Clear(A); S := 'ab'#0'cd'; StrPCopy(A, S); Dump('pcopy embedded null', A);
  Clear(A); T := 'short'; StrPCopy(A, T); Dump('pcopy string[5]', A);
  Clear(A); S := 'x'; StrPCopy(A, S + 'yz'); Dump('pcopy expression', A);
  Clear(A); S := 'abcdefghij'; StrPCopy(A, Copy(S, 3, 4)); Dump('pcopy copy()', A);
  Clear(A); StrPCopy(A, 'q'); Dump('pcopy char', A);
end.
