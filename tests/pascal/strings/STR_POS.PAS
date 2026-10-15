{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrPoss;
{ StrPos(Str1, Str2): first occurrence of Str2 in Str1, nil when absent.
  FPC returns a pointer to the terminator of Str1 for an empty Str2. }
uses Strings;
type
  TBuf = array[0..31] of Char;
var
  A: TBuf;
  Base, P: PChar;
  Count: Integer;

procedure Show(const Lbl: String; R: PChar);
begin
  Write(Lbl, ' ');
  if R = nil then WriteLn('nil') else WriteLn(R - Base, ' [', R, ']');
end;

begin
  StrCopy(A, 'Hello, World');
  Base := A;
  Show('pos World', StrPos(A, 'World'));
  Show('pos start', StrPos(A, 'Hell'));
  Show('pos end', StrPos(A, 'ld'));
  Show('pos one char', StrPos(A, ','));
  Show('pos whole', StrPos(A, 'Hello, World'));
  Show('pos absent', StrPos(A, 'xyz'));
  Show('pos case', StrPos(A, 'WORLD'));
  Show('pos longer', StrPos(A, 'Hello, World!'));
  Show('pos first of two', StrPos(A, 'o'));
  Show('pos from middle', StrPos(Base + 5, 'o'));

  StrCopy(A, 'aaab');
  Show('pos backtrack', StrPos(A, 'aab'));
  StrCopy(A, 'banana');
  Show('pos overlap', StrPos(A, 'ana'));
  Show('pos second', StrPos(Base + 2, 'ana'));
  Show('pos nana', StrPos(A, 'nana'));
  Show('pos near miss', StrPos(A, 'nan_'));

  StrCopy(A, 'abc');
  A[4] := 'x';
  A[5] := 'y';
  A[6] := #0;
  Show('pos stops at null', StrPos(A, 'xy'));
  Show('pos null in pattern', StrPos(A, 'b'#0'z'));

  StrCopy(A, 'abc');
  Show('pos empty pattern', StrPos(A, ''));
  A[0] := #0;
  Show('pos in empty', StrPos(A, 'a'));
  Show('pos empty in empty', StrPos(A, ''));

  StrCopy(A, 'x'#200#201'y'#200#202);
  Show('pos high', StrPos(A, #200#202));
  WriteLn('pos high nil ', StrPos(A, #201#200) = nil);

  StrCopy(A, 'the cat and the hat');
  Count := 0;
  P := StrPos(A, 'the');
  while P <> nil do
  begin
    Inc(Count);
    P := StrPos(P + 1, 'the');
  end;
  WriteLn('count the ', Count);
  P := StrPos('literal text', 'text');
  WriteLn('pos literal ', P);
end.
