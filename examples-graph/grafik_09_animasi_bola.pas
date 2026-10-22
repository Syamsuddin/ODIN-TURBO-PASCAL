{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 9 - Animasi tanpa kedip dengan dua halaman
  Mode EGAHi punya 2 halaman gambar. Gambar baru dibuat di halaman yang tidak
  terlihat (SetActivePage), lalu ditukar (SetVisualPage). Jadi layar tidak
  pernah menampilkan gambar yang setengah jadi. Bola memantul di dinding. }

program grafik_09_animasi_bola;

uses Crt, Graph;

const
  Jari = 18;
  Lebar = 639;
  Tinggi = 349;                         { EGAHi: 640 x 350 }

var
  Driver, Mode, Halaman: Integer;
  X, Y, Dx, Dy, Langkah: Integer;

begin
  Driver := EGA;
  Mode := EGAHi;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  X := 100; Y := 80; Dx := 6; Dy := 4;
  Halaman := 0;
  Langkah := 0;
  while (not KeyPressed) and (Langkah < 600) do
  begin
    SetActivePage(Halaman);            { menggambar di halaman yang tersembunyi }
    ClearDevice;
    SetColor(White);
    Rectangle(0, 0, Lebar, Tinggi);
    SetFillStyle(SolidFill, LightRed);
    SetColor(Yellow);
    FillEllipse(X, Y, Jari, Jari * 77 div 100);   { piksel EGA lebih tinggi }
    OutTextXY(10, 10, 'Tekan sembarang tombol untuk berhenti');

    SetVisualPage(Halaman);            { tukar: halaman ini kini terlihat }
    Halaman := 1 - Halaman;

    X := X + Dx;
    Y := Y + Dy;
    if (X < Jari) or (X > Lebar - Jari) then Dx := -Dx;
    if (Y < Jari) or (Y > Tinggi - Jari) then Dy := -Dy;
    Inc(Langkah);
    Delay(25);
  end;
  if KeyPressed then ReadKey;
  CloseGraph;
end.
