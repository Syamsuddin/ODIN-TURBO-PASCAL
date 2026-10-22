{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Math dari runtime library Odin. Bukan unit Turbo Pascal 7, tetapi
  nama dan perilakunya mengikuti unit Math milik Free Pascal/Delphi yang
  dicari banyak program: trigonometri dan hiperbolik, pangkat dan logaritma,
  pembulatan, statistik larik, dan fungsi keuangan.

  Beda dengan Free Pascal: bahasa Odin belum punya overload, jadi Min dan Max
  hanya untuk bilangan bulat (Int64) dan versi Real bernama MinF/MaxF. Hal
  yang sama berlaku untuk InRange/EnsureRange (InRangeF/EnsureRangeF),
  CompareValue (CompareValueF), Sign (menerima Real, juga bilangan bulat),
  dan Sum (Real) dengan SumInt (Integer). Galat domain (ArcSin di luar
  -1..1, Power(0, -1), dan sebagainya) menjadi runtime error 207, karena
  tidak ada exception. }
unit Math;

{$R-,Q-,I-,X+}

interface

const
  { Hasil CompareValue. }
  LessThanValue = -1;
  EqualsValue = 0;
  GreaterThanValue = 1;

  MinSingle = 1.5e-45;
  MaxSingle = 3.4e+38;
  MinDouble = 5.0e-324;
  MaxDouble = 1.7976931348623157e+308;
  MinExtended = 5.0e-324;
  MaxExtended = 1.7976931348623157e+308;
  MinComp = -9.223372036854775807e+18;
  MaxComp = 9.223372036854775807e+18;

type
  TValueRelationship = -1..1;
  TPaymentTime = (ptEndOfPeriod, ptStartOfPeriod);

var
  { Nilai khusus IEEE, diisi saat unit dimulai. }
  NaN: Double;
  Infinity: Double;
  NegInfinity: Double;

{ Nilai khusus IEEE }
function IsNan(const D: Double): Boolean;
function IsInfinite(const D: Double): Boolean;

{ Sudut }
function DegToRad(Deg: Double): Double;
function RadToDeg(Rad: Double): Double;
function GradToRad(Grad: Double): Double;
function RadToGrad(Rad: Double): Double;
function DegToGrad(Deg: Double): Double;
function GradToDeg(Grad: Double): Double;
function CycleToRad(Cycles: Double): Double;
function RadToCycle(Rad: Double): Double;
function CycleToDeg(Cycles: Double): Double;
function DegToCycle(Deg: Double): Double;

{ Trigonometri }
function Tan(X: Double): Double;
function Cotan(X: Double): Double;
function Cot(X: Double): Double;
function Secant(X: Double): Double;
function Cosecant(X: Double): Double;
procedure SinCos(Theta: Double; var SinV, CosV: Double);
function ArcSin(X: Double): Double;
function ArcCos(X: Double): Double;
function ArcTan2(Y, X: Double): Double;
function Hypot(X, Y: Double): Double;

{ Fungsi hiperbolik }
function Sinh(X: Double): Double;
function Cosh(X: Double): Double;
function Tanh(X: Double): Double;
function Coth(X: Double): Double;
function Sech(X: Double): Double;
function Csch(X: Double): Double;
function ArcSinh(X: Double): Double;
function ArcCosh(X: Double): Double;
function ArcTanh(X: Double): Double;

{ Pangkat dan logaritma }
function Power(Base, Exponent: Double): Double;
function IntPower(Base: Double; Exponent: Integer): Double;
function Log10(X: Double): Double;
function Log2(X: Double): Double;
function LogN(Base, X: Double): Double;
function LnXP1(X: Double): Double;
function Ldexp(X: Double; P: Integer): Double;
procedure Frexp(X: Double; var Mantissa: Double; var Exponent: Integer);

{ Pembulatan dan perbandingan }
function Ceil(X: Double): Int64;
function Floor(X: Double): Int64;
function RoundTo(const AValue: Double; const Digits: Integer): Double;
function SimpleRoundTo(const AValue: Double; const Digits: Integer): Double;
function Sign(X: Double): Integer;
function IsZero(const A: Double; Epsilon: Double): Boolean;
function SameValue(const A, B: Double; Epsilon: Double): Boolean;
function CompareValue(const A, B: Int64): TValueRelationship;
function CompareValueF(const A, B: Double; Epsilon: Double): TValueRelationship;

