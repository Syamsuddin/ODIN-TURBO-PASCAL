unit AIKMeans;
interface
uses AITypes;
function FitKMeans(var D: TDataSet; K, MaxIter: Integer;
  Tolerance: TFloat; Seed: LongInt; var Model: TKMeansModel;
  var Labels: TLabels; var History: TSeries; var HistoryCount: Integer): Boolean;
function PredictCluster(var Model: TKMeansModel; var X: TVector;
  var Cluster: Integer; var Distance2: TFloat): Boolean;
function PredictClusters(var Model: TKMeansModel; var D: TDataSet;
  var Labels: TLabels; var Inertia: TFloat): Boolean;
implementation
uses AIMath;
function Nearest(var Model: TKMeansModel; var X: TVector;
  var Cluster: Integer; var Dist: TFloat): Boolean;
var C: Integer; T: TFloat;
begin
  Nearest := False; Cluster := 1; Dist := 1.0E30;
  for C := 1 to Model.K do begin
    if not DistanceSquared(X,Model.Centers[C],Model.Features,T) then Exit;
    if T < Dist then begin Dist := T; Cluster := C end
  end;
  Nearest := True
end;
function FitKMeans(var D: TDataSet; K, MaxIter: Integer;
  Tolerance: TFloat; Seed: LongInt; var Model: TKMeansModel;
  var Labels: TLabels; var History: TSeries; var HistoryCount: Integer): Boolean;
var Sums: array[1..MaxClusters] of TVector;
    Counts: array[1..MaxClusters] of Integer;
    Distances: TSeries;
    I,J,C,R,OldC,Cluster,Iter,Best: Integer;
    T,Dist,BestDist,Shift,MaxShift,Inertia: TFloat;
begin
  FillChar(Model,SizeOf(Model),0); FillChar(Labels,SizeOf(Labels),0);
  FillChar(History,SizeOf(History),0); HistoryCount := 0;
  FitKMeans := False;
  if not CheckData(D,False) then Exit;
  if (K < 1) or (K > MaxClusters) or (K > D.Count) or
     (MaxIter < 1) or (MaxIter > MaxSamples) then begin
    SetAIError(ErrSize,'K harus 1..8; iterasi harus 1..200'); Exit
  end;
  if not ValidNumber(Tolerance) or (Tolerance < 0) then begin
    SetAIError(ErrValue,'Toleransi harus >= 0'); Exit
  end;
  Model.Features := D.Features; Model.K := 1;
  AISetSeed(Seed); R := AIRandomInt(D.Count)+1;
  Model.Centers[1] := D.X[R];
  { Farthest-first: pusat pertama acak, berikutnya titik terjauh. }
  for C := 2 to K do begin
    Best := 0; BestDist := -1;
    for I := 1 to D.Count do begin
      if not Nearest(Model,D.X[I],Cluster,Dist) then Exit;
      if Dist > BestDist then begin Best := I; BestDist := Dist end
    end;
    if BestDist <= 0 then begin
      SetAIError(ErrValue,'K melebihi jumlah titik fitur yang unik'); Exit
    end;
    Model.Centers[C] := D.X[Best]; Model.K := C
  end;
  Iter := 0;
  repeat
    Inc(Iter); FillChar(Sums,SizeOf(Sums),0); FillChar(Counts,SizeOf(Counts),0);
    for I := 1 to D.Count do begin
      if not Nearest(Model,D.X[I],C,Dist) then Exit;
      Labels[I] := C; Distances[I] := Dist; Inc(Counts[C]);
      for J := 1 to D.Features do Sums[C,J] := Sums[C,J]+D.X[I,J]
    end;
    { Perbaiki cluster kosong dengan memindah titik terjauh dari donor. }
    for C := 1 to K do if Counts[C] = 0 then begin
      Best := 0; BestDist := -1;
      for I := 1 to D.Count do if Counts[Labels[I]] > 1 then
        if Distances[I] > BestDist then begin
          Best := I; BestDist := Distances[I]
        end;
      if Best = 0 then begin
        SetAIError(ErrModel,'Tidak ada donor untuk cluster kosong'); Exit
      end;
      OldC := Labels[Best]; Dec(Counts[OldC]); Counts[C] := 1;
      for J := 1 to D.Features do begin
        Sums[OldC,J] := Sums[OldC,J]-D.X[Best,J];
        Sums[C,J] := D.X[Best,J]
      end;
      Labels[Best] := C; Distances[Best] := 0
    end;
    MaxShift := 0;
    for C := 1 to K do begin
      Shift := 0;
      for J := 1 to D.Features do begin
        T := Sums[C,J]/Counts[C];
        Shift := Shift+Sqr(T-Model.Centers[C,J]);
        Model.Centers[C,J] := T
      end;
      if Shift > MaxShift then MaxShift := Shift
    end;
    { Label, inertia dan history harus sesuai pusat yang terbaru. }
    Inertia := 0;
    for I := 1 to D.Count do begin
      if not Nearest(Model,D.X[I],C,Dist) then Exit;
      Labels[I] := C; Inertia := Inertia+Dist
    end;
    History[Iter] := Inertia; HistoryCount := Iter;
    Model.Converged := Sqrt(MaxShift) <= Tolerance
  until Model.Converged or (Iter >= MaxIter);
  Model.Iterations := Iter; Model.Inertia := Inertia;
  Model.Fitted := True; FitKMeans := True
end;
function PredictCluster(var Model: TKMeansModel; var X: TVector;
  var Cluster: Integer; var Distance2: TFloat): Boolean;
begin
  ClearAIError; Cluster := 0; Distance2 := 0; PredictCluster := False;
  if not Model.Fitted or (Model.K < 1) or (Model.K > MaxClusters) or
     (Model.Features < 1) or (Model.Features > MaxFeatures) then begin
    SetAIError(ErrModel,'Model K-means belum dilatih'); Exit
  end;
  if not CheckVector(X,Model.Features) then Exit;
  PredictCluster := Nearest(Model,X,Cluster,Distance2)
end;
function PredictClusters(var Model: TKMeansModel; var D: TDataSet;
  var Labels: TLabels; var Inertia: TFloat): Boolean;
var I: Integer; Dist: TFloat;
begin
  PredictClusters := False; Inertia := 0;
  FillChar(Labels,SizeOf(Labels),0);
  if not CheckData(D,False) then Exit;
  if D.Features <> Model.Features then begin
    SetAIError(ErrSize,'Jumlah fitur cluster berbeda'); Exit
  end;
  for I := 1 to D.Count do begin
    if not PredictCluster(Model,D.X[I],Labels[I],Dist) then Exit;
    Inertia := Inertia+Dist
  end;
  PredictClusters := True
end;
end.
