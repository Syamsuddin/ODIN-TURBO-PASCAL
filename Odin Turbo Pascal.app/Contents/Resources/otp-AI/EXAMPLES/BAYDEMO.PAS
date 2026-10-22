program BayesDemo;
{ BAYDEMO - Naive Bayes Gaussian dengan AIBAYES.
  Memuat BUNGA.CSV, membagi 70/30 latih/uji, melatih FitGaussian (fitur
  real, diasumsikan Gaussian per kelas) pada data latih, lalu memanggil
  PredictBayes satu baris sekaligus untuk setiap baris uji. Hasilnya
  dirangkum lewat confusion matrix dan accuracy.
  Latihan (DOCS/GUIDE2.TXT bagian 17, urutan #5): bandingkan accuracy
  Naive Bayes di sini dengan KNNDEMO/TREEDEMO pada dataset yang sama -
  ketiganya memakai asumsi yang berbeda tentang data. }
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
  Need(TrainTestSplit(D^,Tr^,Te^,0.3,True,42));        { 30% uji, seed 42 }
  Need(FitGaussian(Tr^,0.000001,M));                   { VarianceFloor kecil, menghindari varians nol }
  for I:=1 to Te^.Count do Need(PredictBayes(M,Te^.X[I],Predictions[I],Prob));  { satu baris uji sekaligus }
  Need(ConfusionMatrix(Te^.Labels,Predictions,Te^.Count,3,CM));  { 3 kelas pada BUNGA.CSV }
  Need(ClassificationMetrics(CM,Metrics)); PrintConfusion(CM);
  WriteLn('Gaussian NB accuracy=',Metrics.Accuracy:0:4);
  FreeData(Te); FreeData(Tr); FreeData(D)
end.
