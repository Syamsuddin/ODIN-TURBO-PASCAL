unit AIModel;
interface
uses AITypes,AILINEAR,AINNet,AIBayes,AITree,AIText,AIRule,AISearch,AIFuzzy,AIReward;
function SaveLinear(FileName: TFileName; var M: TLinearModel): Boolean;
function LoadLinear(FileName: TFileName; var M: TLinearModel): Boolean;
function SaveKMeans(FileName: TFileName; var M: TKMeansModel): Boolean;
function LoadKMeans(FileName: TFileName; var M: TKMeansModel): Boolean;
function SaveScaler(FileName: TFileName; var M: TScaler): Boolean;
function LoadScaler(FileName: TFileName; var M: TScaler): Boolean;
function SaveImputer(FileName: TFileName; var M: TImputer): Boolean;
function LoadImputer(FileName: TFileName; var M: TImputer): Boolean;
function SaveLogistic(FileName: TFileName; var M: TLogisticModel): Boolean;
function LoadLogistic(FileName: TFileName; var M: TLogisticModel): Boolean;
function SavePerceptron(FileName: TFileName; var M: TPerceptronModel): Boolean;
function LoadPerceptron(FileName: TFileName; var M: TPerceptronModel): Boolean;
function SaveNeural(FileName: TFileName; var M: TNeuralModel): Boolean;
function LoadNeural(FileName: TFileName; var M: TNeuralModel): Boolean;
function SaveBayes(FileName: TFileName; var M: TBayesModel): Boolean;
function LoadBayes(FileName: TFileName; var M: TBayesModel): Boolean;
function SaveTree(FileName: TFileName; var M: TTreeModel): Boolean;
function LoadTree(FileName: TFileName; var M: TTreeModel): Boolean;
function SaveVocabulary(FileName: TFileName; var M: TTextModel): Boolean;
function LoadVocabulary(FileName: TFileName; var M: TTextModel): Boolean;
function SaveRules(FileName: TFileName; var M: TRuleSet): Boolean;
function LoadRules(FileName: TFileName; var M: TRuleSet): Boolean;
function SaveFacts(FileName: TFileName; var M: TFacts): Boolean;
function LoadFacts(FileName: TFileName; var M: TFacts): Boolean;
function SaveGrid(FileName: TFileName; var M: TGrid): Boolean;
function LoadGrid(FileName: TFileName; var M: TGrid): Boolean;
function SaveFuzzy(FileName: TFileName; var M: TFuzzySystem): Boolean;
function LoadFuzzy(FileName: TFileName; var M: TFuzzySystem): Boolean;
function SaveQ(FileName: TFileName; var M: TQModel): Boolean;
function LoadQ(FileName: TFileName; var M: TQModel): Boolean;

function SaveKNN(FileName: TFileName; var M: TKNNModel): Boolean;
function LoadKNN(FileName: TFileName; var Storage: TDataSet;
  var M: TKNNModel): Boolean;
implementation
uses AIKNN;
const MaxModelBytes=32760;
type
  TByteBlock=array[0..MaxModelBytes-1] of Byte;
  PByteBlock=^TByteBlock;
  THeader=packed record
    Magic: array[1..8] of Char;
    Version,Kind,Bytes: Word;
    RealBytes,IntBytes,BoolBytes,LittleEndian,CompilerFamily: Byte;
    Layout,Checksum: Word;
  end;
  TKNNStore=record K: Integer; Data: TDataSet end;
  PKNNStore=^TKNNStore;
