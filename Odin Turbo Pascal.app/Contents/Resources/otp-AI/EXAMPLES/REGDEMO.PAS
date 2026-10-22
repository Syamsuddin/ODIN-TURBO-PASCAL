program RegressionDemo;
{ REGDEMO - regresi linear sederhana dengan AILINEAR.
  Memuat JAMNILAI.CSV (jam belajar vs nilai, data sintetis), membagi
  75/25 latih/uji, melatih OLS satu fitur (Ridge=0) pada data latih,
  lalu mengukur MAE/RMSE/R2 pada data UJI - bukan pada data latih,
  agar angkanya mencerminkan generalisasi. Terakhir memprediksi satu
  nilai baru dan mengekspor grafik regresi ke REGRESI.SVG.
  Latihan: ubah seed TrainTestSplit dan amati perubahan MAE/RMSE
  (DOCS/GUIDE.TXT bagian 7, 10, 12). Korelasi di data sintetis ini
  bukan bukti hubungan sebab akibat. }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AISplit,AILINEAR,AISTATS,AIPlot;
var D,TrainData,TestData: PDataSet; Model: TLinearModel;
    Pred,X: TSeries; Metrics: TRegMetrics; V: TVector; P: TFloat;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(TrainData)); Need(NewData(TestData));
  Need(LoadCSV(DataPath('JAMNILAI.CSV'),True,TargetReal,D^));
  Need(TrainTestSplit(D^,TrainData^,TestData^,0.25,True,42));  { 25% uji, acak dengan seed 42 }
  Need(FitLinear(TrainData^,0,Model));                 { Ridge=0: ordinary least squares, satu fitur }
  Need(PredictLinearData(Model,TestData^,Pred));       { prediksi atas seluruh data UJI }
  Need(RegressionMetrics(TestData^.Y,Pred,TestData^.Count,Metrics));
  WriteLn('Data sintetis jam belajar dan nilai. Bukan hubungan sebab akibat.');
  WriteLn('Latih=',TrainData^.Count,' Uji=',TestData^.Count);
  WriteLn('Y = ',Model.Intercept:0:4,' + ',Model.Coeff[1]:0:4,' * X');
  WriteLn('MAE=',Metrics.MAE:0:4,' RMSE=',Metrics.RMSE:0:4);
  if Metrics.R2Defined then WriteLn('R2=',Metrics.R2:0:4);  { R2 bisa tidak terdefinisi, misalnya target konstan }
  FillChar(V,SizeOf(V),0); V[1] := 5;                   { satu observasi baru: X=5 }
  Need(PredictLinear(Model,V,P)); WriteLn('Prediksi untuk X=5: ',P:0:4);
  Need(GetColumn(TrainData^,1,X));                      { ambil fitur 1 dari data latih untuk digambar }
  Need(SaveRegressionSVG('REGRESI.SVG',X,TrainData^.Y,TrainData^.Count,
    Model.Intercept,Model.Coeff[1],'Regresi linear - data latih'));
  WriteLn('Grafik: REGRESI.SVG');
  FreeData(TestData); FreeData(TrainData); FreeData(D)
end.
