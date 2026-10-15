{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngAbsolute;
{ absolute variables: globals, locals, value and var parameters,
  untyped var parameters, string length byte. }
type
  TBytes = array[0..255] of Byte;
  TQuad = array[0..3] of Byte;

var
  L: LongInt;
  LB: TQuad absolute L;
  LW: Word absolute L;
  S: String[10];
  SLen: Byte absolute S;
  SChars: array[0..10] of Char absolute S;
  R: Real;
  RHalves: array[0..1] of LongInt absolute R;
  B: Byte;
  BC: Char absolute B;
  BS: ShortInt absolute B;
  Flag: Boolean;
  FlagByte: Byte absolute Flag;
  Buf: array[1..6] of Integer;
  Words: array[1..3] of Word;
  K: Integer;

procedure ShowLong(X: LongInt);
var
  XB: TQuad absolute X;
begin
  WriteLn('param ', XB[0], ' ', XB[1], ' ', XB[2], ' ', XB[3]);
  XB[3] := 0;
  WriteLn('param after ', X);
end;

procedure ClearHigh(var X: LongInt);
var
  XB: TQuad absolute X;
begin
  XB[2] := 0;
  XB[3] := 0;
end;

procedure FillBytes(var Dest; Count: Integer; Value: Byte);
var
  D: TBytes absolute Dest;
  I: Integer;
begin
  for I := 0 to Count - 1 do D[I] := Value;
end;

function SumBytes(const Src; Count: Integer): Integer;
var
  D: TBytes absolute Src;
  I, T: Integer;
begin
  T := 0;
  for I := 0 to Count - 1 do T := T + D[I];
  SumBytes := T;
end;

procedure LocalAlias;
var
  A: Integer;
  AB: array[0..1] of Byte absolute A;
  G: LongInt absolute L;
begin
  A := 513;
  WriteLn('local ', AB[0], ' ', AB[1], ' global via local ', G);
  G := 77;
end;

begin
  L := $01020304;
  WriteLn('long ', LB[0], ' ', LB[1], ' ', LB[2], ' ', LB[3], ' low word ', LW);
  LB[3] := $7F;
  WriteLn('long after ', L);
  LW := 0;
  WriteLn('low cleared ', L);
  S := 'pascal';
  WriteLn('len ', SLen, ' ', SChars[1], SChars[6]);
  SLen := 3;
  WriteLn('cut ', S);
  SChars[4] := '!';
  SLen := 4;
  WriteLn('grow ', S);
  R := 1.0;
  WriteLn('real ', RHalves[0], ' ', RHalves[1]);
  RHalves[1] := 1073741824;
  WriteLn('real now ', R:0:1);
  B := 65;
  WriteLn('char ', BC, ' ', BS);
  B := 200;
  WriteLn('short ', BS, ' ', Ord(BC));
  BC := 'z';
  WriteLn('byte ', B);
  FlagByte := 1;
  WriteLn('bool ', Flag);
  FlagByte := 0;
  WriteLn('bool ', Flag);
  ShowLong(-1);
  L := $11223344;
  ClearHigh(L);
  WriteLn('cleared ', L);
  FillBytes(Buf, SizeOf(Buf), 1);
  for K := 1 to 6 do Write(Buf[K], ' ');
  WriteLn;
  FillBytes(Words, 3, 255);
  WriteLn(Words[1], ' ', Words[2], ' ', Words[3]);
  WriteLn('sum ', SumBytes(Words, 6), ' ', SumBytes(L, 4));
  LocalAlias;
  WriteLn('global ', L);
end.
