{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 8.3 - Deret Fibonacci
  Deret 1, 1, 2, 3, 5, 8, 13, ... : setiap suku adalah jumlah dua suku
  sebelumnya. Cukup simpan dua suku terakhir, lalu geser. }

program bab08_03_deret_fibonacci;

const
  BatasSuku = 40;                        { agar tetap dalam rentang LongInt }

var
  N, I: Integer;
  Sebelum, Sekarang, Berikut: LongInt;

begin
  repeat
    Write('Berapa suku (1-', BatasSuku, ')? ');
    ReadLn(N);
  until (N >= 1) and (N <= BatasSuku);

  Sebelum := 0;
  Sekarang := 1;
  for I := 1 to N do
  begin
    WriteLn('Suku ', I:2, ': ', Sekarang:10);
    Berikut := Sebelum + Sekarang;       { jumlah dua suku terakhir }
    Sebelum := Sekarang;                 { geser ke depan }
    Sekarang := Berikut;
  end;
end.
