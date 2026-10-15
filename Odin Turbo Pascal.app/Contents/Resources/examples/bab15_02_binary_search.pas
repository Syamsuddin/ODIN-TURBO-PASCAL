{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 15.2 - Pencarian biner (binary search)
  Syarat: data TERURUT. Bandingkan dengan elemen tengah; bila yang
  dicari lebih kecil, buang separuh kanan, bila lebih besar buang
  separuh kiri. Setiap langkah membuang separuh data, jadi 1000 data
  cukup diperiksa sekitar 10 kali. }

program bab15_02_binary_search;

const
  N = 15;
  Data: array[1..N] of Integer =
    (3, 8, 12, 17, 21, 25, 30, 34, 41, 47, 52, 60, 68, 75, 90);

var
  Dicari, Kiri, Kanan, Tengah, Langkah, Posisi, I: Integer;

begin
  Write('Data terurut: ');
  for I := 1 to N do
    Write(Data[I], ' ');
  WriteLn;
  Write('Bilangan yang dicari: ');
  ReadLn(Dicari);

  Kiri := 1;
  Kanan := N;
  Posisi := 0;                           { 0 berarti belum ketemu }
  Langkah := 0;
  while (Kiri <= Kanan) and (Posisi = 0) do
  begin
    Tengah := (Kiri + Kanan) div 2;
    Langkah := Langkah + 1;
    WriteLn('  Langkah ', Langkah, ': rentang ', Kiri, '..', Kanan,
      ', tengah Data[', Tengah, '] = ', Data[Tengah]);
    if Data[Tengah] = Dicari then
      Posisi := Tengah
    else if Dicari < Data[Tengah] then
      Kanan := Tengah - 1                { cari di separuh kiri }
    else
      Kiri := Tengah + 1;                { cari di separuh kanan }
  end;

  if Posisi > 0 then
    WriteLn(Dicari, ' ditemukan di posisi ', Posisi, '.')
  else
    WriteLn(Dicari, ' tidak ada dalam data.');
  WriteLn('Jumlah langkah: ', Langkah, ' (pencarian beruntun bisa sampai ',
    N, ')');
end.
