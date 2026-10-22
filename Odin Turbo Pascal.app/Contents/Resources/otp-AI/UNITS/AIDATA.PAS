unit AIData;
{$B-}
interface
uses AITypes;
function LoadCSV(FileName: TFileName; HasHeader: Boolean;
  TargetKind: Integer; var D: TDataSet): Boolean;
function SaveCSV(FileName: TFileName; var D: TDataSet): Boolean;
function GetColumn(var D: TDataSet; Col: Integer;
  var Values: TSeries): Boolean;
function SelectColumns(var Source: TDataSet; var Columns: TIndexList;
  N: Integer; var Dest: TDataSet): Boolean;
function FilterRange(var Source: TDataSet; Col: Integer;
  Minimum, Maximum: TFloat; var Dest: TDataSet): Boolean;
procedure CopyRow(var Source: TDataSet; SourceRow: Integer;
  var Dest: TDataSet; DestRow: Integer);
procedure DescribeData(var D: TDataSet);

function FitImputer(var D: TDataSet; var M: TImputer): Boolean;
function ImputeData(var M: TImputer; var D: TDataSet): Boolean;
function FitScaler(var D: TDataSet; Kind: Integer;
  var S: TScaler): Boolean;
function TransformData(var S: TScaler; var D: TDataSet): Boolean;
function TransformVector(var S: TScaler; var V: TVector): Boolean;
function InverseVector(var S: TScaler; var V: TVector): Boolean;
procedure InitCategories(var Map: TCategoryMap);
function AddCategory(var Map: TCategoryMap; Name: TName;
  var Code: Integer): Boolean;
function EncodeCategory(var Map: TCategoryMap; Name: TName;
  var Code: Integer): Boolean;
function OneHot(Code, Count: Integer; var V: TVector): Boolean;
implementation
uses AIStats;
type
  TCell = string[63];
  TCells = array[1..MaxFeatures+1] of TCell;
function TrimCell(S: string): string;
begin
  while Length(S) > 0 do begin
    if S[1] > ' ' then Break;
    Delete(S,1,1)
  end;
  while Length(S) > 0 do begin
    if S[Length(S)] > ' ' then Break;
    Delete(S,Length(S),1)
  end;
  TrimCell := S
end;
function ReadLineSafe(var F: Text; var S: string): Boolean;
var C: Char; TooLong: Boolean; E: Integer;
begin
  S := ''; TooLong := False;
  {$I-}
  while not Eoln(F) do begin
    Read(F,C);
    if Length(S) < 255 then S := S+C else TooLong := True
  end;
  ReadLn(F); E := IOResult;
  {$I+}
  ReadLineSafe := False;
  if E <> 0 then begin SetAIError(ErrIO,'Gagal membaca CSV'); Exit end;
  if TooLong then begin
    SetAIError(ErrFormat,'Baris CSV melebihi 255 karakter'); Exit
  end;
  ReadLineSafe := True
end;
function SplitCSV(S: string; var Cells: TCells;
  var N: Integer): Boolean;
var I,State: Integer; C: Char; Token: TCell;
  function AddChar(C: Char): Boolean;
  begin
    AddChar := False;
    if Length(Token) >= 63 then begin
      SetAIError(ErrFormat,'Kolom CSV melebihi 63 karakter'); Exit
    end;
    Token := Token+C; AddChar := True
  end;
  function Finish: Boolean;
  begin
    Finish := False;
    if N >= MaxFeatures+1 then begin
      SetAIError(ErrFormat,'Terlalu banyak kolom CSV'); Exit
    end;
    Inc(N); Cells[N] := TrimCell(Token); Token := ''; Finish := True
  end;
begin
  { State: 0 awal, 1 tanpa kutip, 2 di dalam kutip, 3 kutip tutup. }
  SplitCSV := False; N := 0; I := 1; State := 0; Token := '';
  while I <= Length(S) do begin
    C := S[I];
    case State of
      0: if C = '"' then State := 2
         else if C = ',' then begin if not Finish then Exit end
         else if C > ' ' then begin
           if not AddChar(C) then Exit; State := 1
         end;
      1: if C = ',' then begin
           if not Finish then Exit; State := 0
         end else if C = '"' then begin
           SetAIError(ErrFormat,'Kutip di tengah kolom tanpa kutip'); Exit
         end else if not AddChar(C) then Exit;
      2: if C = '"' then begin
           if I < Length(S) then begin
             if S[I+1] = '"' then begin
               if not AddChar('"') then Exit; Inc(I)
             end else State := 3
           end else State := 3
         end else if not AddChar(C) then Exit;
      3: if C = ',' then begin
           if not Finish then Exit; State := 0
         end else if C > ' ' then begin
           SetAIError(ErrFormat,'Karakter setelah kutip penutup'); Exit
         end
    end;
    Inc(I)
  end;
  if State = 2 then begin
    SetAIError(ErrFormat,'Kutip CSV belum ditutup'); Exit
  end;
  if not Finish then Exit;
  SplitCSV := True
