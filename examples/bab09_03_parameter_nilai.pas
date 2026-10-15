{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 9.3 - Parameter nilai
  Parameter biasa (parameter nilai) menerima SALINAN nilai dari
  pemanggil. Mengubah parameter di dalam prosedur tidak mengubah
  variabel asli di luar. Argumennya boleh berupa ekspresi. }

program bab09_03_parameter_nilai;

procedure Gandakan(X: Integer);          { X hanya salinan }
begin
  X := X * 2;
  WriteLn('  Di dalam prosedur, X = ', X);
end;

procedure CetakBaris(Karakter: Char; Panjang: Integer);
var
  I: Integer;
begin
  for I := 1 to Panjang do
    Write(Karakter);
  WriteLn;
end;

var
  Angka: Integer;

begin
  Angka := 5;
  WriteLn('Sebelum dipanggil, Angka = ', Angka);
  Gandakan(Angka);                       { nilai 5 disalin ke X }
  WriteLn('Sesudah dipanggil, Angka = ', Angka, ' (tidak berubah)');
  WriteLn;

  Gandakan(10 + 3);                      { argumen boleh berupa ekspresi }

  { Urutan argumen harus sesuai urutan parameter: Char dulu, lalu Integer }
  CetakBaris('=', 30);
  CetakBaris('*', Angka);
  CetakBaris('-', Angka * 6);
end.
