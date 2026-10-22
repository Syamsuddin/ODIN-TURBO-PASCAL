program QLearningDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AISearch,AIReward,AIPlot,AIModel;
var G: TGrid; M: TQModel; Info: TQTrainInfo; R: TSearchResult;
    Epochs: TSeries; Groups: TLabels; I: Integer;
{$I COMMON.INC}
begin
  Need(InitGrid(4,4,G)); Need(SetWall(G,2,2,True)); Need(SetWall(G,3,2,True));
  Need(InitQ(16,4,0.3,0.95,0.25,M));
  Need(TrainGridQ(M,G,1,16,1500,100,42,Info));
  WriteLn('Episode=',Info.Episodes,' sukses=',Info.Successes,' langkah=',Info.TotalSteps);
  Need(GreedyGridPath(M,G,1,16,R));
  WriteLn('Rute greedy: found=',R.Found,' cost=',R.Cost); PrintGrid(G,R,1,16);
  for I:=1 to Info.HistoryCount do Epochs[I]:=Info.HistoryEpisode[I];
  FillChar(Groups,SizeOf(Groups),0);
  Need(SaveScatterSVG('QRETURN.SVG',Epochs,Info.Returns,Info.HistoryCount,Groups,'Q-learning: episode vs return'));
  Need(SaveQ('QTABLE.TPM',M)); Need(SaveGrid('GRID.TPM',G))
end.
