unit AIStats;
interface
uses AITypes;
function Mean(var A: TSeries; N: Integer; var Value: TFloat): Boolean;
function Median(var A: TSeries; N: Integer; var Value: TFloat): Boolean;
function Variance(var A: TSeries; N: Integer; Sample: Boolean;
  var Value: TFloat): Boolean;
function StdDev(var A: TSeries; N: Integer; Sample: Boolean;
  var Value: TFloat): Boolean;
function MinMax(var A: TSeries; N: Integer;
  var Minimum, Maximum: TFloat): Boolean;
function Correlation(var A,B: TSeries; N: Integer;
  var Value: TFloat): Boolean;

function RegressionMetrics(var Actual,Predicted: TSeries; N: Integer;
  var Metrics: TRegMetrics): Boolean;
function ConfusionMatrix(var Actual,Predicted: TLabels;
  N,Classes: Integer; var Matrix: TConfusion): Boolean;
function ClassificationMetrics(var Matrix: TConfusion;
  var Metrics: TClassMetrics): Boolean;
procedure PrintConfusion(var Matrix: TConfusion);
implementation
function GoodSeries(var A: TSeries; N: Integer): Boolean;
var I: Integer;
begin
  ClearAIError; GoodSeries := False;
  if (N < 1) or (N > MaxSamples) then begin
    SetAIError(ErrSize, 'Panjang seri harus 1..200'); Exit
  end;
  for I := 1 to N do if not ValidNumber(A[I]) then begin
    SetAIError(ErrValue, 'Angka seri tidak valid'); Exit
  end;
  GoodSeries := True
end;
function Mean(var A: TSeries; N: Integer; var Value: TFloat): Boolean;
var I: Integer;
begin
  Value := 0; Mean := False;
  if not GoodSeries(A,N) then Exit;
  for I := 1 to N do Value := Value+(A[I]-Value)/I;
  Mean := True
end;
function Median(var A: TSeries; N: Integer; var Value: TFloat): Boolean;
var I,J: Integer; T: TSeries; V: TFloat;
begin
  Value := 0; Median := False;
  if not GoodSeries(A,N) then Exit;
  T := A;
  for I := 2 to N do begin
    V := T[I]; J := I-1;
    while J >= 1 do begin
      if T[J] <= V then Break;
      T[J+1] := T[J]; Dec(J)
    end;
    T[J+1] := V
  end;
  if Odd(N) then Value := T[(N+1) div 2]
  else Value := (T[N div 2]+T[N div 2+1])/2;
  Median := True
end;
function Variance(var A: TSeries; N: Integer; Sample: Boolean;
  var Value: TFloat): Boolean;
var I,Den: Integer; Avg,Delta,Sum: TFloat;
begin
  Value := 0; Variance := False;
  if not GoodSeries(A,N) then Exit;
  if Sample and (N < 2) then begin
    SetAIError(ErrSize, 'Varians sampel memerlukan minimal 2 angka'); Exit
  end;
  Avg := 0; Sum := 0;
  for I := 1 to N do begin
    Delta := A[I]-Avg; Avg := Avg+Delta/I;
    Sum := Sum+Delta*(A[I]-Avg)
  end;
  Den := N; if Sample then Dec(Den);
  Value := Sum/Den;
  if Value < 0 then Value := 0;
  Variance := True
end;
function StdDev(var A: TSeries; N: Integer; Sample: Boolean;
  var Value: TFloat): Boolean;
begin
  StdDev := False;
  if not Variance(A,N,Sample,Value) then Exit;
  Value := Sqrt(Value); StdDev := True
end;
function MinMax(var A: TSeries; N: Integer;
  var Minimum, Maximum: TFloat): Boolean;
var I: Integer;
begin
  Minimum := 0; Maximum := 0; MinMax := False;
  if not GoodSeries(A,N) then Exit;
  Minimum := A[1]; Maximum := A[1];
  for I := 2 to N do begin
    if A[I] < Minimum then Minimum := A[I];
    if A[I] > Maximum then Maximum := A[I]
  end;
  MinMax := True
end;
function Correlation(var A,B: TSeries; N: Integer;
  var Value: TFloat): Boolean;
var I: Integer; MA,MB,DA,DB,SA,SB,SAB: TFloat;
begin
  Value := 0; Correlation := False;
  if not GoodSeries(A,N) then Exit;
  if not GoodSeries(B,N) then Exit;
  if N < 2 then begin SetAIError(ErrSize,'Korelasi perlu 2 angka'); Exit end;
  MA := 0; MB := 0; SA := 0; SB := 0; SAB := 0;
  for I := 1 to N do begin
    DA := A[I]-MA; DB := B[I]-MB;
    MA := MA+DA/I; MB := MB+DB/I;
    SA := SA+DA*(A[I]-MA); SB := SB+DB*(B[I]-MB);
    SAB := SAB+DA*(B[I]-MB)
  end;
  if (SA <= 0) or (SB <= 0) then begin
    SetAIError(ErrValue, 'Korelasi tidak terdefinisi untuk seri konstan'); Exit
  end;
  { Dua akar terpisah menghindari SA*SB yang bisa overflow Real48. }
  Value := (SAB/Sqrt(SA))/Sqrt(SB);
  if Value > 1 then Value := 1;
  if Value < -1 then Value := -1;
  Correlation := True
end;

function RegressionMetrics(var Actual,Predicted: TSeries; N: Integer;
  var Metrics: TRegMetrics): Boolean;