end;
function ParseNumber(S: TCell; var V: TFloat): Boolean;
var I,Sign,ESign,E,Digits,EDigits,FractionDigits: Integer;
    Fraction: Boolean; Place: TFloat; C: Char;
begin
  { Parser desimal terkontrol, tidak memanggil Val pada eksponen liar. }
  ParseNumber := False; V := 0; I := 1; Sign := 1;
  ESign := 1; E := 0; Digits := 0; Fraction := False; Place := 1; FractionDigits := 0;
  S := TrimCell(S);
  if Length(S) = 0 then Exit;
  if (S[I] = '+') or (S[I] = '-') then begin
    if S[I] = '-' then Sign := -1; Inc(I)
  end;
  while I <= Length(S) do begin
    C := S[I];
    if (C = 'e') or (C = 'E') then Break;
    if C = '.' then begin
      if Fraction then Exit;
      Fraction := True
    end else if (C >= '0') and (C <= '9') then begin
      Inc(Digits);
      if Fraction then begin
        Inc(FractionDigits); if FractionDigits > 30 then Exit;
        Place := Place/10;
        if Place >= 1.0E-30 then V := V+(Ord(C)-Ord('0'))*Place
      end else begin
        V := V*10+(Ord(C)-Ord('0'));
        if V > AIInputLimit then Exit
      end
    end else Exit;
    Inc(I)
  end;
  if Digits = 0 then Exit;
  if I <= Length(S) then begin
    Inc(I);
    if I <= Length(S) then
      if (S[I] = '+') or (S[I] = '-') then begin
        if S[I] = '-' then ESign := -1; Inc(I)
      end;
    EDigits := 0;
    while I <= Length(S) do begin
      C := S[I];
      if (C < '0') or (C > '9') then Exit;
      Inc(EDigits); E := E*10+Ord(C)-Ord('0');
      if E > 30 then Exit;
      Inc(I)
    end;
    if EDigits = 0 then Exit
  end;
  for I := 1 to E do
    if ESign > 0 then begin
      if V > AIInputLimit/10 then Exit;
      V := V*10
    end else begin
      if (V > 0) and (V < 1.0E-29) then Exit;
      V := V/10
    end;
  V := V*Sign;
  ParseNumber := ValidNumber(V)
end;
function LoadCSV(FileName: TFileName; HasHeader: Boolean;
  TargetKind: Integer; var D: TDataSet): Boolean;
var F: Text; S: string; Cells: TCells;
    N,Expected,J,E,LineNo,Row: Integer;
    HeaderDone,OK: Boolean; V: TFloat; Detail,Num: string[80];
