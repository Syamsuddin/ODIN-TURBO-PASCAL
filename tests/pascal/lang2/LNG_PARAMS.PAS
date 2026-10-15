{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngParams;
{ Routines with many integer and real parameters, mixed with var,
  const, string and record parameters (register and stack passing). }
type
  TRec = record
    A, B: Integer;
    Tag: String[7];
    W: array[1..6] of LongInt;
  end;
  TMany = function(A, B, C, D, E, F, G, H, I: Real): Real;

var
  R, RV: Real;
  L: LongInt;
  S, SV: String;
  N, IV: Integer;
  Rec: TRec;
  M: TMany;

function Sum8(A, B, C, D, E, F, G, H: Integer): LongInt;
begin
  Sum8 := A + 2 * B + 3 * C + 4 * D + 5 * E + 6 * F + 7 * G + 8 * H;
end;

procedure Mixed10(A: ShortInt; B: Byte; C: Integer; D: Word; E: LongInt;
  F: Char; G: Boolean; H: Integer; I: LongInt; J: Byte);
begin
  WriteLn('mixed ', A, ' ', B, ' ', C, ' ', D, ' ', E, ' ', F, ' ', G, ' ', H, ' ', I, ' ', J);
end;

function RSum10(A, B, C, D, E, F, G, H, I, J: Real): Real;
begin
  RSum10 := A + B * 2 + C * 3 + D * 4 + E * 5 + F * 6 + G * 7 + H * 8 + I * 9 + J * 10;
end;

function RWeights(A, B, C, D, E, F, G, H, I: Real): Real;
begin
  RWeights := A * 1 + B * 10 + C * 100 + D * 1000 + E * 10000 + F * 100000 +
    G * 1000000 + H * 10000000 + I * 100000000;
end;

procedure Big(I1: Integer; R1: Real; var V1: Integer; const S1: String; I2: LongInt;
  R2: Real; I3: Integer; R3, R4, R5: Real; var VR: Real; I4, I5: Integer; S2: String;
  R6, R7, R8, R9: Real; I6: Byte; R10: Real; I7: Integer; C1: Char; var VS: String);
begin
  V1 := V1 + I1 + 2 * I2 + 3 * I3 + 4 * I4 + 5 * I5 + 6 * I6 + 7 * I7;
  VR := R1 + 2 * R2 + 3 * R3 + 4 * R4 + 5 * R5 + 6 * R6 + 7 * R7 + 8 * R8 + 9 * R9 + 10 * R10;
  VS := S1 + '/' + S2 + '/' + C1;
  S2 := 'changed';
end;

procedure WithRec(A, B, C, D, E, F, G: Integer; R: TRec; H: Integer; var Out: LongInt);
var K: Integer;
begin
  Out := A + B + C + D + E + F + G + H + R.A * 100 + R.B * 1000;
  for K := 1 to 6 do Out := Out + R.W[K];
  R.A := -1;
  R.Tag := 'local';
end;

procedure ConstRec(const R: TRec; var Into: TRec; K1, K2, K3, K4, K5, K6, K7: Integer);
begin
  Into := R;
  Into.A := R.A + K1 + K2 + K3 + K4 + K5 + K6 + K7;
end;

function SD(A: Single; B: Double; C: Real; D: Single; E: Integer; F: Double;
  G: Single; H: Real; I: Double; J: Single): Real;
begin
  SD := A + B + C + D + E + F + G + H + I + J;
end;

function Deep(N: Integer; A, B, C, D, E, F, G: LongInt; X, Y: Real): Real;
begin
  if N = 0 then
    Deep := A + B + C + D + E + F + G + X + Y
  else
    Deep := Deep(N - 1, B, C, D, E, F, G, A, Y, X) + N;
end;

function Lots(A, B, C, D, E, F, G, H, I: Real): Real;
begin
  Lots := A - B + C - D + E - F + G - H + I;
end;

var
  K: Integer;
begin
  L := Sum8(1, 2, 3, 4, 5, 6, 7, 8);
  WriteLn('sum8 ', L);
  L := Sum8(1, Sum8(1, 1, 1, 1, 1, 1, 1, 1), 3, 4, 5, 6, Sum8(0, 0, 0, 0, 0, 0, 0, 1), 8);
  WriteLn('nested sum8 ', L);
  Mixed10(-100, 200, -30000, 60000, -2000000000, 'z', True, 12345, 2147483647, 255);
  R := RSum10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
  WriteLn('rsum10 ', R:0:1);
  R := RWeights(1, 2, 3, 4, 5, 6, 7, 8, 9);
  WriteLn('rweights ', R:0:0);
  R := RSum10(0.5, 0.25, RSum10(1, 0, 0, 0, 0, 0, 0, 0, 0, 0), 0, 0, 0, 0, 0, 0, 0.125);
  WriteLn('rsum10 nested ', R:0:4);
  IV := 1000;
  RV := 0;
  SV := '';
  S := 'second';
  Big(1, 1.5, IV, 'first', 100000, 2.5, 3, 3.5, 4.5, 5.5, RV, 4, 5, S,
    6.5, 7.5, 8.5, 9.5, 6, 10.5, 7, '!', SV);
  WriteLn('big ', IV, ' ', RV:0:2, ' ', SV, ' ', S);
  Rec.A := 2; Rec.B := 3; Rec.Tag := 'caller';
  for K := 1 to 6 do Rec.W[K] := K * 10000;
  WithRec(1, 2, 3, 4, 5, 6, 7, Rec, 8, L);
  WriteLn('withrec ', L, ' ', Rec.A, ' ', Rec.Tag);
  ConstRec(Rec, Rec, 1, 1, 1, 1, 1, 1, 1);
  WriteLn('constrec ', Rec.A, ' ', Rec.B, ' ', Rec.Tag, ' ', Rec.W[6]);
  R := SD(0.5, 1.25, 2.5, 0.75, 4, 8.125, 16.5, 32.25, 64.0625, 128.5);
  WriteLn('single/double ', R:0:4);
  R := Deep(5, 1, 2, 3, 4, 5, 6, 7, 0.5, 0.25);
  WriteLn('deep ', R:0:2);
  M := Lots;
  R := M(9, 8, 7, 6, 5, 4, 3, 2, 1);
  WriteLn('procvar 9 reals ', R:0:1);
  N := 7;
  R := RSum10(N, N + 1, N * 2, -N, N div 2, N mod 4, Sqr(N), Abs(-N), Ord('A'), Length(S));
  WriteLn('converted ', R:0:1);
end.
