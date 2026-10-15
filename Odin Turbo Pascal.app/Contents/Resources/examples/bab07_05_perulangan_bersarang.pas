{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 7.5 - Perulangan bersarang
  Perulangan di dalam perulangan. Untuk setiap putaran luar, putaran
  dalam berjalan sampai habis. Pola ini cocok untuk tabel dan baris-
  kolom. }

program bab07_05_perulangan_bersarang;

var
  Baris, Kolom: Integer;

begin
  WriteLn('TABEL PERKALIAN 1 - 9');
  Write('   |');
  for Kolom := 1 to 9 do                 { judul kolom }
    Write(Kolom:4);
  WriteLn;
  WriteLn('---+------------------------------------');

  for Baris := 1 to 9 do                 { perulangan luar: baris }
  begin
    Write(Baris:2, ' |');
    for Kolom := 1 to 9 do               { perulangan dalam: kolom }
      Write(Baris * Kolom:4);
    WriteLn;                             { pindah baris setelah 9 kolom }
  end;
  WriteLn;

  { Koordinat (baris, kolom) untuk melihat urutan kerjanya }
  for Baris := 1 to 3 do
  begin
    for Kolom := 1 to 4 do
      Write('(', Baris, ',', Kolom, ') ');
    WriteLn;
  end;
end.