begin
  ClearAIError; InitData(D,0,TargetKind); LoadCSV := False;
  if (TargetKind < TargetNone) or (TargetKind > TargetClass) then begin
    SetAIError(ErrValue,'Jenis target CSV tidak valid'); Exit
  end;
  Assign(F,FileName); {$I-} Reset(F); E := IOResult; {$I+}
  if E <> 0 then begin SetAIError(ErrIO,'Berkas CSV tidak terbuka'); Exit end;
  OK := True; Expected := 0; HeaderDone := not HasHeader; LineNo := 0;
  while not Eof(F) do begin
    Inc(LineNo);
    if not ReadLineSafe(F,S) then begin OK := False; Break end;
    if TrimCell(S) <> '' then begin
      if not SplitCSV(S,Cells,N) then begin OK := False; Break end;
      if Expected = 0 then begin
        Expected := N; D.Features := N;
        if TargetKind <> TargetNone then Dec(D.Features);
        if (D.Features < 1) or (D.Features > MaxFeatures) then begin
          SetAIError(ErrFormat,'CSV memerlukan 1..8 kolom fitur');
          OK := False; Break
        end
      end;
      if N <> Expected then begin
        SetAIError(ErrFormat,'Jumlah kolom CSV tidak konsisten');
        OK := False; Break
      end;
      if not HeaderDone then begin
        for J := 1 to N do if Length(Cells[J]) > 31 then begin
          SetAIError(ErrFormat,'Nama kolom CSV melebihi 31 karakter');
          OK := False; Break
        end;
        if not OK then Break;
        for J := 1 to D.Features do D.Names[J] := Cells[J];
        if TargetKind <> TargetNone then D.TargetName := Cells[N];
        HeaderDone := True
      end else begin
        if D.Count >= MaxSamples then begin
          SetAIError(ErrSize,'CSV melebihi 200 baris data'); OK := False; Break
        end;
        Row := D.Count+1;
        for J := 1 to D.Features do begin
          D.Missing[Row,J] := (Cells[J] = '') or (Cells[J] = '?');
          if not D.Missing[Row,J] then begin
            if not ParseNumber(Cells[J],V) then begin
              SetAIError(ErrFormat,'Fitur CSV bukan angka yang didukung');
              OK := False; Break
            end;
            D.X[Row,J] := V
          end
        end;
        if not OK then Break;
        if TargetKind <> TargetNone then begin
          if not ParseNumber(Cells[N],V) then begin
            SetAIError(ErrFormat,'Target CSV harus berisi angka');
            OK := False; Break
          end;
          if TargetKind = TargetReal then D.Y[Row] := V
          else begin
            if (V < 0) or (V >= MaxClasses) then begin
              SetAIError(ErrFormat,'Label CSV harus 0..9'); OK := False; Break
            end;
            if V <> Trunc(V) then begin
              SetAIError(ErrFormat,'Label CSV harus bilangan bulat');
              OK := False; Break
            end;
            D.Labels[Row] := Trunc(V)
          end
        end;
        Inc(D.Count)
      end
    end
  end;
  {$I-} Close(F); E := IOResult; {$I+}
  if OK and (E <> 0) then begin
    SetAIError(ErrIO,'Gagal menutup CSV'); OK := False
  end;
  if OK then OK := CheckData(D,True);
  if not OK then begin
    Detail := AIError; Str(LineNo,Num);
    SetAIError(AIErrorCode,'Baris '+Num+': '+Detail);
    InitData(D,0,TargetKind); Exit
  end;
  LoadCSV := True
end;
{$I-}
procedure WriteName(var F: Text; S: TName);
var I: Integer;
begin
  Write(F,'"');
  for I := 1 to Length(S) do begin
    if S[I] = '"' then Write(F,'"');
    Write(F,S[I])
  end;
  Write(F,'"')
end;
{$I+}
function SaveCSV(FileName: TFileName; var D: TDataSet): Boolean;
var F: Text; I,J,K,E,CloseErr,HeaderLen: Integer; S: TName;
begin
  SaveCSV := False;
  if not CheckData(D,True) then Exit;
  HeaderLen := D.Features-1;
  if D.TargetKind <> TargetNone then Inc(HeaderLen);
  for J := 1 to D.Features+Ord(D.TargetKind <> TargetNone) do begin
    if J <= D.Features then S := D.Names[J] else S := D.TargetName;
    Inc(HeaderLen,Length(S)+2);
    for K := 1 to Length(S) do if S[K] = '"' then Inc(HeaderLen)
  end;
  if HeaderLen > 255 then begin
    SetAIError(ErrFormat,'Header CSV terlalu panjang, pendekkan nama kolom'); Exit
  end;
  for I := 1 to D.Count do begin
    for J := 1 to D.Features do
      if not D.Missing[I,J] and (D.X[I,J] <> 0) then
        if Abs(D.X[I,J]) < 1.0E-30 then begin
          SetAIError(ErrValue,'CSV tidak mendukung angka di bawah 1E-30'); Exit
        end;
    if (D.TargetKind = TargetReal) and (D.Y[I] <> 0) then
      if Abs(D.Y[I]) < 1.0E-30 then begin
        SetAIError(ErrValue,'CSV tidak mendukung target di bawah 1E-30'); Exit
      end
  end;
  Assign(F,FileName); {$I-} Rewrite(F); E := IOResult; {$I+}
  if E <> 0 then begin SetAIError(ErrIO,'CSV tidak dapat dibuat'); Exit end;
  {$I-}
  for J := 1 to D.Features do begin
    if J > 1 then Write(F,','); WriteName(F,D.Names[J])
  end;
  if D.TargetKind <> TargetNone then begin
    Write(F,','); WriteName(F,D.TargetName)
  end;
  WriteLn(F);
  for I := 1 to D.Count do begin
    for J := 1 to D.Features do begin
      if J > 1 then Write(F,',');
      if not D.Missing[I,J] then Write(F,D.X[I,J]:24)
    end;
    if D.TargetKind = TargetReal then Write(F,',',D.Y[I]:24);
    if D.TargetKind = TargetClass then Write(F,',',D.Labels[I]);
    WriteLn(F)
  end;
  E := IOResult; Close(F); CloseErr := IOResult;
  {$I+}
  if (E <> 0) or (CloseErr <> 0) then begin
    SetAIError(ErrIO,'Gagal menulis CSV'); Exit
  end;
  SaveCSV := True
