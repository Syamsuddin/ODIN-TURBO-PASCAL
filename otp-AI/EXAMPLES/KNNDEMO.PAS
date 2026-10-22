program KNNDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AISplit,AIKNN,AISTATS,AIPlot;
var D,TrainData,TestData: PDataSet; Scaler: TScaler; Model: TKNNModel;
    Labels: TLabels; Pred,X,Y: TSeries;
    CM: TConfusion; Metrics: TClassMetrics;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(TrainData)); Need(NewData(TestData));
  Need(LoadCSV(DataPath('BUNGA.CSV'),True,TargetClass,D^));
  Need(TrainTestSplit(D^,TrainData^,TestData^,0.3,True,42));
  Need(FitScaler(TrainData^,ScaleStandard,Scaler));
  Need(TransformData(Scaler,TrainData^)); Need(TransformData(Scaler,TestData^));
  Need(FitKNN(TrainData^,3,Model));
  Need(PredictKNNData(Model,TestData^,Labels,Pred));
  Need(ConfusionMatrix(TestData^.Labels,Labels,TestData^.Count,3,CM));
  Need(ClassificationMetrics(CM,Metrics)); PrintConfusion(CM);
  WriteLn('Accuracy=',Metrics.Accuracy:0:4,' Macro-F1=',Metrics.MacroF1:0:4);
  Need(GetColumn(TestData^,1,X)); Need(GetColumn(TestData^,2,Y));
  Need(SaveScatterSVG('KNN.SVG',X,Y,TestData^.Count,Labels,'KNN - prediksi data uji'));
  WriteLn('Grafik: KNN.SVG. Dataset bunga sintetis, bukan Iris.');
  Model.Fitted := False; Model.Data := nil;
  FreeData(TestData); FreeData(TrainData); FreeData(D)
end.