function NewBuffer(Size: Word; var P: Pointer): Boolean;
{$IFDEF FPC} var OldNil: Boolean; {$ENDIF}
begin
  P:=nil; NewBuffer:=False;
  if (Size=0) or (Size>MaxModelBytes) then begin SetAIError(ErrSize,'Ukuran model tidak didukung'); Exit end;
  {$IFNDEF FPC}
    {$IFNDEF ODIN}
  if MaxAvail<Size then begin SetAIError(ErrMemory,'Heap model tidak cukup'); Exit end;
    {$ENDIF}
  {$ENDIF}
  {$IFDEF FPC} OldNil:=ReturnNilIfGrowHeapFails; ReturnNilIfGrowHeapFails:=True; {$ENDIF}
  GetMem(P,Size);
  {$IFDEF FPC} ReturnNilIfGrowHeapFails:=OldNil; {$ENDIF}
  if P=nil then begin SetAIError(ErrMemory,'Alokasi model gagal'); Exit end;
  NewBuffer:=True
end;
function SumBytes(var Data; Size: Word): Word;
var P: PByteBlock; I: Word; S: LongInt;
begin
  P:=@Data; S:=5381;
  for I:=0 to Size-1 do S:=(S*33+P^[I]) mod 65521;
  SumBytes:=S
end;
procedure MakeHeader(Kind,Size: Word; var H: THeader);
var W: Word; P: PByteBlock;
begin
  FillChar(H,SizeOf(H),0);
  H.Magic[1]:='T'; H.Magic[2]:='P'; H.Magic[3]:='A'; H.Magic[4]:='I';
  H.Magic[5]:='M'; H.Magic[6]:='D'; H.Magic[7]:='L'; H.Magic[8]:='2';
  H.Version:=1; H.Kind:=Kind; H.Bytes:=Size;
  H.RealBytes:=SizeOf(TFloat); H.IntBytes:=SizeOf(Integer);
  H.BoolBytes:=SizeOf(Boolean); W:=$0102; P:=@W;
  H.LittleEndian:=Ord(P^[0]=2);
  {$IFDEF FPC} H.CompilerFamily:=1;
  {$ELSE}
    {$IFDEF ODIN} H.CompilerFamily:=3;
    {$ELSE} H.CompilerFamily:=2;
    {$ENDIF}
  {$ENDIF}
  H.Layout:=2008
end;
function SaveRaw(FileName: TFileName; Kind,Size: Word; var Data): Boolean;
var F: File; H: THeader; Actual: Word; E,E2: Integer; OK: Boolean;
begin
  SaveRaw:=False; ClearAIError;
  if (Size=0) or (Size>MaxModelBytes) then begin SetAIError(ErrSize,'Model terlalu besar'); Exit end;
  MakeHeader(Kind,Size,H); H.Checksum:=SumBytes(Data,Size);
  Assign(F,FileName); {$I-} Rewrite(F,1); E:=IOResult; {$I+}
  if E<>0 then begin SetAIError(ErrIO,'Berkas model tidak dapat dibuat'); Exit end;
  {$I-}
  BlockWrite(F,H,SizeOf(H),Actual); E:=IOResult;
  OK:=(E=0) and (Actual=SizeOf(H));
  if OK then begin BlockWrite(F,Data,Size,Actual); E:=IOResult; OK:=(E=0) and (Actual=Size) end;
  Close(F); E2:=IOResult;
  {$I+}
  if not OK or (E2<>0) then begin SetAIError(ErrIO,'Penulisan model tidak lengkap'); Exit end;
  SaveRaw:=True
end;
function LoadRaw(FileName: TFileName; Kind,Size: Word; var Data): Boolean;
var F: File; H,Expected: THeader; Actual: Word;
    E,E2,I: Integer; P: Pointer; OK,Match: Boolean; Length: LongInt;
