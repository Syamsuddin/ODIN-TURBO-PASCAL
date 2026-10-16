{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 15.3 - Mencari data di array of record
  Pencarian beruntun pada data barang: menurut kode (harus sama
  persis) dan menurut nama (cukup sebagian, huruf besar/kecil
  diabaikan). }

program bab15_03_cari_data_record;

type
  TBarang = record
    Kode: string[4];
    Nama: string[20];
    Harga: LongInt;
    Stok: Integer;
  end;

const
  N = 6;
  Gudang: array[1..N] of TBarang = (
    (Kode: 'A001'; Nama: 'Buku tulis';    Harga: 5000;  Stok: 120),
    (Kode: 'A002'; Nama: 'Pensil 2B';     Harga: 3500;  Stok: 200),
    (Kode: 'A003'; Nama: 'Penghapus';     Harga: 2000;  Stok: 75),
    (Kode: 'B001'; Nama: 'Buku gambar';   Harga: 8000;  Stok: 40),
    (Kode: 'B002'; Nama: 'Pensil warna';  Harga: 25000; Stok: 15),
    (Kode: 'C001'; Nama: 'Penggaris 30';  Harga: 4500;  Stok: 60));

function Kapital(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    S[I] := UpCase(S[I]);                { S salinan, aslinya aman }
  Kapital := S;
end;

procedure Tampilkan(I: Integer);
begin
  with Gudang[I] do
    WriteLn('  ', Kode, '  ', Nama, '':14 - Length(Nama), 'Rp', Harga:7,
      '  stok ', Stok);
end;

var
  Kode, Kata: string;
  I, Posisi, Banyak: Integer;

begin
  { Cari menurut kode: berhenti begitu ketemu }
  Write('Kode barang: ');
  ReadLn(Kode);
  Kode := Kapital(Kode);
  Posisi := 0;
  I := 1;
  while (I <= N) and (Posisi = 0) do
  begin
    if Gudang[I].Kode = Kode then
      Posisi := I;
    I := I + 1;
  end;
  if Posisi > 0 then
    Tampilkan(Posisi)
  else
    WriteLn('  Kode ', Kode, ' tidak ditemukan.');

  { Cari menurut nama: tampilkan semua yang mengandung kata kunci }
  Write('Kata kunci nama: ');
  ReadLn(Kata);
  Banyak := 0;
  for I := 1 to N do
    if Pos(Kapital(Kata), Kapital(Gudang[I].Nama)) > 0 then
    begin
      Tampilkan(I);
      Banyak := Banyak + 1;
    end;
  WriteLn('  ', Banyak, ' barang cocok.');
end.
