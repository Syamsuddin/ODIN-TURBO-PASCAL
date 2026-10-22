program TextDemo;
{ TEXTDEMO - vektorisasi teks TF-IDF (AITEXT) dan klasifikasi Multinomial
  Naive Bayes (AIBAYES).
  Memuat corpus latih dan uji dari TSV (TEXTTRN/TEXTEST), melatih
  vocabulary TF-IDF (maksimum 8 kata) HANYA dari corpus latih dengan
  FitText, lalu memvektorkan corpus latih itu menjadi TDataSet numerik
  untuk melatih FitMultinomial. Setiap dokumen uji divektorkan dengan
  vocabulary yang SAMA (Vectorize, tidak melatih ulang), diprediksi
  dengan PredictBayes, dan hasilnya diringkas lewat confusion matrix
  dan accuracy. Vocabulary dan model Bayes disimpan ke .TPM.
  Latihan (DOCS/GUIDE2.TXT bagian 19, urutan #6): periksa daftar kata
  vocabulary yang tercetak, lalu bandingkan dokumen uji yang memakai
  kata di luar vocabulary (diabaikan) dengan yang tidak. }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIText,AIBayes,AIModel,AISTATS;
var TrainCorpus,TestCorpus: TCorpus; TextModel: TTextModel;
    Bayes: TBayesModel; D: PDataSet; V: TVector; Prob: TClassProb;
    Actual,Pred: TLabels; I,J,L: Integer; CM: TConfusion; Metric: TClassMetrics;
{$I COMMON.INC}
begin
  Need(NewData(D));
  Need(LoadCorpus(DataPath('TEXTTRN.TSV'),TrainCorpus));
  Need(LoadCorpus(DataPath('TEXTEST.TSV'),TestCorpus));
  Need(FitText(TrainCorpus,8,1,True,True,TextModel));  { maks 8 kata, MinDocumentFreq=1, UseIDF, Normalize }
  WriteLn('Vocabulary dilatih hanya dari corpus latih:');
  for J:=1 to TextModel.Count do WriteLn(J:2,' ',TextModel.Terms[J],' idf=',TextModel.IDF[J]:0:4);
  Need(VectorizeCorpus(TextModel,TrainCorpus,D^));     { corpus latih -> TDataSet TargetClass numerik }
  Need(FitMultinomial(D^,1,Bayes));                    { Alpha=1 (Laplace smoothing) }
  for I:=1 to TestCorpus.Count do begin
    Need(Vectorize(TextModel,TestCorpus.Docs[I],V));   { vocabulary TETAP, tidak diperluas dari data uji }
    Need(PredictBayes(Bayes,V,L,Prob));
    WriteLn(TestCorpus.Docs[I],' => ',L,' P=',Prob[L]:0:4);
    Actual[I]:=TestCorpus.Labels[I]; Pred[I]:=L
  end;
  Need(ConfusionMatrix(Actual,Pred,TestCorpus.Count,2,CM));
  Need(ClassificationMetrics(CM,Metric)); WriteLn('Accuracy uji=',Metric.Accuracy:0:4);
  Need(SaveVocabulary('VOCAB.TPM',TextModel)); Need(SaveBayes('TEXTNB.TPM',Bayes));
  FreeData(D)
end.
