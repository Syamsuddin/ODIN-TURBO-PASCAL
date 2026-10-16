{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 11.3 - Array dua dimensi
  Array dua dimensi berbentuk tabel: indeks pertama untuk baris,
  indeks kedua untuk kolom, ditulis Nilai[Baris, Kolom].
  Di sini datanya diisi lewat konstanta bertipe agar tidak perlu
  diketik satu per satu. }

program bab11_03_array_dua_dimensi;

const
  JumlahSiswa = 3;
  JumlahMapel = 4;
  { Konstanta bertipe: setiap baris dalam kurung adalah satu siswa }
  Nilai: array[1..JumlahSiswa, 1..JumlahMapel] of Integer = (
    (80, 75, 90, 85),
    (65, 70, 60, 75),
    (95, 88, 92, 90));

var
  Baris, Kolom: Integer;
  Total: Integer;

begin
  WriteLn('Siswa   MTK  IPA  IND  ING   Rata');
  for Baris := 1 to JumlahSiswa do
  begin
    Write('  ', Baris, '   ');
    Total := 0;
    for Kolom := 1 to JumlahMapel do
    begin
      Write(Nilai[Baris, Kolom]:5);      { elemen baris B, kolom K }
      Total := Total + Nilai[Baris, Kolom];
    end;
    WriteLn(Total / JumlahMapel:7:2);
  end;

  { Kini kolom di luar, baris di dalam: rata-rata per mapel }
  Write('Rata  ');
  for Kolom := 1 to JumlahMapel do
  begin
    Total := 0;
    for Baris := 1 to JumlahSiswa do
      Total := Total + Nilai[Baris, Kolom];
    Write(Total / JumlahSiswa:5:0);
  end;
  WriteLn;
end.
