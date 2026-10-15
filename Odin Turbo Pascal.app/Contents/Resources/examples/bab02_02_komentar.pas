{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 2.2 - Komentar
  Komentar adalah catatan untuk manusia. Kompiler melewatinya, jadi
  komentar tidak mengubah jalannya program. }

program bab02_02_komentar;

var
  Panjang, Lebar: Integer;   { komentar di akhir baris }

begin
  { Gaya 1: kurung kurawal. Paling umum dipakai di Turbo Pascal. }
  Panjang := 8;

  (* Gaya 2: kurung dan bintang.
     Bisa beberapa baris, sama seperti gaya kurung kurawal. *)
  Lebar := 5;

  // Gaya 3: dua garis miring, berlaku sampai akhir baris.
  // Turbo Pascal 7 asli belum mengenal gaya ini; Odin dan FPC mengenalnya.

  WriteLn('Luas = ', Panjang * Lebar);

  { Komentar juga dipakai untuk "mematikan" baris sementara.
    Baris di bawah tidak dijalankan karena berada di dalam komentar:
    WriteLn('Baris ini tidak akan tampil');
  }

  (* Gaya yang berbeda boleh disisipkan: { ini aman } di dalam *)
  WriteLn('Selesai. Hanya dua baris yang tampil di layar.');
end.