{ Min, Max, rentang }
function Min(A, B: Int64): Int64;
function Max(A, B: Int64): Int64;
function MinF(A, B: Double): Double;
function MaxF(A, B: Double): Double;
function InRange(const AValue, AMin, AMax: Int64): Boolean;
function InRangeF(const AValue, AMin, AMax: Double): Boolean;
function EnsureRange(const AValue, AMin, AMax: Int64): Int64;
function EnsureRangeF(const AValue, AMin, AMax: Double): Double;

{ Acak }
function RandomRange(const AFrom, ATo: Integer): Integer;
function RandG(Mean, StdDev: Double): Double;

{ Statistik larik }
function Sum(const Data: array of Double): Double;
function SumInt(const Data: array of Integer): Int64;
function SumOfSquares(const Data: array of Double): Double;
procedure SumsAndSquares(const Data: array of Double; var Sum, SumOfSquares: Double);
function MinValue(const Data: array of Double): Double;
function MaxValue(const Data: array of Double): Double;
function MinIntValue(const Data: array of Integer): Integer;
function MaxIntValue(const Data: array of Integer): Integer;
function Mean(const Data: array of Double): Double;
procedure MeanAndStdDev(const Data: array of Double; var Mean, StdDev: Double);
function StdDev(const Data: array of Double): Double;
function PopnStdDev(const Data: array of Double): Double;
function Variance(const Data: array of Double): Double;
function PopnVariance(const Data: array of Double): Double;
function TotalVariance(const Data: array of Double): Double;
function Norm(const Data: array of Double): Double;
procedure MomentSkewKurtosis(const Data: array of Double; var M1, M2, M3, M4, Skew, Kurtosis: Double);

{ Keuangan }
function FutureValue(Rate: Double; NPeriods: Integer; Payment, PresentValue: Double;
  PaymentTime: TPaymentTime): Double;