end;
function GetColumn(var D: TDataSet; Col: Integer;
  var Values: TSeries): Boolean;
var I: Integer;
begin
  GetColumn := False; FillChar(Values,SizeOf(Values),0);
  if not CheckData(D,True) then Exit;
  if (Col < 1) or (Col > D.Features) then begin
    SetAIError(ErrSize,'Kolom di luar dataset'); Exit
  end;
  for I := 1 to D.Count do begin
    if D.Missing[I,Col] then begin
      SetAIError(ErrMissing,'Kolom berisi data kosong'); Exit
    end;
    Values[I] := D.X[I,Col]
  end;
  GetColumn := True
end;
procedure CopyRow(var Source: TDataSet; SourceRow: Integer;
  var Dest: TDataSet; DestRow: Integer);
var J: Integer;
begin
  ClearAIError;
  if (Source.Count < 1) or (Source.Count > MaxSamples) or
     (Source.Features < 1) or (Source.Features > MaxFeatures) or
     (SourceRow < 1) or (SourceRow > Source.Count) or
     (DestRow < 1) or (DestRow > MaxSamples) or
     (Dest.Features <> Source.Features) or
     (Dest.TargetKind <> Source.TargetKind) then begin
    SetAIError(ErrSize,'Indeks atau dimensi CopyRow tidak valid'); Exit
  end;
  Dest.X[DestRow] := Source.X[SourceRow];
  Dest.Y[DestRow] := Source.Y[SourceRow];
  Dest.Labels[DestRow] := Source.Labels[SourceRow];
  for J := 1 to Source.Features do
    Dest.Missing[DestRow,J] := Source.Missing[SourceRow,J]
end;
function SelectColumns(var Source: TDataSet; var Columns: TIndexList;
  N: Integer; var Dest: TDataSet): Boolean;
var I,J: Integer;
begin
  SelectColumns := False;
  if not CheckData(Source,True) then Exit;
  if @Source = @Dest then begin
    SetAIError(ErrValue,'SelectColumns memerlukan dataset tujuan terpisah'); Exit
  end;
  if (N < 1) or (N > MaxFeatures) then begin
    SetAIError(ErrSize,'Jumlah kolom pilihan tidak valid'); Exit
  end;
  for J := 1 to N do
    if (Columns[J] < 1) or (Columns[J] > Source.Features) then begin
      SetAIError(ErrSize,'Indeks kolom pilihan tidak valid'); Exit
    end;
  InitData(Dest,N,Source.TargetKind); Dest.Count := Source.Count;
  Dest.TargetName := Source.TargetName;
  for J := 1 to N do Dest.Names[J] := Source.Names[Columns[J]];
  for I := 1 to Source.Count do begin
    Dest.Y[I] := Source.Y[I]; Dest.Labels[I] := Source.Labels[I];
    for J := 1 to N do begin
      Dest.X[I,J] := Source.X[I,Columns[J]];
      Dest.Missing[I,J] := Source.Missing[I,Columns[J]]
    end
  end;
  SelectColumns := True
end;
function FilterRange(var Source: TDataSet; Col: Integer;
  Minimum, Maximum: TFloat; var Dest: TDataSet): Boolean;
