program PlotDemo;
{ PLOTDEMO - pengantar AIPLOT: grafik BGI (Turbo Pascal) dan SVG.
  Membuat 20 titik sintetis di sekitar garis Y=10+3X dengan sedikit
  noise, lalu selalu mengekspor SVG lewat SaveRegressionSVG - ini jalur
  yang portabel dan bisa dibuka di peramban mana pun tanpa compiler.
  Di luar Free Pascal (build Turbo Pascal asli), program juga mencoba
  membuka driver BGI layar penuh untuk menampilkan scatter, regresi dan
  kurva secara interaktif (Enter untuk lanjut tiap tahap); di Free
  Pascal, BGI tidak tersedia sehingga bagian ini dilewati.
  Latihan: lihat bagaimana angka Y yang sama tampil sebagai titik
  (scatter), garis (regresi) dan kurva (DOCS/GUIDE.TXT bagian 11, 12). }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIPlot;
var X,Y: TSeries; Groups: TLabels; I: Integer; Path: TFileName;
{$I COMMON.INC}
begin
  for I := 1 to 20 do begin
    X[I] := I/2; Y[I] := 10+3*X[I]+(I mod 3-1);   { garis Y=10+3X plus noise kecil -1,0,1 berulang }
    Groups[I] := 0                                { semua titik satu kelompok warna }
  end;
  Need(SaveRegressionSVG('PLOT.SVG',X,Y,20,10,3,'Contoh BGI dan SVG'));
  WriteLn('PLOT.SVG sudah dibuat.');
  {$IFNDEF FPC}
  Path := 'C:\TP\BGI';                            { lokasi driver BGI default Turbo Pascal }
  if ParamCount > 0 then Path := ParamStr(1);      { boleh ditimpa lewat argumen program }
  if PlotOpen(Path) then begin
    Need(PlotScatter(X,Y,20,Groups,'Scatter plot. Tekan Enter.')); ReadLn;
    Need(PlotRegression(X,Y,20,10,3,'Regresi. Tekan Enter.')); ReadLn;
    Need(PlotCurve(Y,20,'Kurva. Tekan Enter.')); ReadLn;
    PlotClose
  end else WriteLn(AIError)
  {$ELSE}
  WriteLn('BGI khusus build Turbo Pascal. Buka SVG di peramban.')
  {$ENDIF}
end.
