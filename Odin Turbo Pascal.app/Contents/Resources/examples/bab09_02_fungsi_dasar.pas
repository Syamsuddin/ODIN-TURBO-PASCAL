{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 9.2 - Fungsi
  Fungsi mirip prosedur, tetapi menghasilkan sebuah nilai. Tipe nilai
  ditulis sesudah titik dua. Di dalam fungsi, nilai hasil diberikan
  dengan mengisi nama fungsinya: NamaFungsi := nilai. }

program bab09_02_fungsi_dasar;

function Kuadrat(X: LongInt): LongInt;
begin
  Kuadrat := X * X;                      { nilai yang dikembalikan }
end;

function Terbesar(A, B: Integer): Integer;
begin
  if A > B then
    Terbesar := A
  else
    Terbesar := B;
end;

function Genap(N: Integer): Boolean;
begin
  Genap := N mod 2 = 0;                  { hasil perbandingan: Boolean }
end;

function LuasLingkaran(R: Real): Real;
begin
  LuasLingkaran := Pi * R * R;
end;

var
  Hasil: LongInt;

begin
  Hasil := Kuadrat(12);                  { hasil fungsi disimpan }
  WriteLn('Kuadrat 12       = ', Hasil);
  { Fungsi juga bisa langsung dipakai di dalam ekspresi }
  WriteLn('Kuadrat 3 + 4    = ', Kuadrat(3) + Kuadrat(4));
  WriteLn('Terbesar(17, 42) = ', Terbesar(17, 42));
  WriteLn('Genap(7)?          ', Genap(7));
  WriteLn('Luas lingkaran r=7: ', LuasLingkaran(7):0:2);
  if Genap(Terbesar(10, 3)) then         { fungsi di dalam fungsi }
    WriteLn('Bilangan terbesar dari 10 dan 3 adalah genap.');
end.
