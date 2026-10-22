program Oracle;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}
uses AITypes,AIData,AILINEAR,AIKNN,AIKMeans;
var D: PDataSet; R: TLinearModel; K: TKNNModel; M: TKMeansModel;
    I,J,C,H,E: Integer; P,Ridge: TFloat; V: TVector;
    Labels: TLabels; History: TSeries; FileName: TFileName;
procedure Need(OK: Boolean);
begin if not OK then begin WriteLn('ERROR ',AIError); Halt(1) end end;
begin
  Ridge := 0;
  if ParamCount > 0 then begin
    Val(ParamStr(1),Ridge,E); if E<>0 then Halt(2)
  end;
  {$IFDEF FPC} FileName := 'DATA/ORACLE.CSV';
  {$ELSE} FileName := 'DATA\ORACLE.CSV'; {$ENDIF}
  Need(NewData(D)); Need(LoadCSV(FileName,True,TargetReal,D^));
  Need(FitLinear(D^,Ridge,R));
  WriteLn('COEF 0 ',R.Intercept:0:12);
  for J := 1 to D^.Features do WriteLn('COEF ',J,' ',R.Coeff[J]:0:12);
  Need(FitKNN(D^,5,K));
  for I := 1 to 5 do begin
    V := D^.X[I];
    for J := 1 to D^.Features do V[J] := V[J]+0.11;
    Need(PredictLinear(R,V,P)); WriteLn('PRED ',I,' ',P:0:12);
    Need(PredictKNN(K,V,C,P)); WriteLn('KNN ',I,' ',P:0:12)
  end;
  Need(FitKMeans(D^,3,200,0.0000001,42,M,Labels,History,H));
  for C := 1 to M.K do for J := 1 to M.Features do
    WriteLn('CENTER ',C,' ',J,' ',M.Centers[C,J]:0:12);
  for I := 1 to D^.Count do WriteLn('LABEL ',I,' ',Labels[I]);
  WriteLn('INERTIA ',M.Inertia:0:12);
  for I := 1 to H do WriteLn('HISTORY ',I,' ',History[I]:0:12);
  K.Fitted := False; K.Data := nil; FreeData(D)
end.
