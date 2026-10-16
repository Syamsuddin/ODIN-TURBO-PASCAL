{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 13.4 - Latihan: data mahasiswa
  Menu sederhana untuk mengelola data mahasiswa di dalam array of
  record: tambah, tampilkan, cari menurut NIM, dan statistik IPK.
  Tiga data contoh sudah diisi saat program mulai. }

program bab13_04_data_mahasiswa;

const
  MaksData = 50;

type
  TMahasiswa = record
    NIM: string[10];
    Nama: string[25];
    IPK: Real;
  end;

var
  Data: array[1..MaksData] of TMahasiswa;
  Jumlah: Integer;                       { banyak data yang sudah terisi }

procedure Tambah(NIM, Nama: string; IPK: Real);
begin
  if Jumlah >= MaksData then
    WriteLn('Data penuh.')
  else
  begin
    Jumlah := Jumlah + 1;
    Data[Jumlah].NIM := NIM;
    Data[Jumlah].Nama := Nama;
    Data[Jumlah].IPK := IPK;
  end;
end;

procedure TampilkanSatu(I: Integer);
begin
  with Data[I] do
    WriteLn(NIM, '':12 - Length(NIM), Nama, '':27 - Length(Nama), IPK:4:2);
end;

procedure TampilkanSemua;
var
  I: Integer;
begin
  WriteLn('NIM         Nama                        IPK');
  for I := 1 to Jumlah do
    TampilkanSatu(I);
  WriteLn('(', Jumlah, ' mahasiswa)');
end;

{ Mengembalikan nomor elemen, atau 0 bila NIM tidak ditemukan }
function CariNIM(NIM: string): Integer;
var
  I: Integer;
begin
  CariNIM := 0;
  for I := 1 to Jumlah do
    if Data[I].NIM = NIM then
      CariNIM := I;
end;

procedure Statistik;
var
  I, Terbaik: Integer;
  Total: Real;
begin
  if Jumlah = 0 then
  begin
    WriteLn('Belum ada data.');
    Exit;
  end;
  Total := 0;
  Terbaik := 1;
  for I := 1 to Jumlah do
  begin
    Total := Total + Data[I].IPK;
    if Data[I].IPK > Data[Terbaik].IPK then
      Terbaik := I;
  end;
  WriteLn('Rata-rata IPK : ', Total / Jumlah:0:2);
  WriteLn('IPK tertinggi : ', Data[Terbaik].Nama, ' (',
    Data[Terbaik].IPK:0:2, ')');
end;

var
  Pilihan, Posisi: Integer;
  NIM, Nama: string;
  IPK: Real;

begin
  Jumlah := 0;
  Tambah('2601001', 'Andi Pratama', 3.45);     { data contoh }
  Tambah('2601002', 'Bunga Lestari', 3.80);
  Tambah('2601003', 'Candra Wijaya', 2.95);

  repeat
    WriteLn;
    WriteLn('== DATA MAHASISWA ==');
    WriteLn('1. Tambah  2. Tampilkan  3. Cari NIM  4. Statistik  0. Keluar');
    Write('Pilihan: ');
    ReadLn(Pilihan);
    case Pilihan of
      1: begin
           Write('NIM  : '); ReadLn(NIM);
           if CariNIM(NIM) > 0 then
             WriteLn('NIM sudah terdaftar.')
           else
           begin
             Write('Nama : '); ReadLn(Nama);
             Write('IPK  : '); ReadLn(IPK);
             Tambah(NIM, Nama, IPK);
           end;
         end;
      2: TampilkanSemua;
      3: begin
           Write('NIM yang dicari: '); ReadLn(NIM);
           Posisi := CariNIM(NIM);
           if Posisi = 0 then
             WriteLn('Tidak ditemukan.')
           else
             TampilkanSatu(Posisi);
         end;
      4: Statistik;
    end;
  until Pilihan = 0;
end.
