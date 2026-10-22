program TestAdvanced;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}
uses AITypes,AIMath,AIData,AILINEAR,AIKNN,AIKMeans,AIOptim,AINNet,AIBayes,AITree,AIText,AIRule,AISearch,AIFuzzy,AIReward,AIModel;
var D,Tr,Store: PDataSet; Passed,Failed,I,J,K,L,N,ID: Integer;
    C: TTrainConfig; Info: TTrainInfo; Stop: TStopState;
    LogM,Log2: TLogisticModel; Per,Per2: TPerceptronModel;
    NN,NN2: TNeuralModel; Bay,Bay2: TBayesModel; Prob: TClassProb;
    Tree,Tree2: TTreeModel; Corpus: TCorpus; TextM,Text2: TTextModel;
    Tokens: TTokens; Facts,Facts2: TFacts; Rules,Rules2: TRuleSet;
    Rule: TRule; Grid,Grid2: TGrid; Route,Route2: TSearchResult;
    Fuzzy,Fuzzy2: TFuzzySystem; Tri: TTriangle; Strength: TFuzzyStrength;
    Q,Q2: TQModel; QInfo: TQTrainInfo;
    Linear,Linear2: TLinearModel; KM,KM2: TKMeansModel;
    KNN,KNN2: TKNNModel; Sc,Sc2: TScaler; Imp,Imp2: TImputer;
    V,W,G,Velocity: TVector; A,B: TSeries; Labels: TLabels; Path: TIndexList;
    Value,Value2,Score,Loss,Rate,Before,Reward: TFloat;
    OK,Terminal: Boolean; S,Name: string; F: File; Actual: Word; ByteValue: Byte;
procedure Need(Condition: Boolean);
begin if not Condition then begin WriteLn('FATAL ',AIErrorCode,': ',AIError); Halt(2) end end;
procedure Check(Condition: Boolean; Name: string);
begin
  if Condition then begin Inc(Passed); WriteLn('PASS ',Name) end
  else begin Inc(Failed); WriteLn('FAIL ',Name,' [',AIErrorCode,'] ',AIError) end
end;
procedure Near(Value,Expected,Tolerance: TFloat; Name: string);
begin Check(Abs(Value-Expected)<=Tolerance,Name) end;
function DataPath(Name: TFileName): TFileName;
begin
  {$IFDEF FPC} DataPath:='DATA/'+Name;
  {$ELSE} DataPath:='DATA\'+Name; {$ENDIF}
end;
procedure FlipByte(Offset: LongInt);
begin
  Assign(F,'TESTMOD.TPM'); Reset(F,1);
  if Offset<0 then Offset:=FileSize(F)-1;
  Seek(F,Offset); BlockRead(F,ByteValue,1,Actual);
  ByteValue:=ByteValue xor 255; Seek(F,Offset); BlockWrite(F,ByteValue,1,Actual); Close(F)
end;
procedure InitBinary;
begin
  InitData(D^,2,TargetClass); D^.Count:=4;
  D^.X[1,1]:=0; D^.X[1,2]:=0;
  D^.X[2,1]:=0; D^.X[2,2]:=1;
  D^.X[3,1]:=1; D^.X[3,2]:=0;
  D^.X[4,1]:=1; D^.X[4,2]:=1;
  D^.Labels[1]:=0; D^.Labels[2]:=1; D^.Labels[3]:=1; D^.Labels[4]:=0
