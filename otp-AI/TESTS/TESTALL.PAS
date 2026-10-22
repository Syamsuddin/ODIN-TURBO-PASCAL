program TestAll;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}
uses AITypes,AIMath,AIStats,AIData,AISplit,AILINEAR,AIKNN,AIKMeans,AIPlot;
var D,Tr,Te,Extra: PDataSet;
    Passed,Failed,I,J,N,H,C,Code: Integer;
    V,W: TVector; A,B,P,Hist: TSeries; LA,LB: TLabels;
    M1,M2,M3: TMatrix; Order1,Order2,Folds: TIndexList;
    Sc: TScaler; Imp: TImputer; Cat: TCategoryMap;
    Reg: TLinearModel; KNN: TKNNModel; KM: TKMeansModel;
    RM: TRegMetrics; CM: TConfusion; MC: TClassMetrics;
    Value,Lo,Hi,Dist,Inertia,Earlier: TFloat;
    Seen: array[1..MaxSamples] of Boolean;
    OK: Boolean; F: Text; S: string;
procedure Check(Condition: Boolean; Name: string);
begin
  if Condition then begin Inc(Passed); WriteLn('PASS ',Name) end
  else begin Inc(Failed); WriteLn('FAIL ',Name,' [',AIErrorCode,'] ',AIError) end
end;
procedure Near(Actual,Expected,Tolerance: TFloat; Name: string);
begin Check(Abs(Actual-Expected) <= Tolerance,Name) end;
procedure Need(Condition: Boolean);
begin
  if not Condition then begin WriteLn('FATAL ',AIError); Halt(2) end
end;
procedure CSVFixture(S1,S2: string);
begin
  Assign(F,'FIXTURE.CSV'); Rewrite(F); WriteLn(F,S1); WriteLn(F,S2); Close(F)