begin
  LoadRaw:=False; ClearAIError; P:=nil;
  Assign(F,FileName); {$I-} Reset(F,1); E:=IOResult; {$I+}
  if E<>0 then begin SetAIError(ErrIO,'Berkas model tidak terbuka'); Exit end;
  MakeHeader(Kind,Size,Expected); OK:=False;
  repeat
    {$I-} BlockRead(F,H,SizeOf(H),Actual); E:=IOResult;
    Length:=FileSize(F); E2:=IOResult; {$I+}
    if (E<>0) or (E2<>0) or (Actual<>SizeOf(H)) then begin
      SetAIError(ErrFormat,'Header model terpotong'); Break
    end;
    Match:=True;
    for I:=1 to 8 do if H.Magic[I]<>Expected.Magic[I] then Match:=False;
    if not Match or (H.Version<>Expected.Version) or (H.Kind<>Kind) or
       (H.Bytes<>Size) or (H.RealBytes<>Expected.RealBytes) or
       (H.IntBytes<>Expected.IntBytes) or (H.BoolBytes<>Expected.BoolBytes) or
       (H.LittleEndian<>Expected.LittleEndian) or
       (H.CompilerFamily<>Expected.CompilerFamily) or (H.Layout<>Expected.Layout) or
       (Length<>LongInt(Size)+SizeOf(H)) then begin
      SetAIError(ErrFormat,'Jenis, versi, ABI atau panjang model tidak cocok'); Break
    end;
    if not NewBuffer(Size,P) then Break;
    {$I-} BlockRead(F,P^,Size,Actual); E:=IOResult; {$I+}
    if (E<>0) or (Actual<>Size) then begin SetAIError(ErrFormat,'Isi model terpotong'); Break end;
    if SumBytes(P^,Size)<>H.Checksum then begin SetAIError(ErrFormat,'Checksum model tidak cocok'); Break end;
    OK:=True
  until True;
  {$I-} Close(F); E2:=IOResult; {$I+}
  if OK and (E2<>0) then begin SetAIError(ErrIO,'Gagal menutup model'); OK:=False end;
  if OK then Move(P^,Data,Size);
  if P<>nil then FreeMem(P,Size);
  LoadRaw:=OK
end;
function GoodLinear(var M: TLinearModel): Boolean;
begin
  ClearAIError; GoodLinear:=False;
  if not M.Fitted then begin SetAIError(ErrModel,'Linear belum dilatih'); Exit end;
  if not CheckVector(M.Coeff,M.Features) then Exit;
  if not ValidNumber(M.Intercept) then begin SetAIError(ErrModel,'Intercept tidak valid'); Exit end;
  GoodLinear:=True
end;
function GoodKMeans(var M: TKMeansModel): Boolean;
var I: Integer;
begin
  ClearAIError; GoodKMeans:=False;
  if not M.Fitted or (M.K<1) or (M.K>MaxClusters) or
     (M.Features<1) or (M.Features>MaxFeatures) or
     (M.Iterations<1) or (M.Iterations>MaxSamples) or
     (M.Inertia<>M.Inertia) or (M.Inertia<0) or (M.Inertia>1E30) then begin
    SetAIError(ErrModel,'Model K-means tidak valid'); Exit
  end;
  for I:=1 to M.K do if not CheckVector(M.Centers[I],M.Features) then Exit;
  GoodKMeans:=True
end;
function GoodScaler(var M: TScaler): Boolean;
var J: Integer;
begin
  ClearAIError; GoodScaler:=False;
  if not M.Fitted or (M.Features<1) or (M.Features>MaxFeatures) or
     ((M.Kind<>ScaleMinMax) and (M.Kind<>ScaleStandard)) then begin
    SetAIError(ErrModel,'Scaler tidak valid'); Exit
  end;
  if not CheckVector(M.Offset,M.Features) then Exit;
  for J:=1 to M.Features do if (M.Divisor[J]<>M.Divisor[J]) or
    (M.Divisor[J]<AIEpsilon) or (M.Divisor[J]>2*AIInputLimit) then begin
    SetAIError(ErrModel,'Divisor scaler tidak valid'); Exit
  end;
  GoodScaler:=True
end;
function GoodImputer(var M: TImputer): Boolean;
begin
  ClearAIError; GoodImputer:=False;
  if not M.Fitted then begin SetAIError(ErrModel,'Imputer belum dilatih'); Exit end;
  GoodImputer:=CheckVector(M.Means,M.Features)
