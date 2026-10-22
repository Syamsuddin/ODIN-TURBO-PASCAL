program FuzzyDemo;
{ FUZDEMO - inferensi fuzzy Mamdani dengan AIFUZZY.
  DefaultFuzzy menyiapkan sistem bawaan: dua input (suhu 0..40 dan
  kelembapan 0..100), tiga himpunan segitiga untuk masing-masing, dan
  sembilan aturan yang menyimpulkan kecepatan kipas 0..100. Program
  mengevaluasi satu titik (suhu 28, kelembapan 70), mencetak hasil
  defuzzifikasi dan tingkat firing (keaktifan) setiap aturan, lalu
  menyapu suhu dari 0 sampai 40 pada kelembapan tetap 70 untuk
  mengekspor kurva suhu-vs-kipas ke FUZZY.SVG.
  Latihan (DOCS/GUIDE2.TXT bagian 23, urutan #10): ubah salah satu
  membership function atau aturan dengan CheckFuzzy, lalu amati
  perubahan bentuk kurva output. }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIFuzzy,AIPlot;
var S: TFuzzySystem; Strength: TFuzzyStrength;
    X,Y: TSeries; Groups: TLabels; I: Integer; Output: TFloat;
{$I COMMON.INC}
begin
  DefaultFuzzy(S);
  Need(EvaluateFuzzy(S,28,70,200,Output,Strength));   { 200: jumlah segmen integrasi centroid }
  WriteLn('Suhu=28, kelembapan=70 => kecepatan kipas=',Output:0:3);
  for I:=1 to 9 do WriteLn('Aturan ',I,' firing=',Strength[I]:0:4);  { maksimum 9 aturan Mamdani }
  FillChar(Groups,SizeOf(Groups),0);
  for I:=1 to 41 do begin
    X[I]:=I-1; Need(EvaluateFuzzy(S,X[I],70,200,Y[I],Strength))  { suhu 0..40, kelembapan tetap 70 }
  end;
  Need(SaveScatterSVG('FUZZY.SVG',X,Y,41,Groups,'Suhu vs kipas; kelembapan 70'))
end.
