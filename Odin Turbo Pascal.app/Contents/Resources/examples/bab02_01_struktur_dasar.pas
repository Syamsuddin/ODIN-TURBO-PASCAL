{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 2.1 - Struktur dasar program Pascal
  Urutan bagian program: judul, uses, const, type, var, lalu blok
  begin..end. Bagian yang tidak diperlukan boleh dihilangkan, tetapi
  urutannya tetap seperti ini. }

program bab02_01_struktur_dasar;  { 1. judul program }

{ 2. uses: daftar unit tambahan. Program ini belum memerlukannya. }

const                             { 3. konstanta: nilai yang tetap }
  HargaTiket = 25000;

type                              { 4. tipe data buatan sendiri }
  TJumlah = Integer;

var                               { 5. variabel: tempat menyimpan data }
  JumlahOrang: TJumlah;
  TotalBayar: LongInt;

begin                             { 6. blok utama, dijalankan berurutan }
  JumlahOrang := 4;               { := artinya "isi dengan" }
  TotalBayar := HargaTiket * JumlahOrang;

  WriteLn('Harga satu tiket : ', HargaTiket);
  WriteLn('Jumlah orang     : ', JumlahOrang);
  WriteLn('Total bayar      : ', TotalBayar);
end.                              { 7. titik menandai akhir program }
