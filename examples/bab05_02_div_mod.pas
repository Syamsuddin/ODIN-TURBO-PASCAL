{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 5.2 - div dan mod
  div adalah pembagian bulat (pecahan dibuang), mod adalah sisa bagi.
  Keduanya hanya untuk bilangan bulat. }

program bab05_02_div_mod;

var
  TotalDetik: LongInt;
  Jam, Menit, Detik: LongInt;
  Angka: Integer;

begin
  WriteLn('17 div 5 = ', 17 div 5);     { 17 = 3 x 5 + 2, hasil bagi 3 }
  WriteLn('17 mod 5 = ', 17 mod 5);     { sisanya 2 }
  WriteLn;

  { Contoh: mengubah detik menjadi jam, menit, detik }
  Write('Masukkan jumlah detik: ');
  ReadLn(TotalDetik);
  Jam := TotalDetik div 3600;           { 1 jam = 3600 detik }
  Menit := (TotalDetik mod 3600) div 60;
  Detik := TotalDetik mod 60;
  WriteLn(TotalDetik, ' detik = ', Jam, ' jam ', Menit, ' menit ',
    Detik, ' detik');
  WriteLn;

  { Contoh: bilangan genap habis dibagi 2, jadi sisanya 0 }
  Write('Masukkan sebuah bilangan bulat: ');
  ReadLn(Angka);
  WriteLn('Sisa bagi 2 = ', Angka mod 2);
  WriteLn('Angka satuan = ', Angka mod 10);   { digit paling kanan }
  WriteLn('Tanpa satuan = ', Angka div 10);   { buang digit kanan }
end.
