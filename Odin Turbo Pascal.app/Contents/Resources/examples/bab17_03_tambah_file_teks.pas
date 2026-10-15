{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 17.3 - Menambah isi file teks
  Append membuka file dan menaruh tulisan baru di akhir, tanpa
  menghapus isi lama. Append gagal bila file belum ada, jadi periksa
  dulu dengan IOResult; bila belum ada, buat dengan Rewrite. }

program bab17_03_tambah_file_teks;

const
  NamaFile = 'catatan.txt';

var
  F: Text;
  Catatan, Baris: string;
  Jumlah: Integer;

begin
  Write('Catatan baru: ');
  ReadLn(Catatan);

  Assign(F, NamaFile);
  {$I-}
  Append(F);                             { buka untuk menambah di akhir }
  {$I+}
  if IOResult <> 0 then
  begin
    WriteLn('(', NamaFile, ' belum ada, dibuat baru)');
    Rewrite(F);
  end;
  WriteLn(F, '+ ', Catatan);
  Close(F);

  { Baca ulang untuk melihat hasilnya }
  Reset(F);
  Jumlah := 0;
  while not Eof(F) do
  begin
    ReadLn(F, Baris);
    WriteLn('  ', Baris);
    Jumlah := Jumlah + 1;
  end;
  Close(F);
  WriteLn(NamaFile, ' kini berisi ', Jumlah, ' baris.');
end.
