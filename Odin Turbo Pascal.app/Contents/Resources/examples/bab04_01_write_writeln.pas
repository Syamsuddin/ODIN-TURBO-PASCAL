{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 4.1 - Write dan WriteLn
  Write menulis tanpa pindah baris; WriteLn menulis lalu pindah baris.
  Keduanya bisa menerima beberapa nilai sekaligus, dipisah koma. }

program bab04_01_write_writeln;

var
  Umur: Integer;

begin
  Umur := 16;

  Write('Satu ');                 { kursor tetap di baris yang sama }
  Write('baris ');
  WriteLn('yang sama.');          { pindah baris setelah menulis }

  WriteLn('Baris kedua.');
  WriteLn;                        { WriteLn kosong: baris kosong }

  { Teks, variabel, dan ekspresi boleh dicampur dalam satu WriteLn }
  WriteLn('Umur saya ', Umur, ' tahun.');
  WriteLn('Lima tahun lagi: ', Umur + 5, ' tahun.');
  WriteLn('Hasil 7 x 6 = ', 7 * 6);

  { Petik tunggal di dalam teks ditulis dua kali: '' }
  WriteLn('Hari ini hari Jum''at.');
end.
