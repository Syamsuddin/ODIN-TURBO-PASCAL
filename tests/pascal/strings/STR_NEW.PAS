{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrNews;
{ StrNew allocates a heap copy (nil for nil or an empty string) and
  StrDispose frees it (nil is allowed). }
uses Strings;
type
  TBig = array[0..299] of Char;
var
  A: array[0..15] of Char;
  Big: TBig;
  P, Q: PChar;
  List: array[1..50] of PChar;
  i, Round, Bad: Integer;
  Total: LongInt;
begin
  StrCopy(A, 'original');
  P := StrNew(A);
  WriteLn('new copy ', P, ' ', StrLen(P));
  WriteLn('new is a copy ', P <> PChar(@A), ' ', StrComp(P, A));
  A[0] := 'O';
  WriteLn('new independent ', P, ' ', A);
  P[1] := 'R';
  WriteLn('new writable ', P, ' ', A);
  StrDispose(P);

  P := StrNew('literal');
  WriteLn('new literal ', P);
  Q := StrNew(P);
  WriteLn('new of new ', Q, ' ', P <> Q);
  StrDispose(P);
  WriteLn('other copy survives ', Q);
  StrDispose(Q);

  P := StrNew('');
  WriteLn('new empty is nil ', P = nil);
  P := StrNew(nil);
  WriteLn('new nil is nil ', P = nil);
  StrDispose(nil);
  StrDispose(P);
  WriteLn('dispose nil ok');

  P := StrNew('x');
  WriteLn('new one char ', P, ' ', StrLen(P));
  StrDispose(P);
  P := StrNew('ab'#0'cd');
  WriteLn('new stops at null ', P, ' ', StrLen(P));
  StrDispose(P);
  P := StrNew(#200#255);
  WriteLn('new high ', Ord(P[0]), ' ', Ord(P[1]), ' ', Ord(P[2]));
  StrDispose(P);

  for i := 0 to 298 do Big[i] := Chr(Ord('A') + i mod 26);
  Big[299] := #0;
  P := StrNew(Big);
  WriteLn('new 299 ', StrLen(P), ' ', P[0], P[298], ' ', StrComp(P, Big));
  StrDispose(P);

  for i := 1 to 50 do
  begin
    Str(i * 7, A);
    List[i] := StrNew(A);
  end;
  Total := 0;
  for i := 1 to 50 do Total := Total + StrLen(List[i]);
  WriteLn('list total length ', Total, ' first ', List[1], ' last ', List[50]);
  Bad := 0;
  for i := 1 to 50 do
    for Round := i + 1 to 50 do
      if List[i] = List[Round] then Inc(Bad);
  WriteLn('list distinct pointers ', Bad = 0);
  for i := 1 to 50 do StrDispose(List[i]);

  Bad := 0;
  for Round := 1 to 2000 do
  begin
    P := StrNew('churn the heap');
    if (P = nil) or (StrLen(P) <> 14) then Inc(Bad);
    StrDispose(P);
  end;
  WriteLn('churn 2000 failures ', Bad);
end.
