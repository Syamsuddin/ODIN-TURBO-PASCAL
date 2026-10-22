program RuleDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIRule,AIModel;
var Facts: TFacts; Rules: TRuleSet; Rule: TRule;
    Internet,Power,Ready,Online,N: Integer; Trace: TIndexList;
{$I COMMON.INC}
begin
  InitFacts(Facts);
  Need(AddFact(Facts,'internet_tersedia',1,Internet));
  Need(AddFact(Facts,'listrik_tersedia',1,Power));
  Need(AddFact(Facts,'perangkat_siap',-1,Ready));
  Need(AddFact(Facts,'kelas_daring_siap',-1,Online));
  InitRules(Facts.Count,Rules); FillChar(Rule,SizeOf(Rule),0);
  Rule.Name:='kelas_daring'; Rule.Count:=2;
  Rule.FactIDs[1]:=Ready; Rule.Expected[1]:=1;
  Rule.FactIDs[2]:=Internet; Rule.Expected[2]:=1;
  Rule.Conclusion:=Online; Rule.Value:=1; Need(AddRule(Rules,Rule));
  Rule.Name:='perangkat'; Rule.Count:=1; Rule.FactIDs[1]:=Power;
  Rule.Expected[1]:=1; Rule.Conclusion:=Ready; Need(AddRule(Rules,Rule));
  Need(Infer(Rules,Facts,Trace,N)); WriteLn('Aturan aktif=',N);
  ExplainFact(Rules,Facts,Online);
  Need(SaveRules('RULES.TPM',Rules)); Need(SaveFacts('FACTS.TPM',Facts))
end.
