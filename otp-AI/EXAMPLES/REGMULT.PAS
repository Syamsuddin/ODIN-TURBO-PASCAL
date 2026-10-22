program MultipleRegression;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AILINEAR,AISTATS;
var D: PDataSet; M: TLinearModel; P: TSeries; E: TRegMetrics;
    J: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('MULTIREG.CSV'),True,TargetReal,D^));
  Need(FitLinear(D^,0,M)); Need(PredictLinearData(M,D^,P));
  Need(RegressionMetrics(D^.Y,P,D^.Count,E));
  WriteLn('Identifikasi persamaan sintetis Y = 5 + 2*X1 - 3*X2');
  WriteLn('Intercept=',M.Intercept:0:6);
  for J := 1 to M.Features do WriteLn('Koefisien ',J,'=',M.Coeff[J]:0:6);
  WriteLn('RMSE latih=',E.RMSE:0:8);
  WriteLn('Demo ini memeriksa persamaan, bukan evaluasi generalisasi.');
  FreeData(D)
end.
