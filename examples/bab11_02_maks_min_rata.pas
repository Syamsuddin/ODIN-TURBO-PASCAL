{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 11.2 - Nilai terbesar, terkecil, dan rata-rata
  Pola umum: anggap elemen pertama sebagai yang terbesar/terkecil,
  lalu bandingkan dengan elemen berikutnya satu per satu. }

program bab11_02_maks_min_rata;

const
  MaksData = 20;                         { kapasitas array }

var
  Data: array[1..MaksData] of Integer;
  N, I: Integer;                         { N = banyak data yang dipakai }
  Terbesar, Terkecil, PosisiBesar: Integer;
  Jumlah: LongInt;

begin
  repeat
    Write('Banyak data (1-', MaksData, '): ');
    ReadLn(N);
  until (N >= 1) and (N <= MaksData);

  for I := 1 to N do
  begin
    Write('Data ke-', I, ': ');
    ReadLn(Data[I]);
  end;

  Terbesar := Data[1];                   { mulai dari elemen pertama }
  Terkecil := Data[1];
  PosisiBesar := 1;
  Jumlah := 0;
  for I := 1 to N do
  begin
    if Data[I] > Terbesar then
    begin
      Terbesar := Data[I];
      PosisiBesar := I;                  { ingat posisinya juga }
    end;
    if Data[I] < Terkecil then
      Terkecil := Data[I];
    Jumlah := Jumlah + Data[I];
  end;

  WriteLn;
  WriteLn('Terbesar  : ', Terbesar, ' (data ke-', PosisiBesar, ')');
  WriteLn('Terkecil  : ', Terkecil);
  WriteLn('Jumlah    : ', Jumlah);
  WriteLn('Rata-rata : ', Jumlah / N:0:2);
end.