end;

function SaveLinear(FileName: TFileName; var M: TLinearModel): Boolean;
begin
  SaveLinear:=False;
  if not GoodLinear(M) then Exit;
  SaveLinear:=SaveRaw(FileName,1,SizeOf(M),M)
end;
function LoadLinear(FileName: TFileName; var M: TLinearModel): Boolean;
var Temp: TLinearModel;
begin
  LoadLinear:=False;
  if not LoadRaw(FileName,1,SizeOf(Temp),Temp) then Exit;
  if not GoodLinear(Temp) then Exit;
  M:=Temp; LoadLinear:=True
end;

function SaveKMeans(FileName: TFileName; var M: TKMeansModel): Boolean;
begin
  SaveKMeans:=False;
  if not GoodKMeans(M) then Exit;
  SaveKMeans:=SaveRaw(FileName,2,SizeOf(M),M)
end;
function LoadKMeans(FileName: TFileName; var M: TKMeansModel): Boolean;
var Temp: TKMeansModel;
begin
  LoadKMeans:=False;
  if not LoadRaw(FileName,2,SizeOf(Temp),Temp) then Exit;
  if not GoodKMeans(Temp) then Exit;
  M:=Temp; LoadKMeans:=True
end;

function SaveScaler(FileName: TFileName; var M: TScaler): Boolean;
begin
  SaveScaler:=False;
  if not GoodScaler(M) then Exit;
  SaveScaler:=SaveRaw(FileName,3,SizeOf(M),M)
end;
function LoadScaler(FileName: TFileName; var M: TScaler): Boolean;
var Temp: TScaler;
begin
  LoadScaler:=False;
  if not LoadRaw(FileName,3,SizeOf(Temp),Temp) then Exit;
  if not GoodScaler(Temp) then Exit;
  M:=Temp; LoadScaler:=True
end;

function SaveImputer(FileName: TFileName; var M: TImputer): Boolean;
begin
  SaveImputer:=False;
  if not GoodImputer(M) then Exit;
  SaveImputer:=SaveRaw(FileName,4,SizeOf(M),M)
end;
function LoadImputer(FileName: TFileName; var M: TImputer): Boolean;
var Temp: TImputer;
begin
  LoadImputer:=False;
  if not LoadRaw(FileName,4,SizeOf(Temp),Temp) then Exit;
  if not GoodImputer(Temp) then Exit;
  M:=Temp; LoadImputer:=True
end;

function SaveLogistic(FileName: TFileName; var M: TLogisticModel): Boolean;
begin
  SaveLogistic:=False;
  if not CheckLogistic(M) then Exit;
  SaveLogistic:=SaveRaw(FileName,5,SizeOf(M),M)
end;
function LoadLogistic(FileName: TFileName; var M: TLogisticModel): Boolean;
var Temp: TLogisticModel;
begin
  LoadLogistic:=False;
  if not LoadRaw(FileName,5,SizeOf(Temp),Temp) then Exit;
  if not CheckLogistic(Temp) then Exit;
  M:=Temp; LoadLogistic:=True
end;

function SavePerceptron(FileName: TFileName; var M: TPerceptronModel): Boolean;
begin
  SavePerceptron:=False;
  if not CheckPerceptron(M) then Exit;
  SavePerceptron:=SaveRaw(FileName,6,SizeOf(M),M)
end;
function LoadPerceptron(FileName: TFileName; var M: TPerceptronModel): Boolean;
var Temp: TPerceptronModel;
begin
  LoadPerceptron:=False;
  if not LoadRaw(FileName,6,SizeOf(Temp),Temp) then Exit;
  if not CheckPerceptron(Temp) then Exit;
  M:=Temp; LoadPerceptron:=True
end;