function PresentValue(Rate: Double; NPeriods: Integer; Payment, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
function Payment(Rate: Double; NPeriods: Integer; PresentValue, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
function NumberOfPeriods(Rate, Payment, PresentValue, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
function InterestRate(NPeriods: Integer; Payment, PresentValue, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;

implementation

const
  RadPerDeg = 0.017453292519943295769;
  DegPerRad = 57.295779513082320877;
  GradPerDeg = 1.1111111111111111111;
  DegPerGrad = 0.9;
  RadPerGrad = 0.015707963267948966192;
  GradPerRad = 63.661977236758134308;
  Ln2 = 0.69314718055994530942;
  Ln10 = 2.3025850929940456840;

{ Galat domain: runtime error 207 (operasi floating point tidak sah). }
procedure DomainError;
begin
  RunError(207);
end;

{ ---- nilai khusus --------------------------------------------------------- }

function Bits(const D: Double): Int64;
var
  B: Int64;
begin
  Move(D, B, 8);
  Bits := B;
end;

function IsNan(const D: Double): Boolean;
var
  B: Int64;
begin
  B := Bits(D);
  IsNan := ((B shr 52) and $7FF = $7FF) and (B and $000FFFFFFFFFFFFF <> 0);
end;

function IsInfinite(const D: Double): Boolean;
var
  B: Int64;
begin
  B := Bits(D);
  IsInfinite := ((B shr 52) and $7FF = $7FF) and (B and $000FFFFFFFFFFFFF = 0);
end;

{ ---- sudut -------------------------------------------------------------------- }

function DegToRad(Deg: Double): Double;
begin
  DegToRad := Deg * RadPerDeg;
end;

function RadToDeg(Rad: Double): Double;
begin
  RadToDeg := Rad * DegPerRad;
end;

function GradToRad(Grad: Double): Double;
begin
  GradToRad := Grad * RadPerGrad;
end;

function RadToGrad(Rad: Double): Double;
begin
  RadToGrad := Rad * GradPerRad;
end;

function DegToGrad(Deg: Double): Double;
begin
  DegToGrad := Deg * GradPerDeg;
end;

function GradToDeg(Grad: Double): Double;
begin
  GradToDeg := Grad * DegPerGrad;
end;

function CycleToRad(Cycles: Double): Double;
begin
  CycleToRad := Cycles * 2 * Pi;
end;

function RadToCycle(Rad: Double): Double;
begin
  RadToCycle := Rad / (2 * Pi);
end;

function CycleToDeg(Cycles: Double): Double;
begin
  CycleToDeg := Cycles * 360;
end;

function DegToCycle(Deg: Double): Double;
begin
  DegToCycle := Deg / 360;
end;

{ ---- trigonometri -------------------------------------------------------------- }

function Tan(X: Double): Double;
var
  C: Double;
begin
  C := Cos(X);
  if C = 0 then
    DomainError;
  Tan := Sin(X) / C;
end;

function Cotan(X: Double): Double;
var
  S: Double;
begin
  S := Sin(X);
  if S = 0 then
    DomainError;
  Cotan := Cos(X) / S;
end;

function Cot(X: Double): Double;
begin
  Cot := Cotan(X);
end;

function Secant(X: Double): Double;
var
  C: Double;
begin
  C := Cos(X);
  if C = 0 then
    DomainError;
  Secant := 1 / C;
end;

function Cosecant(X: Double): Double;
var
  S: Double;
begin
  S := Sin(X);
  if S = 0 then
    DomainError;
  Cosecant := 1 / S;
end;

procedure SinCos(Theta: Double; var SinV, CosV: Double);
begin
  SinV := Sin(Theta);
  CosV := Cos(Theta);
end;

function ArcTan2(Y, X: Double): Double;
begin
  if X = 0 then
  begin
    if Y > 0 then
      ArcTan2 := Pi / 2
    else if Y < 0 then
      ArcTan2 := -Pi / 2
    else
      ArcTan2 := 0;
  end
  else if X > 0 then
    ArcTan2 := ArcTan(Y / X)
  else if Y >= 0 then
    ArcTan2 := ArcTan(Y / X) + Pi
  else
    ArcTan2 := ArcTan(Y / X) - Pi;
end;

function ArcSin(X: Double): Double;
begin
  if (X > 1) or (X < -1) then
    DomainError;
  if X = 1 then
    ArcSin := Pi / 2
  else if X = -1 then
    ArcSin := -Pi / 2
  else
    ArcSin := ArcTan(X / Sqrt(1 - X * X));
end;

function ArcCos(X: Double): Double;
begin
  if (X > 1) or (X < -1) then
    DomainError;
  ArcCos := Pi / 2 - ArcSin(X);
end;

function Hypot(X, Y: Double): Double;
var
  T: Double;
begin
  X := Abs(X);
  Y := Abs(Y);
  if X < Y then
  begin
    T := X;
    X := Y;
    Y := T;
  end;
  if X = 0 then
    Hypot := 0
  else
  begin
    { Skala dengan bilangan yang terbesar supaya kuadratnya tidak overflow. }
    T := Y / X;
    Hypot := X * Sqrt(1 + T * T);
  end;
end;

{ ---- hiperbolik ------------------------------------------------------------------- }

function Sinh(X: Double): Double;
var
  E: Double;
begin
  if Abs(X) < 1e-5 then
    Sinh := X + X * X * X / 6
  else
  begin
    E := Exp(X);
    Sinh := (E - 1 / E) / 2;
  end;
end;

function Cosh(X: Double): Double;
var
  E: Double;
begin
  E := Exp(X);
  Cosh := (E + 1 / E) / 2;
end;

function Tanh(X: Double): Double;
var
  E: Double;
begin
  if X > 20 then
    Tanh := 1
  else if X < -20 then
    Tanh := -1
  else if Abs(X) < 1e-5 then
    Tanh := X - X * X * X / 3
  else
  begin
    E := Exp(2 * X);
    Tanh := (E - 1) / (E + 1);
  end;
end;

function Coth(X: Double): Double;
begin
  if X = 0 then
    DomainError;
  Coth := 1 / Tanh(X);
end;

function Sech(X: Double): Double;
begin
  Sech := 1 / Cosh(X);
end;

function Csch(X: Double): Double;
begin
  if X = 0 then
    DomainError;
  Csch := 1 / Sinh(X);
end;

function ArcSinh(X: Double): Double;
begin
  if X = 0 then
    ArcSinh := 0
  else if X < 0 then
    ArcSinh := -Ln(-X + Sqrt(X * X + 1))
  else
    ArcSinh := Ln(X + Sqrt(X * X + 1));
end;

function ArcCosh(X: Double): Double;
begin
  if X < 1 then
    DomainError;
  ArcCosh := Ln(X + Sqrt(X * X - 1));
end;

function ArcTanh(X: Double): Double;
begin
  if (X >= 1) or (X <= -1) then
    DomainError;
  ArcTanh := 0.5 * Ln((1 + X) / (1 - X));
end;

{ ---- pangkat dan logaritma ----------------------------------------------------------- }

function IntPower(Base: Double; Exponent: Integer): Double;
var
  E: LongInt;
  R: Double;
begin
  E := Abs(Exponent);
  R := 1;
  while E > 0 do
  begin
    if Odd(E) then
      R := R * Base;
    Base := Base * Base;
    E := E shr 1;
  end;
  if Exponent < 0 then
  begin
    if R = 0 then
      DomainError;
    R := 1 / R;
  end;
  IntPower := R;
end;

function Power(Base, Exponent: Double): Double;
begin
  if Exponent = 0 then
    Power := 1
  else if Base = 0 then
  begin
    if Exponent < 0 then
      DomainError;
    Power := 0;
  end
  else if (Frac(Exponent) = 0) and (Abs(Exponent) <= 32767) then
    Power := IntPower(Base, Trunc(Exponent))
  else
  begin
    if Base < 0 then
      DomainError;
    Power := Exp(Exponent * Ln(Base));
  end;
end;

function Log10(X: Double): Double;
begin
  Log10 := Ln(X) / Ln10;
end;

function Log2(X: Double): Double;
begin
  Log2 := Ln(X) / Ln2;
end;

function LogN(Base, X: Double): Double;
begin
  LogN := Ln(X) / Ln(Base);
end;

{ Ln(1 + X), tetap teliti untuk X yang sangat kecil. }
function LnXP1(X: Double): Double;
var
  U: Double;
begin
  if X < -1 then
    DomainError;
  U := 1 + X;
  if U = 1 then
    LnXP1 := X
  else
    LnXP1 := Ln(U) * X / (U - 1);
end;

function Ldexp(X: Double; P: Integer): Double;
begin
  while P > 1000 do
  begin
    X := X * IntPower(2, 1000);
    P := P - 1000;
  end;
  while P < -1000 do
  begin
    X := X * IntPower(2, -1000);
    P := P + 1000;
  end;
  Ldexp := X * IntPower(2, P);
end;

procedure Frexp(X: Double; var Mantissa: Double; var Exponent: Integer);
var
  E: Integer;
begin
  if (X = 0) or IsNan(X) or IsInfinite(X) then
  begin
    Mantissa := X;
    Exponent := 0;
    Exit;
  end;
  E := 0;
  while Abs(X) >= 1 do
  begin
    X := X / 2;
    Inc(E);
  end;
  while Abs(X) < 0.5 do
  begin
    X := X * 2;
    Dec(E);
  end;
  Mantissa := X;
  Exponent := E;
end;

{ ---- pembulatan dan perbandingan --------------------------------------------------------- }

function Ceil(X: Double): Int64;
var
  T: Int64;
begin
  T := Trunc(X);
  if Frac(X) > 0 then
    Inc(T);
  Ceil := T;
end;

function Floor(X: Double): Int64;
var
  T: Int64;
begin
  T := Trunc(X);
  if Frac(X) < 0 then
    Dec(T);
  Floor := T;
end;

{ RoundTo(1234.567, -2) = 1234.57, RoundTo(1234.567, 1) = 1230 }
function RoundTo(const AValue: Double; const Digits: Integer): Double;
var
  P: Double;
begin
  P := IntPower(10, Abs(Digits));
  if Digits < 0 then
    RoundTo := Round(AValue * P) / P
  else
    RoundTo := Round(AValue / P) * P;
end;

function SimpleRoundTo(const AValue: Double; const Digits: Integer): Double;
var
  P: Double;
begin
  P := IntPower(10, Abs(Digits));
  if Digits < 0 then
  begin
    if AValue < 0 then
      SimpleRoundTo := Trunc(AValue * P - 0.5) / P
    else
      SimpleRoundTo := Trunc(AValue * P + 0.5) / P;
  end
  else if AValue < 0 then
    SimpleRoundTo := Trunc(AValue / P - 0.5) * P
  else
    SimpleRoundTo := Trunc(AValue / P + 0.5) * P;
end;

function Sign(X: Double): Integer;
begin
  if X > 0 then
    Sign := 1
  else if X < 0 then
    Sign := -1
  else
    Sign := 0;
end;

function IsZero(const A: Double; Epsilon: Double): Boolean;
begin
  if Epsilon = 0 then
    Epsilon := 1e-12;
  IsZero := Abs(A) <= Epsilon;
end;

function SameValue(const A, B: Double; Epsilon: Double): Boolean;
begin
  if Epsilon = 0 then
  begin
    Epsilon := Abs(A);
    if Abs(B) > Epsilon then
      Epsilon := Abs(B);
    Epsilon := Epsilon * 1e-12;
  end;
  if A = B then
    SameValue := True
  else
    SameValue := Abs(A - B) <= Epsilon;
end;

function CompareValue(const A, B: Int64): TValueRelationship;
begin
  if A = B then
    CompareValue := EqualsValue
  else if A < B then
    CompareValue := LessThanValue
  else
    CompareValue := GreaterThanValue;
end;

function CompareValueF(const A, B: Double; Epsilon: Double): TValueRelationship;
begin
  if SameValue(A, B, Epsilon) then
    CompareValueF := EqualsValue
  else if A < B then
    CompareValueF := LessThanValue
  else
    CompareValueF := GreaterThanValue;
end;

{ ---- Min, Max, rentang ------------------------------------------------------------------ }

function Min(A, B: Int64): Int64;
begin
  if A < B then
    Min := A
  else
    Min := B;
end;

function Max(A, B: Int64): Int64;
begin
  if A > B then
    Max := A
  else
    Max := B;
end;

function MinF(A, B: Double): Double;
begin
  if A < B then
    MinF := A
  else
    MinF := B;
end;

function MaxF(A, B: Double): Double;
begin
  if A > B then
    MaxF := A
  else
    MaxF := B;
end;

function InRange(const AValue, AMin, AMax: Int64): Boolean;
begin
  InRange := (AValue >= AMin) and (AValue <= AMax);
end;

function InRangeF(const AValue, AMin, AMax: Double): Boolean;
begin
  InRangeF := (AValue >= AMin) and (AValue <= AMax);
end;

function EnsureRange(const AValue, AMin, AMax: Int64): Int64;
begin
  if AValue < AMin then
    EnsureRange := AMin
  else if AValue > AMax then
    EnsureRange := AMax
  else
    EnsureRange := AValue;
end;

function EnsureRangeF(const AValue, AMin, AMax: Double): Double;
begin
  if AValue < AMin then
    EnsureRangeF := AMin
  else if AValue > AMax then
    EnsureRangeF := AMax
  else
    EnsureRangeF := AValue;
end;

{ ---- acak ------------------------------------------------------------------------------- }

function RandomRange(const AFrom, ATo: Integer): Integer;
var
  Lo, Hi: Integer;
begin
  if AFrom < ATo then
  begin
    Lo := AFrom;
    Hi := ATo;
  end
  else
  begin
    Lo := ATo;
    Hi := AFrom;
  end;
  if Hi = Lo then
    RandomRange := Lo
  else
    RandomRange := Lo + Random(Hi - Lo);
end;

{ Distribusi normal lewat transformasi Box-Muller. }
function RandG(Mean, StdDev: Double): Double;
var
  U1, U2: Double;
begin
  repeat
    U1 := Random;
  until U1 > 0;
  U2 := Random;
  RandG := Mean + StdDev * Sqrt(-2 * Ln(U1)) * Cos(2 * Pi * U2);
end;

{ ---- statistik larik -------------------------------------------------------------------- }

function Sum(const Data: array of Double): Double;
var
  I: Integer;
  T: Double;
begin
  T := 0;
  for I := 0 to High(Data) do
    T := T + Data[I];
  Sum := T;
end;

function SumInt(const Data: array of Integer): Int64;
var
  I: Integer;
  T: Int64;
begin
  T := 0;
  for I := 0 to High(Data) do
    T := T + Data[I];
  SumInt := T;
end;

function SumOfSquares(const Data: array of Double): Double;
var
  I: Integer;
  T: Double;
begin
  T := 0;
  for I := 0 to High(Data) do
    T := T + Data[I] * Data[I];
  SumOfSquares := T;
end;

procedure SumsAndSquares(const Data: array of Double; var Sum, SumOfSquares: Double);
var
  I: Integer;
  S, Q: Double;
begin
  S := 0;
  Q := 0;
  for I := 0 to High(Data) do
  begin
    S := S + Data[I];
    Q := Q + Data[I] * Data[I];
  end;
  Sum := S;
  SumOfSquares := Q;
end;

function MinValue(const Data: array of Double): Double;
var
  I: Integer;
  M: Double;
begin
  M := 0;
  if High(Data) >= 0 then
    M := Data[0];
  for I := 1 to High(Data) do
    if Data[I] < M then
      M := Data[I];
  MinValue := M;
end;

function MaxValue(const Data: array of Double): Double;
var
  I: Integer;
  M: Double;
begin
  M := 0;
  if High(Data) >= 0 then
    M := Data[0];
  for I := 1 to High(Data) do
    if Data[I] > M then
      M := Data[I];
  MaxValue := M;
end;

function MinIntValue(const Data: array of Integer): Integer;
var
  I: Integer;
  M: Integer;
begin
  M := 0;
  if High(Data) >= 0 then
    M := Data[0];
  for I := 1 to High(Data) do
    if Data[I] < M then
      M := Data[I];
  MinIntValue := M;
end;

function MaxIntValue(const Data: array of Integer): Integer;
var
  I: Integer;
  M: Integer;
begin
  M := 0;
  if High(Data) >= 0 then
    M := Data[0];
  for I := 1 to High(Data) do
    if Data[I] > M then
      M := Data[I];
  MaxIntValue := M;
end;

{ Larik kosong memberi 0 untuk semua ukuran di bawah ini. }
function Mean(const Data: array of Double): Double;
begin
  if High(Data) < 0 then
    Mean := 0
  else
    Mean := Sum(Data) / (High(Data) + 1);
end;

function TotalVariance(const Data: array of Double): Double;
var
  I: Integer;
  M, D, T: Double;
begin
  if High(Data) < 0 then
  begin
    TotalVariance := 0;
    Exit;
  end;
  M := Mean(Data);
  T := 0;
  for I := 0 to High(Data) do
  begin
    D := Data[I] - M;
    T := T + D * D;
  end;
  TotalVariance := T;
end;

function PopnVariance(const Data: array of Double): Double;
begin
  if High(Data) < 0 then
    PopnVariance := 0
  else
    PopnVariance := TotalVariance(Data) / (High(Data) + 1);
end;

function Variance(const Data: array of Double): Double;
begin
  if High(Data) < 1 then
    Variance := 0
  else
    Variance := TotalVariance(Data) / High(Data);
end;

function StdDev(const Data: array of Double): Double;
begin
  StdDev := Sqrt(Variance(Data));
end;

function PopnStdDev(const Data: array of Double): Double;
begin
  PopnStdDev := Sqrt(PopnVariance(Data));
end;

procedure MeanAndStdDev(const Data: array of Double; var Mean, StdDev: Double);
var
  M, V: Double;
begin
  M := Math.Mean(Data);
  V := Variance(Data);
  Mean := M;
  StdDev := Sqrt(V);
end;

function Norm(const Data: array of Double): Double;
begin
  Norm := Sqrt(SumOfSquares(Data));
end;

procedure MomentSkewKurtosis(const Data: array of Double; var M1, M2, M3, M4, Skew, Kurtosis: Double);
var
  I, N: Integer;
  D, D2, S2, S3, S4, Mu: Double;
begin
  N := High(Data) + 1;
  M1 := 0;
  M2 := 0;
  M3 := 0;
  M4 := 0;
  Skew := 0;
  Kurtosis := 0;
  if N = 0 then
    Exit;
  Mu := Mean(Data);
  S2 := 0;
  S3 := 0;
  S4 := 0;
  for I := 0 to N - 1 do
  begin
    D := Data[I] - Mu;
    D2 := D * D;
    S2 := S2 + D2;
    S3 := S3 + D2 * D;
    S4 := S4 + D2 * D2;
  end;
  M1 := Mu;
  M2 := S2 / N;
  M3 := S3 / N;
  M4 := S4 / N;
  if M2 > 0 then
  begin
    Skew := M3 / (M2 * Sqrt(M2));
    Kurtosis := M4 / (M2 * M2);
  end;
end;

{ ---- keuangan ---------------------------------------------------------------------------- }

function PeriodFactor(Rate: Double; PaymentTime: TPaymentTime): Double;
begin
  if PaymentTime = ptStartOfPeriod then
    PeriodFactor := 1 + Rate
  else
    PeriodFactor := 1;
end;

function FutureValue(Rate: Double; NPeriods: Integer; Payment, PresentValue: Double;
  PaymentTime: TPaymentTime): Double;
var
  Q: Double;
begin
  if Rate = 0 then
    FutureValue := -PresentValue - Payment * NPeriods
  else
  begin
    Q := IntPower(1 + Rate, NPeriods);
    FutureValue := -PresentValue * Q - Payment * PeriodFactor(Rate, PaymentTime) * (Q - 1) / Rate;
  end;
end;

function PresentValue(Rate: Double; NPeriods: Integer; Payment, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
var
  Q: Double;
begin
  if Rate = 0 then
    PresentValue := -FutureValue - Payment * NPeriods
  else
  begin
    Q := IntPower(1 + Rate, NPeriods);
    PresentValue := -(FutureValue + Payment * PeriodFactor(Rate, PaymentTime) * (Q - 1) / Rate) / Q;
  end;
end;

function Payment(Rate: Double; NPeriods: Integer; PresentValue, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
var
  Q: Double;
begin
  if NPeriods = 0 then
    DomainError;
  if Rate = 0 then
    Payment := -(PresentValue + FutureValue) / NPeriods
  else
  begin
    Q := IntPower(1 + Rate, NPeriods);
    Payment := -(PresentValue * Q + FutureValue) / (PeriodFactor(Rate, PaymentTime) * (Q - 1) / Rate);
  end;
end;

function NumberOfPeriods(Rate, Payment, PresentValue, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
var
  A: Double;
begin
  if Rate = 0 then
  begin
    if Payment = 0 then
      DomainError;
    NumberOfPeriods := -(PresentValue + FutureValue) / Payment;
  end
  else
  begin
    A := Payment * PeriodFactor(Rate, PaymentTime) / Rate;
    if (A + PresentValue = 0) or ((A - FutureValue) / (A + PresentValue) <= 0) then
      DomainError;
    NumberOfPeriods := Ln((A - FutureValue) / (A + PresentValue)) / Ln(1 + Rate);
  end;
end;

{ Newton dengan turunan numerik; mulai dari 10% per periode. }
function InterestRate(NPeriods: Integer; Payment, PresentValue, FutureValue: Double;
  PaymentTime: TPaymentTime): Double;
var
  R, F, F2, H, Step: Double;
  I: Integer;
begin
  R := 0.1;
  H := 1e-7;
  for I := 1 to 100 do
  begin
    F := Math.FutureValue(R, NPeriods, Payment, PresentValue, PaymentTime) - FutureValue;
    F2 := Math.FutureValue(R + H, NPeriods, Payment, PresentValue, PaymentTime) - FutureValue;
    if F2 = F then
      Break;
    Step := F * H / (F2 - F);
    R := R - Step;
    if R <= -1 then
      R := -0.99;
    if Abs(Step) < 1e-14 then
      Break;
  end;
  InterestRate := R;
end;

var
  QNaN, PosInf, NegInf: Int64;

begin
  QNaN := $7FF8000000000000;
  PosInf := $7FF0000000000000;
  NegInf := -$10000000000000;  { bit $FFF0000000000000 }
  Move(QNaN, NaN, 8);
  Move(PosInf, Infinity, 8);
  Move(NegInf, NegInfinity, 8);
end.
