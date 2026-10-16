{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 7.6 - Latihan: menu berulang
  Gabungan repeat..until dan case: menu tampil terus sampai pengguna
  memilih 0 (keluar). Pola ini dipakai di banyak program interaktif. }

program bab07_06_menu_berulang;

var
  Pilihan: Integer;
  Celsius, Fahrenheit, Kilometer: Real;

begin
  repeat
    WriteLn;
    WriteLn('=== KONVERSI SATUAN ===');
    WriteLn('1. Celsius ke Fahrenheit');
    WriteLn('2. Fahrenheit ke Celsius');
    WriteLn('3. Kilometer ke mil');
    WriteLn('0. Keluar');
    Write('Pilihan: ');
    ReadLn(Pilihan);

    case Pilihan of
      1: begin
           Write('Suhu Celsius   : '); ReadLn(Celsius);
           WriteLn('Hasil          : ', Celsius * 9 / 5 + 32:0:1, ' F');
         end;
      2: begin
           Write('Suhu Fahrenheit: '); ReadLn(Fahrenheit);
           WriteLn('Hasil          : ', (Fahrenheit - 32) * 5 / 9:0:1, ' C');
         end;
      3: begin
           Write('Jarak (km)     : '); ReadLn(Kilometer);
           WriteLn('Hasil          : ', Kilometer * 0.621371:0:2, ' mil');
         end;
      0: WriteLn('Terima kasih!');
    else
      WriteLn('Pilihan tidak tersedia.');
    end;
  until Pilihan = 0;                     { keluar saat memilih 0 }
end.
