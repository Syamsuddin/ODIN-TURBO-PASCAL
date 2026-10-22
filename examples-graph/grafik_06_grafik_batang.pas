{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 6 - Grafik batang
  Data dalam array digambar sebagai balok 3D (Bar3D) dengan skala otomatis.
  Rumus skala: tinggi piksel = nilai * tinggi area / nilai maksimum. }

program grafik_06_grafik_batang;

uses Crt, Graph;

const
  Jumlah = 6;
  Nama: array[1..Jumlah] of String = ('Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun');
  Nilai: array[1..Jumlah] of Integer = (120, 85, 150, 95, 175, 130);
  Kiri = 100;
  Dasar = 380;
  Tinggi = 280;

var
  Driver, Mode, I, Maks, T, X: Integer;
  Teks: String;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  SetColor(White);
  SetTextStyle(DefaultFont, HorizDir, 2);
  SetTextJustify(CenterText, TopText);
  OutTextXY(GetMaxX div 2, 20, 'Penjualan per Bulan');
  SetTextStyle(DefaultFont, HorizDir, 1);
  SetTextJustify(LeftText, TopText);

  Maks := Nilai[1];
  for I := 2 to Jumlah do
    if Nilai[I] > Maks then Maks := Nilai[I];

  Line(Kiri, Dasar - Tinggi - 20, Kiri, Dasar);       { sumbu Y }
  Line(Kiri, Dasar, Kiri + Jumlah * 80 + 20, Dasar);  { sumbu X }

  for I := 1 to Jumlah do
  begin
    T := Nilai[I] * Tinggi div Maks;
    X := Kiri + 20 + (I - 1) * 80;
    SetFillStyle(SolidFill, 8 + I);
    SetColor(White);
    Bar3D(X, Dasar - T, X + 40, Dasar, 12, TopOn);
    Str(Nilai[I], Teks);
    SetColor(Yellow);
    OutTextXY(X + 8, Dasar - T - 30, Teks);
    SetColor(White);
    OutTextXY(X + 6, Dasar + 10, Nama[I]);
  end;

  OutTextXY(Kiri, 440, 'Tekan sembarang tombol...');
  ReadKey;
  CloseGraph;
end.
