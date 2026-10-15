{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 20.3 - Proyek: buku telepon
  Data kontak dibaca dari file saat program mulai, diolah di array
  (tampil, tambah, cari, hapus), lalu ditulis kembali ke file saat
  keluar. Kontak selalu disimpan urut nama, jadi tampilannya rapi.
  Jalankan beberapa kali: kontak yang disimpan tidak hilang. }

program bab20_03_buku_telepon;

const
  NamaFileData = 'kontak.dat';
  MaksKontak = 100;
  KarakterTelepon = ['0'..'9', '+', '-', ' '];

type
  TKontak = record
    Nama: string[25];
    Telepon: string[15];
    Email: string[30];
  end;

var
  Kontak: array[1..MaksKontak] of TKontak;
  Jumlah: Integer;
  Berubah: Boolean;                      { ada perubahan yang belum disimpan }

function Kapital(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    S[I] := UpCase(S[I]);
  Kapital := S;
end;

procedure Muat;
var
  F: file of TKontak;
begin
  Jumlah := 0;
  Assign(F, NamaFileData);
  {$I-}
  Reset(F);
  {$I+}
  if IOResult <> 0 then
    Exit;                                { belum ada file: mulai kosong }
  while not Eof(F) and (Jumlah < MaksKontak) do
  begin
    Jumlah := Jumlah + 1;
    Read(F, Kontak[Jumlah]);
  end;
  Close(F);
end;

procedure Simpan;
var
  F: file of TKontak;
  I: Integer;
begin
  Assign(F, NamaFileData);
  Rewrite(F);                            { tulis ulang seluruh isi }
  for I := 1 to Jumlah do
    Write(F, Kontak[I]);
  Close(F);
  Berubah := False;
end;

procedure TampilkanSatu(I: Integer);
begin
  with Kontak[I] do
    WriteLn(I:3, '. ', Nama, '':26 - Length(Nama), Telepon,
      '':16 - Length(Telepon), Email);
end;

procedure TampilkanSemua;
var
  I: Integer;
begin
  if Jumlah = 0 then
    WriteLn('Buku telepon masih kosong.')
  else
  begin
    WriteLn('No.  Nama                      Telepon         Email');
    for I := 1 to Jumlah do
      TampilkanSatu(I);
  end;
end;

function TeleponSah(T: string): Boolean;
var
  I: Integer;
begin
  TeleponSah := Length(T) >= 6;
  for I := 1 to Length(T) do
    if not (T[I] in KarakterTelepon) then
      TeleponSah := False;
end;

procedure Tambah;
var
  Baru: TKontak;
  Nama, Telepon: string;
  Posisi, I: Integer;
begin
  if Jumlah = MaksKontak then
  begin
    WriteLn('Buku telepon penuh.');
    Exit;
  end;
  Write('Nama    : '); ReadLn(Nama);
  if Nama = '' then Exit;
  repeat
    Write('Telepon : '); ReadLn(Telepon);
    if not TeleponSah(Telepon) then
      WriteLn('  Hanya angka, +, -, spasi; minimal 6 karakter.');
  until TeleponSah(Telepon);
  Baru.Nama := Nama;
  Baru.Telepon := Telepon;
  Write('Email   : '); ReadLn(Baru.Email);

  { Cari tempat agar urutan nama tetap terjaga, lalu geser ke kanan }
  Posisi := Jumlah + 1;
  while (Posisi > 1) and
        (Kapital(Kontak[Posisi - 1].Nama) > Kapital(Baru.Nama)) do
    Posisi := Posisi - 1;
  for I := Jumlah downto Posisi do
    Kontak[I + 1] := Kontak[I];
  Kontak[Posisi] := Baru;
  Jumlah := Jumlah + 1;
  Berubah := True;
  WriteLn('Kontak ditambahkan.');
end;

procedure Cari;
var
  Kata: string;
  I, Ketemu: Integer;
begin
  Write('Cari nama: '); ReadLn(Kata);
  Ketemu := 0;
  for I := 1 to Jumlah do
    if Pos(Kapital(Kata), Kapital(Kontak[I].Nama)) > 0 then
    begin
      TampilkanSatu(I);
      Ketemu := Ketemu + 1;
    end;
  WriteLn(Ketemu, ' kontak ditemukan.');
end;

procedure Hapus;
var
  Nomor, I: Integer;
  Teks: string;
  Kode: Integer;
  Yakin: Char;
begin
  TampilkanSemua;
  if Jumlah = 0 then Exit;
  Write('Nomor yang dihapus: '); ReadLn(Teks);
  Val(Teks, Nomor, Kode);
  if (Kode <> 0) or (Nomor < 1) or (Nomor > Jumlah) then
  begin
    WriteLn('Nomor tidak ada.');
    Exit;
  end;
  Write('Hapus ', Kontak[Nomor].Nama, ' (Y/T)? '); ReadLn(Yakin);
  if UpCase(Yakin) = 'Y' then
  begin
    for I := Nomor to Jumlah - 1 do      { geser ke kiri menutup celah }
      Kontak[I] := Kontak[I + 1];
    Jumlah := Jumlah - 1;
    Berubah := True;
    WriteLn('Kontak dihapus.');
  end;
end;

var
  Pilihan: string;
  Folder: string;

begin
  Muat;
  Berubah := False;
  GetDir(0, Folder);
  WriteLn('BUKU TELEPON - ', Jumlah, ' kontak dimuat dari ', NamaFileData);
  WriteLn('Folder data: ', Folder);
  repeat
    WriteLn;
    WriteLn('1. Tampilkan  2. Tambah  3. Cari  4. Hapus  0. Simpan & keluar');
    Write('Pilihan: '); ReadLn(Pilihan);
    if Pilihan = '1' then TampilkanSemua
    else if Pilihan = '2' then Tambah
    else if Pilihan = '3' then Cari
    else if Pilihan = '4' then Hapus
    else if Pilihan <> '0' then WriteLn('Pilihan tidak tersedia.');
  until Pilihan = '0';

  if Berubah then
  begin
    Simpan;
    WriteLn(Jumlah, ' kontak disimpan ke ', NamaFileData, '.');
  end
  else
    WriteLn('Tidak ada perubahan.');
end.
