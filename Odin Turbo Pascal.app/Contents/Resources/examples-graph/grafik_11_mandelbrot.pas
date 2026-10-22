{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 11 - Himpunan Mandelbrot
  Tiap piksel (x, y) dipetakan ke bilangan kompleks c. Iterasi z := z*z + c
  dihitung sampai |z| lebih dari 2 atau 40 kali; jumlah putarannya menjadi
  nomor warna. Gambar muncul baris demi baris selagi dihitung, karena
  PutPixel memperbarui jendela grafik. }

program grafik_11_mandelbrot;

uses Crt, Graph;

const
  Maks = 40;

var
  Driver, Mode, X, Y, N: Integer;
  Cr, Ci, Zr, Zi, T: Real;

begin
  Driver := VGA;
  Mode := VGAHi;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  for Y := 0 to 479 do
  begin
    for X := 0 to 639 do
    begin
      Cr := (X - 440) / 200.0;
      Ci := (Y - 240) / 200.0;
      Zr := 0;
      Zi := 0;
      N := 0;
      while (N < Maks) and (Zr * Zr + Zi * Zi < 4) do
      begin
        T := Zr * Zr - Zi * Zi + Cr;
        Zi := 2 * Zr * Zi + Ci;
        Zr := T;
        Inc(N);
      end;
      if N < Maks then
        PutPixel(X, Y, 1 + N mod 15)
      else
        PutPixel(X, Y, Black);
    end;
    if KeyPressed then Break;
  end;

  SetColor(White);
  OutTextXY(10, 10, 'Mandelbrot - tekan sembarang tombol');
  ReadKey;
  CloseGraph;
end.
