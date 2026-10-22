unit AIFuzzy;
interface
uses AITypes;
const FuzzyInputs=2; FuzzySets=3; MaxFuzzyRules=9;
type
  TTriangle = record A,B,C: TFloat end;
  TFuzzyRule = record Set1,Set2,OutputSet: Integer; Weight: TFloat end;
  TFuzzySystem = record
    Ready: Boolean;
    RuleCount: Integer;
    InMin,InMax: array[1..FuzzyInputs] of TFloat;
    OutMin,OutMax: TFloat;
    Inputs: array[1..FuzzyInputs,1..FuzzySets] of TTriangle;
    Outputs: array[1..FuzzySets] of TTriangle;
    Rules: array[1..MaxFuzzyRules] of TFuzzyRule;
  end;
  TFuzzyStrength = array[1..MaxFuzzyRules] of TFloat;
function TriangleMembership(X: TFloat; var T: TTriangle;
  var Degree: TFloat): Boolean;
function CheckFuzzy(var S: TFuzzySystem): Boolean;
procedure DefaultFuzzy(var S: TFuzzySystem);
function EvaluateFuzzy(var S: TFuzzySystem; Input1,Input2: TFloat;
  Segments: Integer; var Output: TFloat; var Strengths: TFuzzyStrength): Boolean;
implementation
function GoodTriangle(var T: TTriangle): Boolean;
begin
  GoodTriangle:=False;
  if not ValidNumber(T.A) or not ValidNumber(T.B) or not ValidNumber(T.C) or
     (T.A>T.B) or (T.B>T.C) or (T.A>=T.C) then begin
    SetAIError(ErrValue,'Segitiga memerlukan A<=B<=C dan A<C'); Exit
  end;
  GoodTriangle:=True
end;
function TriangleMembership(X: TFloat; var T: TTriangle;
  var Degree: TFloat): Boolean;
begin
  ClearAIError; Degree:=0; TriangleMembership:=False;
  if not GoodTriangle(T) then Exit;
  if not ValidNumber(X) then begin SetAIError(ErrValue,'Input membership tidak valid'); Exit end;
  if X=T.B then Degree:=1
  else if (X<=T.A) or (X>=T.C) then Degree:=0
  else if X<T.B then Degree:=(X-T.A)/(T.B-T.A)
  else Degree:=(T.C-X)/(T.C-T.B);
  TriangleMembership:=True
end;
function CheckFuzzy(var S: TFuzzySystem): Boolean;
var I,J: Integer;
begin
  ClearAIError; CheckFuzzy:=False;
  if not S.Ready or (S.RuleCount<1) or (S.RuleCount>MaxFuzzyRules) then begin
    SetAIError(ErrModel,'Sistem fuzzy belum siap'); Exit
  end;
  for I:=1 to FuzzyInputs do begin
    if not ValidNumber(S.InMin[I]) or not ValidNumber(S.InMax[I]) or
       (Abs(S.InMin[I])>1E6) or (Abs(S.InMax[I])>1E6) or
       (S.InMin[I]>=S.InMax[I]) then begin SetAIError(ErrModel,'Rentang input fuzzy tidak valid'); Exit end;
    for J:=1 to FuzzySets do begin
      if not GoodTriangle(S.Inputs[I,J]) then Exit;
      if (S.Inputs[I,J].A<S.InMin[I]) or (S.Inputs[I,J].C>S.InMax[I]) then begin
        SetAIError(ErrModel,'Membership input di luar universe'); Exit
      end
    end
  end;
  if not ValidNumber(S.OutMin) or not ValidNumber(S.OutMax) or
     (Abs(S.OutMin)>1E6) or (Abs(S.OutMax)>1E6) or (S.OutMin>=S.OutMax) then begin
    SetAIError(ErrModel,'Rentang output fuzzy tidak valid'); Exit
  end;
  for J:=1 to FuzzySets do begin
    if not GoodTriangle(S.Outputs[J]) then Exit;
    if (S.Outputs[J].A<S.OutMin) or (S.Outputs[J].C>S.OutMax) then begin
      SetAIError(ErrModel,'Membership output di luar universe'); Exit
    end
  end;
  for I:=1 to S.RuleCount do with S.Rules[I] do
    if (Set1<1) or (Set1>FuzzySets) or (Set2<1) or (Set2>FuzzySets) or
       (OutputSet<1) or (OutputSet>FuzzySets) or not ValidNumber(Weight) or
       (Weight<0) or (Weight>1) then begin SetAIError(ErrModel,'Aturan fuzzy tidak valid'); Exit end;
  CheckFuzzy:=True
