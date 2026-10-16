{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 10.1 - Faktorial secara rekursif
  Fungsi rekursif memanggil dirinya sendiri dengan masalah yang lebih
  kecil. Wajib ada kasus dasar yang menghentikan pemanggilan.
  N! = N x (N-1)!, dan 0! = 1! = 1. }

program bab10_01_faktorial_rekursif;

function Faktorial(N: Integer): LongInt;
begin
  if N <= 1 then
    Faktorial := 1                       { kasus dasar: berhenti di sini }
  else
    Faktorial := N * Faktorial(N - 1);   { kasus rekursif }
end;

{ Versi yang sama, tetapi mencetak jejak setiap pemanggilan.
  Tingkat dipakai untuk menjorokkan tulisan sesuai kedalaman. }
function FaktorialJejak(N, Tingkat: Integer): LongInt;
var
  Hasil: LongInt;
begin
  WriteLn('':Tingkat * 2, 'masuk Faktorial(', N, ')');
  if N <= 1 then
    Hasil := 1
  else
    Hasil := N * FaktorialJejak(N - 1, Tingkat + 1);
  WriteLn('':Tingkat * 2, 'Faktorial(', N, ') = ', Hasil);
  FaktorialJejak := Hasil;
end;

var
  I: Integer;
  Hasil: LongInt;

begin
  Hasil := FaktorialJejak(4, 0);
  WriteLn;
  for I := 0 to 12 do                    { 13! sudah melebihi LongInt }
    WriteLn(I:2, '! = ', Faktorial(I):10);
end.
