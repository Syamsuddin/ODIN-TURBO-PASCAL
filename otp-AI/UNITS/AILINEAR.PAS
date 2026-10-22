unit AILinear;
interface
uses AITypes,AIOptim;
function FitLinear(var D: TDataSet; Ridge: TFloat;
  var Model: TLinearModel): Boolean;
function PredictLinear(var Model: TLinearModel; var X: TVector;
  var Prediction: TFloat): Boolean;
function PredictLinearData(var Model: TLinearModel; var D: TDataSet;
  var Predictions: TSeries): Boolean;

type
  TLogisticModel = record
    Fitted: Boolean;
    Features: Integer;
    Weights: TVector;
    Bias: TFloat;
  end;
function CheckLogistic(var M: TLogisticModel): Boolean;
function FitLogistic(var D: TDataSet; var Config: TTrainConfig;
  var M: TLogisticModel; var Info: TTrainInfo): Boolean;
function PredictLogistic(var M: TLogisticModel; var X: TVector;
  Threshold: TFloat; var Probability: TFloat; var LabelValue: Integer): Boolean;
function LogisticData(var M: TLogisticModel; var D: TDataSet;
  Threshold: TFloat; var Probabilities: TSeries; var Labels: TLabels): Boolean;

type
  TPerceptronModel = record
    Fitted: Boolean;
    Features: Integer;
    Weights: TVector;
    Bias: TFloat;
  end;
function CheckPerceptron(var M: TPerceptronModel): Boolean;
function FitPerceptron(var D: TDataSet; MaxEpochs: Integer;
  Rate: TFloat; Seed: LongInt; var M: TPerceptronModel;
  var Info: TTrainInfo): Boolean;
function PredictPerceptron(var M: TPerceptronModel; var X: TVector;
  var LabelValue: Integer; var Score: TFloat): Boolean;
implementation
uses AIDATA,AIMath;
function FitLinear(var D: TDataSet; Ridge: TFloat;
  var Model: TLinearModel): Boolean;
var A: array[1..MaxFeatures,1..MaxFeatures+1] of TFloat;
    Coeff,Z: TVector; S: TScaler;
    I,J,K,P,Best,N: Integer;
    AvgY,Pivot,Factor,T,BestAbs: TFloat;
begin
  FillChar(Model,SizeOf(Model),0); FitLinear := False;
  if not CheckData(D,False) then Exit;
  if D.TargetKind <> TargetReal then begin
    SetAIError(ErrValue,'Regresi memerlukan target numerik'); Exit
  end;
  if not ValidNumber(Ridge) or (Ridge < 0) then begin
    SetAIError(ErrValue,'Ridge harus >= 0'); Exit
  end;
  N := D.Features;
  if (Ridge = 0) and (D.Count <= N) then begin
    SetAIError(ErrSize,'OLS perlu jumlah baris lebih besar dari fitur'); Exit
  end;
  if not FitScaler(D,ScaleStandard,S) then Exit;
  AvgY := 0;
  for I := 1 to D.Count do AvgY := AvgY+(D.Y[I]-AvgY)/I;
  FillChar(A,SizeOf(A),0); FillChar(Coeff,SizeOf(Coeff),0);
  for I := 1 to D.Count do begin
    Z := D.X[I];
    if not TransformVector(S,Z) then Exit;
    for J := 1 to N do begin
      for K := 1 to N do A[J,K] := A[J,K]+Z[J]*Z[K];
      A[J,N+1] := A[J,N+1]+Z[J]*(D.Y[I]-AvgY)
    end
  end;
  { Penalti hanya pada koefisien fitur yang distandardisasi. }
  for J := 1 to N do A[J,J] := A[J,J]+Ridge;
  { Eliminasi Gauss dengan pivot parsial atas normal equations. }
  for P := 1 to N do begin
    Best := P; BestAbs := Abs(A[P,P]);
    for I := P+1 to N do if Abs(A[I,P]) > BestAbs then begin
      Best := I; BestAbs := Abs(A[I,P])
    end;
    if BestAbs < AIEpsilon then begin
      SetAIError(ErrSingular,'Fitur konstan/kolinear. Hapus fitur atau pakai ridge');
      Exit
    end;
    if Best <> P then for K := P to N+1 do begin
      T := A[P,K]; A[P,K] := A[Best,K]; A[Best,K] := T
    end;
    Pivot := A[P,P];
    for I := P+1 to N do begin
      Factor := A[I,P]/Pivot;
      for K := P to N+1 do A[I,K] := A[I,K]-Factor*A[P,K]
    end
  end;
  for I := N downto 1 do begin
    T := A[I,N+1];
    for J := I+1 to N do T := T-A[I,J]*Coeff[J];
    Coeff[I] := T/A[I,I]
  end;
  Model.Intercept := AvgY;
  for J := 1 to N do begin
    Model.Coeff[J] := Coeff[J]/S.Divisor[J];
    if not ValidNumber(Model.Coeff[J]) then begin
      SetAIError(ErrValue,'Koefisien regresi melampaui batas'); Exit
    end;
    Model.Intercept := Model.Intercept-Model.Coeff[J]*S.Offset[J]
  end;
  if not ValidNumber(Model.Intercept) then begin
    SetAIError(ErrValue,'Intercept regresi melampaui batas'); Exit
  end;
  Model.Features := N; Model.Fitted := True; FitLinear := True
