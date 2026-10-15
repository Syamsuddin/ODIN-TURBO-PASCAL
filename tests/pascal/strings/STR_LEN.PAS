{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrLenEnd;
{ StrLen and StrEnd from the Strings unit. }
uses Strings;
type
  TBuf = array[0..31] of Char;
var
  A: TBuf;
  P, Q, Base: PChar;
  S: String;
  i: Integer;
begin
  WriteLn('len literal ', StrLen('Turbo Pascal'));
  WriteLn('len empty ', StrLen(''));
  WriteLn('len one char ', StrLen('x'));
  WriteLn('len embedded null ', StrLen('ab'#0'cd'));
  WriteLn('len control chars ', StrLen(#13#10#9));
  WriteLn('len high chars ', StrLen(#128#200#255));
  WriteLn('len signed result ', StrLen('abc') - 10);

  for i := 0 to 31 do A[i] := '*';
  A[0] := #0;
  WriteLn('len array empty ', StrLen(A));
  A[7] := #0;
  Base := A;
  WriteLn('len array 7 ', StrLen(Base + 1) + 1);
  A[0] := '*';
  WriteLn('len array full prefix ', StrLen(A));
  A[31] := #0;
  for i := 7 to 30 do A[i] := Chr(Ord('a') + i - 7);
  WriteLn('len array 31 ', StrLen(A));

  P := 'hello';
  WriteLn('len pchar ', StrLen(P));
  WriteLn('len pchar+2 ', StrLen(P + 2));
  WriteLn('len pchar+5 ', StrLen(P + 5));

  S := 'from a string';
  S[Length(S) + 1] := #0;
  WriteLn('len via @S[1] ', StrLen(@S[1]));

  Base := A;
  A[0] := #0;
  Q := StrEnd(A);
  WriteLn('end empty ', Q - Base, ' ', Q = Base);
  A[0] := 'x';
  A[1] := 'y';
  A[2] := #0;
  Q := StrEnd(A);
  WriteLn('end xy ', Q - Base, ' ', Ord(Q^));
  Q := StrEnd(Base + 1);
  WriteLn('end from middle ', Q - Base);
  P := 'abcdef';
  Q := StrEnd(P);
  WriteLn('end literal ', Q - P, ' ', StrLen(P) = Q - P);
  Q := StrEnd(StrEnd(P));
  WriteLn('end of end ', Q - P);
  Q := StrEnd(#200#201);
  P := Q - 2;
  WriteLn('end high ', Ord(Q^), ' ', Ord(P[1]), ' ', Ord(P^));
end.
