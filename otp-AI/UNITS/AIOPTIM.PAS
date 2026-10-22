unit AIOptim;
interface
uses AITypes;
const StopGoal=1; StopPlateau=2; StopLimit=3;
type
  TTrainConfig = record
    MaxEpochs, Patience: Integer;
    Rate, Momentum, L2, Clip, GoalLoss, MinDelta: TFloat;
    Seed: LongInt;
  end;
  TTrainInfo = record
    Epochs, StopReason, HistoryCount: Integer;
    Converged: Boolean;
    FinalLoss: TFloat;
    History: TSeries;
    HistoryEpoch: TIndexList;
  end;
  TStopState = record Best: TFloat; Stale: Integer end;
procedure DefaultTraining(var C: TTrainConfig);
function CheckTraining(var C: TTrainConfig): Boolean;
function CheckBinaryData(var D: TDataSet): Boolean;
function SGDStep(var Value, Velocity: TFloat; Gradient, Rate,
  Momentum, Clip: TFloat): Boolean;
function VectorStep(var Values,Velocity,Gradient: TVector;
  N: Integer; Rate,Momentum,Clip: TFloat): Boolean;
function BinaryLoss(Logit: TFloat; Target: Integer): TFloat;
procedure InitTraining(var Info: TTrainInfo; var Stop: TStopState);
procedure RecordLoss(var Info: TTrainInfo; Epoch,MaxEpochs: Integer;
  Loss: TFloat; Force: Boolean);
function ShouldStop(var C: TTrainConfig; var S: TStopState;
  Loss: TFloat; var Reason: Integer): Boolean;
procedure ShuffleRows(N: Integer; var Order: TIndexList);
implementation
uses AIMath;
procedure DefaultTraining(var C: TTrainConfig);
begin
  C.MaxEpochs:=2000; C.Patience:=300; C.Rate:=0.1;
  C.Momentum:=0; C.L2:=0; C.Clip:=5; C.GoalLoss:=0.01;
  C.MinDelta:=1E-8; C.Seed:=42
end;
function CheckTraining(var C: TTrainConfig): Boolean;
begin
  ClearAIError; CheckTraining:=False;
  if (C.MaxEpochs<1) or (C.MaxEpochs>10000) or
     (C.Patience<1) or (C.Patience>10000) then begin
    SetAIError(ErrSize,'Epoch/patience harus 1..10000'); Exit
  end;
  if not ValidNumber(C.Rate) or not ValidNumber(C.Momentum) or
     not ValidNumber(C.L2) or not ValidNumber(C.Clip) or
     not ValidNumber(C.GoalLoss) or not ValidNumber(C.MinDelta) then begin
    SetAIError(ErrValue,'Konfigurasi pelatihan bukan angka valid'); Exit
  end;
  if (C.Rate<=0) or (C.Rate>10) or (C.Momentum<0) or
     (C.Momentum>=1) or (C.L2<0) or (C.L2>100) or
     (C.Clip<=0) or (C.Clip>1E6) or (C.GoalLoss<0) or
     (C.MinDelta<0) then begin
    SetAIError(ErrValue,'Parameter pelatihan di luar batas'); Exit
  end;
  CheckTraining:=True
end;
function CheckBinaryData(var D: TDataSet): Boolean;
var I,J: Integer;
begin
  CheckBinaryData:=False;
  if not CheckData(D,False) then Exit;
  if D.TargetKind<>TargetClass then begin
    SetAIError(ErrValue,'Pelatihan ini memerlukan target kelas 0/1'); Exit
  end;
  for I:=1 to D.Count do begin
    if (D.Labels[I]<>0) and (D.Labels[I]<>1) then begin
      SetAIError(ErrValue,'Label harus 0 atau 1'); Exit
    end;
    for J:=1 to D.Features do if Abs(D.X[I,J])>1E4 then begin
      SetAIError(ErrValue,'Skalakan fitur latih ke magnitudo <=1E4'); Exit
    end
  end;
  CheckBinaryData:=True
end;
function SGDStep(var Value, Velocity: TFloat; Gradient, Rate,
  Momentum, Clip: TFloat): Boolean;
