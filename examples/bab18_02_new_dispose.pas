{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 18.2 - New dan Dispose
  New(P) meminta memori baru selama program berjalan (alokasi
  dinamis) dan membuat P menunjuk ke sana. Dispose(P) mengembalikan
  memori itu. Setiap New harus punya pasangan Dispose. }

program bab18_02_new_dispose;

type
  PSiswa = ^TSiswa;
  TSiswa = record
    Nama: string[20];
    Nilai: Integer;
  end;

var
  PAngka: ^Integer;
  A, B: PSiswa;

begin
  New(PAngka);                           { pesan tempat untuk satu Integer }
  PAngka^ := 2026;
  WriteLn('Isi memori baru: ', PAngka^);
  Dispose(PAngka);                       { kembalikan memorinya }
  PAngka := nil;                         { tandai sudah tidak dipakai }

  { Pointer ke record: field diakses dengan P^.Field }
  New(A);
  A^.Nama := 'Rudi';
  A^.Nilai := 81;
  New(B);
  B^ := A^;                              { salin isi record }
  B^.Nama := 'Sari';
  WriteLn(A^.Nama, ': ', A^.Nilai);
  WriteLn(B^.Nama, ': ', B^.Nilai);

  Dispose(A);
  Dispose(B);
  { Setelah Dispose, A dan B masih berisi alamat lama, tetapi memorinya
    bukan milik kita lagi. Jangan memakai A^ atau B^ lagi. }
  WriteLn('Memori sudah dikembalikan.');
end.
