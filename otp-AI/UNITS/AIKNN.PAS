unit AIKNN;
interface
uses AITypes;
function FitKNN(var D: TDataSet; K: Integer;
  var Model: TKNNModel): Boolean;
function PredictKNN(var Model: TKNNModel; var X: TVector;
  var ClassLabel: Integer; var Prediction: TFloat): Boolean;
function PredictKNNData(var Model: TKNNModel; var D: TDataSet;
  var ClassLabels: TLabels; var Predictions: TSeries): Boolean;
implementation
uses AIMath;
function FitKNN(var D: TDataSet; K: Integer;
  var Model: TKNNModel): Boolean;
begin
  FillChar(Model,SizeOf(Model),0); FitKNN := False;
  if not CheckData(D,False) then Exit;
  if (D.TargetKind <> TargetReal) and (D.TargetKind <> TargetClass) then begin
    SetAIError(ErrValue,'KNN memerlukan target regresi atau kelas'); Exit
  end;
  if (K < 1) or (K > D.Count) then begin
    SetAIError(ErrSize,'K harus 1 sampai jumlah baris latih'); Exit
  end;
  Model.Data := @D; Model.K := K; Model.TargetKind := D.TargetKind;
  Model.Features := D.Features; Model.Count := D.Count;
  Model.Fitted := True; FitKNN := True
end;
function PredictKNN(var Model: TKNNModel; var X: TVector;
  var ClassLabel: Integer; var Prediction: TFloat): Boolean;
var Dist: TSeries; Order: TIndexList;
    Votes: array[0..MaxClasses-1] of Integer;
    I,J,Index,Best: Integer; V: TFloat;
begin
  ClearAIError; ClassLabel := -1; Prediction := 0; PredictKNN := False;
  if not Model.Fitted or (Model.Data = nil) then begin
    SetAIError(ErrModel,'Model KNN belum dilatih'); Exit
  end;
  { Data tidak boleh dibebaskan/diubah selama model dipakai. }
  if not CheckData(Model.Data^,False) then Exit;
  if (Model.K < 1) or (Model.K > Model.Data^.Count) or
     (Model.Count <> Model.Data^.Count) or
     (Model.Features <> Model.Data^.Features) or
     (Model.TargetKind <> Model.Data^.TargetKind) then begin
    SetAIError(ErrModel,'Dataset latih KNN berubah atau model tidak valid'); Exit
  end;
  if (Model.TargetKind <> TargetReal) and
     (Model.TargetKind <> TargetClass) then begin
    SetAIError(ErrModel,'Jenis target model KNN tidak valid'); Exit
  end;
  if not CheckVector(X,Model.Features) then Exit;
  for I := 1 to Model.Count do begin
    Order[I] := I;
    if not DistanceSquared(X,Model.Data^.X[I],Model.Features,Dist[I]) then Exit
  end;
  { Insertion sort stabil: jarak sama memakai urutan baris latih. }
  for I := 2 to Model.Count do begin
    Index := Order[I]; V := Dist[Index]; J := I-1;
    while J >= 1 do begin
      if Dist[Order[J]] <= V then Break;
      Order[J+1] := Order[J]; Dec(J)
    end;
    Order[J+1] := Index
  end;
  if Model.TargetKind = TargetReal then begin
    for I := 1 to Model.K do
      Prediction := Prediction+(Model.Data^.Y[Order[I]]-Prediction)/I
  end else begin
    FillChar(Votes,SizeOf(Votes),0);
    for I := 1 to Model.K do Inc(Votes[Model.Data^.Labels[Order[I]]]);
    Best := 0;
    for I := 1 to MaxClasses-1 do if Votes[I] > Votes[Best] then Best := I;
    { Suara sama: label numerik terkecil menang. }
    ClassLabel := Best; Prediction := Best
  end;
  PredictKNN := True
end;
function PredictKNNData(var Model: TKNNModel; var D: TDataSet;
  var ClassLabels: TLabels; var Predictions: TSeries): Boolean;
var I: Integer;
begin
  PredictKNNData := False;
  FillChar(ClassLabels,SizeOf(ClassLabels),0);
  FillChar(Predictions,SizeOf(Predictions),0);
  if not CheckData(D,False) then Exit;
  if D.Features <> Model.Features then begin
    SetAIError(ErrSize,'Jumlah fitur KNN berbeda'); Exit
  end;
  for I := 1 to D.Count do
    if not PredictKNN(Model,D.X[I],ClassLabels[I],Predictions[I]) then Exit;
  PredictKNNData := True
end;
end.