end;
begin
  Passed:=0; Failed:=0; WriteLn('OTP-AI 2.0 TESTADV');
  Need(NewData(D)); Need(NewData(Tr)); Need(NewData(Store));
  DefaultTraining(C); Need(CheckTraining(C));
  C.Rate:=0; Check(not CheckTraining(C),'Training menolak rate nol');
  DefaultTraining(C); C.Momentum:=1; Check(not CheckTraining(C),'Training menolak momentum satu');
  DefaultTraining(C); C.MaxEpochs:=0; Check(not CheckTraining(C),'Training menolak epoch nol');
  DefaultTraining(C);
  Value:=0; Value2:=0; Need(SGDStep(Value,Value2,2,0.1,0,10));
  Near(Value,-0.2,1E-8,'SGD satu langkah');
  Need(SGDStep(Value,Value2,2,0.1,0.5,10)); Near(Value,-0.5,1E-8,'Momentum memakai velocity sebelumnya');
  Value:=0; Value2:=0; Need(SGDStep(Value,Value2,100,0.1,0,1));
  Near(Value,-0.1,1E-8,'Gradient clipping');
  Before:=Value; Check(not SGDStep(Value,Value2,1,-1,0,1),'SGD menolak rate negatif');
  Near(Value,Before,1E-8,'SGD gagal tidak memutasi nilai');
  FillChar(V,SizeOf(V),0); FillChar(Velocity,SizeOf(Velocity),0);
  G[1]:=2; G[2]:=-2; Need(VectorStep(V,Velocity,G,2,0.1,0,10));
  Near(V[1],-0.2,1E-8,'Vector SGD komponen pertama');
  Near(V[2],0.2,1E-8,'Vector SGD komponen kedua');
  Near(BinaryLoss(0,0),Ln(2),1E-8,'BCE logit nol');
  Near(BinaryLoss(1000,1),0,1E-8,'BCE positif ekstrem stabil');
  Near(BinaryLoss(-1000,1),1000,1E-8,'BCE negatif ekstrem stabil');
  Loss:=BinaryLoss(0,2); Check(AIErrorCode=ErrValue,'BCE target invalid');
  InitTraining(Info,Stop); C.Patience:=2; C.GoalLoss:=0;
  OK:=ShouldStop(C,Stop,1,K); Check(not OK,'Early stop perbaikan pertama');
  OK:=ShouldStop(C,Stop,1,K); Check(not OK,'Early stop belum mencapai patience');
  Check(ShouldStop(C,Stop,1,K) and (K=StopPlateau),'Early stop plateau');
  Need(LoadCSV(DataPath('BINARY.CSV'),True,TargetClass,D^));
  DefaultTraining(C); C.MaxEpochs:=2000;
  Need(FitLogistic(D^,C,LogM,Info)); Check(LogM.Fitted,'Logistic fitted');
  Check(Info.FinalLoss<0.02,'Logistic loss turun');
  OK:=True;
  for I:=1 to D^.Count do begin
    Need(PredictLogistic(LogM,D^.X[I],0.5,Value,L));
    if L<>D^.Labels[I] then OK:=False
  end;
  Check(OK,'Logistic klasifikasi data terpisah');
  Check(not PredictLogistic(LogM,D^.X[1],1,Value,L),'Logistic threshold invalid');
  D^.Labels[1]:=2; Check(not FitLogistic(D^,C,Log2,Info),'Logistic menolak kelas nonbiner');
  Check(not Log2.Fitted,'Logistic gagal tidak fitted'); D^.Labels[1]:=0;
  Need(SaveLogistic('TESTMOD.TPM',LogM)); Need(LoadLogistic('TESTMOD.TPM',Log2));
  Need(PredictLogistic(LogM,D^.X[1],0.5,Value,L));
  Need(PredictLogistic(Log2,D^.X[1],0.5,Value2,L)); Near(Value,Value2,1E-8,'Roundtrip logistic');

  Need(LoadCSV(DataPath('AND.CSV'),True,TargetClass,D^));
  Need(FitPerceptron(D^,100,0.1,42,Per,Info)); Check(Info.Converged,'Perceptron AND konvergen');
  OK:=True;
  for I:=1 to D^.Count do begin Need(PredictPerceptron(Per,D^.X[I],L,Score)); if L<>D^.Labels[I] then OK:=False end;
  Check(OK,'Perceptron tabel AND benar');
  Need(SavePerceptron('TESTMOD.TPM',Per)); Need(LoadPerceptron('TESTMOD.TPM',Per2));
  Need(PredictPerceptron(Per2,D^.X[4],L,Score)); Check(L=1,'Roundtrip perceptron');
  InitBinary; Need(FitPerceptron(D^,50,0.1,42,Per,Info));
  Check(not Info.Converged,'Perceptron XOR tidak konvergen');
  Check(Info.FinalLoss>0,'Perceptron XOR masih memiliki kesalahan');
  Check(not FitPerceptron(D^,0,0.1,42,Per2,Info),'Perceptron epoch invalid');

  DefaultTraining(C); C.MaxEpochs:=6000; C.Rate:=0.5;
  C.Momentum:=0.5; C.Patience:=1000; C.GoalLoss:=0.01;
  Need(FitNeural(D^,4,C,NN,Info)); Check(Info.Converged,'Neural XOR konvergen');
  Check(Info.FinalLoss<=C.GoalLoss,'Neural XOR mencapai goal loss');
  OK:=True;
  for I:=1 to D^.Count do begin Need(PredictNeural(NN,D^.X[I],Value,L)); if L<>D^.Labels[I] then OK:=False end;
  Check(OK,'Neural empat keluaran XOR benar');
  Check((Info.HistoryCount>1) and (Info.HistoryCount<=MaxSamples),'History training dibatasi');
  Check(Info.HistoryEpoch[Info.HistoryCount]=Info.Epochs,'History mencakup epoch terakhir');
  Need(SaveNeural('TESTMOD.TPM',NN)); Need(LoadNeural('TESTMOD.TPM',NN2));
  Need(PredictNeural(NN,D^.X[2],Value,L)); Need(PredictNeural(NN2,D^.X[2],Value2,L));
  Near(Value,Value2,1E-8,'Roundtrip neural');
  Check(not FitNeural(D^,9,C,NN2,Info),'Neural menolak hidden berlebih');

  InitData(D^,1,TargetClass); D^.Count:=4;
  D^.X[1,1]:=0; D^.X[2,1]:=2; D^.X[3,1]:=8; D^.X[4,1]:=10;
  D^.Labels[1]:=0; D^.Labels[2]:=0; D^.Labels[3]:=2; D^.Labels[4]:=2;
  Need(FitGaussian(D^,1E-6,Bay)); Near(Bay.Means[0,1],1,1E-8,'Gaussian mean kelas');
  Near(Bay.Variances[0,1],1,1E-8,'Gaussian varians populasi');
  FillChar(V,SizeOf(V),0); V[1]:=1;
  Need(PredictBayes(Bay,V,L,Prob)); Check(L=0,'Gaussian prediksi');
  Near(Prob[1],0,1E-8,'Gaussian kelas tak teramati peluang nol');
  Near(Prob[0]+Prob[1]+Prob[2],1,1E-8,'Posterior Bayes berjumlah satu');
  Need(SaveBayes('TESTMOD.TPM',Bay)); Need(LoadBayes('TESTMOD.TPM',Bay2));
  Need(PredictBayes(Bay2,V,L,Prob)); Check(L=0,'Roundtrip Gaussian');
  Check(not FitGaussian(D^,0,Bay2),'Gaussian floor nol ditolak');
  InitData(D^,2,TargetClass); D^.Count:=2;
  D^.X[1,1]:=3; D^.X[1,2]:=0; D^.Labels[1]:=0;
  D^.X[2,1]:=0; D^.X[2,2]:=3; D^.Labels[2]:=1;
  Need(FitMultinomial(D^,1,Bay)); Near(Exp(Bay.LogFeature[0,1]),0.8,1E-8,'Multinomial Laplace smoothing');
  V[1]:=1; V[2]:=0; Need(PredictBayes(Bay,V,L,Prob));
  Near(Prob[0],0.8,1E-8,'Multinomial posterior diketahui');
  Need(SaveBayes('TESTMOD.TPM',Bay)); Need(LoadBayes('TESTMOD.TPM',Bay2));
  Need(PredictBayes(Bay2,V,L,Prob)); Near(Prob[0],0.8,1E-8,'Roundtrip multinomial');
  D^.X[1,1]:=-1; Check(not FitMultinomial(D^,1,Bay2),'Multinomial fitur negatif ditolak');
  D^.X[1,1]:=3; Check(not FitMultinomial(D^,0,Bay2),'Multinomial alpha nol ditolak');

  InitBinary; Need(FitTree(D^,4,1,0,Tree)); Check(Tree.NodeCount=7,'Pohon XOR tujuh node');
  OK:=True;
  for I:=1 to 4 do begin Need(PredictTree(Tree,D^.X[I],L)); if L<>D^.Labels[I] then OK:=False end;
  Check(OK,'Pohon XOR benar saat min-gain nol');
  Need(TraceTree(Tree,D^.X[2],Path,N,L)); Check((N=3) and (Path[1]=1),'Trace pohon dari akar');
  Need(SaveTree('TESTMOD.TPM',Tree)); Need(LoadTree('TESTMOD.TPM',Tree2));
  Need(PredictTree(Tree2,D^.X[2],L)); Check(L=1,'Roundtrip tree');
  Tree2.Nodes[1].LeftChild:=1; Check(not CheckTree(Tree2),'Pohon menolak siklus');
  Need(FitTree(D^,0,1,0,Tree2)); Check(Tree2.NodeCount=1,'Depth nol menghasilkan satu daun');
  Need(FitTree(D^,4,1,1E-6,Tree2)); Check(Tree2.NodeCount=1,'Greedy tree berhenti saat gain awal nol');
  Need(FitTree(D^,4,3,0,Tree2)); Check(Tree2.NodeCount=1,'MinLeaf mencegah pemisahan');
  Check(not FitTree(D^,9,1,0,Tree2),'Depth berlebih ditolak');

  Need(Tokenize('Bagus, CEPAT! kode123',Tokens));
  Check((Tokens.Count=3) and (Tokens.Words[1]='bagus') and (Tokens.Words[3]='kode123'),'Tokenizer lowercase dan tanda baca');
  S:=''; for I:=1 to 32 do S:=S+'a'; Check(not Tokenize(S,Tokens),'Token terlalu panjang ditolak');
  S:=Chr(200); Check(not Tokenize(S,Tokens),'Tokenizer non ASCII ditolak');
  Need(Tokenize('... !!!',Tokens)); Check(Tokens.Count=0,'Tokenizer teks tanpa kata');
  S:=''; for I:=1 to 65 do S:=S+'a '; Check(not Tokenize(S,Tokens),'Tokenizer terlalu banyak token ditolak');
  FillChar(Corpus,SizeOf(Corpus),0); Corpus.Count:=3;
  Corpus.Docs[1]:='apel apel pisang'; Corpus.Docs[2]:='apel jeruk'; Corpus.Docs[3]:='pisang';
  Need(FitText(Corpus,8,1,True,False,TextM));
  Check((TextM.Count=3) and (TextM.Terms[1]='apel') and (TextM.Terms[2]='pisang'),'Vocabulary urut DF dan alfabet');
  Near(TextM.IDF[1],Ln(4/3)+1,1E-8,'IDF smoothing');
  Need(Vectorize(TextM,'apel apel tidakdikenal',V));
  Near(V[1],2*(Ln(4/3)+1),1E-8,'TF-IDF count dikali IDF');
  Need(Vectorize(TextM,'takdikenal',V)); Near(V[1]+V[2]+V[3],0,1E-8,'Kata baru diabaikan tanpa mengubah vocabulary');
  Check(TextM.Count=3,'Transform tidak memperbesar vocabulary');
  TextM.Normalize:=True; Need(Vectorize(TextM,'apel pisang',V));
  Near(Sqrt(Sqr(V[1])+Sqr(V[2])),1,1E-8,'TF-IDF normalisasi L2');
  Need(SaveVocabulary('TESTMOD.TPM',TextM)); Need(LoadVocabulary('TESTMOD.TPM',Text2));
  Need(Vectorize(Text2,'apel pisang',W)); Near(W[1],V[1],1E-8,'Roundtrip vocabulary');
  Need(VectorizeCorpus(TextM,Corpus,D^)); Check((D^.Count=3) and (D^.Features=3),'Corpus menjadi dataset');
  Check(not FitText(Corpus,9,1,True,False,Text2),'Vocabulary lebih dari 8 ditolak');
  Check(not FitText(Corpus,8,3,True,False,Text2),'Vocabulary kosong karena min-df ditolak');
  Need(LoadCorpus(DataPath('TEXTTRN.TSV'),Corpus)); Check(Corpus.Count=8,'Pembaca corpus TSV');
  Check(not LoadCorpus('NOFILE.TSV',Corpus),'Corpus berkas hilang');

  InitFacts(Facts); Need(AddFact(Facts,'A',1,ID)); Need(AddFact(Facts,'B',-1,ID));
  Need(AddFact(Facts,'C',-1,ID)); InitRules(3,Rules); FillChar(Rule,SizeOf(Rule),0);
  Rule.Count:=1; Rule.FactIDs[1]:=2; Rule.Expected[1]:=1; Rule.Conclusion:=3; Rule.Value:=1;
  Need(AddRule(Rules,Rule)); Rule.FactIDs[1]:=1; Rule.Conclusion:=2; Need(AddRule(Rules,Rule));
  Need(Infer(Rules,Facts,Path,N)); Check((N=2) and (Facts.Values[3]=1),'Forward chain lintas dua putaran');
  Check((Path[1]=2) and (Path[2]=1),'Urutan trace firing');
  Check((Facts.SourceRule[2]=2) and (Facts.SourceRule[3]=1),'Provenance fakta');
  Need(SaveRules('TESTMOD.TPM',Rules)); Need(LoadRules('TESTMOD.TPM',Rules2));
  Check(Rules2.Rules[1].Conclusion=3,'Roundtrip rules');
  Need(SaveFacts('TESTMOD.TPM',Facts)); Need(LoadFacts('TESTMOD.TPM',Facts2));
  Check(Facts2.Values[3]=1,'Roundtrip facts');
  Need(SetFact(Facts,1,0)); Check((Facts.Values[2]=-1) and (Facts.Values[3]=-1),'Perubahan fakta mereset kesimpulan turunan');
  Need(Infer(Rules,Facts,Path,N)); Check((N=0) and (Facts.Values[3]=-1),'Unknown tidak memenuhi premis true');
  Need(SetFact(Facts,1,1)); Rule.FactIDs[1]:=1; Rule.Conclusion:=2; Rule.Value:=0;
  Need(AddRule(Rules,Rule)); Check(not Infer(Rules,Facts,Path,N),'Konflik aturan ditolak');
  Check((Facts.Values[2]=-1) and (Facts.Values[3]=-1),'Konflik tidak memutasi fakta');
  InitRules(3,Rules); Rule.FactIDs[1]:=2; Rule.Conclusion:=3; Rule.Value:=1;
  Need(AddRule(Rules,Rule)); Rule.FactIDs[1]:=3; Rule.Conclusion:=2; Need(AddRule(Rules,Rule));
  Need(Infer(Rules,Facts,Path,N)); Check(N=0,'Siklus tanpa fakta pemicu berhenti');
  Check(not AddFact(Facts,'A',1,ID),'Fakta duplikat ditolak');

  Need(InitGrid(4,4,Grid)); Need(SetWall(Grid,2,2,True)); Need(SetWall(Grid,3,2,True));
  Need(SearchGrid(Grid,1,16,SearchBFS,Route)); Check(Route.Found and (Route.Cost=6),'BFS rute terpendek');
  Need(SearchGrid(Grid,1,16,SearchAStar,Route2)); Check(Route2.Found and (Route2.Cost=Route.Cost),'A-star cocok BFS');
  Need(SearchGrid(Grid,1,16,SearchDFS,Route2)); Check(Route2.Found,'DFS menemukan rute');
  Check((Route.Cells[1]=1) and (Route.Cells[Route.Count]=16),'Rute berawal dan berakhir benar');
  OK:=True;
  for I:=2 to Route.Count do begin
    Need(CellPosition(Grid,Route.Cells[I-1],J,K)); Need(CellPosition(Grid,Route.Cells[I],L,N));
    if Abs(J-L)+Abs(K-N)<>1 then OK:=False;
    if Grid.Blocked[L,N] then OK:=False
  end;
  Check(OK,'Rute hanya bergerak empat arah tanpa menembus dinding');
  Need(SearchGrid(Grid,1,1,SearchBFS,Route2)); Check(Route2.Found and (Route2.Count=1) and (Route2.Cost=0),'Start sama dengan goal');
  Need(SetWall(Grid,1,2,True)); Need(SetWall(Grid,2,1,True));
  Need(SearchGrid(Grid,1,16,SearchBFS,Route2)); Check(not Route2.Found,'Grid terputus memberi Found false');
  Check(not SearchGrid(Grid,1,6,SearchBFS,Route2),'Goal dinding ditolak');
  Check(not SearchGrid(Grid,0,16,SearchBFS,Route2),'Start di luar grid ditolak');
  Check(not InitGrid(17,1,Grid2),'Ukuran grid berlebih ditolak');
  Need(SaveGrid('TESTMOD.TPM',Grid)); Need(LoadGrid('TESTMOD.TPM',Grid2));
  Check(Grid2.Blocked[2,2],'Roundtrip grid');
  Need(InitGrid(16,16,Grid)); Need(SearchGrid(Grid,1,256,SearchBFS,Route));
  Check(Route.Found and (Route.Cost=30) and (Route.Expanded=256),'BFS kapasitas maksimum 256 sel');

  Tri.A:=0; Tri.B:=5; Tri.C:=10;
  Need(TriangleMembership(2.5,Tri,Value)); Near(Value,0.5,1E-8,'Membership naik');
  Need(TriangleMembership(7.5,Tri,Value)); Near(Value,0.5,1E-8,'Membership turun');
  Need(TriangleMembership(5,Tri,Value)); Near(Value,1,1E-8,'Membership puncak');
  Need(TriangleMembership(20,Tri,Value)); Near(Value,0,1E-8,'Membership luar dukungan');
  Tri.B:=0; Need(TriangleMembership(0,Tri,Value)); Near(Value,1,1E-8,'Left shoulder tanpa pembagian nol');
  Tri.B:=10; Need(TriangleMembership(10,Tri,Value)); Near(Value,1,1E-8,'Right shoulder tanpa pembagian nol');
  Tri.A:=10; Check(not TriangleMembership(10,Tri,Value),'Segitiga degenerat ditolak');
  DefaultFuzzy(Fuzzy); Need(EvaluateFuzzy(Fuzzy,0,0,400,Value,Strength));
  Near(Value,100/6,0.001,'Centroid low shoulder');
  Need(EvaluateFuzzy(Fuzzy,40,100,400,Value,Strength)); Near(Value,500/6,0.001,'Centroid high shoulder');
  Need(EvaluateFuzzy(Fuzzy,20,50,400,Value,Strength)); Near(Value,50,1E-6,'Centroid simetris');
  Need(SaveFuzzy('TESTMOD.TPM',Fuzzy)); Need(LoadFuzzy('TESTMOD.TPM',Fuzzy2));
  Need(EvaluateFuzzy(Fuzzy2,20,50,400,Value,Strength)); Near(Value,50,1E-6,'Roundtrip fuzzy');
  Check(not EvaluateFuzzy(Fuzzy,-1,50,200,Value,Strength),'Fuzzy input di luar universe ditolak');
  Check(not EvaluateFuzzy(Fuzzy,20,50,0,Value,Strength),'Fuzzy segmen nol ditolak');
  for I:=1 to Fuzzy.RuleCount do Fuzzy.Rules[I].Weight:=0;
  Check(not EvaluateFuzzy(Fuzzy,20,50,200,Value,Strength),'Fuzzy tanpa rule aktif ditolak');

  Need(InitQ(2,2,0.5,0.9,0,Q)); Q.Q[2,1]:=10; Q.Q[2,2]:=5;
  Need(UpdateQ(Q,1,1,2,2,False)); Near(Q.Q[1,1],5.5,1E-8,'Q update Bellman');
  Q.Q[1,1]:=0; Need(UpdateQ(Q,1,1,0,2,True)); Near(Q.Q[1,1],1,1E-8,'Terminal tidak bootstrap');
  Need(ChooseAction(Q,1,False,L)); Check(L=1,'Q argmax');
  Q.Q[1,2]:=1; Need(ChooseAction(Q,1,False,L)); Check(L=1,'Q tie memilih aksi terkecil');
  Q.Epsilon:=1; AISetSeed(42); OK:=True;
  for I:=1 to 50 do begin Need(ChooseAction(Q,1,True,L)); if (L<1) or (L>2) then OK:=False end;
  Check(OK,'Epsilon exploration selalu menghasilkan aksi valid');
  Need(DecayEpsilon(Q,0.5,0.2)); Near(Q.Epsilon,0.5,1E-8,'Epsilon decay');
  Need(DecayEpsilon(Q,0.1,0.2)); Near(Q.Epsilon,0.2,1E-8,'Epsilon floor');
  Check(not UpdateQ(Q,0,1,2,1,False),'Q state nol ditolak');
  Check(not UpdateQ(Q,1,3,2,1,False),'Q aksi berlebih ditolak');
  Need(InitGrid(4,4,Grid)); Need(SetWall(Grid,2,2,True)); Need(SetWall(Grid,3,2,True));
  Need(GridStep(Grid,1,1,16,L,Reward,Terminal)); Check((L=1) and (Reward=-2),'Benturan grid self-loop dan penalti');
  Need(GridStep(Grid,15,2,16,L,Reward,Terminal)); Check((L=16) and Terminal and (Reward=10),'Goal terminal dengan reward');
  Need(GridStep(Grid,16,1,16,L,Reward,Terminal)); Check((L=16) and Terminal and (Reward=0),'Goal absorbing');
  Need(InitQ(16,4,0.3,0.95,0.25,Q));
  Need(TrainGridQ(Q,Grid,1,16,1000,100,42,QInfo));
  Need(GreedyGridPath(Q,Grid,1,16,Route)); Check(Route.Found,'Q-learning menemukan rute');
  Check(Route.Cost=6,'Q-learning contoh mencapai rute terpendek');
  Check(QInfo.Successes>950,'Q-learning episode berhasil');
  Check(QInfo.HistoryEpisode[QInfo.HistoryCount]=1000,'Q history mencakup episode terakhir');
  Need(SaveQ('TESTMOD.TPM',Q)); Need(LoadQ('TESTMOD.TPM',Q2));
  Need(GreedyGridPath(Q2,Grid,1,16,Route2)); Check(Route2.Found and (Route2.Cost=Route.Cost),'Roundtrip Q-table');
  Need(InitQ(16,4,0.3,0.95,0,Q2)); Need(GreedyGridPath(Q2,Grid,1,16,Route2));
  Check(not Route2.Found,'Greedy policy belum belajar berhenti saat siklus');
  Check(not InitQ(257,4,0.3,0.9,0.1,Q2),'Q kapasitas berlebih ditolak');

  Need(LoadCSV(DataPath('JAMNILAI.CSV'),True,TargetReal,D^));
  Need(FitLinear(D^,0,Linear)); Need(SaveLinear('TESTMOD.TPM',Linear));
  Need(LoadLinear('TESTMOD.TPM',Linear2)); Near(Linear2.Coeff[1],Linear.Coeff[1],1E-8,'Roundtrip linear v1');
  Need(FitScaler(D^,ScaleStandard,Sc)); Need(SaveScaler('TESTMOD.TPM',Sc));
  Need(LoadScaler('TESTMOD.TPM',Sc2)); Near(Sc2.Offset[1],Sc.Offset[1],1E-8,'Roundtrip scaler v1');
  Need(FitImputer(D^,Imp)); Need(SaveImputer('TESTMOD.TPM',Imp));
  Need(LoadImputer('TESTMOD.TPM',Imp2)); Near(Imp2.Means[1],Imp.Means[1],1E-8,'Roundtrip imputer v1');
  Need(FitKNN(D^,3,KNN)); Need(SaveKNN('TESTMOD.TPM',KNN));
  Need(LoadKNN('TESTMOD.TPM',Store^,KNN2));
  Check(KNN2.Data=@Store^,'KNN loader mengikat pointer ke storage pemanggil');
  V[1]:=5; Need(PredictKNN(KNN,V,L,Value)); Need(PredictKNN(KNN2,V,L,Value2));
  Near(Value,Value2,1E-8,'Roundtrip KNN dan dataset v1');
  Need(LoadCSV(DataPath('CLUSTER.CSV'),True,TargetNone,Tr^));
  Need(FitKMeans(Tr^,3,100,0.0001,42,KM,Labels,A,N));
  Need(SaveKMeans('TESTMOD.TPM',KM)); Need(LoadKMeans('TESTMOD.TPM',KM2));
  Need(PredictCluster(KM,Tr^.X[1],L,Value)); Need(PredictCluster(KM2,Tr^.X[1],K,Value2));
  Check(K=L,'Roundtrip K-means v1'); Near(Value,Value2,1E-8,'Jarak K-means roundtrip');
  Need(SaveLinear('TESTMOD.TPM',Linear)); Before:=Linear2.Intercept;
  Check(not LoadTree('TESTMOD.TPM',Tree2),'Loader menolak jenis model berbeda');
  FlipByte(-1); Check(not LoadLinear('TESTMOD.TPM',Linear2),'Loader menolak checksum rusak');
  Near(Linear2.Intercept,Before,1E-8,'Load gagal tidak memutasi model');
  Need(SaveLinear('TESTMOD.TPM',Linear)); FlipByte(0);
  Check(not LoadLinear('TESTMOD.TPM',Linear2),'Loader menolak magic salah');
  Need(SaveLinear('TESTMOD.TPM',Linear)); FlipByte(14);
  Check(not LoadLinear('TESTMOD.TPM',Linear2),'Loader menolak ABI berbeda');
  Need(SaveLinear('TESTMOD.TPM',Linear)); Assign(F,'TESTMOD.TPM'); Reset(F,1);
  Seek(F,FileSize(F)); ByteValue:=0; BlockWrite(F,ByteValue,1,Actual); Close(F);
  Check(not LoadLinear('TESTMOD.TPM',Linear2),'Loader menolak trailing bytes');
  Assign(F,'TESTMOD.TPM'); Rewrite(F,1); ByteValue:=0; BlockWrite(F,ByteValue,1,Actual); Close(F);
  Check(not LoadLinear('TESTMOD.TPM',Linear2),'Loader menolak header terpotong');
  Check(not LoadLinear('NOFILE.TPM',Linear2),'Loader berkas hilang');
  Check(not SaveLinear('NO_DIR/TEST.TPM',Linear),'Saver folder hilang');
  Linear2.Fitted:=False; Check(not SaveLinear('TESTMOD.TPM',Linear2),'Saver menolak model belum terlatih');

  KNN.Fitted:=False; KNN.Data:=nil; KNN2.Fitted:=False; KNN2.Data:=nil;
  FreeData(Store); FreeData(Tr); FreeData(D);
  WriteLn('TOTAL ADV PASS=',Passed,' FAIL=',Failed);
  if Failed<>0 then Halt(1)
end.
