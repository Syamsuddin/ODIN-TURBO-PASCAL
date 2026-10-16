{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 12.5 - Konversi angka dan string
  Str(Angka, S)        mengubah bilangan menjadi string (boleh berformat)
  Val(S, Angka, Kode)  mengubah string menjadi bilangan. Kode = 0 bila
                       berhasil, selain itu posisi karakter yang salah.
  Dengan Val, masukan yang salah tidak lagi menghentikan program. }

program bab12_05_konversi_angka_string;

{ Menyisipkan titik setiap tiga digit: 1250000 menjadi 1.250.000.
  Hanya untuk bilangan positif. }
function FormatRibuan(N: LongInt): string;
var
  S: string;
  P: Integer;
begin
  Str(N, S);                             { bilangan -> string }
  P := Length(S) - 2;
  while P > 1 do
  begin
    Insert('.', S, P);
    P := P - 3;
  end;
  FormatRibuan := S;
end;

var
  Teks, Hasil: string;
  Harga: LongInt;
  Kode: Integer;
  Pajak: Real;

begin
  { Membaca sebagai string dulu, lalu diperiksa dengan Val }
  repeat
    Write('Harga barang (angka saja): ');
    ReadLn(Teks);
    Val(Teks, Harga, Kode);              { string -> bilangan }
    if Kode <> 0 then
      WriteLn('  "', Teks, '" bukan angka (salah di karakter ke-',
        Kode, '). Coba lagi.')
    else if Harga < 0 then
      WriteLn('  Harga tidak boleh negatif.');
  until (Kode = 0) and (Harga >= 0);

  WriteLn('Harga      : Rp ', FormatRibuan(Harga));

  Pajak := Harga * 0.11;
  Str(Pajak:0:2, Hasil);                 { Str juga menerima format }
  WriteLn('PPN 11%    : Rp ', Hasil, ' (', Length(Hasil), ' karakter)');

  Str(Harga, Hasil);
  WriteLn('Jumlah digit harga: ', Length(Hasil));
end.
