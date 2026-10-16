{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 19.2 - Unit Crt
  Crt adalah unit bawaan untuk mengatur layar teks dan keyboard:
    ClrScr           bersihkan layar      GotoXY(X, Y)  pindah kursor
    TextColor(W)     warna tulisan        TextBackground(W)  warna latar
    Delay(ms)        jeda sekian milidetik
    ReadKey          tunggu satu tombol, tanpa perlu Enter
  Layar berukuran 80 kolom x 25 baris; posisi (1, 1) di kiri atas. }

program bab19_02_unit_crt;

uses
  Crt;

var
  I, X, Y: Integer;
  Tombol: Char;

begin
  TextBackground(Blue);                  { latar biru... }
  ClrScr;                                { ...berlaku setelah ClrScr }
  TextColor(Yellow);
  GotoXY(32, 2);                         { kolom 32, baris 2 }
  Write('BELAJAR UNIT CRT');

  TextColor(White);
  GotoXY(5, 4);
  Write('Enam belas warna teks, nomor 0 sampai 15:');
  for I := 0 to 15 do
  begin
    TextColor(I);                        { 1 = Blue: sewarna latar }
    GotoXY(5 + (I div 8) * 30, 6 + I mod 8);
    Write('Warna nomor ', I:2);
  end;

  TextColor(LightCyan);
  GotoXY(5, 16);
  X := WhereX;                           { posisi kursor saat ini }
  Y := WhereY;
  Write('Kursor ada di kolom ', X, ', baris ', Y);

  TextColor(White);                      { animasi sederhana dengan Delay }
  GotoXY(5, 18);
  Write('Memuat: ');
  for I := 1 to 40 do
  begin
    Write('#');
    Delay(25);
  end;

  TextColor(LightGreen);
  GotoXY(5, 22);
  Write('Tekan sembarang tombol untuk selesai...');
  Tombol := ReadKey;                     { tidak tampil di layar }

  TextColor(LightGray);                  { kembalikan warna semula }
  TextBackground(Black);
  ClrScr;
  if Tombol = #0 then                    { tombol khusus: F1, panah, ... }
    WriteLn('Anda menekan tombol khusus, kode ', Ord(ReadKey))
  else
    WriteLn('Anda menekan tombol "', Tombol, '"');
  WriteLn('Program selesai.');
end.
