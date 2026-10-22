{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 3 - Bentuk dasar
  Persegi panjang, lingkaran, busur, elips, dan segi banyak (DrawPoly).
  Sudut busur dalam derajat, berlawanan jarum jam dari arah jam 3. }

program grafik_03_bentuk_dasar;

uses Crt, Graph;

var
  Driver, Mode: Integer;
  Segitiga: array[1..4] of PointType;     { titik terakhir = titik pertama: tertutup }
  Bintang: array[1..6] of PointType;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  SetColor(Yellow);
  Rectangle(40, 40, 200, 140);
  OutTextXY(40, 150, 'Rectangle');

  SetColor(LightGreen);
  Circle(320, 90, 50);
  OutTextXY(280, 150, 'Circle');

  SetColor(LightCyan);
  Arc(470, 110, 30, 150, 60);            { busur dari 30 sampai 150 derajat }
  OutTextXY(440, 150, 'Arc');

  SetColor(LightMagenta);
  Ellipse(100, 260, 0, 360, 70, 35);     { pusat, sudut awal, akhir, jari-jari x dan y }
  OutTextXY(60, 310, 'Ellipse');

  Segitiga[1].X := 250; Segitiga[1].Y := 300;
  Segitiga[2].X := 350; Segitiga[2].Y := 300;
  Segitiga[3].X := 300; Segitiga[3].Y := 220;
  Segitiga[4] := Segitiga[1];
  SetColor(LightRed);
  DrawPoly(4, Segitiga);
  OutTextXY(250, 310, 'DrawPoly');

  { Bintang segi lima: loncat dua titik pada lingkaran }
  Bintang[1].X := 520; Bintang[1].Y := 220;
  Bintang[2].X := 560; Bintang[2].Y := 300;
  Bintang[3].X := 480; Bintang[3].Y := 245;
  Bintang[4].X := 560; Bintang[4].Y := 245;
  Bintang[5].X := 480; Bintang[5].Y := 300;
  Bintang[6] := Bintang[1];
  SetColor(White);
  DrawPoly(6, Bintang);
  OutTextXY(480, 310, 'Bintang');

  OutTextXY(40, 440, 'Tekan sembarang tombol...');
  ReadKey;
  CloseGraph;
end.
