program PerceptronDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AILINEAR,AIOptim;
var D: PDataSet; M: TPerceptronModel; Info: TTrainInfo;
    I,LabelValue: Integer; Score: TFloat;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('AND.CSV'),True,TargetClass,D^));
  Need(FitPerceptron(D^,100,0.1,42,M,Info));
  WriteLn('AND: epoch=',Info.Epochs,' konvergen=',Info.Converged);
  for I:=1 to D^.Count do begin
    Need(PredictPerceptron(M,D^.X[I],LabelValue,Score));
    WriteLn(D^.X[I,1]:0:0,' ',D^.X[I,2]:0:0,' => ',LabelValue)
  end;
  Need(LoadCSV(DataPath('XOR.CSV'),True,TargetClass,D^));
  Need(FitPerceptron(D^,100,0.1,42,M,Info));
  WriteLn('XOR: konvergen=',Info.Converged,' error=',Info.FinalLoss:0:4);
  WriteLn('Perceptron tunggal tidak memisahkan XOR secara linear.'); FreeData(D)
end.
