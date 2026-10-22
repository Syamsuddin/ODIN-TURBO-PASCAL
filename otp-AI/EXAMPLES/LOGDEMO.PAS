program LogisticDemo;
{ LOGDEMO - regresi logistik dengan AILINEAR dan AIOPTIM.
  Alur supervised lengkap: muat BINARY.CSV, split 75/25 latih/uji,
  standardisasi fitur dari data latih, lalu FitLogistic melatih dengan
  full-batch gradient descent (sigmoid + binary cross-entropy) memakai
  konfigurasi default dari AIOPTIM. LogisticData menerapkan threshold
  0.5 pada data uji untuk mendapat label, lalu dicetak confusion matrix
  dan accuracy. Terakhir, kurva epoch-vs-loss diekspor ke LOGLOSS.SVG.
  Latihan (DOCS/GUIDE2.TXT bagian 14, urutan #3): ubah threshold 0.5
  pada LogisticData dan bandingkan confusion matrix yang baru. }
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
  Need(TrainTestSplit(D^,Tr^,Te^,0.25,True,42));      { 25% uji, seed 42 }
  Need(FitScaler(Tr^,ScaleStandard,S));
  Need(TransformData(S,Tr^)); Need(TransformData(S,Te^));
  DefaultTraining(C); Need(FitLogistic(Tr^,C,M,Info));  { C: konfigurasi default AIOPTIM, tidak diubah di sini }
  Need(LogisticData(M,Te^,0.5,P,L));                   { threshold 0.5 untuk ubah probabilitas jadi label }
  Need(ConfusionMatrix(Te^.Labels,L,Te^.Count,2,CM));
  Need(ClassificationMetrics(CM,Metrics)); PrintConfusion(CM);
  WriteLn('Epoch=',Info.Epochs,' loss=',Info.FinalLoss:0:6,
    ' stop=',Info.StopReason,' accuracy=',Metrics.Accuracy:0:4);
  for I:=1 to Info.HistoryCount do X[I]:=Info.HistoryEpoch[I];  { sumbu X: epoch tercatat, bukan 1..Epochs }
  FillChar(L,SizeOf(L),0);                             { label 0 untuk semua titik: cuma dipakai sebagai warna }
  Need(SaveScatterSVG('LOGLOSS.SVG',X,Info.History,Info.HistoryCount,L,'Logistic: epoch versus loss'));
  FreeData(Te); FreeData(Tr); FreeData(D)
end.