end;
function PredictLinear(var Model: TLinearModel; var X: TVector;
  var Prediction: TFloat): Boolean;
var J: Integer;
begin
  ClearAIError; Prediction := 0; PredictLinear := False;
  if not Model.Fitted or (Model.Features < 1) or
     (Model.Features > MaxFeatures) then begin
    SetAIError(ErrModel,'Model regresi belum dilatih'); Exit
  end;
  if not CheckVector(X,Model.Features) then Exit;
  if not CheckVector(Model.Coeff,Model.Features) then Exit;
  if not ValidNumber(Model.Intercept) then begin
    SetAIError(ErrModel,'Intercept tidak valid'); Exit
  end;
  Prediction := Model.Intercept;
  for J := 1 to Model.Features do
    Prediction := Prediction+Model.Coeff[J]*X[J];
  if not ValidNumber(Prediction) then begin
    Prediction := 0; SetAIError(ErrValue,'Prediksi melampaui batas angka'); Exit
  end;
  PredictLinear := True
end;
function PredictLinearData(var Model: TLinearModel; var D: TDataSet;
  var Predictions: TSeries): Boolean;
var I: Integer;
begin
  FillChar(Predictions,SizeOf(Predictions),0); PredictLinearData := False;
  if not CheckData(D,False) then Exit;
  if D.Features <> Model.Features then begin
    SetAIError(ErrSize,'Jumlah fitur prediksi berbeda'); Exit
  end;
  for I := 1 to D.Count do
    if not PredictLinear(Model,D.X[I],Predictions[I]) then Exit;
  PredictLinearData := True
end;

function CheckLogistic(var M: TLogisticModel): Boolean;
begin
  ClearAIError; CheckLogistic:=False;
  if not M.Fitted then begin SetAIError(ErrModel,'Logistic belum dilatih'); Exit end;
  if not CheckVector(M.Weights,M.Features) then Exit;
  if not ValidNumber(M.Bias) then begin SetAIError(ErrModel,'Bias tidak valid'); Exit end;
  CheckLogistic:=True
end;
function Logit(var M: TLogisticModel; var X: TVector): TFloat;
var J: Integer; Z: TFloat;
begin
  Z:=M.Bias;
  for J:=1 to M.Features do Z:=Z+M.Weights[J]*X[J];
  Logit:=Z
end;
function FitLogistic(var D: TDataSet; var Config: TTrainConfig;
  var M: TLogisticModel; var Info: TTrainInfo): Boolean;
var G,V: TVector; GB,VB,Z,E,Loss: TFloat;
    I,J,Epoch,Reason: Integer; Stop: TStopState; Done: Boolean;
begin
  FillChar(M,SizeOf(M),0); InitTraining(Info,Stop); FitLogistic:=False;
  if not CheckBinaryData(D) then Exit;
  if not CheckTraining(Config) then Exit;
  M.Features:=D.Features; FillChar(V,SizeOf(V),0); VB:=0;
  Epoch:=0;
  repeat
    Inc(Epoch); FillChar(G,SizeOf(G),0); GB:=0;
    for I:=1 to D.Count do begin
      Z:=Logit(M,D.X[I]);
      if not ValidNumber(Z) then begin SetAIError(ErrValue,'Logit melampaui batas'); Exit end;
      E:=Sigmoid(Z)-D.Labels[I]; GB:=GB+E/D.Count;
      for J:=1 to D.Features do G[J]:=G[J]+E*D.X[I,J]/D.Count
    end;
    for J:=1 to D.Features do G[J]:=G[J]+Config.L2*M.Weights[J];
    if not VectorStep(M.Weights,V,G,D.Features,Config.Rate,Config.Momentum,Config.Clip) then Exit;
    if not SGDStep(M.Bias,VB,GB,Config.Rate,Config.Momentum,Config.Clip) then Exit;
    Loss:=0;
    for I:=1 to D.Count do begin
      Z:=Logit(M,D.X[I]); E:=BinaryLoss(Z,D.Labels[I]);
      if AIErrorCode<>0 then Exit;
      Loss:=Loss+E/D.Count
    end;
    for J:=1 to D.Features do Loss:=Loss+0.5*Config.L2*Sqr(M.Weights[J]);
    if not ValidNumber(Loss) then begin SetAIError(ErrValue,'Loss melampaui batas'); Exit end;
    Done:=ShouldStop(Config,Stop,Loss,Reason);
    RecordLoss(Info,Epoch,Config.MaxEpochs,Loss,Done or (Epoch=Config.MaxEpochs))
  until Done or (Epoch>=Config.MaxEpochs);
  if Reason=0 then Reason:=StopLimit;
  Info.StopReason:=Reason; Info.Converged:=Reason=StopGoal;
  M.Fitted:=True; FitLogistic:=True
