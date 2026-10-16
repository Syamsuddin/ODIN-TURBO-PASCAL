{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 13.1 - Record
  Record mengelompokkan beberapa data yang berbeda tipe menjadi satu
  kesatuan, misalnya data sebuah buku. Setiap bagian disebut field
  dan diakses dengan titik: Buku.Judul. }

program bab13_01_record_dasar;

type
  TBuku = record
    Judul: string[40];                   { field bertipe string }
    Penulis: string[30];
    Tahun: Integer;                      { field bertipe Integer }
    Harga: LongInt;
  end;

var
  Buku1, Buku2: TBuku;

begin
  { Mengisi field satu per satu }
  Buku1.Judul := 'Belajar Pemrograman Pascal';
  Buku1.Penulis := 'Siti Aminah';
  Buku1.Tahun := 2024;
  Buku1.Harga := 85000;

  { with: tidak perlu menulis "Buku2." berulang-ulang }
  with Buku2 do
  begin
    Judul := 'Algoritma untuk Pemula';
    Penulis := 'Ahmad Fauzi';
    Tahun := 2022;
    Harga := 67500;
  end;

  WriteLn('Buku 1: ', Buku1.Judul, ' (', Buku1.Tahun, ')');
  WriteLn('        oleh ', Buku1.Penulis, ', Rp ', Buku1.Harga);
  with Buku2 do
  begin
    WriteLn('Buku 2: ', Judul, ' (', Tahun, ')');
    WriteLn('        oleh ', Penulis, ', Rp ', Harga);
  end;

  { Record bisa disalin utuh dengan satu penugasan }
  Buku2 := Buku1;
  Buku2.Harga := Buku1.Harga - 10000;    { ubah salinannya saja }
  WriteLn('Salinan: ', Buku2.Judul, ', harga diskon Rp ', Buku2.Harga);
  WriteLn('Asli   : harga tetap Rp ', Buku1.Harga);
end.