var I: Integer;
begin
  FilterRange := False;
  if not CheckData(Source,True) then Exit;
  if @Source = @Dest then begin
    SetAIError(ErrValue,'FilterRange memerlukan dataset tujuan terpisah'); Exit
  end;
  if (Col < 1) or (Col > Source.Features) then begin
    SetAIError(ErrSize,'Kolom filter tidak valid'); Exit
  end;
  if not ValidNumber(Minimum) or not ValidNumber(Maximum) or
     (Minimum > Maximum) then begin
    SetAIError(ErrValue,'Batas filter tidak valid'); Exit
  end;
  InitData(Dest,Source.Features,Source.TargetKind);
  Dest.Names := Source.Names; Dest.TargetName := Source.TargetName;
  for I := 1 to Source.Count do
    if not Source.Missing[I,Col] then
      if (Source.X[I,Col] >= Minimum) and
         (Source.X[I,Col] <= Maximum) then begin
        Inc(Dest.Count); CopyRow(Source,I,Dest,Dest.Count)
      end;
  { Hasil kosong tetap sukses; algoritma model menolaknya. }
  FilterRange := True
end;
procedure DescribeData(var D: TDataSet);
var J,I,N,MissingCount: Integer; A: TSeries; Avg,SD,Lo,Hi: TFloat;
    OK: Boolean;
begin
  if not CheckData(D,True) then begin WriteLn(AIError); Exit end;
  WriteLn('Baris: ',D.Count,'  Fitur: ',D.Features,
    '  Jenis target: ',D.TargetKind);
  for J := 1 to D.Features do begin
    N := 0; MissingCount := 0;
    for I := 1 to D.Count do
      if D.Missing[I,J] then Inc(MissingCount)
      else begin Inc(N); A[N] := D.X[I,J] end;
    Write(D.Names[J],': terisi=',N,' kosong=',MissingCount);
    if N > 0 then begin
      OK := Mean(A,N,Avg); OK := StdDev(A,N,False,SD);
      OK := MinMax(A,N,Lo,Hi);
      if OK then Write(' mean=',Avg:0:3,' sd=',SD:0:3,
        ' min=',Lo:0:3,' max=',Hi:0:3)
    end;
    WriteLn
  end
end;

function FitImputer(var D: TDataSet; var M: TImputer): Boolean;
var I,J,N: Integer;
begin
  FillChar(M,SizeOf(M),0); FitImputer := False;
  if not CheckData(D,True) then Exit;
  for J := 1 to D.Features do begin
    N := 0;
    for I := 1 to D.Count do if not D.Missing[I,J] then begin
      Inc(N); M.Means[J] := M.Means[J]+(D.X[I,J]-M.Means[J])/N
    end;
    if N = 0 then begin
      SetAIError(ErrMissing,'Seluruh isi kolom latih kosong'); Exit
    end
  end;
  M.Features := D.Features; M.Fitted := True; FitImputer := True
end;
function ImputeData(var M: TImputer; var D: TDataSet): Boolean;
var I,J: Integer;
begin
  ImputeData := False;
  if not CheckData(D,True) then Exit;
  if not M.Fitted or (M.Features <> D.Features) then begin
    SetAIError(ErrModel,'Imputer belum dilatih atau dimensi berbeda'); Exit
  end;
  if not CheckVector(M.Means,M.Features) then Exit;
  for I := 1 to D.Count do for J := 1 to D.Features do
    if D.Missing[I,J] then begin
      D.X[I,J] := M.Means[J]; D.Missing[I,J] := False
    end;
  ImputeData := True
end;
function FitScaler(var D: TDataSet; Kind: Integer;
  var S: TScaler): Boolean;
var I,J: Integer; Mean,M2,Delta,Lo,Hi: TFloat;
begin
  FillChar(S,SizeOf(S),0); FitScaler := False;
  if not CheckData(D,False) then Exit;
  if (Kind <> ScaleMinMax) and (Kind <> ScaleStandard) then begin
    SetAIError(ErrValue,'Jenis scaler tidak dikenal'); Exit
  end;
  for J := 1 to D.Features do begin
    Mean := 0; M2 := 0; Lo := D.X[1,J]; Hi := Lo;
    for I := 1 to D.Count do begin
      Delta := D.X[I,J]-Mean; Mean := Mean+Delta/I;
      M2 := M2+Delta*(D.X[I,J]-Mean);
      if D.X[I,J] < Lo then Lo := D.X[I,J];
      if D.X[I,J] > Hi then Hi := D.X[I,J]
    end;
    if Kind = ScaleMinMax then begin
      S.Offset[J] := Lo; S.Divisor[J] := Hi-Lo
    end else begin
      S.Offset[J] := Mean;
      if M2 < 0 then M2 := 0;
      S.Divisor[J] := Sqrt(M2/D.Count)
    end;
    if S.Divisor[J] < AIEpsilon then S.Divisor[J] := 1
  end;
  S.Features := D.Features; S.Kind := Kind; S.Fitted := True;
  FitScaler := True
