program MultipleRegression;
{ REGMULT - regresi linear berganda dengan AILINEAR.
  MULTIREG.CSV dibuat dari persamaan sintetis yang sudah diketahui,
  Y = 5 + 2*X1 - 3*X2 ditambah sedikit noise. Program melatih OLS dua
  fitur atas SELURUH dataset (tanpa split latih/uji) lalu membandingkan
  koefisien yang ditemukan dengan koefisien aslinya - ini memeriksa
  apakah model dapat menemukan kembali persamaan yang ditanam, bukan
  mengevaluasi kemampuan generalisasi pada data baru.
  Latihan: lihat DOCS/GUIDE.TXT bagian 7 dan 12 untuk REGDEMO yang
  memakai split latih/uji. }
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
  Need(FitLinear(D^,0,M)); Need(PredictLinearData(M,D^,P));  { Ridge=0; prediksi atas data yang sama }
  Need(RegressionMetrics(D^.Y,P,D^.Count,E));
  WriteLn('Identifikasi persamaan sintetis Y = 5 + 2*X1 - 3*X2');
  WriteLn('Intercept=',M.Intercept:0:6);                { bandingkan dengan 5 }
  for J := 1 to M.Features do WriteLn('Koefisien ',J,'=',M.Coeff[J]:0:6);  { bandingkan dengan 2 dan -3 }
  WriteLn('RMSE latih=',E.RMSE:0:8);
  WriteLn('Demo ini memeriksa persamaan, bukan evaluasi generalisasi.');
  FreeData(D)
end.
