{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 10.4 - Menara Hanoi
  Pindahkan N cakram dari tiang A ke tiang C dengan bantuan tiang B.
  Hanya satu cakram dipindah per langkah, dan cakram besar tidak boleh
  berada di atas cakram kecil. Pemecahan rekursifnya:
    1. pindahkan N-1 cakram atas dari Asal ke Bantu
    2. pindahkan cakram terbesar dari Asal ke Tujuan
    3. pindahkan N-1 cakram dari Bantu ke Tujuan }

program bab10_04_menara_hanoi;

var
  JumlahLangkah: LongInt;

procedure Hanoi(N: Integer; Asal, Tujuan, Bantu: Char);
begin
  if N = 0 then
    Exit;                                { kasus dasar: keluar dari prosedur }
  Hanoi(N - 1, Asal, Bantu, Tujuan);     { langkah 1 }
  JumlahLangkah := JumlahLangkah + 1;
  WriteLn(JumlahLangkah:4, '. Cakram ', N, ': ', Asal, ' -> ', Tujuan);
  Hanoi(N - 1, Bantu, Tujuan, Asal);     { langkah 3 }
end;

var
  N: Integer;

begin
  repeat
    Write('Jumlah cakram (1-8): ');
    ReadLn(N);
  until (N >= 1) and (N <= 8);

  JumlahLangkah := 0;
  Hanoi(N, 'A', 'C', 'B');
  WriteLn('Selesai dalam ', JumlahLangkah, ' langkah (2^N - 1).');
end.