var V,W: TFloat;
begin
  ClearAIError; SGDStep:=False;
  if not ValidNumber(Value) or not ValidNumber(Velocity) or
     not ValidNumber(Gradient) or not ValidNumber(Rate) or
     not ValidNumber(Momentum) or not ValidNumber(Clip) then begin
    SetAIError(ErrValue,'Argumen SGD bukan angka valid'); Exit
  end;
  if (Rate<=0) or (Rate>10) or (Momentum<0) or (Momentum>=1) or
     (Clip<=0) or (Clip>1E6) then begin
    SetAIError(ErrValue,'Rate, momentum atau clip tidak valid'); Exit
  end;
  if Gradient>Clip then Gradient:=Clip;
  if Gradient < -Clip then Gradient:=-Clip;
  V:=Momentum*Velocity+Gradient; W:=Value-Rate*V;
  if not ValidNumber(V) or not ValidNumber(W) then begin
    SetAIError(ErrValue,'Langkah SGD melampaui batas numerik'); Exit
  end;
  Velocity:=V; Value:=W; SGDStep:=True
end;
function VectorStep(var Values,Velocity,Gradient: TVector;
  N: Integer; Rate,Momentum,Clip: TFloat): Boolean;
var V,W: TVector; J: Integer;
begin
  VectorStep:=False;
  if not CheckVector(Values,N) then Exit;
  if not CheckVector(Velocity,N) then Exit;
  if not CheckVector(Gradient,N) then Exit;
  W:=Values; V:=Velocity;
  for J:=1 to N do
    if not SGDStep(W[J],V[J],Gradient[J],Rate,Momentum,Clip) then Exit;
  Values:=W; Velocity:=V; VectorStep:=True
end;
function BinaryLoss(Logit: TFloat; Target: Integer): TFloat;
var T: TFloat;
begin
  ClearAIError; BinaryLoss:=0;
  if not ValidNumber(Logit) or ((Target<>0) and (Target<>1)) then begin
    SetAIError(ErrValue,'Logit atau target loss tidak valid'); Exit
  end;
  T:=Abs(Logit);
  if T>80 then T:=0 else T:=Ln(1+Exp(-T));
  if Logit>=0 then BinaryLoss:=Logit*(1-Target)+T
  else BinaryLoss:=-Logit*Target+T
end;
procedure InitTraining(var Info: TTrainInfo; var Stop: TStopState);
begin
  FillChar(Info,SizeOf(Info),0); Stop.Best:=1E30; Stop.Stale:=0
end;
procedure RecordLoss(var Info: TTrainInfo; Epoch,MaxEpochs: Integer;
  Loss: TFloat; Force: Boolean);
var Stride,P: Integer;
begin
  Info.Epochs:=Epoch; Info.FinalLoss:=Loss;
  Stride:=(MaxEpochs+MaxSamples-1) div MaxSamples;
  if Stride<1 then Stride:=1;
  if Force or (Epoch=1) or (Epoch mod Stride=0) then begin
    P:=Info.HistoryCount;
    if P>0 then if Info.HistoryEpoch[P]=Epoch then begin
      Info.History[P]:=Loss; Exit
    end;
    if P<MaxSamples then Inc(P);
    Info.History[P]:=Loss; Info.HistoryEpoch[P]:=Epoch;
    Info.HistoryCount:=P
  end
end;
function ShouldStop(var C: TTrainConfig; var S: TStopState;
  Loss: TFloat; var Reason: Integer): Boolean;
begin
  Reason:=0; ShouldStop:=True;
  if Loss<=C.GoalLoss then begin Reason:=StopGoal; Exit end;
  if Loss < S.Best-C.MinDelta then begin S.Best:=Loss; S.Stale:=0 end
  else Inc(S.Stale);
  if S.Stale>=C.Patience then begin Reason:=StopPlateau; Exit end;
  ShouldStop:=False
end;
procedure ShuffleRows(N: Integer; var Order: TIndexList);
var I,J,T: Integer;
begin
  ClearAIError;
  if (N<1) or (N>MaxSamples) then begin
    SetAIError(ErrSize,'ShuffleRows memerlukan 1..200 baris'); Exit
  end;
  for I:=1 to N do Order[I]:=I;
  for I:=N downto 2 do begin
    J:=AIRandomInt(I)+1; T:=Order[I]; Order[I]:=Order[J]; Order[J]:=T
  end
end;
end.
