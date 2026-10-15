{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 15.1 - Pencarian beruntun (sequential search)
  Periksa elemen satu per satu dari depan sampai yang dicari ketemu
  atau data habis. Sederhana, dan data tidak perlu terurut. }

program bab15_01_sequential_search;

const
  N = 10;
  Data: array[1..N] of Integer = (34, 7, 23, 32, 5, 62, 32, 18, 9, 41);

var
  Dicari, I, Langkah: Integer;
  Ketemu: Boolean;

begin
  Write('Data: ');
  for I := 1 to N do
    Write(Data[I], ' ');
  WriteLn;
  Write('Bilangan yang dicari: ');
  ReadLn(Dicari);

  I := 1;
  Ketemu := False;
  Langkah := 0;
  while (I <= N) and not Ketemu do       { berhenti bila ketemu atau habis }
  begin
    Langkah := Langkah + 1;
    if Data[I] = Dicari then
      Ketemu := True
    else
      I := I + 1;
  end;

  if Ketemu then
    WriteLn(Dicari, ' ditemukan di posisi ', I, ' setelah ', Langkah,
      ' perbandingan.')
  else
    WriteLn(Dicari, ' tidak ada. Semua ', Langkah, ' data sudah diperiksa.');

  { Variasi: cari SEMUA posisi, jadi perulangan tidak berhenti di awal }
  Write('Semua posisi: ');
  for I := 1 to N do
    if Data[I] = Dicari then
      Write(I, ' ');
  WriteLn;
end.