var I: Integer; Avg,Error,SSE,SST: TFloat;
begin
  ClearAIError; FillChar(Metrics,SizeOf(Metrics),0);
  RegressionMetrics := False;
  if (N < 1) or (N > MaxSamples) then begin
    SetAIError(ErrSize,'Evaluasi perlu 1..200 baris'); Exit
  end;
  Avg := 0;
  for I := 1 to N do begin
    if not ValidNumber(Actual[I]) or not ValidNumber(Predicted[I]) then begin
      SetAIError(ErrValue,'Data evaluasi tidak valid'); Exit
    end;
    Avg := Avg+(Actual[I]-Avg)/I
  end;
  SSE := 0; SST := 0;
  for I := 1 to N do begin
    Error := Actual[I]-Predicted[I];
    Metrics.MAE := Metrics.MAE+Abs(Error);
    SSE := SSE+Error*Error; SST := SST+Sqr(Actual[I]-Avg)
  end;
  Metrics.MAE := Metrics.MAE/N; Metrics.MSE := SSE/N;
  Metrics.RMSE := Sqrt(Metrics.MSE);
  Metrics.R2Defined := (N >= 2) and (SST > 0);
  if Metrics.R2Defined then begin
    { Hindari overflow rasio pada target yang hampir konstan. }
    if SST < 1 then
      if SSE > 1.0E30*SST then Metrics.R2Defined := False;
    if Metrics.R2Defined then Metrics.R2 := 1-SSE/SST
  end;
  RegressionMetrics := True
end;
function ConfusionMatrix(var Actual,Predicted: TLabels;
  N,Classes: Integer; var Matrix: TConfusion): Boolean;
var I: Integer;
begin
  ClearAIError; FillChar(Matrix,SizeOf(Matrix),0); ConfusionMatrix := False;
  if (N < 1) or (N > MaxSamples) or
     (Classes < 1) or (Classes > MaxClasses) then begin
    SetAIError(ErrSize,'Ukuran confusion matrix tidak valid'); Exit
  end;
  for I := 1 to N do
    if (Actual[I] < 0) or (Actual[I] >= Classes) or
       (Predicted[I] < 0) or (Predicted[I] >= Classes) then begin
      SetAIError(ErrValue,'Label di luar rentang kelas evaluasi'); Exit
    end;
  Matrix.Classes := Classes; Matrix.Total := N;
  for I := 1 to N do Inc(Matrix.Cells[Actual[I],Predicted[I]]);
  ConfusionMatrix := True
end;
function ClassificationMetrics(var Matrix: TConfusion;
  var Metrics: TClassMetrics): Boolean;
var I,J,RowSum,ColSum,Correct: Integer; Total: LongInt; Den: TFloat;
begin
  ClearAIError; FillChar(Metrics,SizeOf(Metrics),0);
  ClassificationMetrics := False;
  if (Matrix.Classes < 1) or (Matrix.Classes > MaxClasses) or
     (Matrix.Total < 1) or (Matrix.Total > MaxSamples) then begin
    SetAIError(ErrSize,'Confusion matrix kosong/tidak valid'); Exit
  end;
  Total := 0;
  for I := 0 to Matrix.Classes-1 do for J := 0 to Matrix.Classes-1 do begin
    if (Matrix.Cells[I,J] < 0) or (Matrix.Cells[I,J] > MaxSamples) then begin
      SetAIError(ErrValue,'Frekuensi confusion matrix tidak valid'); Exit
    end;
    Total := Total+Matrix.Cells[I,J]
  end;
  if Total <> Matrix.Total then begin
    SetAIError(ErrValue,'Total confusion matrix tidak cocok'); Exit
  end;
  Correct := 0;
  for I := 0 to Matrix.Classes-1 do begin
    RowSum := 0; ColSum := 0;
    for J := 0 to Matrix.Classes-1 do begin
      RowSum := RowSum+Matrix.Cells[I,J];
      ColSum := ColSum+Matrix.Cells[J,I]
    end;
    Inc(Correct,Matrix.Cells[I,I]); Metrics.Support[I] := RowSum;
    if ColSum > 0 then Metrics.Precision[I] := Matrix.Cells[I,I]/ColSum;
    if RowSum > 0 then Metrics.Recall[I] := Matrix.Cells[I,I]/RowSum;
    Den := Metrics.Precision[I]+Metrics.Recall[I];
    if Den > 0 then Metrics.F1[I] :=
      2*Metrics.Precision[I]*Metrics.Recall[I]/Den;
    Metrics.MacroPrecision := Metrics.MacroPrecision+Metrics.Precision[I];
    Metrics.MacroRecall := Metrics.MacroRecall+Metrics.Recall[I];
    Metrics.MacroF1 := Metrics.MacroF1+Metrics.F1[I]
  end;
  Metrics.Accuracy := Correct/Matrix.Total;
  Metrics.MacroPrecision := Metrics.MacroPrecision/Matrix.Classes;
  Metrics.MacroRecall := Metrics.MacroRecall/Matrix.Classes;
  Metrics.MacroF1 := Metrics.MacroF1/Matrix.Classes;
  ClassificationMetrics := True
end;
procedure PrintConfusion(var Matrix: TConfusion);
var I,J: Integer; M: TClassMetrics;
begin
  if not ClassificationMetrics(Matrix,M) then begin WriteLn(AIError); Exit end;
  WriteLn('Baris = aktual; kolom = prediksi');
  Write('    ');
  for J := 0 to Matrix.Classes-1 do Write(J:5); WriteLn;
  for I := 0 to Matrix.Classes-1 do begin
    Write(I:3,' ');
    for J := 0 to Matrix.Classes-1 do Write(Matrix.Cells[I,J]:5);
    WriteLn
  end
end;
end.
