{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrMoves;
{ StrMove copies exactly Count bytes, ignores #0, never adds a
  terminator, and handles overlapping blocks in both directions.
  '~' shows #0. }
uses Strings;
type
  TBuf = array[0..15] of Char;
  TBig = array[0..299] of Char;
var
  A: TBuf;
  Big, Big2: TBig;
  Base, P: PChar;
  i, Bad: Integer;

procedure Fill(var X: TBuf);
var k: Integer;
begin
  for k := 0 to 15 do X[k] := '.';
  for k := 0 to 9 do X[k] := Chr(Ord('a') + k);
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
  Fill(A); Dump('start', A);

  Fill(A); P := StrMove(A, 'XYZ', 3); Dump('move 3', A);
  WriteLn('move returns dest ', P = Base);
  Fill(A); StrMove(A, 'XYZ', 4); Dump('move with null', A);
  Fill(A); StrMove(A, 'XYZ', 0); Dump('move 0', A);
  Fill(A); StrMove(A, 'P'#0'Q', 3); Dump('move past null', A);
  Fill(A); StrMove(Base + 12, 'tail', 4); Dump('move to offset', A);

  Fill(A); P := StrMove(Base + 2, Base, 5); Dump('overlap forward', A);
  WriteLn('overlap returns ', P - Base);
  Fill(A); P := StrMove(Base, Base + 2, 5); Dump('overlap backward', A);
  WriteLn('overlap returns ', P - Base);
  Fill(A); StrMove(Base + 1, Base, 9); Dump('shift right 1', A);
  Fill(A); StrMove(Base, Base + 1, 9); Dump('shift left 1', A);
  Fill(A); StrMove(Base + 3, Base + 3, 4); Dump('same place', A);

  for i := 0 to 299 do Big[i] := Chr(32 + i mod 90);
  for i := 0 to 299 do Big2[i] := '-';
  P := Big2;
  StrMove(P, Big, 300);
  Bad := 0;
  for i := 0 to 299 do
    if Big2[i] <> Big[i] then Inc(Bad);
  WriteLn('move 300 differences ', Bad);

  for i := 0 to 299 do Big[i] := Chr(32 + i mod 90);
  P := Big;
  StrMove(P + 10, P, 280);
  Bad := 0;
  for i := 0 to 279 do
    if Big[i + 10] <> Chr(32 + i mod 90) then Inc(Bad);
  WriteLn('overlap 280 forward differences ', Bad, ' ', Big[0], Big[9]);

  for i := 0 to 299 do Big[i] := Chr(32 + i mod 90);
  StrMove(P, P + 10, 280);
  Bad := 0;
  for i := 0 to 279 do
    if Big[i] <> Chr(32 + (i + 10) mod 90) then Inc(Bad);
  WriteLn('overlap 280 backward differences ', Bad, ' ', Big[290], Big[299]);

  Fill(A);
  A[0] := #200; A[1] := #0; A[2] := #255;
  StrMove(Base + 5, Base, 3);
  WriteLn('move high ', Ord(A[5]), ' ', Ord(A[6]), ' ', Ord(A[7]), ' ', A[8]);
end.
