unit AINNet;
interface
uses AITypes,AIOptim;
const MaxHidden=8;
type
  TNeuralModel = record
    Fitted: Boolean;
    Features,Hidden: Integer;
    InputW: array[1..MaxHidden] of TVector;
    HiddenBias,OutputW: TVector;
    OutputBias: TFloat;
  end;
function CheckNeural(var M: TNeuralModel): Boolean;
function FitNeural(var D: TDataSet; Hidden: Integer;
  var Config: TTrainConfig; var M: TNeuralModel; var Info: TTrainInfo): Boolean;
function PredictNeural(var M: TNeuralModel; var X: TVector;
  var Probability: TFloat; var LabelValue: Integer): Boolean;
implementation
uses AIMath;
function CheckNeural(var M: TNeuralModel): Boolean;
var H: Integer;
begin
  ClearAIError; CheckNeural:=False;
  if not M.Fitted or (M.Features<1) or (M.Features>MaxFeatures) or
     (M.Hidden<1) or (M.Hidden>MaxHidden) then begin
    SetAIError(ErrModel,'Jaringan belum dilatih atau dimensi tidak valid'); Exit
  end;
  for H:=1 to M.Hidden do if not CheckVector(M.InputW[H],M.Features) then Exit;
  if not CheckVector(M.HiddenBias,M.Hidden) then Exit;
  if not CheckVector(M.OutputW,M.Hidden) then Exit;
  if not ValidNumber(M.OutputBias) then begin SetAIError(ErrModel,'Bias output tidak valid'); Exit end;
  CheckNeural:=True
end;
function Forward(var M: TNeuralModel; var X,A: TVector;
  var Z,P: TFloat): Boolean;
var H,J: Integer; S: TFloat;
begin
  Forward:=False;
  for H:=1 to M.Hidden do begin
    S:=M.HiddenBias[H];
    for J:=1 to M.Features do S:=S+M.InputW[H,J]*X[J];
    if not ValidNumber(S) then begin SetAIError(ErrValue,'Aktivasi hidden melampaui batas'); Exit end;
    A[H]:=Sigmoid(S)
  end;
  Z:=M.OutputBias;
  for H:=1 to M.Hidden do Z:=Z+M.OutputW[H]*A[H];
  if not ValidNumber(Z) then begin SetAIError(ErrValue,'Aktivasi output melampaui batas'); Exit end;
  P:=Sigmoid(Z); Forward:=True
end;
function FitNeural(var D: TDataSet; Hidden: Integer;
  var Config: TTrainConfig; var M: TNeuralModel; var Info: TTrainInfo): Boolean;
var V: TNeuralModel; A,Delta: TVector; Order: TIndexList;
    I,J,H,R,Epoch,Reason: Integer;
    Z,P,E,G,Loss,Range: TFloat; Stop: TStopState; Done: Boolean;
begin
  FillChar(M,SizeOf(M),0); FillChar(V,SizeOf(V),0);
  InitTraining(Info,Stop); FitNeural:=False;
  if not CheckBinaryData(D) then Exit;
  if not CheckTraining(Config) then Exit;
  if (Hidden<1) or (Hidden>MaxHidden) then begin
    SetAIError(ErrSize,'Hidden harus 1..8'); Exit
  end;
  M.Features:=D.Features; M.Hidden:=Hidden; AISetSeed(Config.Seed);
  Range:=6; Range:=Sqrt(Range/(D.Features+Hidden));
  for H:=1 to Hidden do for J:=1 to D.Features do
    M.InputW[H,J]:=(2*AIRandom-1)*Range;
  Range:=6; Range:=Sqrt(Range/(Hidden+1));
  for H:=1 to Hidden do M.OutputW[H]:=(2*AIRandom-1)*Range;
  Epoch:=0;
  repeat
    Inc(Epoch); ShuffleRows(D.Count,Order);
    for I:=1 to D.Count do begin
      R:=Order[I];
      if not Forward(M,D.X[R],A,Z,P) then Exit;
      E:=P-D.Labels[R];
      { Hitung delta dengan bobot output LAMA sebelum pembaruan apa pun. }
      for H:=1 to Hidden do Delta[H]:=E*M.OutputW[H]*A[H]*(1-A[H]);
      for H:=1 to Hidden do begin
        G:=E*A[H]+Config.L2*M.OutputW[H];
        if not SGDStep(M.OutputW[H],V.OutputW[H],G,Config.Rate,Config.Momentum,Config.Clip) then Exit;
        for J:=1 to D.Features do begin
          G:=Delta[H]*D.X[R,J]+Config.L2*M.InputW[H,J];
          if not SGDStep(M.InputW[H,J],V.InputW[H,J],G,Config.Rate,Config.Momentum,Config.Clip) then Exit
        end;
        if not SGDStep(M.HiddenBias[H],V.HiddenBias[H],Delta[H],Config.Rate,Config.Momentum,Config.Clip) then Exit
      end;
      if not SGDStep(M.OutputBias,V.OutputBias,E,Config.Rate,Config.Momentum,Config.Clip) then Exit
    end;
    Loss:=0;
    for I:=1 to D.Count do begin
      if not Forward(M,D.X[I],A,Z,P) then Exit;
      E:=BinaryLoss(Z,D.Labels[I]); if AIErrorCode<>0 then Exit;
      Loss:=Loss+E/D.Count
    end;
    for H:=1 to Hidden do begin
      Loss:=Loss+0.5*Config.L2*Sqr(M.OutputW[H]);
      for J:=1 to D.Features do Loss:=Loss+0.5*Config.L2*Sqr(M.InputW[H,J])
    end;
    if not ValidNumber(Loss) then begin SetAIError(ErrValue,'Loss jaringan melampaui batas'); Exit end;
    Done:=ShouldStop(Config,Stop,Loss,Reason);
    RecordLoss(Info,Epoch,Config.MaxEpochs,Loss,Done or (Epoch=Config.MaxEpochs))
  until Done or (Epoch>=Config.MaxEpochs);
  if Reason=0 then Reason:=StopLimit;
  Info.StopReason:=Reason; Info.Converged:=Reason=StopGoal;
  M.Fitted:=True; FitNeural:=True
end;
function PredictNeural(var M: TNeuralModel; var X: TVector;
  var Probability: TFloat; var LabelValue: Integer): Boolean;
var A: TVector; Z: TFloat;
begin
  PredictNeural:=False; Probability:=0; LabelValue:=-1;
  if not CheckNeural(M) then Exit;
  if not CheckVector(X,M.Features) then Exit;
  if not Forward(M,X,A,Z,Probability) then Exit;
  LabelValue:=Ord(Probability>=0.5); PredictNeural:=True
end;
end.
