{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 3.4 - Konstanta
  Konstanta adalah nama untuk nilai yang tidak berubah selama program
  berjalan. Bila nilainya perlu diganti, cukup ubah di satu tempat. }

program bab03_04_konstanta;

const
  NamaToko = 'Toko Buku Pelita';   { konstanta teks }
  HargaBuku = 45000;               { konstanta bilangan bulat }
  Diskon = 0.10;                   { konstanta pecahan: 10 persen }
  JumlahBeli = 3;

var
  Total, Potongan: Real;

begin
  Total := HargaBuku * JumlahBeli;
  Potongan := Total * Diskon;

  WriteLn(NamaToko);
  WriteLn('Harga buku : Rp ', HargaBuku);
  WriteLn('Jumlah     : ', JumlahBeli, ' buku');
  WriteLn('Total      : Rp ', Total:0:0);
  WriteLn('Diskon 10% : Rp ', Potongan:0:0);
  WriteLn('Bayar      : Rp ', Total - Potongan:0:0);

  { Konstanta tidak bisa diubah. Hapus tanda komentar pada baris
    berikut, lalu kompilasi: kompiler akan menolaknya.
    HargaBuku := 50000;
  }
end.
