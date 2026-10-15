{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosPackTime;
{ TP7 Dos unit: PackTime adds the shifted fields (out-of-range values carry
  into the next field and the year wraps at 32 bits); UnpackTime masks
  each field. Seconds are stored in units of two. }
uses Dos;
var
  T: DateTime;
  L: LongInt;

procedure Show(P: LongInt);
begin
  UnpackTime(P, T);
  WriteLn(P, ' -> ', T.Year, '-', T.Month, '-', T.Day, ' ', T.Hour, ':', T.Min, ':', T.Sec);
end;

procedure Pk(Y, Mo, D, H, Mi, Se: Word);
begin
  T.Year := Y; T.Month := Mo; T.Day := D; T.Hour := H; T.Min := Mi; T.Sec := Se;
  PackTime(T, L);
  Write('pack ', Y, ' ', Mo, ' ', D, ' ', H, ' ', Mi, ' ', Se, ' = ', L, '  ');
  Show(L);
end;

begin
  Pk(2026, 10, 15, 23, 59, 58);
  Pk(2026, 10, 15, 23, 59, 59);
  Pk(1980, 1, 1, 0, 0, 0);
  Pk(1979, 1, 1, 0, 0, 0);
  Pk(2107, 12, 31, 23, 59, 58);
  Pk(2108, 1, 1, 0, 0, 0);
  Pk(2000, 13, 32, 24, 60, 62);
  Pk(2000, 0, 0, 0, 0, 0);
  Pk(1999, 12, 31, 23, 59, 1);
  Show(0);
  Show(-1);
  Show($7FFFFFFF);
  Show(1557095516);
  Show(-2147483647 - 1);
end.
