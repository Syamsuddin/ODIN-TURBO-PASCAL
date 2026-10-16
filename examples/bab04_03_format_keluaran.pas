{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 4.3 - Format keluaran
  Nilai:N   menulis nilai rata kanan dalam N kolom.
  Nilai:N:D menulis bilangan Real dalam N kolom dengan D angka desimal.
  Dengan lebar yang sama di setiap baris, kolom tabel menjadi lurus. }

program bab04_03_format_keluaran;

var
  X: Real;

begin
  { Lebar kolom untuk bilangan bulat dan teks }
  WriteLn('[', 42, ']');           { tanpa format }
  WriteLn('[', 42:6, ']');         { 6 kolom, rata kanan }
  WriteLn('[', 'Ani':6, ']');      { teks juga rata kanan }

  { Bilangan Real tanpa format tampil dalam notasi ilmiah (E+000) }
  X := 3.14159265;
  WriteLn(X);
  WriteLn(X:0:2);                  { 2 desimal, lebar secukupnya }
  WriteLn(X:10:4);                 { 10 kolom, 4 desimal }
  WriteLn;

  { Tabel: teks diberi spasi agar sama panjang, bilangan diberi lebar }
  WriteLn('No  Barang        Jumlah      Harga');
  WriteLn('------------------------------------');
  WriteLn(1:2, '  ', 'Pensil    ', 8:8, 2500.0:11:2);
  WriteLn(2:2, '  ', 'Buku tulis', 5:8, 6000.0:11:2);
  WriteLn(3:2, '  ', 'Penghapus ', 12:8, 1500.0:11:2);
end.
