unit AITree;
interface
uses AITypes;
const MaxTreeNodes=63; MaxTreeDepth=8;
type
  TTreeNode = record
    Feature,LeftChild,RightChild,LabelValue,Samples: Integer;
    Threshold,Gain: TFloat;
    Counts: array[0..MaxClasses-1] of Integer;
  end;
  TTreeModel = record
    Fitted,Truncated: Boolean;
    Features,Classes,NodeCount: Integer;
    Nodes: array[1..MaxTreeNodes] of TTreeNode;
  end;
function CheckTree(var M: TTreeModel): Boolean;
function FitTree(var D: TDataSet; DepthLimit,MinLeaf: Integer;
  MinGain: TFloat; var M: TTreeModel): Boolean;
function PredictTree(var M: TTreeModel; var X: TVector;
  var LabelValue: Integer): Boolean;
function TraceTree(var M: TTreeModel; var X: TVector;
  var Path: TIndexList; var Length,LabelValue: Integer): Boolean;
implementation
type TCounts=array[0..MaxClasses-1] of Integer;
function Entropy(var Counts: TCounts; N: Integer): TFloat;
var C: Integer; P,H: TFloat;
begin
  H:=0;
  if N>0 then for C:=0 to MaxClasses-1 do if Counts[C]>0 then begin
    P:=Counts[C]/N; H:=H-P*Ln(P)/Ln(2)
  end;
  Entropy:=H
end;
function CheckTree(var M: TTreeModel): Boolean;
var Parents: array[1..MaxTreeNodes] of Integer;
    I,C,N,L,R: Integer;
begin
  ClearAIError; CheckTree:=False;
  if not M.Fitted or (M.Features<1) or (M.Features>MaxFeatures) or
     (M.Classes<1) or (M.Classes>MaxClasses) or
     (M.NodeCount<1) or (M.NodeCount>MaxTreeNodes) then begin
    SetAIError(ErrModel,'Dimensi pohon tidak valid'); Exit
  end;
  FillChar(Parents,SizeOf(Parents),0);
  for I:=1 to M.NodeCount do begin
    with M.Nodes[I] do begin
      if (Samples<1) or (Samples>MaxSamples) or
         (LabelValue<0) or (LabelValue>=M.Classes) or
         not ValidNumber(Threshold) or not ValidNumber(Gain) or
         (Gain<0) or (Feature<0) or (Feature>M.Features) then begin
        SetAIError(ErrModel,'Isi node pohon tidak valid'); Exit
      end;
      N:=0;
      for C:=0 to M.Classes-1 do begin
        if (Counts[C]<0) or (Counts[C]>MaxSamples) then begin
          SetAIError(ErrModel,'Hitungan node tidak valid'); Exit
        end;
        Inc(N,Counts[C])
      end;
      if N<>Samples then begin SetAIError(ErrModel,'Total node tidak cocok'); Exit end;
      if Feature=0 then begin
        if (LeftChild<>0) or (RightChild<>0) then begin
          SetAIError(ErrModel,'Daun tidak boleh memiliki anak'); Exit
        end
      end else begin
        L:=LeftChild; R:=RightChild;
        if (L<=I) or (R<=I) or (L>M.NodeCount) or (R>M.NodeCount) or (L=R) then begin
          SetAIError(ErrModel,'Anak pohon tidak valid atau membentuk siklus'); Exit
        end;
        Inc(Parents[L]); Inc(Parents[R]);
        if M.Nodes[L].Samples+M.Nodes[R].Samples<>Samples then begin
          SetAIError(ErrModel,'Jumlah sampel anak tidak cocok'); Exit
        end
      end
    end
  end;
  for I:=2 to M.NodeCount do if Parents[I]<>1 then begin
    SetAIError(ErrModel,'Node terputus atau dipakai dua induk'); Exit
  end;
  CheckTree:=True
end;
function FitTree(var D: TDataSet; DepthLimit,MinLeaf: Integer;
  MinGain: TFloat; var M: TTreeModel): Boolean;
