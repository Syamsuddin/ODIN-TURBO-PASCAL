program QLearningDemo;
{ QDEMO - reinforcement learning (Q-learning) dengan AIREWARD, dibandingkan
  dengan pencarian jalur AISEARCH.
  Membuat grid 4x4 dengan dua dinding, lalu melatih tabel Q (16 state x
  4 aksi) selama 1500 episode (maksimum 100 langkah per episode) dengan
  learning rate 0.3, discount factor 0.95 dan epsilon-greedy 0.25 untuk
  eksplorasi. Setelah pelatihan, GreedyGridPath mengekstrak rute terbaik
  menurut tabel Q yang sudah dipelajari (selalu memilih aksi bernilai Q
  tertinggi, tanpa eksplorasi lagi) dari sel 1 ke sel 16, sebagai
  pembanding rute BFS/A-star pada PATHDEMO. Kurva return per episode
  diekspor ke QRETURN.SVG, dan tabel Q serta grid disimpan ke .TPM.
  Latihan (DOCS/GUIDE2.TXT bagian 24, urutan #11): ubah epsilon atau
  struktur reward, lalu bandingkan rute greedy yang dihasilkan dengan
  rute BFS pada PATHDEMO sebagai patokan. Keberhasilan satu seed bukan
  jaminan konvergensi umum. }
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
  Need(InitQ(16,4,0.3,0.95,0.25,M));                  { Alpha=0.3, Gamma=0.95, Epsilon=0.25 }
  Need(TrainGridQ(M,G,1,16,1500,100,42,Info));         { start=1, goal=16, 1500 episode, maks 100 langkah, seed 42 }
  WriteLn('Episode=',Info.Episodes,' sukses=',Info.Successes,' langkah=',Info.TotalSteps);
  Need(GreedyGridPath(M,G,1,16,R));                    { rute murni dari tabel Q, tanpa eksplorasi }
  WriteLn('Rute greedy: found=',R.Found,' cost=',R.Cost); PrintGrid(G,R,1,16);
  for I:=1 to Info.HistoryCount do Epochs[I]:=Info.HistoryEpisode[I];
  FillChar(Groups,SizeOf(Groups),0);
  Need(SaveScatterSVG('QRETURN.SVG',Epochs,Info.Returns,Info.HistoryCount,Groups,'Q-learning: episode vs return'));
  Need(SaveQ('QTABLE.TPM',M)); Need(SaveGrid('GRID.TPM',G))
end.
