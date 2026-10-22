unit AIText;
{$B-}
interface
uses AITypes;
const MaxDocuments=32; MaxTokens=64; MaxCandidates=128;
type
  TWord = string[31];
  TTokens = record Count: Integer; Words: array[1..MaxTokens] of TWord end;
  TCorpus = record
    Count: Integer;
    Docs: array[1..MaxDocuments] of string;
    Labels: array[1..MaxDocuments] of Integer;
  end;
  TTextModel = record
    Fitted,UseIDF,Normalize: Boolean;
    Count,Documents: Integer;
    Terms: array[1..MaxFeatures] of TWord;
    IDF: TVector;
  end;
function Tokenize(S: string; var Tokens: TTokens): Boolean;
function LoadCorpus(FileName: TFileName; var Corpus: TCorpus): Boolean;
function CheckTextModel(var M: TTextModel): Boolean;
function FitText(var Corpus: TCorpus; Limit,MinDocumentFreq: Integer;
  UseIDF,Normalize: Boolean; var M: TTextModel): Boolean;
function Vectorize(var M: TTextModel; S: string; var V: TVector): Boolean;
function VectorizeCorpus(var M: TTextModel; var Corpus: TCorpus;
  var D: TDataSet): Boolean;
implementation
function IsWord(C: Char): Boolean;
begin IsWord:=((C>='a') and (C<='z')) or ((C>='A') and (C<='Z')) or ((C>='0') and (C<='9')) end;
function Tokenize(S: string; var Tokens: TTokens): Boolean;
var I: Integer; C: Char; W: TWord;
  function Push: Boolean;
  begin
    Push:=False;
    if W<>'' then begin
      if Tokens.Count=MaxTokens then begin SetAIError(ErrSize,'Dokumen melebihi 64 token'); Exit end;
      Inc(Tokens.Count); Tokens.Words[Tokens.Count]:=W; W:=''
    end;
    Push:=True
  end;
begin
  ClearAIError; FillChar(Tokens,SizeOf(Tokens),0); Tokenize:=False; W:='';
  for I:=1 to Length(S) do begin
    C:=S[I];
    if Ord(C)>127 then begin SetAIError(ErrFormat,'Tokenizer hanya mendukung teks ASCII'); Exit end;
    if IsWord(C) then begin
      if (C>='A') and (C<='Z') then C:=Chr(Ord(C)+32);
      if Length(W)=31 then begin SetAIError(ErrSize,'Token melebihi 31 karakter'); Exit end;
      W:=W+C
    end else if not Push then Exit
  end;
  if not Push then Exit;
  Tokenize:=True
