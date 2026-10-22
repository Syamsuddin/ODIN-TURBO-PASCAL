program DataPrepDemo;
{ DATAPREP - praproses data dengan AIDATA dan AISPLIT.
  Memuat MISSING.CSV (ada fitur kosong), membagi 75/25 latih/uji, lalu
  melatih imputer dan scaler HANYA pada data latih sebelum menerapkannya
  ke data latih dan data uji dengan parameter yang sama - inilah cara
  menghindari data leakage (DOCS/GUIDE.TXT bagian 5-6). Sisanya
  memperagakan SelectColumns/FilterRange atas dataset, serta encoding
  kategori teks menjadi kode dan vektor one-hot.
  Latihan: bandingkan hasil ScaleStandard di sini dengan ScaleMinMax,
  dan amati bagaimana data leakage muncul jika scaler dilatih sebelum
  split (DOCS/GUIDE.TXT bagian 12). }
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
  Need(NewData(D)); Need(NewData(TrainData));           { empat dataset terpisah, bukan alias satu sama lain }
  Need(NewData(TestData)); Need(NewData(Selected));
  Need(LoadCSV(DataPath('MISSING.CSV'),True,TargetReal,D^));
  DescribeData(D^);                                     { cetak ringkasan: jumlah baris, fitur, missing }
  Need(TrainTestSplit(D^,TrainData^,TestData^,0.25,True,42));  { 25% uji, acak dengan seed 42 }
  Need(FitImputer(TrainData^,Imputer));                 { mean tiap fitur dihitung dari data LATIH saja }
  Need(ImputeData(Imputer,TrainData^)); Need(ImputeData(Imputer,TestData^));  { imputer yang sama untuk keduanya }
  Need(FitScaler(TrainData^,ScaleStandard,Scaler));      { (X-mean)/SD, juga hanya dari data latih }
  Need(TransformData(Scaler,TrainData^)); Need(TransformData(Scaler,TestData^));
  Need(SaveCSV('PREPTRN.CSV',TrainData^)); Need(SaveCSV('PREPTST.CSV',TestData^));
  Columns[1] := 2; Columns[2] := 1;                      { urutan baru: fitur 2 lalu fitur 1 }
  Need(SelectColumns(TrainData^,Columns,2,Selected^));    { Selected kini dataset 2 kolom terurut ulang }
  Need(FilterRange(TrainData^,1,-1,1,Selected^));         { Selected ditulis ulang: hanya baris fitur 1 di [-1,1] }
  WriteLn('Baris latih dengan fitur 1 antara -1 dan 1: ',Selected^.Count);
  InitCategories(Map);
  Need(AddCategory(Map,'MERAH',Code)); Need(AddCategory(Map,'BIRU',Code));  { MERAH=0, BIRU=1 }
  Need(EncodeCategory(Map,'BIRU',Code)); Need(OneHot(Code,Map.Count,V));   { kode -> vektor one-hot 2 kolom }
  WriteLn('BIRU = ',Code,'; one-hot = ',V[1]:0:0,',',V[2]:0:0);
  WriteLn('Hasil: PREPTRN.CSV dan PREPTST.CSV');
  FreeData(Selected); FreeData(TestData); FreeData(TrainData); FreeData(D)
end.
