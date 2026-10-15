{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 10.3 - Pangkat secara rekursif
  Cara biasa : A^N = A x A^(N-1), kasus dasar A^0 = 1.
  Cara cepat : A^N = (A^(N div 2))^2, dikali A sekali lagi bila N
  ganjil. Pangkat dibagi dua setiap langkah, jadi jauh lebih sedikit
  pemanggilan. }

program bab10_03_pangkat_rekursif;

var
  Langkah: Integer;                      { menghitung pemanggilan }

function Pangkat(A: Real; N: Integer): Real;
begin
  Langkah := Langkah + 1;
  if N = 0 then
    Pangkat := 1                         { kasus dasar }
  else
    Pangkat := A * Pangkat(A, N - 1);
end;

function PangkatCepat(A: Real; N: Integer): Real;
var
  Separuh: Real;
begin
  Langkah := Langkah + 1;
  if N = 0 then
    PangkatCepat := 1
  else
  begin
    Separuh := PangkatCepat(A, N div 2); { dihitung sekali saja }
    if N mod 2 = 0 then
      PangkatCepat := Separuh * Separuh
    else
      PangkatCepat := Separuh * Separuh * A;
  end;
end;

var
  Basis, Hasil: Real;
  N: Integer;

begin
  Write('Bilangan pokok : '); ReadLn(Basis);
  repeat
    Write('Pangkat (0-100): '); ReadLn(N);
  until (N >= 0) and (N <= 100);

  Langkah := 0;
  Hasil := Pangkat(Basis, N);            { hitung dulu, Langkah ikut terisi }
  WriteLn('Cara biasa : ', Hasil:0:2, '  (', Langkah, ' pemanggilan)');

  Langkah := 0;
  Hasil := PangkatCepat(Basis, N);
  WriteLn('Cara cepat : ', Hasil:0:2, '  (', Langkah, ' pemanggilan)');
end.
