{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 6.1 - if..then
  Perintah sesudah then hanya dijalankan bila syaratnya bernilai True.
  Bila syaratnya False, perintah itu dilewati. }

program bab06_01_if_then;

var
  Suhu: Integer;

begin
  Write('Suhu badan hari ini (derajat Celsius): ');
  ReadLn(Suhu);

  if Suhu >= 38 then                     { syarat: suhu 38 atau lebih }
    WriteLn('Anda demam. Istirahatlah.');

  { Lebih dari satu perintah? Bungkus dengan begin..end }
  if Suhu < 35 then
  begin
    WriteLn('Suhu terlalu rendah.');
    WriteLn('Segera hubungi petugas kesehatan.');
  end;

  WriteLn('Pemeriksaan selesai.');       { selalu dijalankan }
end.