function SaveNeural(FileName: TFileName; var M: TNeuralModel): Boolean;
begin
  SaveNeural:=False;
  if not CheckNeural(M) then Exit;
  SaveNeural:=SaveRaw(FileName,7,SizeOf(M),M)
end;
function LoadNeural(FileName: TFileName; var M: TNeuralModel): Boolean;
var Temp: TNeuralModel;
begin
  LoadNeural:=False;
  if not LoadRaw(FileName,7,SizeOf(Temp),Temp) then Exit;
  if not CheckNeural(Temp) then Exit;
  M:=Temp; LoadNeural:=True
end;

function SaveBayes(FileName: TFileName; var M: TBayesModel): Boolean;
begin
  SaveBayes:=False;
  if not CheckBayes(M) then Exit;
  SaveBayes:=SaveRaw(FileName,8,SizeOf(M),M)
end;
function LoadBayes(FileName: TFileName; var M: TBayesModel): Boolean;
var Temp: TBayesModel;
begin
  LoadBayes:=False;
  if not LoadRaw(FileName,8,SizeOf(Temp),Temp) then Exit;
  if not CheckBayes(Temp) then Exit;
  M:=Temp; LoadBayes:=True
end;

function SaveTree(FileName: TFileName; var M: TTreeModel): Boolean;
begin
  SaveTree:=False;
  if not CheckTree(M) then Exit;
  SaveTree:=SaveRaw(FileName,9,SizeOf(M),M)
end;
function LoadTree(FileName: TFileName; var M: TTreeModel): Boolean;
var Temp: TTreeModel;
begin
  LoadTree:=False;
  if not LoadRaw(FileName,9,SizeOf(Temp),Temp) then Exit;
  if not CheckTree(Temp) then Exit;
  M:=Temp; LoadTree:=True
end;

function SaveVocabulary(FileName: TFileName; var M: TTextModel): Boolean;
begin
  SaveVocabulary:=False;
  if not CheckTextModel(M) then Exit;
  SaveVocabulary:=SaveRaw(FileName,10,SizeOf(M),M)
end;
function LoadVocabulary(FileName: TFileName; var M: TTextModel): Boolean;
var Temp: TTextModel;
begin
  LoadVocabulary:=False;
  if not LoadRaw(FileName,10,SizeOf(Temp),Temp) then Exit;
  if not CheckTextModel(Temp) then Exit;
  M:=Temp; LoadVocabulary:=True
end;

function SaveRules(FileName: TFileName; var M: TRuleSet): Boolean;
begin
  SaveRules:=False;
  if not CheckRules(M) then Exit;
  SaveRules:=SaveRaw(FileName,11,SizeOf(M),M)
end;
function LoadRules(FileName: TFileName; var M: TRuleSet): Boolean;
var Temp: TRuleSet;
begin
  LoadRules:=False;
  if not LoadRaw(FileName,11,SizeOf(Temp),Temp) then Exit;
  if not CheckRules(Temp) then Exit;
  M:=Temp; LoadRules:=True
end;

function SaveFacts(FileName: TFileName; var M: TFacts): Boolean;
begin
  SaveFacts:=False;
  if not CheckFacts(M) then Exit;
  SaveFacts:=SaveRaw(FileName,12,SizeOf(M),M)
end;
function LoadFacts(FileName: TFileName; var M: TFacts): Boolean;
var Temp: TFacts;
begin
  LoadFacts:=False;
  if not LoadRaw(FileName,12,SizeOf(Temp),Temp) then Exit;
  if not CheckFacts(Temp) then Exit;
  M:=Temp; LoadFacts:=True
end;

function SaveGrid(FileName: TFileName; var M: TGrid): Boolean;
begin
  SaveGrid:=False;
  if not CheckGrid(M) then Exit;
  SaveGrid:=SaveRaw(FileName,13,SizeOf(M),M)
