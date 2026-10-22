program NeuralDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AINNet,AIOptim,AIModel,AIPlot;
var D: PDataSet; M,Loaded: TNeuralModel; C: TTrainConfig; Info: TTrainInfo;
    I,L: Integer; P: TFloat; Epochs: TSeries; Groups: TLabels;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('XOR.CSV'),True,TargetClass,D^));
  DefaultTraining(C); C.MaxEpochs:=6000; C.Rate:=0.5;
  C.Momentum:=0.5; C.Patience:=1000; C.GoalLoss:=0.01;
  Need(FitNeural(D^,4,C,M,Info));
  WriteLn('Jaringan 2-4-1: epoch=',Info.Epochs,' loss=',Info.FinalLoss:0:6);
  for I:=1 to D^.Count do begin
    Need(PredictNeural(M,D^.X[I],P,L));
    WriteLn(D^.X[I,1]:0:0,' ',D^.X[I,2]:0:0,' => P=',P:0:6,' kelas=',L)
  end;
  Need(SaveNeural('XOR.TPM',M)); Need(LoadNeural('XOR.TPM',Loaded));
  for I:=1 to Info.HistoryCount do Epochs[I]:=Info.HistoryEpoch[I];
  FillChar(Groups,SizeOf(Groups),0);
  Need(SaveScatterSVG('NNLOSS.SVG',Epochs,Info.History,Info.HistoryCount,Groups,'XOR: epoch versus loss'));
  WriteLn('Model: XOR.TPM. Grafik: NNLOSS.SVG.'); FreeData(D)
end.