end;
function PredictLogistic(var M: TLogisticModel; var X: TVector;
  Threshold: TFloat; var Probability: TFloat; var LabelValue: Integer): Boolean;
var Z: TFloat;
begin
  Probability:=0; LabelValue:=-1; PredictLogistic:=False;
  if not CheckLogistic(M) then Exit;
  if not CheckVector(X,M.Features) then Exit;
  if not ValidNumber(Threshold) or (Threshold<=0) or (Threshold>=1) then begin
    SetAIError(ErrValue,'Threshold harus antara 0 dan 1'); Exit
  end;
  Z:=Logit(M,X);
  if not ValidNumber(Z) then begin SetAIError(ErrValue,'Logit melampaui batas'); Exit end;
  Probability:=Sigmoid(Z); LabelValue:=Ord(Probability>=Threshold);
  PredictLogistic:=True
end;
function LogisticData(var M: TLogisticModel; var D: TDataSet;
  Threshold: TFloat; var Probabilities: TSeries; var Labels: TLabels): Boolean;
var I: Integer;
begin
  LogisticData:=False;
  if not CheckData(D,False) then Exit;
  if D.Features<>M.Features then begin SetAIError(ErrSize,'Fitur berbeda'); Exit end;
  for I:=1 to D.Count do
    if not PredictLogistic(M,D.X[I],Threshold,Probabilities[I],Labels[I]) then Exit;
  LogisticData:=True
end;

function CheckPerceptron(var M: TPerceptronModel): Boolean;
begin
  ClearAIError; CheckPerceptron:=False;
  if not M.Fitted then begin SetAIError(ErrModel,'Perceptron belum dilatih'); Exit end;
  if not CheckVector(M.Weights,M.Features) then Exit;
  if not ValidNumber(M.Bias) then begin SetAIError(ErrModel,'Bias tidak valid'); Exit end;
  CheckPerceptron:=True
end;
function ScoreOf(var M: TPerceptronModel; var X: TVector): TFloat;
var Z: TFloat; J: Integer;
begin
  Z:=M.Bias;
  for J:=1 to M.Features do Z:=Z+M.Weights[J]*X[J];
  ScoreOf:=Z
end;
function FitPerceptron(var D: TDataSet; MaxEpochs: Integer;
  Rate: TFloat; Seed: LongInt; var M: TPerceptronModel;
  var Info: TTrainInfo): Boolean;
var Order: TIndexList; I,J,R,Epoch,E,Mistakes: Integer;
    Z,Loss: TFloat; Stop: TStopState;
begin
  FillChar(M,SizeOf(M),0); InitTraining(Info,Stop); FitPerceptron:=False;
  if not CheckBinaryData(D) then Exit;
  if (MaxEpochs<1) or (MaxEpochs>10000) or not ValidNumber(Rate) or
     (Rate<=0) or (Rate>10) then begin
    SetAIError(ErrValue,'Epoch 1..10000 dan rate 0<rate<=10 diperlukan'); Exit
  end;
  M.Features:=D.Features; AISetSeed(Seed); Epoch:=0;
  repeat
    Inc(Epoch); ShuffleRows(D.Count,Order);
    for I:=1 to D.Count do begin
      R:=Order[I]; Z:=ScoreOf(M,D.X[R]);
      if not ValidNumber(Z) then begin SetAIError(ErrValue,'Score melampaui batas'); Exit end;
      E:=D.Labels[R]-Ord(Z>=0);
      for J:=1 to D.Features do M.Weights[J]:=M.Weights[J]+Rate*E*D.X[R,J];
      M.Bias:=M.Bias+Rate*E
    end;
    Mistakes:=0;
    for I:=1 to D.Count do if Ord(ScoreOf(M,D.X[I])>=0)<>D.Labels[I] then Inc(Mistakes);
    Loss:=Mistakes/D.Count;
    RecordLoss(Info,Epoch,MaxEpochs,Loss,(Mistakes=0) or (Epoch=MaxEpochs))
  until (Mistakes=0) or (Epoch>=MaxEpochs);
  Info.Converged:=Mistakes=0;
  if Info.Converged then Info.StopReason:=StopGoal else Info.StopReason:=StopLimit;
  M.Fitted:=True; FitPerceptron:=True
end;
function PredictPerceptron(var M: TPerceptronModel; var X: TVector;
  var LabelValue: Integer; var Score: TFloat): Boolean;
begin
  LabelValue:=-1; Score:=0; PredictPerceptron:=False;
  if not CheckPerceptron(M) then Exit;
  if not CheckVector(X,M.Features) then Exit;
  Score:=ScoreOf(M,X);
  if not ValidNumber(Score) then begin SetAIError(ErrValue,'Score melampaui batas'); Exit end;
  LabelValue:=Ord(Score>=0); PredictPerceptron:=True
end;
end.
