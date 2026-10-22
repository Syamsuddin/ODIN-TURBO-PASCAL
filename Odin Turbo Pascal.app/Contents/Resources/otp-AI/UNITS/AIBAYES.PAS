unit AIBayes;
interface
uses AITypes;
const BayesGaussian=1; BayesMultinomial=2;
type
  TClassProb = array[0..MaxClasses-1] of TFloat;
  TBayesModel = record
    Fitted: Boolean;
    Kind,Features,Classes,Total: Integer;
    Counts: array[0..MaxClasses-1] of Integer;
    LogPrior: TClassProb;
    Means,Variances,LogFeature: array[0..MaxClasses-1] of TVector;
  end;
function CheckBayes(var M: TBayesModel): Boolean;
function FitGaussian(var D: TDataSet; VarianceFloor: TFloat;
  var M: TBayesModel): Boolean;
function FitMultinomial(var D: TDataSet; Alpha: TFloat;
  var M: TBayesModel): Boolean;
function PredictBayes(var M: TBayesModel; var X: TVector;
  var LabelValue: Integer; var Probabilities: TClassProb): Boolean;
implementation
function CheckBayes(var M: TBayesModel): Boolean;
var C,J,Total: Integer;
begin
  ClearAIError; CheckBayes:=False;
  if not M.Fitted or (M.Features<1) or (M.Features>MaxFeatures) or
     (M.Classes<1) or (M.Classes>MaxClasses) or
     (M.Total<1) or (M.Total>MaxSamples) or
     ((M.Kind<>BayesGaussian) and (M.Kind<>BayesMultinomial)) then begin
    SetAIError(ErrModel,'Model Bayes tidak valid'); Exit
  end;
  Total:=0;
  for C:=0 to M.Classes-1 do begin
    if (M.Counts[C]<0) or (M.Counts[C]>MaxSamples) then begin
      SetAIError(ErrModel,'Jumlah kelas Bayes tidak valid'); Exit
    end;
    Inc(Total,M.Counts[C]);
    if M.Counts[C]>0 then begin
      if not ValidNumber(M.LogPrior[C]) or (M.LogPrior[C]>0) then begin
        SetAIError(ErrModel,'Prior Bayes tidak valid'); Exit
      end;
      for J:=1 to M.Features do
        if M.Kind=BayesGaussian then begin
          if not ValidNumber(M.Means[C,J]) or
             not ValidNumber(M.Variances[C,J]) or (M.Variances[C,J]<1E-8) then begin
            SetAIError(ErrModel,'Mean/varians Bayes tidak valid'); Exit
          end
        end else if not ValidNumber(M.LogFeature[C,J]) or
                    (M.LogFeature[C,J]>0) then begin
          SetAIError(ErrModel,'Peluang fitur Bayes tidak valid'); Exit
        end
    end
  end;
  if Total<>M.Total then begin SetAIError(ErrModel,'Total Bayes tidak cocok'); Exit end;
  CheckBayes:=True
end;
function StartFit(var D: TDataSet; Kind: Integer; var M: TBayesModel): Boolean;
var I,J,C: Integer;
begin
  FillChar(M,SizeOf(M),0); StartFit:=False;
  if not CheckData(D,False) then Exit;
  if D.TargetKind<>TargetClass then begin SetAIError(ErrValue,'Bayes memerlukan label kelas'); Exit end;
  M.Kind:=Kind; M.Features:=D.Features; M.Total:=D.Count;
  for I:=1 to D.Count do begin
    C:=D.Labels[I]; Inc(M.Counts[C]);
    if C+1>M.Classes then M.Classes:=C+1;
    for J:=1 to D.Features do if Abs(D.X[I,J])>1E6 then begin
      SetAIError(ErrValue,'Skalakan fitur Bayes ke magnitudo <=1E6'); Exit
    end
  end;
  for C:=0 to M.Classes-1 do if M.Counts[C]>0 then
    M.LogPrior[C]:=Ln(M.Counts[C]/M.Total);
  StartFit:=True
end;
function FitGaussian(var D: TDataSet; VarianceFloor: TFloat;
  var M: TBayesModel): Boolean;
var Seen: array[0..MaxClasses-1] of Integer;
    I,J,C: Integer; Delta: TFloat;
