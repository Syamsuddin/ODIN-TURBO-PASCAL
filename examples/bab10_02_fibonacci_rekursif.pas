{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 10.2 - Fibonacci secara rekursif
  Fib(1) = Fib(2) = 1, dan Fib(N) = Fib(N-1) + Fib(N-2).
  Rumusnya pendek, tetapi lambat: suku yang sama dihitung berulang
  kali. Variabel Panggilan menghitung berapa kali fungsi dipanggil. }

program bab10_02_fibonacci_rekursif;

var
  Panggilan: LongInt;                    { global: dihitung oleh Fib }

function Fib(N: Integer): LongInt;
begin
  Panggilan := Panggilan + 1;
  if N <= 2 then
    Fib := 1                             { dua kasus dasar }
  else
    Fib := Fib(N - 1) + Fib(N - 2);      { dua pemanggilan rekursif }
end;

var
  N: Integer;
  Hasil: LongInt;

begin
  Write('Deret: ');
  for N := 1 to 15 do
    Write(Fib(N), ' ');
  WriteLn;
  WriteLn;

  WriteLn(' N        Fib(N)   Jumlah panggilan');
  N := 5;
  while N <= 25 do
  begin
    Panggilan := 0;
    Hasil := Fib(N);
    WriteLn(N:2, Hasil:14, Panggilan:19);
    N := N + 5;
  end;
  WriteLn('Panggilan naik sangat cepat. Versi perulangan di Bab 8.3');
  WriteLn('cukup mengulang N kali.');
end.
