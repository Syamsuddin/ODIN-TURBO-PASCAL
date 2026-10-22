program DataPrepDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AISplit;
var D,TrainData,TestData,Selected: PDataSet;
    Imputer: TImputer; Scaler: TScaler; Columns: TIndexList;
    Map: TCategoryMap; Code: Integer; V: TVector;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(TrainData));
  Need(NewData(TestData)); Need(NewData(Selected));
  Need(LoadCSV(DataPath('MISSING.CSV'),True,TargetReal,D^));
  DescribeData(D^);
  Need(TrainTestSplit(D^,TrainData^,TestData^,0.25,True,42));
  Need(FitImputer(TrainData^,Imputer));
  Need(ImputeData(Imputer,TrainData^)); Need(ImputeData(Imputer,TestData^));
  Need(FitScaler(TrainData^,ScaleStandard,Scaler));
  Need(TransformData(Scaler,TrainData^)); Need(TransformData(Scaler,TestData^));
  Need(SaveCSV('PREPTRN.CSV',TrainData^)); Need(SaveCSV('PREPTST.CSV',TestData^));
  Columns[1] := 2; Columns[2] := 1;
  Need(SelectColumns(TrainData^,Columns,2,Selected^));
  Need(FilterRange(TrainData^,1,-1,1,Selected^));
  WriteLn('Baris latih dengan fitur 1 antara -1 dan 1: ',Selected^.Count);
  InitCategories(Map);
  Need(AddCategory(Map,'MERAH',Code)); Need(AddCategory(Map,'BIRU',Code));
  Need(EncodeCategory(Map,'BIRU',Code)); Need(OneHot(Code,Map.Count,V));
  WriteLn('BIRU = ',Code,'; one-hot = ',V[1]:0:0,',',V[2]:0:0);
  WriteLn('Hasil: PREPTRN.CSV dan PREPTST.CSV');
  FreeData(Selected); FreeData(TestData); FreeData(TrainData); FreeData(D)
end.
