{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program NilaiSiswa;
const
  Jumlah = 5;
var
  Nilai: array[1..Jumlah] of Integer;
  I, Total: Integer;
begin
  Total := 0;
  for I := 1 to Jumlah do
  begin
    Nilai[I] := 60 + I * 5;
    Total := Total + Nilai[I];
    WriteLn('Siswa ', I, ': ', Nilai[I]);
  end;
  WriteLn('Rata-rata: ', Total / Jumlah:0:2);
end.
