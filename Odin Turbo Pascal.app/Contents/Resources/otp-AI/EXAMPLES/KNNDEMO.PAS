program KNNDemo;
{ KNNDEMO - klasifikasi K-Nearest Neighbors dengan AIKNN.
  Memuat BUNGA.CSV (dataset bunga sintetis tiga kelas, bukan Iris asli),
  membagi 70/30 latih/uji, menstandardisasi fitur (penting karena KNN
  berbasis jarak), melatih K=3 pada data latih, memprediksi data uji,
  lalu mencetak confusion matrix dan accuracy/macro-F1. Terakhir
  mengekspor scatter plot prediksi ke KNN.SVG.
  Latihan: ubah K menjadi 1 dan 5, bandingkan confusion matrix yang
  berubah (DOCS/GUIDE.TXT bagian 8, 10, 11, 12). }
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
  Need(TrainTestSplit(D^,TrainData^,TestData^,0.3,True,42));  { 30% uji, acak dengan seed 42 }
  Need(FitScaler(TrainData^,ScaleStandard,Scaler));     { skala dilatih hanya dari data latih }
  Need(TransformData(Scaler,TrainData^)); Need(TransformData(Scaler,TestData^));
  Need(FitKNN(TrainData^,3,Model));                     { K=3; model hanya menyimpan pointer ke TrainData }
  Need(PredictKNNData(Model,TestData^,Labels,Pred));
  Need(ConfusionMatrix(TestData^.Labels,Labels,TestData^.Count,3,CM));  { 3 kelas pada BUNGA.CSV }
  Need(ClassificationMetrics(CM,Metrics)); PrintConfusion(CM);
  WriteLn('Accuracy=',Metrics.Accuracy:0:4,' Macro-F1=',Metrics.MacroF1:0:4);
  Need(GetColumn(TestData^,1,X)); Need(GetColumn(TestData^,2,Y));
  Need(SaveScatterSVG('KNN.SVG',X,Y,TestData^.Count,Labels,'KNN - prediksi data uji'));
  WriteLn('Grafik: KNN.SVG. Dataset bunga sintetis, bukan Iris.');
  Model.Fitted := False; Model.Data := nil;  { wajib sebelum membebaskan TrainData yang ditunjuk model }
  FreeData(TestData); FreeData(TrainData); FreeData(D)
end.
