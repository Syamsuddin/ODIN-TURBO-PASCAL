program NeuralDemo;
{ NNDEMO - jaringan saraf kecil (MLP) dengan AINNET, menyelesaikan XOR.
  Melatih jaringan 2-input/4-hidden/1-output (sigmoid di kedua lapisan)
  pada XOR.CSV dengan konfigurasi kustom (rate 0.5, momentum 0.5,
  patience 1000, goal loss 0.01, maksimum 6000 epoch) - inilah yang
  tidak bisa dilakukan perceptron tunggal di PERDEMO karena XOR tidak
  terpisah linear. Program mencetak prediksi keempat baris XOR,
  menyimpan model ke XOR.TPM lalu memuatnya kembali, dan mengekspor
  kurva loss ke NNLOSS.SVG.
  Latihan (DOCS/GUIDE2.TXT bagian 16, urutan #4): ubah jumlah neuron
  hidden (1/2/4/8) dan seed, bandingkan epoch serta loss akhir. }
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
  DefaultTraining(C); C.MaxEpochs:=6000; C.Rate:=0.5;   { mulai dari default, lalu timpa parameter yang perlu }
  C.Momentum:=0.5; C.Patience:=1000; C.GoalLoss:=0.01;
  Need(FitNeural(D^,4,C,M,Info));                       { 4 neuron hidden }
  WriteLn('Jaringan 2-4-1: epoch=',Info.Epochs,' loss=',Info.FinalLoss:0:6);
  for I:=1 to D^.Count do begin
    Need(PredictNeural(M,D^.X[I],P,L));
    WriteLn(D^.X[I,1]:0:0,' ',D^.X[I,2]:0:0,' => P=',P:0:6,' kelas=',L)
  end;
  Need(SaveNeural('XOR.TPM',M)); Need(LoadNeural('XOR.TPM',Loaded));  { bukti round-trip simpan/muat }
  for I:=1 to Info.HistoryCount do Epochs[I]:=Info.HistoryEpoch[I];
  FillChar(Groups,SizeOf(Groups),0);
  Need(SaveScatterSVG('NNLOSS.SVG',Epochs,Info.History,Info.HistoryCount,Groups,'XOR: epoch versus loss'));
  WriteLn('Model: XOR.TPM. Grafik: NNLOSS.SVG.'); FreeData(D)
end.
