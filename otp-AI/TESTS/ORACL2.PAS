program OracleAdvanced;
{$IFNDEF FPC}{$M 16384,0,655360}{$ENDIF}
{$R+}{$S+}{$B-}
uses AITypes,AIOptim,AILINEAR,AINNet,AIBayes,AIText,AIFuzzy,AIReward;
var D: PDataSet; C: TTrainConfig; Info: TTrainInfo; LogM: TLogisticModel;
    NN: TNeuralModel; Bay: TBayesModel; Probs: TClassProb;
    Corpus: TCorpus; TextM: TTextModel; Fuzzy: TFuzzySystem;
    Strength: TFuzzyStrength; Q: TQModel; V: TVector;
    I,J,L: Integer; P: TFloat;
procedure Need(B: Boolean);
begin if not B then begin WriteLn(AIError); Halt(1) end end;
procedure Emit(S: string; X: TFloat);
begin WriteLn(S,' ',X:0:14) end;
begin
  WriteLn('ABI ',SizeOf(Real),' ',SizeOf(Integer),' ',SizeOf(Boolean));
  Need(NewData(D)); InitData(D^,2,TargetClass); D^.Count:=3;
  D^.X[1,1]:=-2; D^.X[1,2]:=1; D^.Labels[1]:=0;
  D^.X[2,1]:=1; D^.X[2,2]:=3; D^.Labels[2]:=1;
  D^.X[3,1]:=2; D^.X[3,2]:=-1; D^.Labels[3]:=1;
  DefaultTraining(C); C.MaxEpochs:=1; C.Rate:=0.2; C.L2:=0; C.Clip:=100;
  Need(FitLogistic(D^,C,LogM,Info));
  Emit('LOGW1',LogM.Weights[1]); Emit('LOGW2',LogM.Weights[2]);
  Emit('LOGB',LogM.Bias); Emit('LOGL',Info.FinalLoss);
  C.Rate:=0.1; C.Momentum:=0; C.Seed:=42;
  Need(FitNeural(D^,2,C,NN,Info));
  for I:=1 to 2 do for J:=1 to 2 do
    WriteLn('NNW ',I,' ',J,' ',NN.InputW[I,J]:0:14);
  for I:=1 to 2 do begin
    WriteLn('NNB ',I,' ',NN.HiddenBias[I]:0:14);
    WriteLn('NNO ',I,' ',NN.OutputW[I]:0:14)
  end;
  Emit('NNOB',NN.OutputBias); Emit('NNLOSS',Info.FinalLoss);
  Need(FitGaussian(D^,0.1,Bay)); V[1]:=0.2; V[2]:=1.1;
  Need(PredictBayes(Bay,V,L,Probs)); Emit('GAUSS0',Probs[0]); Emit('GAUSS1',Probs[1]);
  D^.X[1,1]:=3; D^.X[1,2]:=1; D^.X[2,1]:=1; D^.X[2,2]:=4;
  D^.X[3,1]:=2; D^.X[3,2]:=5;
  Need(FitMultinomial(D^,0.5,Bay)); V[1]:=2; V[2]:=1;
  Need(PredictBayes(Bay,V,L,Probs)); Emit('MULT0',Probs[0]); Emit('MULT1',Probs[1]);
  FillChar(Corpus,SizeOf(Corpus),0); Corpus.Count:=3;
  Corpus.Docs[1]:='apel apel pisang'; Corpus.Docs[2]:='apel jeruk'; Corpus.Docs[3]:='pisang';
  Need(FitText(Corpus,8,1,True,True,TextM)); Need(Vectorize(TextM,'apel apel jeruk',V));
  for I:=1 to 3 do WriteLn('TFIDF ',TextM.Terms[I],' ',V[I]:0:14);
  DefaultFuzzy(Fuzzy); Need(EvaluateFuzzy(Fuzzy,28,70,400,P,Strength)); Emit('FUZZY',P);
  Need(InitQ(3,2,0.3,0.9,0.1,Q)); Q.Q[2,1]:=4; Q.Q[2,2]:=2;
  Q.Q[1,1]:=0.7; Need(UpdateQ(Q,1,1,2,-1,False)); Emit('QSTEP',Q.Q[1,1]);
  Need(UpdateQ(Q,1,1,0,10,True)); Emit('QTERM',Q.Q[1,1]); FreeData(D)
end.
