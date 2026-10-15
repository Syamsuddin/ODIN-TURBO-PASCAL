{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 7.2 - Perulangan for..downto
  downto menghitung mundur: pencacah turun 1 setiap putaran.
  Pencacah juga boleh bertipe Char. }

program bab07_02_for_downto;

var
  I: Integer;
  Huruf: Char;

begin
  Write('Hitung mundur: ');
  for I := 10 downto 1 do
    Write(I, ' ');
  WriteLn('Mulai!');

  { Pencacah bertipe Char berjalan menurut urutan abjad }
  Write('Abjad terbalik: ');
  for Huruf := 'Z' downto 'A' do
    Write(Huruf);
  WriteLn;

  { Bila nilai awal lebih kecil dari nilai akhir, downto tidak
    berjalan sama sekali }
  for I := 1 downto 5 do
    WriteLn('Baris ini tidak pernah tampil');

  { Kelipatan 5 dari 50 turun ke 5, memakai perkalian }
  Write('Kelipatan 5: ');
  for I := 10 downto 1 do
    Write(I * 5, ' ');
  WriteLn;
end.
