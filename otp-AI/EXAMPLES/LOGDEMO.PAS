program LogisticDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AISplit,AILINEAR,AIOptim,AISTATS,AIPlot;
var D,Tr,Te: PDataSet; S: TScaler; C: TTrainConfig;
    M: TLogisticModel; Info: TTrainInfo; P,X: TSeries; L: TLabels;
    CM: TConfusion; Metrics: TClassMetrics; I: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(Tr)); Need(NewData(Te));
  Need(LoadCSV(DataPath('BINARY.CSV'),True,TargetClass,D^));
  Need(TrainTestSplit(D^,Tr^,Te^,0.25,True,42));
  Need(FitScaler(Tr^,ScaleStandard,S));
  Need(TransformData(S,Tr^)); Need(TransformData(S,Te^));
  DefaultTraining(C); Need(FitLogistic(Tr^,C,M,Info));
  Need(LogisticData(M,Te^,0.5,P,L));
  Need(ConfusionMatrix(Te^.Labels,L,Te^.Count,2,CM));
  Need(ClassificationMetrics(CM,Metrics)); PrintConfusion(CM);
  WriteLn('Epoch=',Info.Epochs,' loss=',Info.FinalLoss:0:6,
    ' stop=',Info.StopReason,' accuracy=',Metrics.Accuracy:0:4);
  for I:=1 to Info.HistoryCount do X[I]:=Info.HistoryEpoch[I];
  FillChar(L,SizeOf(L),0);
  Need(SaveScatterSVG('LOGLOSS.SVG',X,Info.History,Info.HistoryCount,L,'Logistic: epoch versus loss'));
  FreeData(Te); FreeData(Tr); FreeData(D)
end.
