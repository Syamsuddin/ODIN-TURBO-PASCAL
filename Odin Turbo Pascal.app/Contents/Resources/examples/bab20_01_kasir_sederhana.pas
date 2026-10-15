{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 20.1 - Proyek: kasir sederhana
  Gabungan materi: record, array, fungsi, validasi dengan Val, dan
  file teks. Kasir mencatat belanjaan, menghitung diskon dan kembalian,
  lalu mencetak struk ke layar sekaligus menyimpannya ke file.
  Trik: prosedur CetakStruk menerima variabel Text, jadi bisa diberi
  Output (layar) atau variabel file. }

program bab20_01_kasir_sederhana;

const
  NamaFileStruk = 'struk.txt';
  BatasDiskon = 100000;                  { belanja minimal untuk diskon }
  PersenDiskon = 10;
  JumlahBarang = 6;
  MaksBelanja = 20;

type
  TBarang = record
    Kode: string[3];
    Nama: string[18];
    Harga: LongInt;
  end;
  TBelanja = record
    Barang: Integer;                     { nomor barang di DaftarBarang }
    Jumlah: Integer;
  end;

const
  DaftarBarang: array[1..JumlahBarang] of TBarang = (
    (Kode: 'B01'; Nama: 'Beras 5 kg';      Harga: 72000),
    (Kode: 'B02'; Nama: 'Minyak goreng 1L'; Harga: 18500),
    (Kode: 'B03'; Nama: 'Gula pasir 1 kg'; Harga: 17000),
    (Kode: 'B04'; Nama: 'Telur 1 kg';      Harga: 29000),
    (Kode: 'B05'; Nama: 'Teh celup';       Harga: 7500),
    (Kode: 'B06'; Nama: 'Sabun mandi';     Harga: 4500));

var
  Belanja: array[1..MaksBelanja] of TBelanja;
  BanyakBelanja: Integer;
  Total, Diskon, Bayar: LongInt;

function Rupiah(N: LongInt): string;     { 72000 -> 'Rp 72.000' }
var
  S: string;
  P: Integer;
begin
  Str(N, S);
  P := Length(S) - 2;
  while P > 1 do
  begin
    Insert('.', S, P);
    P := P - 3;
  end;
  Rupiah := 'Rp ' + S;
end;

{ Membaca bilangan dengan aman: diulang sampai sah dan >= Minimal }
function BacaBilangan(Pesan: string; Minimal: LongInt): LongInt;
var
  Teks: string;
  Nilai: LongInt;
  Kode: Integer;
begin
  repeat
    Write(Pesan);
    ReadLn(Teks);
    Val(Teks, Nilai, Kode);
    if (Kode <> 0) or (Nilai < Minimal) then
      WriteLn('  Masukkan angka minimal ', Minimal, '.');
  until (Kode = 0) and (Nilai >= Minimal);
  BacaBilangan := Nilai;
end;

function CariBarang(Kode: string): Integer;   { 0 bila tidak ada }
var
  I: Integer;
begin
  CariBarang := 0;
  for I := 1 to Length(Kode) do
    Kode[I] := UpCase(Kode[I]);
  for I := 1 to JumlahBarang do
    if DaftarBarang[I].Kode = Kode then
      CariBarang := I;
end;

procedure TampilkanDaftar;
var
  I: Integer;
begin
  WriteLn('Kode  Barang                  Harga');
  for I := 1 to JumlahBarang do
    with DaftarBarang[I] do
      WriteLn(Kode, '   ', Nama, '':18 - Length(Nama), Rupiah(Harga):11);
end;

procedure CatatBelanja;
var
  Kode: string;
  Nomor, I, Ada: Integer;
  Jumlah: LongInt;
begin
  BanyakBelanja := 0;
  repeat
    Write('Kode barang (kosong = selesai): ');
    ReadLn(Kode);
    if Kode <> '' then
    begin
      Nomor := CariBarang(Kode);
      if Nomor = 0 then
        WriteLn('  Kode tidak dikenal.')
      else
      begin
        Jumlah := BacaBilangan('  Jumlah ' + DaftarBarang[Nomor].Nama +
          ': ', 1);
        Ada := 0;                        { barang sudah ada di keranjang? }
        for I := 1 to BanyakBelanja do
          if Belanja[I].Barang = Nomor then
            Ada := I;
        if Ada > 0 then
          Belanja[Ada].Jumlah := Belanja[Ada].Jumlah + Jumlah
        else if BanyakBelanja < MaksBelanja then
        begin
          BanyakBelanja := BanyakBelanja + 1;
          Belanja[BanyakBelanja].Barang := Nomor;
          Belanja[BanyakBelanja].Jumlah := Jumlah;
        end
        else
          WriteLn('  Keranjang penuh.');
      end;
    end;
  until Kode = '';
end;

procedure CetakStruk(var F: Text);     { F: layar (Output) atau file }
var
  I: Integer;
  Subtotal: LongInt;
begin
  WriteLn(F, '========================================');
  WriteLn(F, '          TOKO SERBA ADA PELITA');
  WriteLn(F, '========================================');
  for I := 1 to BanyakBelanja do
    with DaftarBarang[Belanja[I].Barang] do
    begin
      Subtotal := Harga * Belanja[I].Jumlah;
      WriteLn(F, Nama);
      WriteLn(F, '  ', Belanja[I].Jumlah:3, ' x ', Rupiah(Harga):11,
        Rupiah(Subtotal):20);
    end;
  WriteLn(F, '----------------------------------------');
  WriteLn(F, 'Total    ', Rupiah(Total):31);
  if Diskon > 0 then
    WriteLn(F, 'Diskon ', PersenDiskon, '%', Rupiah(Diskon):30);
  WriteLn(F, 'Dibayar  ', Rupiah(Total - Diskon):31);
  WriteLn(F, 'Tunai    ', Rupiah(Bayar):31);
  WriteLn(F, 'Kembali  ', Rupiah(Bayar - (Total - Diskon)):31);
  WriteLn(F, '========================================');
  WriteLn(F, '      Terima kasih atas kunjungan Anda');
end;

var
  I: Integer;
  FileStruk: Text;
  Folder: string;

begin
  TampilkanDaftar;
  WriteLn;
  CatatBelanja;
  if BanyakBelanja = 0 then
  begin
    WriteLn('Tidak ada belanjaan.');
    Exit;                                { Exit di program utama: selesai }
  end;

  Total := 0;
  for I := 1 to BanyakBelanja do
    Total := Total + DaftarBarang[Belanja[I].Barang].Harga *
      Belanja[I].Jumlah;
  if Total >= BatasDiskon then
    Diskon := Total * PersenDiskon div 100
  else
    Diskon := 0;

  WriteLn('Yang harus dibayar: ', Rupiah(Total - Diskon));
  Bayar := BacaBilangan('Uang tunai        : ', Total - Diskon);

  WriteLn;
  CetakStruk(Output);                    { ke layar }
  Assign(FileStruk, NamaFileStruk);
  Rewrite(FileStruk);
  CetakStruk(FileStruk);                 { ke file, isi sama persis }
  Close(FileStruk);
  GetDir(0, Folder);
  WriteLn;
  WriteLn('Struk disimpan ke ', NamaFileStruk, ' di folder ', Folder);
end.