end;
procedure DefaultFuzzy(var S: TFuzzySystem);
var I,J,N: Integer;
  procedure Tri(var T: TTriangle; A,B,C: TFloat);
  begin T.A:=A; T.B:=B; T.C:=C end;
begin
  ClearAIError; FillChar(S,SizeOf(S),0); S.Ready:=True; S.RuleCount:=9;
  S.InMin[1]:=0; S.InMax[1]:=40; S.InMin[2]:=0; S.InMax[2]:=100;
  S.OutMin:=0; S.OutMax:=100;
  Tri(S.Inputs[1,1],0,0,20); Tri(S.Inputs[1,2],10,20,30); Tri(S.Inputs[1,3],20,40,40);
  Tri(S.Inputs[2,1],0,0,50); Tri(S.Inputs[2,2],25,50,75); Tri(S.Inputs[2,3],50,100,100);
  for J:=1 to 3 do S.Outputs[J]:=S.Inputs[2,J];
  N:=0;
  for I:=1 to 3 do for J:=1 to 3 do begin
    Inc(N); S.Rules[N].Set1:=I; S.Rules[N].Set2:=J;
    S.Rules[N].OutputSet:=I;
    if (J=3) and (I<3) then S.Rules[N].OutputSet:=I+1;
    S.Rules[N].Weight:=1
  end
end;
function EvaluateFuzzy(var S: TFuzzySystem; Input1,Input2: TFloat;
  Segments: Integer; var Output: TFloat; var Strengths: TFuzzyStrength): Boolean;
var I,K: Integer; A,B,X,Mu,T,Sum,Weighted,Weight: TFloat;
begin
  Output:=0; FillChar(Strengths,SizeOf(Strengths),0); EvaluateFuzzy:=False;
  if not CheckFuzzy(S) then Exit;
  if not ValidNumber(Input1) or not ValidNumber(Input2) or
     (Input1<S.InMin[1]) or (Input1>S.InMax[1]) or
     (Input2<S.InMin[2]) or (Input2>S.InMax[2]) or
     (Segments<10) or (Segments>400) then begin
    SetAIError(ErrValue,'Input di luar universe atau segmen bukan 10..400'); Exit
  end;
  for I:=1 to S.RuleCount do begin
    if not TriangleMembership(Input1,S.Inputs[1,S.Rules[I].Set1],A) then Exit;
    if not TriangleMembership(Input2,S.Inputs[2,S.Rules[I].Set2],B) then Exit;
    if B<A then A:=B;
    Strengths[I]:=A*S.Rules[I].Weight
  end;
  Sum:=0; Weighted:=0;
  for K:=0 to Segments do begin
    X:=S.OutMin+(S.OutMax-S.OutMin)*K/Segments; Mu:=0;
    for I:=1 to S.RuleCount do begin
      if not TriangleMembership(X,S.Outputs[S.Rules[I].OutputSet],T) then Exit;
      if Strengths[I]<T then T:=Strengths[I];
      if T>Mu then Mu:=T
    end;
    Weight:=1; if (K=0) or (K=Segments) then Weight:=0.5;
    Sum:=Sum+Weight*Mu; Weighted:=Weighted+Weight*X*Mu
  end;
  if Sum<=0 then begin SetAIError(ErrValue,'Tidak ada keluaran fuzzy yang aktif'); Exit end;
  Output:=Weighted/Sum; EvaluateFuzzy:=True
end;
end.
