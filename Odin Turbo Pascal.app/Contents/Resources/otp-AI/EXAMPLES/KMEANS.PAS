program KMeansDemo;
{ KMEANS - klastering K-means dengan AIKMEANS (unsupervised, tanpa label).
  Memuat CLUSTER.CSV sebagai TargetNone (tidak ada target/label sama
  sekali), menstandardisasi fitur, lalu mengelompokkan menjadi K=3
  klaster dengan inisialisasi farthest-first (bukan k-means++).
  Program mencetak jumlah iterasi, status konvergensi, inertia akhir
  dan koordinat setiap pusat klaster, lalu mengekspor scatter klaster
  ke CLUSTER.SVG dan kurva inertia per iterasi ke INERTIA.SVG.
  Latihan: ubah K menjadi 2 dan 4, amati perubahan inertia dan posisi
  pusat (DOCS/GUIDE.TXT bagian 9, 11, 12). Nomor klaster tidak memiliki
  arti kelas atau urutan mutu. }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AIKMeans,AIPlot;
var D: PDataSet; S: TScaler; M: TKMeansModel;
    Labels: TLabels; X,Y,History: TSeries; H,C: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('CLUSTER.CSV'),True,TargetNone,D^));
  Need(FitScaler(D^,ScaleStandard,S)); Need(TransformData(S,D^));
  Need(FitKMeans(D^,3,100,0.0001,42,M,Labels,History,H));  { K=3, maks 100 iterasi, toleransi 1E-4, seed 42 }
  WriteLn('Iterasi=',M.Iterations,' Konvergen=',M.Converged);
  WriteLn('Inertia=',M.Inertia:0:6);                   { jumlah kuadrat jarak ke pusat terdekat }
  for C := 1 to M.K do
    WriteLn('Pusat ',C,': ',M.Centers[C,1]:0:4,', ',M.Centers[C,2]:0:4);
  Need(GetColumn(D^,1,X)); Need(GetColumn(D^,2,Y));
  Need(SaveScatterSVG('CLUSTER.SVG',X,Y,D^.Count,Labels,'K-means - fitur standar'));
  Need(SaveCurveSVG('INERTIA.SVG',History,H,'Inertia per iterasi'));  { H = HistoryCount, bukan M.Iterations }
  WriteLn('Grafik: CLUSTER.SVG dan INERTIA.SVG'); FreeData(D)
end.
