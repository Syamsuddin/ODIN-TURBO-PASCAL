{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Math: statistik larik dan fungsi keuangan. }
program MATH_STATS;

uses Math;

procedure R(const What: String; V: Double);
begin
  WriteLn(What, ' = ', V:0:4);
end;

var
  A: array[1..5] of Double;
  B: array[1..4] of Integer;
  E: array[1..1] of Double;
  S, Q, M, D, M1, M2, M3, M4, Sk, Ku: Double;
begin
  A[1] := 2;
  A[2] := 4;
  A[3] := 4;
  A[4] := 4;
  A[5] := 5;
  B[1] := 4;
  B[2] := -2;
  B[3] := 9;
  B[4] := 1;
  R('Sum', Sum(A));
  WriteLn('SumInt = ', SumInt(B));
  R('SumOfSquares', SumOfSquares(A));
  SumsAndSquares(A, S, Q);
  R('SumsAndSquares: sum', S);
  R('SumsAndSquares: kuadrat', Q);
  R('MinValue', MinValue(A));
  R('MaxValue', MaxValue(A));
  WriteLn('MinIntValue = ', MinIntValue(B), ' MaxIntValue = ', MaxIntValue(B));
  R('Mean', Mean(A));
  R('Variance', Variance(A));
  R('PopnVariance', PopnVariance(A));
  R('TotalVariance', TotalVariance(A));
  R('StdDev', StdDev(A));
  R('PopnStdDev', PopnStdDev(A));
  MeanAndStdDev(A, M, D);
  R('MeanAndStdDev: rata-rata', M);
  R('MeanAndStdDev: simpangan', D);
  R('Norm', Norm(A));
  MomentSkewKurtosis(A, M1, M2, M3, M4, Sk, Ku);
  R('M1', M1);
  R('M2', M2);
  R('M3', M3);
  R('M4', M4);
  R('Skew', Sk);
  R('Kurtosis', Ku);
  E[1] := 7;
  R('Mean satu elemen', Mean(E));
  R('Variance satu elemen', Variance(E));
  R('StdDev satu elemen', StdDev(E));

  WriteLn('Keuangan');
  R('FutureValue(5%, 10, -100, 0)', FutureValue(0.05, 10, -100, 0, ptEndOfPeriod));
  R('FutureValue awal periode', FutureValue(0.05, 10, -100, 0, ptStartOfPeriod));
  R('FutureValue tanpa bunga', FutureValue(0, 10, -100, -50, ptEndOfPeriod));
  R('PresentValue(5%, 10, -100, 0)', PresentValue(0.05, 10, -100, 0, ptEndOfPeriod));
  R('PresentValue tanpa bunga', PresentValue(0, 10, -100, 0, ptEndOfPeriod));
  R('Payment(1%, 12, 1000, 0)', Payment(0.01, 12, 1000, 0, ptEndOfPeriod));
  R('Payment awal periode', Payment(0.01, 12, 1000, 0, ptStartOfPeriod));
  R('Payment tanpa bunga', Payment(0, 10, 1000, 0, ptEndOfPeriod));
  R('NumberOfPeriods(1%, -88.85, 1000, 0)', NumberOfPeriods(0.01, -88.85, 1000, 0, ptEndOfPeriod));
  R('NumberOfPeriods tanpa bunga', NumberOfPeriods(0, -100, 1000, 0, ptEndOfPeriod));
  R('InterestRate(12, -88.8488, 1000, 0)', InterestRate(12, -88.8488, 1000, 0, ptEndOfPeriod) * 100);
end.