var Rows: TIndexList; I: Integer;
  procedure Build(Node,Lo,Hi,Depth: Integer);
  var Counts,LC,RC: TCounts;
      I,J,K,C,N,NL,NR,BestF,A,B,T,L,R: Integer;
      H,G,BestG,Threshold,BestT,V,NextV: TFloat;
      HasNext: Boolean;
  begin
    FillChar(Counts,SizeOf(Counts),0); N:=Hi-Lo+1;
    for I:=Lo to Hi do Inc(Counts[D.Labels[Rows[I]]]);
    C:=0;
    for I:=1 to MaxClasses-1 do if Counts[I]>Counts[C] then C:=I;
    M.Nodes[Node].LabelValue:=C; M.Nodes[Node].Samples:=N;
    for I:=0 to MaxClasses-1 do M.Nodes[Node].Counts[I]:=Counts[I];
    H:=Entropy(Counts,N);
    if (H<=0) or (Depth>=DepthLimit) or (N<2*MinLeaf) then Exit;
    if M.NodeCount+2>MaxTreeNodes then begin M.Truncated:=True; Exit end;
    BestG:=-1; BestF:=0; BestT:=0;
    for J:=1 to D.Features do for I:=Lo to Hi do begin
      V:=D.X[Rows[I],J]; HasNext:=False; NextV:=0;
      for K:=Lo to Hi do if D.X[Rows[K],J]>V then
        if not HasNext or (D.X[Rows[K],J]<NextV) then begin
          NextV:=D.X[Rows[K],J]; HasNext:=True
        end;
      if HasNext then begin
        Threshold:=V+(NextV-V)/2;
        FillChar(LC,SizeOf(LC),0); FillChar(RC,SizeOf(RC),0); NL:=0; NR:=0;
        for K:=Lo to Hi do begin
          C:=D.Labels[Rows[K]];
          if D.X[Rows[K],J]<=Threshold then begin Inc(LC[C]); Inc(NL) end
          else begin Inc(RC[C]); Inc(NR) end
        end;
        if (NL>=MinLeaf) and (NR>=MinLeaf) then begin
          G:=H-NL/N*Entropy(LC,NL)-NR/N*Entropy(RC,NR);
          if G<0 then G:=0;
          if (G>BestG+1E-12) or
             ((Abs(G-BestG)<=1E-12) and (J=BestF) and (Threshold<BestT)) then begin
            BestG:=G; BestF:=J; BestT:=Threshold
          end
        end
      end
    end;
    if (BestF=0) or (BestG<MinGain) then Exit;
    A:=Lo; B:=Hi;
    while A<=B do
      if D.X[Rows[A],BestF]<=BestT then Inc(A)
      else begin T:=Rows[A]; Rows[A]:=Rows[B]; Rows[B]:=T; Dec(B) end;
    L:=M.NodeCount+1; R:=M.NodeCount+2; M.NodeCount:=R;
    with M.Nodes[Node] do begin
      Feature:=BestF; Threshold:=BestT; Gain:=BestG; LeftChild:=L; RightChild:=R
    end;
    Build(L,Lo,B,Depth+1); Build(R,A,Hi,Depth+1)
  end;
begin
  FillChar(M,SizeOf(M),0); FitTree:=False;
  if not CheckData(D,False) then Exit;
  if D.TargetKind<>TargetClass then begin SetAIError(ErrValue,'Tree memerlukan kelas'); Exit end;
  if (DepthLimit<0) or (DepthLimit>MaxTreeDepth) or
     (MinLeaf<1) or (MinLeaf>MaxSamples) or not ValidNumber(MinGain) or (MinGain<0) then begin
    SetAIError(ErrValue,'Depth 0..8, min-leaf 1..200, min-gain >=0'); Exit
  end;
  M.Features:=D.Features; M.NodeCount:=1;
  for I:=1 to D.Count do begin
    Rows[I]:=I;
    if D.Labels[I]+1>M.Classes then M.Classes:=D.Labels[I]+1
  end;
  Build(1,1,D.Count,0); M.Fitted:=True;
  if not CheckTree(M) then begin M.Fitted:=False; Exit end;
  FitTree:=True
end;
function TraceTree(var M: TTreeModel; var X: TVector;
  var Path: TIndexList; var Length,LabelValue: Integer): Boolean;
var Node: Integer;
begin
  Length:=0; LabelValue:=-1; TraceTree:=False;
  if not CheckTree(M) then Exit;
  if not CheckVector(X,M.Features) then Exit;
  Node:=1;
  repeat
    Inc(Length); Path[Length]:=Node;
    if M.Nodes[Node].Feature=0 then begin
      LabelValue:=M.Nodes[Node].LabelValue; Break
    end;
    if X[M.Nodes[Node].Feature]<=M.Nodes[Node].Threshold then Node:=M.Nodes[Node].LeftChild
    else Node:=M.Nodes[Node].RightChild
  until False;
  TraceTree:=True
end;
function PredictTree(var M: TTreeModel; var X: TVector;
  var LabelValue: Integer): Boolean;
var Path: TIndexList; N: Integer;
begin PredictTree:=TraceTree(M,X,Path,N,LabelValue) end;
end.
