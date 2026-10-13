{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Kalkulator;
var
  A, B: Real;
  Pilihan: Integer;
begin
  WriteLn('KALKULATOR PASCAL');
  Write('Bilangan pertama: '); ReadLn(A);
  Write('Bilangan kedua  : '); ReadLn(B);
  WriteLn('1. Tambah  2. Kurang  3. Kali  4. Bagi');
  Write('Pilihan: '); ReadLn(Pilihan);
  case Pilihan of
    1: WriteLn('Hasil: ', A + B:0:2);
    2: WriteLn('Hasil: ', A - B:0:2);
    3: WriteLn('Hasil: ', A * B:0:2);
    4: if B = 0 then
         WriteLn('Pembagi tidak boleh nol.')
       else
         WriteLn('Hasil: ', A / B:0:2);
  else
    WriteLn('Pilihan tidak tersedia.');
  end;
end.
