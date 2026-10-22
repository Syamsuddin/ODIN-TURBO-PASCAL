program RegressionDemo;
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
  Need(TrainTestSplit(D^,TrainData^,TestData^,0.25,True,42));
  Need(FitLinear(TrainData^,0,Model));
  Need(PredictLinearData(Model,TestData^,Pred));
  Need(RegressionMetrics(TestData^.Y,Pred,TestData^.Count,Metrics));
  WriteLn('Data sintetis jam belajar dan nilai. Bukan hubungan sebab akibat.');
  WriteLn('Latih=',TrainData^.Count,' Uji=',TestData^.Count);
  WriteLn('Y = ',Model.Intercept:0:4,' + ',Model.Coeff[1]:0:4,' * X');
  WriteLn('MAE=',Metrics.MAE:0:4,' RMSE=',Metrics.RMSE:0:4);
  if Metrics.R2Defined then WriteLn('R2=',Metrics.R2:0:4);
  FillChar(V,SizeOf(V),0); V[1] := 5;
  Need(PredictLinear(Model,V,P)); WriteLn('Prediksi untuk X=5: ',P:0:4);
  Need(GetColumn(TrainData^,1,X));
  Need(SaveRegressionSVG('REGRESI.SVG',X,TrainData^.Y,TrainData^.Count,
    Model.Intercept,Model.Coeff[1],'Regresi linear - data latih'));
  WriteLn('Grafik: REGRESI.SVG');
  FreeData(TestData); FreeData(TrainData); FreeData(D)
end.