end;
function GoodScaler(var S: TScaler): Boolean;
var J: Integer;
begin
  ClearAIError; GoodScaler := False;
  if not S.Fitted or (S.Features < 1) or
     (S.Features > MaxFeatures) then begin
    SetAIError(ErrModel,'Scaler belum dilatih'); Exit
  end;
  for J := 1 to S.Features do
    if (S.Divisor[J] < AIEpsilon) or
       (S.Divisor[J] > 2*AIInputLimit) or
       (S.Divisor[J] <> S.Divisor[J]) or
       not ValidNumber(S.Offset[J]) then begin
      SetAIError(ErrModel,'Parameter scaler tidak valid'); Exit
    end;
  GoodScaler := True
end;
function TransformVector(var S: TScaler; var V: TVector): Boolean;
var J: Integer; T: TVector;
begin
  TransformVector := False;
  if not GoodScaler(S) then Exit;
  if not CheckVector(V,S.Features) then Exit;
  T := V;
  for J := 1 to S.Features do begin
    T[J] := (V[J]-S.Offset[J])/S.Divisor[J];
    if not ValidNumber(T[J]) then begin
      SetAIError(ErrValue,'Hasil normalisasi melampaui batas'); Exit
    end
  end;
  V := T; TransformVector := True
end;
function TransformData(var S: TScaler; var D: TDataSet): Boolean;
var I: Integer; V: TVector;
begin
  TransformData := False;
  if not CheckData(D,False) then Exit;
  if not GoodScaler(S) then Exit;
  if D.Features <> S.Features then begin
    SetAIError(ErrSize,'Dimensi scaler dan dataset berbeda'); Exit
  end;
  { Validasi seluruh hasil sebelum mutasi. }
  for I := 1 to D.Count do begin
    V := D.X[I]; if not TransformVector(S,V) then Exit
  end;
  for I := 1 to D.Count do
    if not TransformVector(S,D.X[I]) then Exit;
  TransformData := True
end;
function InverseVector(var S: TScaler; var V: TVector): Boolean;
var J: Integer; T: TVector;
begin
  InverseVector := False;
  if not GoodScaler(S) then Exit;
  if not CheckVector(V,S.Features) then Exit;
  T := V;
  for J := 1 to S.Features do begin
    T[J] := V[J]*S.Divisor[J]+S.Offset[J];
    if not ValidNumber(T[J]) then begin
      SetAIError(ErrValue,'Hasil invers scaler melampaui batas'); Exit
    end
  end;
  V := T; InverseVector := True
end;
procedure InitCategories(var Map: TCategoryMap);
begin ClearAIError; FillChar(Map,SizeOf(Map),0) end;
function EncodeCategory(var Map: TCategoryMap; Name: TName;
  var Code: Integer): Boolean;
var I: Integer;
begin
  ClearAIError; Code := -1; EncodeCategory := False;
  if (Map.Count < 0) or (Map.Count > MaxCategories) then begin
    SetAIError(ErrSize,'Kamus kategori rusak'); Exit
  end;
  for I := 1 to Map.Count do if Map.Names[I] = Name then begin
    Code := I-1; EncodeCategory := True; Exit
  end;
  SetAIError(ErrValue,'Kategori belum terdaftar')
end;
function AddCategory(var Map: TCategoryMap; Name: TName;
  var Code: Integer): Boolean;
begin
  AddCategory := False;
  if EncodeCategory(Map,Name,Code) then begin AddCategory := True; Exit end;
  if AIErrorCode = ErrSize then Exit;
  ClearAIError;
  if Name = '' then begin SetAIError(ErrValue,'Nama kategori kosong'); Exit end;
  if Map.Count >= MaxCategories then begin
    SetAIError(ErrSize,'Kamus kategori penuh'); Exit
  end;
  Inc(Map.Count); Map.Names[Map.Count] := Name; Code := Map.Count-1;
  AddCategory := True
end;
function OneHot(Code, Count: Integer; var V: TVector): Boolean;
begin
  ClearAIError; FillChar(V,SizeOf(V),0); OneHot := False;
  if (Count < 1) or (Count > MaxFeatures) or
     (Code < 0) or (Code >= Count) then begin
    SetAIError(ErrSize,'One-hot memerlukan kode valid dan 1..8 kategori'); Exit
  end;
  V[Code+1] := 1; OneHot := True
end;
end.
