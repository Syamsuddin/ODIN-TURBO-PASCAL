{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 7.3 - Perulangan while..do
  while memeriksa syarat SEBELUM mengulang. Selama syarat True,
  badannya diulang. Bila sejak awal False, badannya tidak dijalankan.
  Pastikan ada perintah yang akhirnya membuat syarat menjadi False. }

program bab07_03_while_do;

var
  Angka, Sisa, JumlahDigit: LongInt;
  Bilangan, Total, Banyak: Integer;

begin
  { Contoh 1: menjumlahkan digit sebuah bilangan }
  Write('Masukkan bilangan bulat positif: ');
  ReadLn(Angka);
  Sisa := Angka;
  JumlahDigit := 0;
  while Sisa > 0 do
  begin
    JumlahDigit := JumlahDigit + Sisa mod 10;   { ambil digit kanan }
    Sisa := Sisa div 10;                        { buang digit kanan }
  end;
  WriteLn('Jumlah digit ', Angka, ' = ', JumlahDigit);
  WriteLn;

  { Contoh 2: membaca bilangan sampai pengguna mengetik 0 }
  WriteLn('Ketik beberapa bilangan, akhiri dengan 0.');
  Total := 0;
  Banyak := 0;
  Write('Bilangan: ');
  ReadLn(Bilangan);
  while Bilangan <> 0 do                 { 0 adalah tanda berhenti }
  begin
    Total := Total + Bilangan;
    Banyak := Banyak + 1;
    Write('Bilangan: ');
    ReadLn(Bilangan);
  end;
  WriteLn('Banyak bilangan: ', Banyak, ', jumlahnya: ', Total);
end.
