program CrossValidation;
{ CROSSVAL - validasi silang 5-fold dengan AISPLIT dan AIKNN.
  Memuat BUNGA.CSV, membagi menjadi 5 fold acak (bukan stratifikasi
  kelas), lalu pada setiap fold: melatih scaler dan model KNN (K=3)
  dari fold latihnya sendiri, memprediksi fold ujinya, dan mencetak
  accuracy fold tersebut. Di akhir, accuracy gabungan dihitung langsung
  dari jumlah prediksi benar di semua fold dibagi total baris - bukan
  rata-rata accuracy per fold, sehingga fold dengan baris lebih banyak
  ikut berpengaruh lebih besar.
  Latihan: bandingkan accuracy gabungan ini dengan satu kali holdout
  split seperti pada KNNDEMO (DOCS/GUIDE.TXT bagian 12). }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AISplit,AIKNN,AISTATS;
var D,Tr,Te: PDataSet; Folds: TIndexList; Labels: TLabels;
    Pred: TSeries; Scaler: TScaler; Model: TKNNModel;
    CM: TConfusion; Metrics: TClassMetrics;
    Fold: Integer; Correct,Total: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(Tr)); Need(NewData(Te));
  Need(LoadCSV(DataPath('BUNGA.CSV'),True,TargetClass,D^));
  Need(MakeFolds(D^.Count,5,True,42,Folds)); Correct := 0; Total := 0;  { 5 fold, acak, seed 42 }
  for Fold := 1 to 5 do begin
    Need(FoldSplit(D^,Folds,5,Fold,Tr^,Te^));          { fold ke-Fold jadi uji, sisanya jadi latih }
    Need(FitScaler(Tr^,ScaleStandard,Scaler));
    Need(TransformData(Scaler,Tr^)); Need(TransformData(Scaler,Te^));
    Need(FitKNN(Tr^,3,Model)); Need(PredictKNNData(Model,Te^,Labels,Pred));
    Need(ConfusionMatrix(Te^.Labels,Labels,Te^.Count,3,CM));
    Need(ClassificationMetrics(CM,Metrics));
    Inc(Correct,CM.Cells[0,0]+CM.Cells[1,1]+CM.Cells[2,2]);  { jumlah diagonal = prediksi benar fold ini }
    Inc(Total,Te^.Count);
    WriteLn('Fold ',Fold,': accuracy=',Metrics.Accuracy:0:4)
  end;
  WriteLn('Accuracy gabungan = ',Correct/Total:0:4);
  WriteLn('Fold acak biasa. Pembagian ini tidak memakai stratifikasi.');
  Model.Fitted := False; Model.Data := nil;  { Model masih menunjuk Tr dari fold terakhir }
  FreeData(Te); FreeData(Tr); FreeData(D)
end.