end;
function LoadCorpus(FileName: TFileName; var Corpus: TCorpus): Boolean;
var F: Text; S: string; C: Char; E,N: Integer; OK,TooLong: Boolean;
begin
  ClearAIError; FillChar(Corpus,SizeOf(Corpus),0); LoadCorpus:=False;
  Assign(F,FileName); {$I-} Reset(F); E:=IOResult; {$I+}
  if E<>0 then begin SetAIError(ErrIO,'Berkas corpus tidak terbuka'); Exit end;
  OK:=True;
  while not Eof(F) do begin
    S:=''; TooLong:=False;
    {$I-}
    while not Eoln(F) do begin
      Read(F,C);
      if Length(S)<255 then S:=S+C else TooLong:=True
    end;
    ReadLn(F); E:=IOResult;
    {$I+}
    if (E<>0) or TooLong then begin SetAIError(ErrFormat,'Baris corpus terlalu panjang atau gagal dibaca'); OK:=False; Break end;
    if S<>'' then begin
      if (Length(S)<3) or (S[1]<'0') or (S[1]>'9') or (S[2]<>#9) then begin
        SetAIError(ErrFormat,'Format corpus: satu digit kelas, TAB, teks'); OK:=False; Break
      end;
      if Corpus.Count=MaxDocuments then begin SetAIError(ErrSize,'Corpus melebihi 32 dokumen'); OK:=False; Break end;
      Inc(Corpus.Count); N:=Corpus.Count;
      Corpus.Labels[N]:=Ord(S[1])-Ord('0'); Corpus.Docs[N]:=Copy(S,3,253)
    end
  end;
  {$I-} Close(F); E:=IOResult; {$I+}
  if E<>0 then begin SetAIError(ErrIO,'Gagal menutup corpus'); OK:=False end;
  if OK and (Corpus.Count=0) then begin SetAIError(ErrSize,'Corpus kosong'); OK:=False end;
  if not OK then begin Corpus.Count:=0; Exit end;
  LoadCorpus:=True
end;
function CheckTextModel(var M: TTextModel): Boolean;
var I,J: Integer; T: TTokens;
begin
  ClearAIError; CheckTextModel:=False;
  if not M.Fitted or (M.Count<1) or (M.Count>MaxFeatures) or
     (M.Documents<1) or (M.Documents>MaxDocuments) then begin
    SetAIError(ErrModel,'Vocabulary tidak valid'); Exit
  end;
  for I:=1 to M.Count do begin
    if Length(M.Terms[I])>31 then begin SetAIError(ErrModel,'Panjang istilah tidak valid'); Exit end;
    if not Tokenize(M.Terms[I],T) then Exit;
    if (T.Count<>1) or (T.Words[1]<>M.Terms[I]) or
       not ValidNumber(M.IDF[I]) or (M.IDF[I]<1) or (M.IDF[I]>5) then begin
      SetAIError(ErrModel,'Istilah atau IDF tidak valid'); Exit
    end;
    for J:=1 to I-1 do if M.Terms[J]=M.Terms[I] then begin
      SetAIError(ErrModel,'Vocabulary duplikat'); Exit
    end
  end;
  CheckTextModel:=True
end;
function FitText(var Corpus: TCorpus; Limit,MinDocumentFreq: Integer;
  UseIDF,Normalize: Boolean; var M: TTextModel): Boolean;
var Words: array[1..MaxCandidates] of TWord;
    DF,LastDoc: array[1..MaxCandidates] of Integer;
    Used: array[1..MaxCandidates] of Boolean;
    T: TTokens; N,I,J,K,Index,Best: Integer; Ratio: TFloat;
begin
  FillChar(M,SizeOf(M),0); FitText:=False; ClearAIError;
  if (Corpus.Count<1) or (Corpus.Count>MaxDocuments) or
     (Limit<1) or (Limit>MaxFeatures) or
     (MinDocumentFreq<1) or (MinDocumentFreq>Corpus.Count) then begin
    SetAIError(ErrSize,'Ukuran corpus/vocabulary/min-df tidak valid'); Exit
  end;
  N:=0; FillChar(DF,SizeOf(DF),0); FillChar(LastDoc,SizeOf(LastDoc),0);
  FillChar(Used,SizeOf(Used),0);
  for I:=1 to Corpus.Count do begin
    if not Tokenize(Corpus.Docs[I],T) then Exit;
    for J:=1 to T.Count do begin
      Index:=0;
      for K:=1 to N do if Words[K]=T.Words[J] then begin Index:=K; Break end;
      if Index=0 then begin
        if N=MaxCandidates then begin SetAIError(ErrSize,'Corpus melebihi 128 kata unik'); Exit end;
        Inc(N); Index:=N; Words[Index]:=T.Words[J]
      end;
      if LastDoc[Index]<>I then begin Inc(DF[Index]); LastDoc[Index]:=I end
    end
  end;
  for J:=1 to Limit do begin
    Best:=0;
    for K:=1 to N do if not Used[K] and (DF[K]>=MinDocumentFreq) then begin
      if Best=0 then Best:=K
      else if (DF[K]>DF[Best]) or ((DF[K]=DF[Best]) and (Words[K]<Words[Best])) then Best:=K
    end;
    if Best=0 then Break;
    Used[Best]:=True; Inc(M.Count); M.Terms[M.Count]:=Words[Best];
    Ratio:=Corpus.Count+1; Ratio:=Ratio/(DF[Best]+1);
    M.IDF[M.Count]:=Ln(Ratio)+1
  end;
  if M.Count=0 then begin SetAIError(ErrValue,'Tidak ada kata yang memenuhi min-df'); Exit end;
  M.UseIDF:=UseIDF; M.Normalize:=Normalize; M.Documents:=Corpus.Count;
  M.Fitted:=True; FitText:=True
end;
function Vectorize(var M: TTextModel; S: string; var V: TVector): Boolean;
var T: TTokens; I,J: Integer; Norm: TFloat;
begin
  FillChar(V,SizeOf(V),0); Vectorize:=False;
  if not CheckTextModel(M) then Exit;
  if not Tokenize(S,T) then Exit;
  for I:=1 to T.Count do for J:=1 to M.Count do
    if T.Words[I]=M.Terms[J] then V[J]:=V[J]+1;
  Norm:=0;
  for J:=1 to M.Count do begin
    if M.UseIDF then V[J]:=V[J]*M.IDF[J]; Norm:=Norm+Sqr(V[J])
  end;
  if M.Normalize and (Norm>0) then begin
    Norm:=Sqrt(Norm); for J:=1 to M.Count do V[J]:=V[J]/Norm
  end;
  Vectorize:=True
end;
function VectorizeCorpus(var M: TTextModel; var Corpus: TCorpus;
  var D: TDataSet): Boolean;
var I,J: Integer;
begin
  VectorizeCorpus:=False; InitData(D,0,TargetClass);
  if not CheckTextModel(M) then Exit;
  if (Corpus.Count<1) or (Corpus.Count>MaxDocuments) then begin
    SetAIError(ErrSize,'Corpus kosong atau terlalu besar'); Exit
  end;
  for I:=1 to Corpus.Count do if (Corpus.Labels[I]<0) or (Corpus.Labels[I]>=MaxClasses) then begin
    SetAIError(ErrValue,'Label corpus harus 0..9'); Exit
  end;
  D.Features:=M.Count;
  for J:=1 to M.Count do D.Names[J]:=M.Terms[J];
  for I:=1 to Corpus.Count do begin
    if not Vectorize(M,Corpus.Docs[I],D.X[I]) then begin D.Count:=0; Exit end;
    D.Labels[I]:=Corpus.Labels[I]
  end;
  D.Count:=Corpus.Count; VectorizeCorpus:=True
end;
end.
