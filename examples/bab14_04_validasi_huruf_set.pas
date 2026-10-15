{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 14.4 - Latihan: validasi dengan set
  Set of Char memudahkan pemeriksaan jenis karakter. Daripada menulis
  (C >= 'A') and (C <= 'Z'), cukup tulis C in HurufBesar.
  Program ini menilai kekuatan kata sandi dan memeriksa nomor HP. }

program bab14_04_validasi_huruf_set;

const
  HurufBesar = ['A'..'Z'];
  HurufKecil = ['a'..'z'];
  Angka = ['0'..'9'];
  Simbol = ['!', '@', '#', '$', '%', '&', '*', '-', '_', '?'];

var
  Sandi, NomorHP: string;
  I, Skor: Integer;
  AdaBesar, AdaKecil, AdaAngka, AdaSimbol, Sah: Boolean;

begin
  Write('Kata sandi baru: ');
  ReadLn(Sandi);
  AdaBesar := False; AdaKecil := False;
  AdaAngka := False; AdaSimbol := False;
  for I := 1 to Length(Sandi) do
  begin
    if Sandi[I] in HurufBesar then AdaBesar := True;
    if Sandi[I] in HurufKecil then AdaKecil := True;
    if Sandi[I] in Angka then AdaAngka := True;
    if Sandi[I] in Simbol then AdaSimbol := True;
  end;

  Skor := 0;                             { satu poin untuk tiap syarat }
  if Length(Sandi) >= 8 then Skor := Skor + 1;
  if AdaBesar then Skor := Skor + 1;
  if AdaKecil then Skor := Skor + 1;
  if AdaAngka then Skor := Skor + 1;
  if AdaSimbol then Skor := Skor + 1;
  case Skor of
    0..2: WriteLn('Kekuatan: LEMAH (', Skor, '/5)');
    3..4: WriteLn('Kekuatan: SEDANG (', Skor, '/5)');
    5:    WriteLn('Kekuatan: KUAT (', Skor, '/5)');
  end;
  if not AdaAngka then WriteLn('  Saran: tambahkan angka.');
  if not AdaSimbol then WriteLn('  Saran: tambahkan simbol seperti ! atau #.');
  WriteLn;

  { Nomor HP: diawali 08, panjang 10-13, hanya berisi angka }
  Write('Nomor HP: ');
  ReadLn(NomorHP);
  Sah := (Length(NomorHP) >= 10) and (Length(NomorHP) <= 13)
         and (Copy(NomorHP, 1, 2) = '08');
  for I := 1 to Length(NomorHP) do
    if not (NomorHP[I] in Angka) then    { kurung: not lalu in }
      Sah := False;
  if Sah then
    WriteLn('Nomor HP sah.')
  else
    WriteLn('Nomor HP tidak sah.');
end.