begin
  FitGaussian:=False;
  if not StartFit(D,BayesGaussian,M) then Exit;
  if not ValidNumber(VarianceFloor) or (VarianceFloor<1E-8) or
     (VarianceFloor>1E6) then begin
    SetAIError(ErrValue,'Variance floor harus 1E-8..1E6'); Exit
  end;
  FillChar(Seen,SizeOf(Seen),0);
  for I:=1 to D.Count do begin
    C:=D.Labels[I]; Inc(Seen[C]);
    for J:=1 to D.Features do begin
      Delta:=D.X[I,J]-M.Means[C,J];
      M.Means[C,J]:=M.Means[C,J]+Delta/Seen[C];
      M.Variances[C,J]:=M.Variances[C,J]+Delta*(D.X[I,J]-M.Means[C,J])
    end
  end;
  for C:=0 to M.Classes-1 do if M.Counts[C]>0 then
    for J:=1 to M.Features do begin
      M.Variances[C,J]:=M.Variances[C,J]/M.Counts[C];
      if M.Variances[C,J]<VarianceFloor then M.Variances[C,J]:=VarianceFloor
    end;
  M.Fitted:=True;
  if not CheckBayes(M) then begin M.Fitted:=False; Exit end;
  FitGaussian:=True
end;
function FitMultinomial(var D: TDataSet; Alpha: TFloat;
  var M: TBayesModel): Boolean;
var I,J,C: Integer; Total: TFloat;
begin
  FitMultinomial:=False;
  if not StartFit(D,BayesMultinomial,M) then Exit;
  if not ValidNumber(Alpha) or (Alpha<1E-8) or (Alpha>1E6) then begin
    SetAIError(ErrValue,'Alpha harus 1E-8..1E6'); Exit
  end;
  for I:=1 to D.Count do begin
    C:=D.Labels[I];
    for J:=1 to D.Features do begin
      if D.X[I,J]<0 then begin SetAIError(ErrValue,'Multinomial memerlukan fitur nonnegatif'); Exit end;
      M.LogFeature[C,J]:=M.LogFeature[C,J]+D.X[I,J]
    end
  end;
  for C:=0 to M.Classes-1 do if M.Counts[C]>0 then begin
    Total:=Alpha*M.Features;
    for J:=1 to M.Features do Total:=Total+M.LogFeature[C,J];
    for J:=1 to M.Features do M.LogFeature[C,J]:=Ln((M.LogFeature[C,J]+Alpha)/Total)
  end;
  M.Fitted:=True; FitMultinomial:=True
end;
function PredictBayes(var M: TBayesModel; var X: TVector;
  var LabelValue: Integer; var Probabilities: TClassProb): Boolean;
var Scores: TClassProb; C,J: Integer; S,Z,Best,Sum: TFloat;
begin
  LabelValue:=-1; FillChar(Probabilities,SizeOf(Probabilities),0); PredictBayes:=False;
  if not CheckBayes(M) then Exit;
  if not CheckVector(X,M.Features) then Exit;
  if M.Kind=BayesMultinomial then
    for J:=1 to M.Features do if X[J]<0 then begin
      SetAIError(ErrValue,'Multinomial memerlukan fitur nonnegatif'); Exit
    end;
  Best:=-1E35;
  for C:=0 to M.Classes-1 do if M.Counts[C]>0 then begin
    S:=M.LogPrior[C];
    for J:=1 to M.Features do
      if M.Kind=BayesGaussian then begin
        Z:=(X[J]-M.Means[C,J])/Sqrt(M.Variances[C,J]);
        if Abs(Z)>1E15 then begin SetAIError(ErrValue,'Jarak Gaussian terlalu besar'); Exit end;
        S:=S-0.5*(Ln(6.283185307179586)+Ln(M.Variances[C,J])+Z*Z)
      end else S:=S+X[J]*M.LogFeature[C,J];
    Scores[C]:=S;
    if S>Best then begin Best:=S; LabelValue:=C end
  end;
  Sum:=0;
  for C:=0 to M.Classes-1 do if M.Counts[C]>0 then begin
    Z:=Scores[C]-Best;
    if Z < -80 then Probabilities[C]:=0 else Probabilities[C]:=Exp(Z);
    Sum:=Sum+Probabilities[C]
  end;
  for C:=0 to M.Classes-1 do Probabilities[C]:=Probabilities[C]/Sum;
  PredictBayes:=True
end;
end.
