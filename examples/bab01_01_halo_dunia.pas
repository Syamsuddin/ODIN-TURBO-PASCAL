{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Odin Turbo Pascal v2.4.0 - program pertama }

{ Bab 1.1 - Halo, Dunia!
  Program Pascal paling sederhana: menampilkan tulisan ke layar.
  Tekan Ctrl+F9 untuk mengompilasi dan menjalankan program. Hasilnya
  tampil di User screen; Alt+F5 membukanya lagi kapan saja. }

program bab01_01_halo_dunia;    { judul program, diakhiri titik koma }

begin                           { awal bagian perintah }
  WriteLn('Halo, Dunia!');      { tulis teks, lalu pindah ke baris baru }
  WriteLn('Selamat datang di Odin Turbo Pascal.');
  WriteLn('Program pertama Anda sudah berjalan.');
end.                            { program selalu ditutup dengan end. }
