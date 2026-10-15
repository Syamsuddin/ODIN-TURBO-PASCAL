{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 9.1 - Prosedur
  Prosedur adalah kumpulan perintah yang diberi nama. Ditulis sekali
  di atas program utama, lalu dipanggil dengan namanya berkali-kali.
  Program menjadi lebih pendek dan mudah dibaca. }

program bab09_01_prosedur_dasar;

procedure GarisPemisah;                  { deklarasi prosedur }
begin
  WriteLn('----------------------------------------');
end;

procedure TampilkanJudul;
begin
  GarisPemisah;                          { memanggil prosedur di atasnya }
  WriteLn('       DAFTAR MENU KANTIN SEKOLAH');
  GarisPemisah;
end;

procedure TampilkanMenu;
begin
  WriteLn(' 1. Nasi goreng ............ Rp 12000');
  WriteLn(' 2. Mi ayam ................ Rp 10000');
  WriteLn(' 3. Soto banjar ............ Rp 15000');
  WriteLn(' 4. Es teh ................. Rp  3000');
end;

begin                                    { program utama mulai di sini }
  TampilkanJudul;                        { panggil cukup dengan namanya }
  TampilkanMenu;
  GarisPemisah;
  WriteLn('Selamat makan!');
end.
