program BayesDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AISplit,AIBayes,AISTATS;
var D,Tr,Te: PDataSet; M: TBayesModel; Prob: TClassProb;
    Predictions: TLabels; I: Integer; CM: TConfusion; Metrics: TClassMetrics;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(Tr)); Need(NewData(Te));
  Need(LoadCSV(DataPath('BUNGA.CSV'),True,TargetClass,D^));
  Need(TrainTestSplit(D^,Tr^,Te^,0.3,True,42));
  Need(FitGaussian(Tr^,0.000001,M));
  for I:=1 to Te^.Count do Need(PredictBayes(M,Te^.X[I],Predictions[I],Prob));
  Need(ConfusionMatrix(Te^.Labels,Predictions,Te^.Count,3,CM));
  Need(ClassificationMetrics(CM,Metrics)); PrintConfusion(CM);
  WriteLn('Gaussian NB accuracy=',Metrics.Accuracy:0:4);
  FreeData(Te); FreeData(Tr); FreeData(D)
end.
