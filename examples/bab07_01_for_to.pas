{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 7.1 - Perulangan for..to
  for mengulang perintah sebanyak yang sudah diketahui. Variabel
  pencacah naik 1 setiap putaran, dari nilai awal sampai nilai akhir. }

program bab07_01_for_to;

var
  I, N: Integer;
  Jumlah: LongInt;

begin
  { Menulis 1 sampai 10 dalam satu baris }
  for I := 1 to 10 do
    Write(I, ' ');
  WriteLn;

  { Menjumlahkan 1 + 2 + ... + N }
  Write('Jumlahkan 1 sampai berapa? ');
  ReadLn(N);
  Jumlah := 0;                         { mulai dari nol }
  for I := 1 to N do
    Jumlah := Jumlah + I;              { tambahkan I pada setiap putaran }
  WriteLn('1 + 2 + ... + ', N, ' = ', Jumlah);

  { Lebih dari satu perintah per putaran: pakai begin..end }
  WriteLn('Tabel perkalian ', N, ':');
  for I := 1 to 10 do
  begin
    Write(N:3, ' x ', I:2, ' = ');
    WriteLn(N * I:4);
  end;

  { Jangan mengubah nilai I di dalam badan for: kompiler menolaknya }
end.
