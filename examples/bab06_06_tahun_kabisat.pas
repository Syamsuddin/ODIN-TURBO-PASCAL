{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 6.6 - Latihan: tahun kabisat
  Aturan kalender Masehi: tahun kabisat habis dibagi 4, KECUALI habis
  dibagi 100. Tetapi yang habis dibagi 400 tetap kabisat.
  Contoh: 2024 kabisat, 1900 bukan, 2000 kabisat. }

program bab06_06_tahun_kabisat;

var
  Tahun: Integer;
  Kabisat: Boolean;

begin
  Write('Masukkan tahun: ');
  ReadLn(Tahun);

  { Cara 1: if bersarang, mengikuti aturan langkah demi langkah }
  if Tahun mod 400 = 0 then
    Kabisat := True
  else if Tahun mod 100 = 0 then
    Kabisat := False
  else if Tahun mod 4 = 0 then
    Kabisat := True
  else
    Kabisat := False;

  { Cara 2: satu ekspresi logika. Hasilnya harus sama dengan cara 1. }
  if Kabisat <> ((Tahun mod 4 = 0) and (Tahun mod 100 <> 0)
                 or (Tahun mod 400 = 0)) then
    WriteLn('Aneh, kedua cara memberi hasil berbeda!');

  if Kabisat then
    WriteLn(Tahun, ' adalah tahun kabisat (Februari 29 hari).')
  else
    WriteLn(Tahun, ' bukan tahun kabisat (Februari 28 hari).');
end.
