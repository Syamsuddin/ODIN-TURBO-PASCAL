unit AIRule;
interface
uses AITypes;
const MaxFacts=32; MaxRules=32; MaxPremises=4;
      FactUnknown=-1; FactFalse=0; FactTrue=1;
type
  TFacts = record
    Count: Integer;
    Names: array[1..MaxFacts] of TName;
    Values: array[1..MaxFacts] of Integer;
    SourceRule: array[1..MaxFacts] of Integer;
  end;
  TPremises = array[1..MaxPremises] of Integer;
  TRule = record
    Name: TName;
    Count: Integer;
    FactIDs,Expected: TPremises;
    Conclusion,Value: Integer;
  end;
  TRuleSet = record
    FactCount,Count: Integer;
    Rules: array[1..MaxRules] of TRule;
  end;
procedure InitFacts(var F: TFacts);
function CheckFacts(var F: TFacts): Boolean;
procedure ResetDerivedFacts(var F: TFacts);
function AddFact(var F: TFacts; Name: TName; Value: Integer;
  var ID: Integer): Boolean;
function SetFact(var F: TFacts; ID,Value: Integer): Boolean;
procedure InitRules(FactCount: Integer; var R: TRuleSet);
function CheckRules(var R: TRuleSet): Boolean;
function AddRule(var R: TRuleSet; var Rule: TRule): Boolean;
function Infer(var R: TRuleSet; var F: TFacts; var Trace: TIndexList;
  var TraceCount: Integer): Boolean;
procedure ExplainFact(var R: TRuleSet; var F: TFacts; ID: Integer);
implementation
procedure InitFacts(var F: TFacts);
var I: Integer;
begin
  ClearAIError; FillChar(F,SizeOf(F),0);
  for I:=1 to MaxFacts do F.Values[I]:=FactUnknown
end;
function CheckFacts(var F: TFacts): Boolean;
var I,J: Integer;
begin
  ClearAIError; CheckFacts:=False;
  if (F.Count<0) or (F.Count>MaxFacts) then begin SetAIError(ErrSize,'Jumlah fakta tidak valid'); Exit end;
  for I:=1 to F.Count do begin
    if (Length(F.Names[I])>31) or (F.Names[I]='') or (F.Values[I]<-1) or (F.Values[I]>1) or
       (F.SourceRule[I]<0) or (F.SourceRule[I]>MaxRules) then begin
      SetAIError(ErrValue,'Isi fakta tidak valid'); Exit
    end;
    for J:=1 to I-1 do if F.Names[I]=F.Names[J] then begin
      SetAIError(ErrValue,'Nama fakta duplikat'); Exit
    end
  end;
  CheckFacts:=True
end;
procedure ResetDerivedFacts(var F: TFacts);
var I: Integer;
begin
  if not CheckFacts(F) then Exit;
  for I:=1 to F.Count do if F.SourceRule[I]<>0 then begin
    F.Values[I]:=FactUnknown; F.SourceRule[I]:=0
  end
end;
function AddFact(var F: TFacts; Name: TName; Value: Integer;
  var ID: Integer): Boolean;
var I: Integer;
begin
  ID:=0; AddFact:=False;
  if not CheckFacts(F) then Exit;
  if (Name='') or (Value<-1) or (Value>1) then begin SetAIError(ErrValue,'Nama/nilai fakta tidak valid'); Exit end;
  for I:=1 to F.Count do if F.Names[I]=Name then begin
    SetAIError(ErrValue,'Fakta sudah terdaftar'); Exit
  end;
  if F.Count=MaxFacts then begin SetAIError(ErrSize,'Fakta penuh'); Exit end;
  Inc(F.Count); ID:=F.Count; F.Names[ID]:=Name; F.Values[ID]:=Value;
  F.SourceRule[ID]:=0; AddFact:=True
end;
function SetFact(var F: TFacts; ID,Value: Integer): Boolean;
begin
  SetFact:=False;
  if not CheckFacts(F) then Exit;
  if (ID<1) or (ID>F.Count) or (Value<-1) or (Value>1) then begin
    SetAIError(ErrValue,'ID/nilai fakta tidak valid'); Exit
  end;
  ResetDerivedFacts(F);
  F.Values[ID]:=Value; F.SourceRule[ID]:=0; SetFact:=True
