{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Math: trigonometri, hiperbolik, pangkat, logaritma, pembulatan, Min/Max. }
program MATH_FUNCS;

uses Math;

procedure R(const What: String; V: Double);
begin
  WriteLn(What, ' = ', V:0:6);
end;

var
  M: Double;
  E: Integer;
begin
  R('Tan(0.5)', Tan(0.5));
  R('Cotan(0.5)', Cotan(0.5));
  R('Secant(0.5)', Secant(0.5));
  R('Cosecant(0.5)', Cosecant(0.5));
  R('ArcSin(0.5)', ArcSin(0.5));
  R('ArcSin(1)', ArcSin(1));
  R('ArcSin(-1)', ArcSin(-1));
  R('ArcCos(0.5)', ArcCos(0.5));
  R('ArcCos(-1)', ArcCos(-1));
  R('ArcTan2(1, 1)', ArcTan2(1, 1));
  R('ArcTan2(1, -1)', ArcTan2(1, -1));
  R('ArcTan2(-1, -1)', ArcTan2(-1, -1));
  R('ArcTan2(-1, 1)', ArcTan2(-1, 1));
  R('ArcTan2(1, 0)', ArcTan2(1, 0));
  R('ArcTan2(-1, 0)', ArcTan2(-1, 0));
  R('ArcTan2(0, -1)', ArcTan2(0, -1));
  R('ArcTan2(0, 0)', ArcTan2(0, 0));
  R('Hypot(3, 4)', Hypot(3, 4));
  R('Hypot(1e200, 1e200) / 1e200', Hypot(1e200, 1e200) / 1e200);
  R('Sinh(1)', Sinh(1));
  R('Sinh(0.000001)', Sinh(0.000001) * 1e6);
  R('Cosh(1)', Cosh(1));
  R('Tanh(1)', Tanh(1));
  R('Tanh(30)', Tanh(30));
  R('Coth(1)', Coth(1));
  R('Sech(1)', Sech(1));
  R('Csch(1)', Csch(1));
  R('ArcSinh(1)', ArcSinh(1));
  R('ArcSinh(-1)', ArcSinh(-1));
  R('ArcCosh(2)', ArcCosh(2));
  R('ArcTanh(0.5)', ArcTanh(0.5));
  R('DegToRad(180)', DegToRad(180));
  R('RadToDeg(Pi)', RadToDeg(Pi));
  R('GradToRad(200)', GradToRad(200));
  R('RadToGrad(Pi)', RadToGrad(Pi));
  R('DegToGrad(90)', DegToGrad(90));
  R('GradToDeg(100)', GradToDeg(100));
  R('CycleToRad(0.5)', CycleToRad(0.5));
  R('RadToCycle(Pi)', RadToCycle(Pi));
  R('Power(2, 10)', Power(2, 10));
  R('Power(2, 0.5)', Power(2, 0.5));
  R('Power(-2, 3)', Power(-2, 3));
  R('Power(2, -2)', Power(2, -2));
  R('Power(5, 0)', Power(5, 0));
  R('Power(0, 3)', Power(0, 3));
  R('IntPower(3, 4)', IntPower(3, 4));
  R('IntPower(2, -3)', IntPower(2, -3));
  R('Log10(1000)', Log10(1000));
  R('Log2(1024)', Log2(1024));
  R('LogN(3, 81)', LogN(3, 81));
  R('LnXP1(1e-10) * 1e10', LnXP1(1e-10) * 1e10);
  R('Ldexp(0.75, 4)', Ldexp(0.75, 4));
  Frexp(40, M, E);
  WriteLn('Frexp(40) = ', M:0:4, ' x 2^', E);
  Frexp(0.1, M, E);
  WriteLn('Frexp(0.1) = ', M:0:4, ' x 2^', E);
  WriteLn('Ceil: ', Ceil(2.1), ' ', Ceil(-2.1), ' ', Ceil(3.0), ' ', Ceil(-0.5), ' ', Ceil(0));
  WriteLn('Floor: ', Floor(2.9), ' ', Floor(-2.1), ' ', Floor(-3.0), ' ', Floor(0.5), ' ', Floor(0));
  R('RoundTo(1234.567, -2)', RoundTo(1234.567, -2));
  R('RoundTo(1234.567, 1)', RoundTo(1234.567, 1));
  R('RoundTo(1234.567, 0)', RoundTo(1234.567, 0));
  R('SimpleRoundTo(2.345, -2)', SimpleRoundTo(2.345, -2));
  R('SimpleRoundTo(-2.345, -2)', SimpleRoundTo(-2.345, -2));
  WriteLn('Sign: ', Sign(-3), Sign(0), Sign(2.5), Sign(-0.1));
  WriteLn('Min/Max: ', Min(3, 9), ' ', Max(3, 9), ' ', Min(-5, 2), ' ', Max(-5, 2), ' ', Min(7, 7));
  R('MinF(1.5, 2.5)', MinF(1.5, 2.5));
  R('MaxF(1.5, 2.5)', MaxF(1.5, 2.5));
  WriteLn('InRange: ', InRange(5, 1, 10), ' ', InRange(11, 1, 10), ' ', InRange(1, 1, 10));
  WriteLn('EnsureRange: ', EnsureRange(15, 1, 10), ' ', EnsureRange(-3, 1, 10), ' ', EnsureRange(5, 1, 10));
  R('EnsureRangeF(2.5, 0, 1)', EnsureRangeF(2.5, 0, 1));
  WriteLn('SameValue: ', SameValue(0.1 + 0.2, 0.3, 0), ' ', SameValue(1, 1.1, 0), ' ', SameValue(1, 1.1, 0.2));
  WriteLn('IsZero: ', IsZero(1e-15, 0), ' ', IsZero(0.1, 0), ' ', IsZero(0.1, 0.5));
  WriteLn('CompareValue: ', CompareValue(3, 5), ' ', CompareValue(5, 5), ' ', CompareValue(9, 5));
  WriteLn('CompareValueF: ', CompareValueF(1.0, 2.0, 0), ' ', CompareValueF(1.0, 1.0000000001, 0), ' ',
    CompareValueF(3.0, 2.0, 0));
  WriteLn('IsNan: ', IsNan(NaN), ' ', IsNan(1.0), ' ', IsNan(Infinity));
  WriteLn('IsInfinite: ', IsInfinite(Infinity), ' ', IsInfinite(NegInfinity), ' ', IsInfinite(1.0), ' ', IsInfinite(NaN));
  WriteLn('Infinity > 1e308: ', Infinity > 1e308, ' ', NegInfinity < -1e308);
  WriteLn('MaxDouble > 1e308: ', MaxDouble > 1e308);
  WriteLn('RandomRange: ', (RandomRange(10, 20) >= 10) and (RandomRange(10, 20) < 20), ' ', RandomRange(7, 7));
  WriteLn('RandG: ', Abs(RandG(100, 1) - 100) < 10);
end.
