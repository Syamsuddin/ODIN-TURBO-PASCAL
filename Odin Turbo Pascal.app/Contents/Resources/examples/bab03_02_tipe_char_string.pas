{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 3.2 - Tipe Char dan string
  Char menyimpan satu karakter, string menyimpan deretan karakter
  (paling banyak 255). Teks ditulis di antara tanda petik tunggal. }

program bab03_02_tipe_char_string;

var
  Huruf: Char;                 { tepat satu karakter }
  Nama: string;                { teks sampai 255 karakter }
  Kota: string[9];             { teks dibatasi 9 karakter }
  Kalimat: string;

begin
  Huruf := 'A';
  Nama := 'Budi Santoso';
  Kota := 'Kandangan Barat';    { kelebihan karakter dipotong }

  WriteLn('Huruf : ', Huruf);
  WriteLn('Nama  : ', Nama);
  WriteLn('Kota  : ', Kota, ' (dipotong menjadi 9 karakter)');

  { Setiap karakter punya nomor kode (ASCII). Ord dan Chr saling balik. }
  WriteLn('Kode huruf A   : ', Ord(Huruf));
  WriteLn('Karakter ke-66 : ', Chr(66));

  { Karakter di dalam string diambil dengan indeks, dimulai dari 1 }
  WriteLn('Huruf pertama nama: ', Nama[1]);
  WriteLn('Panjang nama      : ', Length(Nama), ' karakter');

  { Tanda + menyambung string. Petik di dalam teks ditulis dua kali. }
  Kalimat := 'Halo, ' + Nama + '! Ini Jum''at yang cerah.';
  WriteLn(Kalimat);
end.
