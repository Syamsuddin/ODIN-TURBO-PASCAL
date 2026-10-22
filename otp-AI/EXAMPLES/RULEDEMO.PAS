program RuleDemo;
{ RULEDEMO - sistem pakar berbasis aturan (forward chaining) dengan AIRULE.
  Ini penalaran simbolik, bukan model yang belajar dari data berlabel.
  Fakta dibuat dengan nilai -1 (unknown)/0 (false)/1 (true): dua fakta
  diketahui (internet, listrik tersedia), dua lagi belum diketahui
  (perangkat siap, kelas daring siap). Dua aturan dipasang: "perangkat"
  (listrik => perangkat siap) dan "kelas_daring" (perangkat siap DAN
  internet => kelas daring siap). Infer menjalankan forward chaining
  sampai tidak ada fakta baru, lalu ExplainFact mencetak pohon alasan
  di balik kesimpulan "kelas_daring_siap". Aturan dan fakta disimpan
  ke .TPM.
  Latihan (DOCS/GUIDE2.TXT bagian 21, urutan #8): tambahkan fakta atau
  aturan baru yang saling bertentangan, lalu amati hasil Infer. }
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
  Need(AddFact(Facts,'internet_tersedia',1,Internet));   { diketahui true }
  Need(AddFact(Facts,'listrik_tersedia',1,Power));        { diketahui true }
  Need(AddFact(Facts,'perangkat_siap',-1,Ready));         { belum diketahui, akan diturunkan }
  Need(AddFact(Facts,'kelas_daring_siap',-1,Online));      { belum diketahui, akan diturunkan }
  InitRules(Facts.Count,Rules); FillChar(Rule,SizeOf(Rule),0);
  Rule.Name:='kelas_daring'; Rule.Count:=2;                { dua premis, digabung AND }
  Rule.FactIDs[1]:=Ready; Rule.Expected[1]:=1;
  Rule.FactIDs[2]:=Internet; Rule.Expected[2]:=1;
  Rule.Conclusion:=Online; Rule.Value:=1; Need(AddRule(Rules,Rule));
  Rule.Name:='perangkat'; Rule.Count:=1; Rule.FactIDs[1]:=Power;  { satu premis: listrik => perangkat siap }
  Rule.Expected[1]:=1; Rule.Conclusion:=Ready; Need(AddRule(Rules,Rule));
  Need(Infer(Rules,Facts,Trace,N)); WriteLn('Aturan aktif=',N);  { forward chaining sampai berhenti }
  ExplainFact(Rules,Facts,Online);                         { pohon alasan di balik kelas_daring_siap }
  Need(SaveRules('RULES.TPM',Rules)); Need(SaveFacts('FACTS.TPM',Facts))
end.
