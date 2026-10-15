{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 9.6 - Latihan: kalkulator modular
  Kalkulator dipecah menjadi prosedur dan fungsi kecil. Setiap bagian
  punya satu tugas, sehingga program utama ringkas dan mudah dibaca. }

program bab09_06_kalkulator_modular;

procedure TampilkanMenu;
begin
  WriteLn;
  WriteLn('=== KALKULATOR ===');
  WriteLn('1. Tambah   2. Kurang   3. Kali   4. Bagi   0. Keluar');
  Write('Pilihan: ');
end;

function BacaBilangan(Pesan: string): Real;
var
  X: Real;
begin
  Write(Pesan);
  ReadLn(X);
  BacaBilangan := X;
end;

{ Mengembalikan False bila operasi tidak bisa dihitung }
function Hitung(A, B: Real; Operasi: Integer; var Hasil: Real): Boolean;
begin
  Hitung := True;
  case Operasi of
    1: Hasil := A + B;
    2: Hasil := A - B;
    3: Hasil := A * B;
    4: if B = 0 then
         Hitung := False                 { pembagian dengan nol ditolak }
       else
         Hasil := A / B;
  end;
end;

var
  Pilihan: Integer;
  A, B, Hasil: Real;

begin
  repeat
    TampilkanMenu;
    ReadLn(Pilihan);
    if (Pilihan >= 1) and (Pilihan <= 4) then
    begin
      A := BacaBilangan('Bilangan pertama: ');
      B := BacaBilangan('Bilangan kedua  : ');
      if Hitung(A, B, Pilihan, Hasil) then
        WriteLn('Hasil: ', Hasil:0:2)
      else
        WriteLn('Pembagi tidak boleh nol.');
    end
    else if Pilihan <> 0 then
      WriteLn('Pilihan tidak tersedia.');
  until Pilihan = 0;
  WriteLn('Sampai jumpa!');
end.