end;
begin
  Passed := 0; Failed := 0;
  Need(NewData(D)); Need(NewData(Tr)); Need(NewData(Te)); Need(NewData(Extra));
  WriteLn('OTP-AI TESTALL');
  Check(SizeOf(TDataSet) < 60000,'Dataset satu blok < 60000 byte');
  FillChar(V,SizeOf(V),0); FillChar(W,SizeOf(W),0);
  V[1] := 1; V[2] := 2; W[1] := 4; W[2] := 6;
  Need(Euclidean(V,W,2,Value)); Near(Value,5,1E-7,'Euclidean 3-4-5');
  Need(DotProduct(V,W,2,Value)); Near(Value,16,1E-7,'Dot product');
  Need(Manhattan(V,W,2,Value)); Near(Value,7,1E-7,'Manhattan');
  Check(not Euclidean(V,W,0,Value),'Tolak vektor kosong');
  Near(Sigmoid(0),0.5,1E-7,'Sigmoid nol');
  Near(Sigmoid(-1000),0,1E-7,'Sigmoid negatif ekstrem');
  Near(Sigmoid(1000),1,1E-7,'Sigmoid positif ekstrem');
  Check(not SafeLn(0,Value),'Log nol ditolak');
  Check(not SafeSqrt(-1,Value),'Akar negatif ditolak');
  Check(not SafeExp(100,Value),'Eksponen besar ditolak');
  Need(SafeLn(1,Value)); Near(Value,0,1E-7,'Log satu');
  Need(SafeExp(0,Value)); Near(Value,1,1E-7,'Exp nol');
  Need(SafeSqrt(9,Value)); Near(Value,3,1E-7,'Akar sembilan');
  Need(IntPower(2,-3,Value)); Near(Value,0.125,1E-7,'Pangkat negatif');
  Check(not IntPower(0,-1,Value),'Nol pangkat negatif ditolak');
  Check(not IntPower(1E12,100,Value),'Overflow pangkat ditolak');
  AISetSeed(1); Near(AIRandom,16807/2147483647.0,1E-10,'PRNG Park-Miller');
  AISetSeed(-2147483647); Value := AIRandom;
  Check((Value > 0) and (Value < 1),'Seed negatif tetap valid');
  Check(AIRandomInt(1) = 0,'Acak satu kemungkinan');
  Check(AIRandomInt(0) = 0,'Acak batas nol tidak crash');
  Check(AIErrorCode = ErrValue,'Acak nol memberi error');

  Need(MatrixInit(M1,2,3)); Need(MatrixInit(M2,3,2));
  for I := 1 to 2 do for J := 1 to 3 do M1.V[I,J] := (I-1)*3+J;
  for I := 1 to 3 do for J := 1 to 2 do M2.V[I,J] := (I-1)*2+J;
  Need(MatrixMultiply(M1,M2,M3)); Near(M3.V[1,1],22,1E-7,'Matriks kali 1,1');
  Near(M3.V[2,2],64,1E-7,'Matriks kali 2,2');
  Need(MatrixTranspose(M1,M1)); Check((M1.Rows=3) and (M1.Cols=2),'Transpose in-place');
  Near(M1.V[3,2],6,1E-7,'Nilai transpose');
  Need(MatrixIdentity(M2,3)); Check(not MatrixAdd(M1,M2,M3),'Tambah dimensi salah');
  Need(MatrixScale(M2,2,M2)); Near(M2.V[1,1],2,1E-7,'Skala in-place');
  Need(MatrixSubtract(M2,M2,M3)); Near(M3.V[2,2],0,1E-7,'Pengurangan matriks');
  Need(MatrixAdd(M2,M3,M2)); Near(M2.V[1,1],2,1E-7,'Tambah in-place');
  Check(not MatrixInit(M1,17,1),'Matriks melampaui kapasitas');
  Need(MatrixInit(M1,1,1)); Need(MatrixInit(M2,1,1)); Need(MatrixInit(M3,1,1));
  M3.V[1,1] := 123;
  M1.V[1,1] := 7E11; M2.V[1,1] := 7E11;
  Check((not MatrixAdd(M1,M2,M3)) and (AIErrorCode=ErrValue) and
    (M3.V[1,1]=123),'Tambah menolak hasil di atas 1E12');
  M1.V[1,1] := 7E11; M2.V[1,1] := -7E11;
  Check((not MatrixSubtract(M1,M2,M3)) and (AIErrorCode=ErrValue) and
    (M3.V[1,1]=123),'Kurang menolak hasil di atas 1E12');
  M1.V[1,1] := 6E11;
  Check((not MatrixScale(M1,2,M3)) and (AIErrorCode=ErrValue) and
    (M3.V[1,1]=123),'Skala menolak hasil di atas 1E12');
  M1.V[1,1] := 1E12; M2.V[1,1] := 2;
  Check((not MatrixMultiply(M1,M2,M3)) and (AIErrorCode=ErrValue) and
    (M3.V[1,1]=123),'Kali menolak hasil di atas 1E12');

  for I := 1 to 5 do begin A[I] := I; B[I] := 2*I+1 end;
  Need(Mean(A,5,Value)); Near(Value,3,1E-7,'Mean');
  Need(Median(A,5,Value)); Near(Value,3,1E-7,'Median ganjil');
  Need(Median(A,4,Value)); Near(Value,2.5,1E-7,'Median genap');
  Need(Variance(A,5,False,Value)); Near(Value,2,1E-7,'Varians populasi');
  Need(Variance(A,5,True,Value)); Near(Value,2.5,1E-7,'Varians sampel');
  Need(StdDev(A,5,False,Value)); Near(Value,Sqrt(2),1E-7,'Simpangan baku');
  Need(MinMax(A,5,Lo,Hi)); Check((Lo=1) and (Hi=5),'Min max');
  Need(Correlation(A,B,5,Value)); Near(Value,1,1E-7,'Korelasi positif');
  for I := 1 to 5 do B[I] := -A[I];
  Need(Correlation(A,B,5,Value)); Near(Value,-1,1E-7,'Korelasi negatif');
  for I := 1 to 5 do B[I] := 1;
  Check(not Correlation(A,B,5,Value),'Korelasi konstan tak terdefinisi');
  Check(not Variance(A,1,True,Value),'Varians sampel satu angka ditolak');

  CSVFixture('"FITUR,A","FITUR ""B""",Y','"1.5",,3');
  Need(LoadCSV('FIXTURE.CSV',True,TargetReal,D^));
  Check(D^.Names[1]='FITUR,A','Header CSV dengan koma');
  Check(D^.Names[2]='FITUR "B"','Escape kutip CSV');
  Check(D^.Missing[1,2],'Kolom kosong ditandai');
  Near(D^.X[1,1],1.5,1E-7,'Angka dalam kutip');
  Need(SaveCSV('ROUND.CSV',D^)); Need(LoadCSV('ROUND.CSV',True,TargetReal,Extra^));
  Check(Extra^.Names[2]=D^.Names[2],'Roundtrip header CSV');
  Check(Extra^.Missing[1,2],'Roundtrip nilai kosong CSV');
  CSVFixture('X,Y','1,2,3'); Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak kolom tidak konsisten');
  Check(D^.Count=0,'CSV gagal mengosongkan hasil');
  CSVFixture('X,Y','1E99,2'); Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak eksponen CSV ekstrem');
  CSVFixture('X,Y','1,'); Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak target kosong');
  CSVFixture('X,Y','1,1.5'); Check(not LoadCSV('FIXTURE.CSV',True,TargetClass,D^),'Tolak label pecahan');
  CSVFixture('X,Y','1,-1'); Check(not LoadCSV('FIXTURE.CSV',True,TargetClass,D^),'Tolak label negatif');
  CSVFixture('X,Y','"1,2'); Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak kutip terbuka');
  CSVFixture('X,Y','abc,2'); Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak teks fitur');
  CSVFixture('X,Y','1E-25,2'); Need(LoadCSV('FIXTURE.CSV',True,TargetReal,D^));
  Need(SaveCSV('ROUND.CSV',D^)); Need(LoadCSV('ROUND.CSV',True,TargetReal,Extra^));
  Near(Extra^.X[1,1]/1E-25,1,1E-7,'Roundtrip angka kecil');
  Check(not LoadCSV('NOFILE.CSV',True,TargetReal,D^),'CSV berkas hilang');
  Check(not SaveCSV('NO_DIR/OUT.CSV',Extra^),'CSV folder tujuan hilang');
  Assign(F,'FIXTURE.CSV'); Rewrite(F); WriteLn(F,'X,Y');
  for I := 1 to 300 do Write(F,'1'); WriteLn(F,',2'); Close(F);
  Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak baris >255 karakter');
  Assign(F,'FIXTURE.CSV'); Rewrite(F); WriteLn(F,'X,Y');
  for I := 1 to 201 do WriteLn(F,I,',',I); Close(F);
  Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Tolak 201 baris');
  CSVFixture('1,2','3,4'); Need(LoadCSV('FIXTURE.CSV',False,TargetNone,D^));
  Check((D^.Count=2) and (D^.Features=2),'CSV tanpa header dan tanpa target');
  Need(GetColumn(D^,1,A)); Near(A[2],3,1E-7,'GetColumn');
  Order1[1] := 2; Need(SelectColumns(D^,Order1,1,Extra^));
  Near(Extra^.X[2,1],4,1E-7,'SelectColumns');
  Need(FilterRange(D^,1,2,4,Extra^)); Check(Extra^.Count=1,'FilterRange');
  Need(FilterRange(D^,1,20,40,Extra^)); Check(Extra^.Count=0,'Filter kosong tetap sukses');
  Check(not FilterRange(D^,1,0,4,D^),'Filter alias ditolak');

  InitData(D^,2,TargetReal); D^.Count := 3;
  for I := 1 to 3 do begin D^.X[I,1] := I*2; D^.X[I,2] := 7; D^.Y[I] := I end;
  D^.Missing[2,1] := True;
  Check(not FitScaler(D^,ScaleStandard,Sc),'Scaler menolak missing');
  Need(FitImputer(D^,Imp)); Near(Imp.Means[1],4,1E-7,'Imputer mean hanya nilai terisi');
  Need(ImputeData(Imp,D^)); Near(D^.X[2,1],4,1E-7,'Imputer mengganti nilai');
  Need(FitScaler(D^,ScaleStandard,Sc)); V := D^.X[1]; W := V;
  Need(TransformVector(Sc,V)); Near(V[2],0,1E-7,'Fitur konstan menjadi nol');
  Need(InverseVector(Sc,V)); Near(V[1],W[1],1E-7,'Inverse scaler');
  Need(TransformData(Sc,D^)); Need(GetColumn(D^,1,A));
  Need(Mean(A,3,Value)); Near(Value,0,1E-7,'Mean setelah standardisasi');
  Need(Variance(A,3,False,Value)); Near(Value,1,1E-7,'Varians standar populasi');
  InitData(D^,1,TargetNone); D^.Count := 2; D^.X[1,1] := 0; D^.X[2,1] := 10;
  Need(FitScaler(D^,ScaleMinMax,Sc)); V[1] := 20;
  Need(TransformVector(Sc,V)); Near(V[1],2,1E-7,'Minmax data baru boleh di luar 0..1');
  Near(Sc.Divisor[1],10,1E-7,'Transform tidak melatih ulang scaler');
  D^.Missing[1,1] := True; D^.Missing[2,1] := True;
  Check(not FitImputer(D^,Imp),'Imputer kolom seluruhnya kosong ditolak');
  InitCategories(Cat); Need(AddCategory(Cat,'A',Code)); Check(Code=0,'Kategori nol');
  Need(AddCategory(Cat,'B',Code)); Check(Code=1,'Kategori satu');
  Need(AddCategory(Cat,'A',Code)); Check(Cat.Count=2,'Kategori duplikat tidak ditambah');
  Check(not EncodeCategory(Cat,'C',Code),'Kategori baru ditolak saat transform');
  Need(OneHot(1,2,V)); Check((V[1]=0) and (V[2]=1),'One hot');
  Check(not OneHot(3,2,V),'One hot kode salah');

  InitData(D^,1,TargetReal); D^.Count := 20;
  for I := 1 to 20 do begin D^.X[I,1] := I; D^.Y[I] := 2*I+3 end;
  Need(TrainTestSplit(D^,Tr^,Te^,0.25,True,42));
  Check((Tr^.Count=15) and (Te^.Count=5),'Proporsi split');
  FillChar(Seen,SizeOf(Seen),0); OK := True;
  for I := 1 to Tr^.Count do begin J := Round(Tr^.X[I,1]); if Seen[J] then OK := False; Seen[J] := True end;
  for I := 1 to Te^.Count do begin J := Round(Te^.X[I,1]); if Seen[J] then OK := False; Seen[J] := True end;
  for I := 1 to 20 do if not Seen[I] then OK := False;
  Check(OK,'Split disjoint dan seluruh baris terpakai');
  Need(MakeOrder(20,True,42,Order1)); Need(MakeOrder(20,True,42,Order2));
  OK := True; for I := 1 to 20 do if Order1[I]<>Order2[I] then OK := False;
  Check(OK,'Seed yang sama menghasilkan urutan sama');
  Check(not TrainTestSplit(D^,D^,Te^,0.25,True,42),'Split alias ditolak');
  Check(not TrainTestSplit(D^,Tr^,Te^,1,True,42),'Fraksi split satu ditolak');
  Need(MakeFolds(20,5,True,42,Folds)); FillChar(Seen,SizeOf(Seen),0); OK := True;
  for C := 1 to 5 do begin
    Need(FoldSplit(D^,Folds,5,C,Tr^,Te^));
    if Te^.Count<>4 then OK := False;
    for I := 1 to Te^.Count do begin
      J := Round(Te^.X[I,1]); if Seen[J] then OK := False; Seen[J] := True
    end
  end;
  for I := 1 to 20 do if not Seen[I] then OK := False;
  Check(OK,'K-fold setiap baris diuji tepat satu kali');

  Need(FitLinear(D^,0,Reg)); Near(Reg.Intercept,3,1E-6,'OLS intercept');
  Near(Reg.Coeff[1],2,1E-6,'OLS slope'); V[1] := 25;
  Need(PredictLinear(Reg,V,Value)); Near(Value,53,1E-6,'OLS prediksi data baru');
  Need(PredictLinearData(Reg,D^,P));
  Need(RegressionMetrics(D^.Y,P,D^.Count,RM)); Near(RM.RMSE,0,1E-6,'OLS RMSE');
  {$IFDEF FPC} S := 'DATA/MULTIREG.CSV';
  {$ELSE}
    {$IFDEF UNIX} S := 'DATA/MULTIREG.CSV';
    {$ELSE} S := 'DATA\MULTIREG.CSV'; {$ENDIF}
  {$ENDIF}
  Need(LoadCSV(S,True,TargetReal,D^)); Need(FitLinear(D^,0,Reg));
  Near(Reg.Intercept,5,1E-6,'OLS berganda intercept');
  Near(Reg.Coeff[1],2,1E-6,'OLS berganda koefisien 1');
  Near(Reg.Coeff[2],-3,1E-6,'OLS berganda koefisien 2');
  for I := 1 to D^.Count do D^.X[I,2] := 2*D^.X[I,1];
  Check(not FitLinear(D^,0,Reg),'OLS kolinear ditolak');
  Check(not Reg.Fitted,'Model gagal tidak ditandai fitted');
  Need(FitLinear(D^,0.1,Reg)); Check(Reg.Fitted,'Ridge menangani kolinear');

  InitData(D^,1,TargetClass); D^.Count := 4;
  D^.X[1,1] := 0; D^.X[2,1] := 1; D^.X[3,1] := 9; D^.X[4,1] := 10;
  D^.Labels[1] := 0; D^.Labels[2] := 0; D^.Labels[3] := 1; D^.Labels[4] := 1;
  Need(FitKNN(D^,3,KNN)); V[1] := 9;
  Need(PredictKNN(KNN,V,C,Value)); Check(C=1,'KNN klasifikasi');
  Need(FitKNN(D^,2,KNN)); V[1] := 5;
  Need(PredictKNN(KNN,V,C,Value)); Check(C=0,'KNN seri suara memilih kelas terkecil');
  Check(not FitKNN(D^,5,KNN),'KNN K terlalu besar');
  D^.TargetKind := TargetReal;
  for I := 1 to D^.Count do D^.Y[I] := D^.X[I,1]*2;
  Need(FitKNN(D^,2,KNN)); V[1] := 9.5;
  Need(PredictKNN(KNN,V,C,Value)); Near(Value,19,1E-7,'KNN regresi mean tetangga');
  Dec(D^.Count); Check(not PredictKNN(KNN,V,C,Value),'KNN mendeteksi dimensi data berubah');
  KNN.Fitted := False; KNN.Data := nil;

  InitData(D^,2,TargetNone); D^.Count := 6;
  for I := 1 to 3 do begin D^.X[I,1] := I-1; D^.X[I,2] := 0 end;
  for I := 4 to 6 do begin D^.X[I,1] := I+6; D^.X[I,2] := 10 end;
  Need(FitKMeans(D^,2,100,0.00001,42,KM,LA,Hist,H));
  Check(KM.Converged,'K-means konvergen');
  Near(KM.Inertia,4,1E-6,'K-means inertia diketahui');
  Check((LA[1]=LA[2]) and (LA[2]=LA[3]) and (LA[1]<>LA[4]),'K-means partisi');
  Need(PredictClusters(KM,D^,LB,Inertia)); Near(Inertia,KM.Inertia,1E-6,'K-means fit dan predict inertia konsisten');
  OK := True; for I := 1 to D^.Count do if LA[I]<>LB[I] then OK := False;
  Check(OK,'K-means label cocok pusat akhir');
  OK := True; for I := 2 to H do if Hist[I]>Hist[I-1]+1E-6 then OK := False;
  Check(OK,'K-means history tidak meningkat');
  Need(FitKMeans(D^,2,1,0,42,KM,LA,Hist,H));
  Check((KM.Iterations=1) and not KM.Converged,'K-means batas iterasi dilaporkan');
  for I := 1 to D^.Count do begin D^.X[I,1] := 1; D^.X[I,2] := 1 end;
  Check(not FitKMeans(D^,2,100,0.001,42,KM,LA,Hist,H),'K melebihi titik unik ditolak');
  Need(FitKMeans(D^,1,100,0.001,42,KM,LA,Hist,H)); Near(KM.Inertia,0,1E-7,'K-means satu pusat titik identik');

  A[1] := 1; A[2] := 2; A[3] := 3; B[1] := 1; B[2] := 2; B[3] := 4;
  Need(RegressionMetrics(A,B,3,RM)); Near(RM.MAE,1/3,1E-7,'MAE');
  Near(RM.MSE,1/3,1E-7,'MSE'); Near(RM.R2,0.5,1E-7,'R2');
  A[1] := 1; A[2] := 1; Need(RegressionMetrics(A,B,2,RM));
  Check(not RM.R2Defined,'R2 target konstan tidak terdefinisi');
  LA[1] := 0; LA[2] := 0; LA[3] := 1; LA[4] := 1;
  LB[1] := 0; LB[2] := 1; LB[3] := 1; LB[4] := 1;
  Need(ConfusionMatrix(LA,LB,4,2,CM)); Need(ClassificationMetrics(CM,MC));
  Near(MC.Accuracy,0.75,1E-7,'Accuracy'); Near(MC.Precision[1],2/3,1E-7,'Precision');
  Near(MC.Recall[1],1,1E-7,'Recall'); Near(MC.F1[1],0.8,1E-7,'F1');
  Near(MC.MacroF1,(2/3+0.8)/2,1E-7,'Macro F1');
  LA[1] := 0; LB[1] := 0; Need(ConfusionMatrix(LA,LB,1,3,CM));
  Need(ClassificationMetrics(CM,MC)); Near(MC.MacroF1,1/3,1E-7,'Kelas kosong bernilai nol dalam macro');
  LB[1] := -1; Check(not ConfusionMatrix(LA,LB,1,2,CM),'Label negatif evaluasi ditolak');

  InitData(D^,8,TargetReal); D^.Count := 200;
  for I := 1 to 200 do begin
    for J := 1 to 8 do D^.X[I,J] := I*J/10;
    D^.Y[I] := I
  end;
  Need(SaveCSV('ROUND.CSV',D^));
  Need(LoadCSV('ROUND.CSV',True,TargetReal,Extra^));
  Check((Extra^.Count=200) and (Extra^.Features=8),'CSV kapasitas maksimum');
  Near(Extra^.X[200,8],160,1E-7,'CSV nilai terakhir kapasitas maksimum');
  for J := 1 to 8 do D^.Names[J] := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ12345';
  D^.TargetName := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ12345';
  Check(not SaveCSV('ROUND.CSV',D^),'CSV menolak header hasil >255 karakter');
  InitData(D^,1,TargetReal); D^.Count := 1; D^.X[1,1] := 1E-31;
  Check(not SaveCSV('ROUND.CSV',D^),'CSV menolak angka terlalu kecil untuk format');
  InitData(Extra^,1,TargetReal);
  CopyRow(D^,0,Extra^,1); Check(AIErrorCode=ErrSize,'CopyRow menolak indeks nol');
  CSVFixture('ABCDEFGHIJKLMNOPQRSTUVWXYZ123456,Y','1,2');
  Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'Header CSV >31 karakter ditolak');
  CSVFixture('X,Y','0.1234567890123456789012345678901,2');
  Check(not LoadCSV('FIXTURE.CSV',True,TargetReal,D^),'CSV presisi fraksi berlebih ditolak');

  for I := 1 to 4 do begin A[I] := I; B[I] := 2*I+3; LA[I] := I mod 2 end;
  Need(SaveScatterSVG('TSCATTER.SVG',A,B,4,LA,'X < Y & "AI"'));
  Need(SaveCurveSVG('TCURVE.SVG',B,4,'Kurva'));
  Need(SaveRegressionSVG('TREG.SVG',A,B,4,3,2,'Regresi'));
  Check(not SaveCurveSVG('BAD.SVG',B,0,'Kosong'),'Plot menolak data kosong');
  Check(not SaveCurveSVG('NO_DIR/X.SVG',B,4,'IO'),'Plot mendeteksi kegagalan berkas');
  Check(not PlotScatter(A,B,4,LA,'Belum buka'),'Plot BGI perlu dibuka');
  FreeData(Extra); FreeData(Te); FreeData(Tr); FreeData(D);
  Check(D=nil,'FreeData mengosongkan pointer');
  WriteLn('TOTAL PASS=',Passed,' FAIL=',Failed);
  if Failed>0 then Halt(1)
end.
