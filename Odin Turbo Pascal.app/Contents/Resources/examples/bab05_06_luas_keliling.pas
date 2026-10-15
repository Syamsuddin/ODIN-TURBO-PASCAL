{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 5.6 - Latihan: luas dan keliling
  Menghitung luas dan keliling persegi panjang serta lingkaran dari
  ukuran yang dimasukkan pengguna. Pi adalah fungsi bawaan Pascal. }

program bab05_06_luas_keliling;

var
  Panjang, Lebar: Real;
  JariJari: Real;
  Luas, Keliling: Real;

begin
  WriteLn('PERSEGI PANJANG');
  Write('Panjang (cm): '); ReadLn(Panjang);
  Write('Lebar   (cm): '); ReadLn(Lebar);
  Luas := Panjang * Lebar;
  Keliling := 2 * (Panjang + Lebar);   { kurung: jumlahkan dulu }
  WriteLn('Luas     = ', Luas:0:2, ' cm2');
  WriteLn('Keliling = ', Keliling:0:2, ' cm');
  WriteLn;

  WriteLn('LINGKARAN');
  Write('Jari-jari (cm): '); ReadLn(JariJari);
  Luas := Pi * Sqr(JariJari);          { Pi x r x r }
  Keliling := 2 * Pi * JariJari;       { 2 x Pi x r }
  WriteLn('Luas     = ', Luas:0:2, ' cm2');
  WriteLn('Keliling = ', Keliling:0:2, ' cm');
end.