end;
procedure InitRules(FactCount: Integer; var R: TRuleSet);
begin ClearAIError; FillChar(R,SizeOf(R),0); R.FactCount:=FactCount end;
function GoodRule(var Rule: TRule; FactCount: Integer): Boolean;
var I: Integer;
begin
  GoodRule:=False;
  if (Length(Rule.Name)>31) or (Rule.Count<0) or (Rule.Count>MaxPremises) or
     (Rule.Conclusion<1) or (Rule.Conclusion>FactCount) or
     (Rule.Value<0) or (Rule.Value>1) then begin
    SetAIError(ErrValue,'Kesimpulan/ukuran aturan tidak valid'); Exit
  end;
  for I:=1 to Rule.Count do if (Rule.FactIDs[I]<1) or
    (Rule.FactIDs[I]>FactCount) or (Rule.Expected[I]<0) or
    (Rule.Expected[I]>1) then begin
    SetAIError(ErrValue,'Premis aturan tidak valid'); Exit
  end;
  GoodRule:=True
end;
function CheckRules(var R: TRuleSet): Boolean;
var I: Integer;
begin
  ClearAIError; CheckRules:=False;
  if (R.Count<0) or (R.Count>MaxRules) or
     (R.FactCount<1) or (R.FactCount>MaxFacts) then begin
    SetAIError(ErrSize,'Ukuran basis aturan tidak valid'); Exit
  end;
  for I:=1 to R.Count do if not GoodRule(R.Rules[I],R.FactCount) then Exit;
  CheckRules:=True
end;
function AddRule(var R: TRuleSet; var Rule: TRule): Boolean;
begin
  AddRule:=False;
  if not CheckRules(R) then Exit;
  if not GoodRule(Rule,R.FactCount) then Exit;
  if R.Count=MaxRules then begin SetAIError(ErrSize,'Basis aturan penuh'); Exit end;
  Inc(R.Count); R.Rules[R.Count]:=Rule; AddRule:=True
end;
function Infer(var R: TRuleSet; var F: TFacts; var Trace: TIndexList;
  var TraceCount: Integer): Boolean;
var Work: TFacts; LocalTrace: TIndexList; I,J,K,N: Integer;
    Match,Changed: Boolean;
begin
  Infer:=False; TraceCount:=0;
  if not CheckRules(R) then Exit;
  if not CheckFacts(F) then Exit;
  if F.Count<>R.FactCount then begin SetAIError(ErrSize,'Jumlah fakta dan aturan berbeda'); Exit end;
  Work:=F; N:=0;
  repeat
    Changed:=False;
    for I:=1 to R.Count do begin
      Match:=True;
      for J:=1 to R.Rules[I].Count do
        if Work.Values[R.Rules[I].FactIDs[J]]<>R.Rules[I].Expected[J] then Match:=False;
      if Match then begin
        K:=R.Rules[I].Conclusion;
        if Work.Values[K]=FactUnknown then begin
          Work.Values[K]:=R.Rules[I].Value; Work.SourceRule[K]:=I;
          Inc(N); LocalTrace[N]:=I; Changed:=True
        end else if Work.Values[K]<>R.Rules[I].Value then begin
          SetAIError(ErrValue,'Konflik kesimpulan aturan; fakta tidak diubah'); Exit
        end
      end
    end
  until not Changed;
  F:=Work; TraceCount:=N;
  for I:=1 to N do Trace[I]:=LocalTrace[I];
  Infer:=True
end;
procedure ExplainFact(var R: TRuleSet; var F: TFacts; ID: Integer);
var Seen: array[1..MaxFacts] of Boolean;
  procedure PrintProof(K,Depth: Integer);
  var I,RuleID: Integer;
  begin
    for I:=1 to Depth do Write('  ');
    Write(F.Names[K],' = ',F.Values[K]);
    if Seen[K] then begin WriteLn(' (sudah ditampilkan)'); Exit end;
    Seen[K]:=True; RuleID:=F.SourceRule[K];
    if RuleID=0 then begin WriteLn(' (fakta awal/unknown)'); Exit end;
    if RuleID>R.Count then begin WriteLn(' (sumber tidak valid)'); Exit end;
    WriteLn(' <= aturan ',RuleID,': ',R.Rules[RuleID].Name);
    for I:=1 to R.Rules[RuleID].Count do PrintProof(R.Rules[RuleID].FactIDs[I],Depth+1)
  end;
begin
  if not CheckRules(R) then Exit;
  if not CheckFacts(F) then Exit;
  if (F.Count<>R.FactCount) or (ID<1) or (ID>F.Count) then begin
    SetAIError(ErrSize,'Fakta penjelasan tidak valid'); Exit
  end;
  FillChar(Seen,SizeOf(Seen),0); PrintProof(ID,0)
end;
end.