end;
function LoadGrid(FileName: TFileName; var M: TGrid): Boolean;
var Temp: TGrid;
begin
  LoadGrid:=False;
  if not LoadRaw(FileName,13,SizeOf(Temp),Temp) then Exit;
  if not CheckGrid(Temp) then Exit;
  M:=Temp; LoadGrid:=True
end;

function SaveFuzzy(FileName: TFileName; var M: TFuzzySystem): Boolean;
begin
  SaveFuzzy:=False;
  if not CheckFuzzy(M) then Exit;
  SaveFuzzy:=SaveRaw(FileName,14,SizeOf(M),M)
end;
function LoadFuzzy(FileName: TFileName; var M: TFuzzySystem): Boolean;
var Temp: TFuzzySystem;
begin
  LoadFuzzy:=False;
  if not LoadRaw(FileName,14,SizeOf(Temp),Temp) then Exit;
  if not CheckFuzzy(Temp) then Exit;
  M:=Temp; LoadFuzzy:=True
end;

function SaveQ(FileName: TFileName; var M: TQModel): Boolean;
begin
  SaveQ:=False;
  if not CheckQ(M) then Exit;
  SaveQ:=SaveRaw(FileName,15,SizeOf(M),M)
end;
function LoadQ(FileName: TFileName; var M: TQModel): Boolean;
var Temp: TQModel;
begin
  LoadQ:=False;
  if not LoadRaw(FileName,15,SizeOf(Temp),Temp) then Exit;
  if not CheckQ(Temp) then Exit;
  M:=Temp; LoadQ:=True
end;

function GoodStoredData(var D: TDataSet): Boolean;
var J: Integer;
begin
  GoodStoredData:=False;
  if not CheckData(D,False) then Exit;
  if Length(D.TargetName)>31 then begin
    SetAIError(ErrFormat,'Panjang nama target tidak valid'); Exit
  end;
  for J:=1 to D.Features do if Length(D.Names[J])>31 then begin
    SetAIError(ErrFormat,'Panjang nama fitur tidak valid'); Exit
  end;
  GoodStoredData:=True
end;
function SaveKNN(FileName: TFileName; var M: TKNNModel): Boolean;
var P: Pointer; Store: PKNNStore; Temp: TKNNModel; OK: Boolean;
begin
  ClearAIError; SaveKNN:=False;
  if not M.Fitted or (M.Data=nil) then begin SetAIError(ErrModel,'KNN belum dilatih'); Exit end;
  if not GoodStoredData(M.Data^) then Exit;
  if not FitKNN(M.Data^,M.K,Temp) then Exit;
  if (Temp.Count<>M.Count) or (Temp.Features<>M.Features) or
     (Temp.TargetKind<>M.TargetKind) then begin SetAIError(ErrModel,'Metadata KNN berubah'); Exit end;
  if not NewBuffer(SizeOf(TKNNStore),P) then Exit;
  Store:=P; FillChar(Store^,SizeOf(TKNNStore),0);
  Store^.K:=M.K; Store^.Data:=M.Data^;
  OK:=SaveRaw(FileName,16,SizeOf(TKNNStore),Store^);
  FreeMem(P,SizeOf(TKNNStore)); SaveKNN:=OK
end;
function LoadKNN(FileName: TFileName; var Storage: TDataSet;
  var M: TKNNModel): Boolean;
var P: Pointer; Store: PKNNStore; Temp: TKNNModel; OK: Boolean;
begin
  ClearAIError; LoadKNN:=False;
  if not NewBuffer(SizeOf(TKNNStore),P) then Exit;
  Store:=P;
  OK:=LoadRaw(FileName,16,SizeOf(TKNNStore),Store^);
  if OK then OK:=GoodStoredData(Store^.Data);
  if OK then OK:=FitKNN(Store^.Data,Store^.K,Temp);
  if OK then begin
    Storage:=Store^.Data; Temp.Data:=@Storage; M:=Temp
  end;
  FreeMem(P,SizeOf(TKNNStore)); LoadKNN:=OK
end;
end.
