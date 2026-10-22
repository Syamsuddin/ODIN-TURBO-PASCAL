unit AISplit;
interface
uses AITypes;
function MakeOrder(N: Integer; Shuffle: Boolean; Seed: LongInt;
  var Order: TIndexList): Boolean;
function TakeRows(var Source: TDataSet; var Order: TIndexList;
  First, Count: Integer; var Dest: TDataSet): Boolean;
function TrainTestSplit(var Source, TrainData, TestData: TDataSet;
  TestFraction: TFloat; Shuffle: Boolean; Seed: LongInt): Boolean;
function MakeFolds(N, Folds: Integer; Shuffle: Boolean; Seed: LongInt;
  var FoldOfRow: TIndexList): Boolean;
function FoldSplit(var Source: TDataSet; var FoldOfRow: TIndexList;
  Folds, TestFold: Integer; var TrainData, TestData: TDataSet): Boolean;
implementation
uses AIMath,AIData;
function MakeOrder(N: Integer; Shuffle: Boolean; Seed: LongInt;
  var Order: TIndexList): Boolean;
var I,J,T: Integer;
begin
  ClearAIError; MakeOrder := False; FillChar(Order,SizeOf(Order),0);
  if (N < 1) or (N > MaxSamples) then begin
    SetAIError(ErrSize,'Jumlah indeks harus 1..200'); Exit
  end;
  for I := 1 to N do Order[I] := I;
  if Shuffle then begin
    AISetSeed(Seed);
    for I := N downto 2 do begin
      J := AIRandomInt(I)+1;
      T := Order[I]; Order[I] := Order[J]; Order[J] := T
    end
  end;
  MakeOrder := True
end;
function TakeRows(var Source: TDataSet; var Order: TIndexList;
  First, Count: Integer; var Dest: TDataSet): Boolean;
var I,R: Integer;
begin
  TakeRows := False;
  if not CheckData(Source,True) then Exit;
  if @Source = @Dest then begin
    SetAIError(ErrValue,'Dataset sumber dan tujuan harus terpisah'); Exit
  end;
  if (First < 1) or (Count < 1) or (Count > MaxSamples) then begin
    SetAIError(ErrSize,'Rentang indeks tidak valid'); Exit
  end;
  if LongInt(First)+Count-1 > MaxSamples then begin
    SetAIError(ErrSize,'Rentang indeks melewati kapasitas'); Exit
  end;
  for I := First to First+Count-1 do
    if (Order[I] < 1) or (Order[I] > Source.Count) then begin
      SetAIError(ErrSize,'Indeks baris di luar dataset'); Exit
    end;
  InitData(Dest,Source.Features,Source.TargetKind);
  Dest.Count := Count; Dest.Names := Source.Names;
  Dest.TargetName := Source.TargetName;
  for I := 1 to Count do begin
    R := Order[First+I-1]; CopyRow(Source,R,Dest,I)
  end;
  TakeRows := True
end;
function Separate(var Source,TrainData,TestData: TDataSet): Boolean;
begin
  Separate := False;
  if (@Source = @TrainData) or (@Source = @TestData) or
     (@TrainData = @TestData) then begin
    SetAIError(ErrValue,'Split memerlukan tiga dataset terpisah'); Exit
  end;
  Separate := True
end;
function TrainTestSplit(var Source, TrainData, TestData: TDataSet;
  TestFraction: TFloat; Shuffle: Boolean; Seed: LongInt): Boolean;
var Order: TIndexList; NTest,NTrain: Integer;
begin
  TrainTestSplit := False;
  if not CheckData(Source,True) then Exit;
  if not Separate(Source,TrainData,TestData) then Exit;
  if not ValidNumber(TestFraction) or (TestFraction <= 0) or
     (TestFraction >= 1) or (Source.Count < 2) then begin
    SetAIError(ErrValue,'Split perlu >=2 baris dan fraksi antara 0 dan 1'); Exit
  end;
  NTest := Trunc(Source.Count*TestFraction+0.5);
  if NTest < 1 then NTest := 1;
  if NTest >= Source.Count then NTest := Source.Count-1;
  NTrain := Source.Count-NTest;
  if not MakeOrder(Source.Count,Shuffle,Seed,Order) then Exit;
  if not TakeRows(Source,Order,1,NTrain,TrainData) then Exit;
  if not TakeRows(Source,Order,NTrain+1,NTest,TestData) then Exit;
  TrainTestSplit := True
end;
function MakeFolds(N, Folds: Integer; Shuffle: Boolean; Seed: LongInt;
  var FoldOfRow: TIndexList): Boolean;
var Order: TIndexList; I: Integer;
begin
  ClearAIError; MakeFolds := False; FillChar(FoldOfRow,SizeOf(FoldOfRow),0);
  if (Folds < 2) or (Folds > N) then begin
    SetAIError(ErrSize,'Jumlah fold harus antara 2 dan jumlah baris'); Exit
  end;
  if not MakeOrder(N,Shuffle,Seed,Order) then Exit;
  for I := 1 to N do FoldOfRow[Order[I]] := (I-1) mod Folds+1;
  MakeFolds := True
end;
function FoldSplit(var Source: TDataSet; var FoldOfRow: TIndexList;
  Folds, TestFold: Integer; var TrainData, TestData: TDataSet): Boolean;
var I,NTest: Integer;
begin
  FoldSplit := False;
  if not CheckData(Source,True) then Exit;
  if not Separate(Source,TrainData,TestData) then Exit;
  if (Folds < 2) or (Folds > Source.Count) or
     (TestFold < 1) or (TestFold > Folds) then begin
    SetAIError(ErrSize,'Nomor fold tidak valid'); Exit
  end;
  NTest := 0;
  for I := 1 to Source.Count do begin
    if (FoldOfRow[I] < 1) or (FoldOfRow[I] > Folds) then begin
      SetAIError(ErrValue,'Pemetaan fold tidak valid'); Exit
    end;
    if FoldOfRow[I] = TestFold then Inc(NTest)
  end;
  if (NTest = 0) or (NTest = Source.Count) then begin
    SetAIError(ErrSize,'Fold menghasilkan data latih/uji kosong'); Exit
  end;
  InitData(TrainData,Source.Features,Source.TargetKind);
  InitData(TestData,Source.Features,Source.TargetKind);
  TrainData.Names := Source.Names; TestData.Names := Source.Names;
  TrainData.TargetName := Source.TargetName;
  TestData.TargetName := Source.TargetName;
  for I := 1 to Source.Count do
    if FoldOfRow[I] = TestFold then begin
      Inc(TestData.Count); CopyRow(Source,I,TestData,TestData.Count)
    end else begin
      Inc(TrainData.Count); CopyRow(Source,I,TrainData,TrainData.Count)
    end;
  FoldSplit := True
end;
end.
