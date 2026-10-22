program TextDemo;
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
  Need(FitText(TrainCorpus,8,1,True,True,TextModel));
  WriteLn('Vocabulary dilatih hanya dari corpus latih:');
  for J:=1 to TextModel.Count do WriteLn(J:2,' ',TextModel.Terms[J],' idf=',TextModel.IDF[J]:0:4);
  Need(VectorizeCorpus(TextModel,TrainCorpus,D^));
  Need(FitMultinomial(D^,1,Bayes));
  for I:=1 to TestCorpus.Count do begin
    Need(Vectorize(TextModel,TestCorpus.Docs[I],V));
    Need(PredictBayes(Bayes,V,L,Prob));
    WriteLn(TestCorpus.Docs[I],' => ',L,' P=',Prob[L]:0:4);
    Actual[I]:=TestCorpus.Labels[I]; Pred[I]:=L
  end;
  Need(ConfusionMatrix(Actual,Pred,TestCorpus.Count,2,CM));
  Need(ClassificationMetrics(CM,Metric)); WriteLn('Accuracy uji=',Metric.Accuracy:0:4);
  Need(SaveVocabulary('VOCAB.TPM',TextModel)); Need(SaveBayes('TEXTNB.TPM',Bayes));
  FreeData(D)
end.
