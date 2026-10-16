{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 6.3 - if bersarang
  Sebuah if boleh berada di dalam if lain. Pola else if dipakai untuk
  memilih satu dari beberapa kemungkinan secara berurutan. }

program bab06_03_if_bersarang;

var
  Umur: Integer;
  Pelajar: Char;
  Harga: LongInt;

begin
  Write('Umur pengunjung: ');
  ReadLn(Umur);

  { Rantai else if: diperiksa dari atas, berhenti di syarat pertama
    yang benar }
  if Umur < 5 then
    Harga := 0
  else if Umur < 13 then
    Harga := 15000
  else if Umur < 60 then
    Harga := 30000
  else
    Harga := 20000;

  { if di dalam if: pertanyaan kedua hanya untuk umur 13 sampai 22 }
  if (Umur >= 13) and (Umur <= 22) then
  begin
    Write('Apakah pelajar/mahasiswa (Y/T)? ');
    ReadLn(Pelajar);
    if (Pelajar = 'Y') or (Pelajar = 'y') then
      Harga := Harga - 10000;           { potongan pelajar }
  end;

  if Harga = 0 then
    WriteLn('Masuk gratis.')
  else
    WriteLn('Harga tiket: Rp ', Harga);
end.
