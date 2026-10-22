{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Graph: lingkaran, busur, elips, pie, sektor. Lintasan dihitung dengan Sin dan Cos,
  jadi tes memeriksa sifat bentuknya (titik ekstrem, isi, rentang jumlah piksel), bukan
  setiap pikselnya. }
program GRAPH_SHAPES;

uses Graph;

var
  O: Text;

function Count(X1, Y1, X2, Y2: Integer): Integer;
var
  X, Y, N: Integer;
begin
  N := 0;
  for Y := Y1 to Y2 do
    for X := X1 to X2 do
      if GetPixel(X, Y) <> 0 then
        Inc(N);
  Count := N;
end;

procedure Check(const What: String; Ok: Boolean);
begin
  if Ok then
    WriteLn(O, What, ': ya')
  else
    WriteLn(O, What, ': TIDAK');
end;

var
  D, M: Integer;
  Ac: ArcCoordsType;
  N: Integer;
begin
  Assign(O, '');
  Rewrite(O);
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');
  SetColor(9);

  WriteLn(O, 'Lingkaran jari-jari 100 di (300,200), mode VGAHi (piksel persegi)');
  Circle(300, 200, 100);
  Check('titik kanan', GetPixel(400, 200) = 9);
  Check('titik kiri', GetPixel(200, 200) = 9);
  Check('titik atas', GetPixel(300, 100) = 9);
  Check('titik bawah', GetPixel(300, 300) = 9);
  Check('pusat kosong', GetPixel(300, 200) = 0);
  Check('di luar kosong', GetPixel(401, 200) = 0);
  N := Count(190, 90, 410, 310);
  Check('jumlah piksel 600..900', (N >= 600) and (N <= 900));
  ClearDevice;

  WriteLn(O, 'Circle(x, y, 0) menggambar satu titik');
  Circle(50, 50, 0);
  WriteLn(O, Count(40, 40, 60, 60), ' piksel, di tengah: ', GetPixel(50, 50));
  ClearDevice;

  WriteLn(O, 'Elips 80 x 30 di (300,200)');
  Ellipse(300, 200, 0, 360, 80, 30);
  Check('kanan', GetPixel(380, 200) = 9);
  Check('kiri', GetPixel(220, 200) = 9);
  Check('atas', GetPixel(300, 170) = 9);
  Check('bawah', GetPixel(300, 230) = 9);
  Check('di luar atas', GetPixel(300, 169) = 0);
  ClearDevice;

  WriteLn(O, 'Busur 0..90 derajat: seperempat kanan atas');
  Arc(300, 200, 0, 90, 50);
  GetArcCoords(Ac);
  WriteLn(O, 'pusat ', Ac.X, ',', Ac.Y, ' awal ', Ac.Xstart, ',', Ac.Ystart, ' akhir ', Ac.Xend, ',', Ac.Yend);
  Check('titik awal', GetPixel(350, 200) = 9);
  Check('titik akhir', GetPixel(300, 150) = 9);
  Check('kiri bawah kosong', Count(240, 205, 299, 260) = 0);
  Check('kanan atas ada', Count(301, 150, 350, 199) > 40);
  ClearDevice;

  WriteLn(O, 'Busur 270..90 melewati 0 derajat: setengah kanan');
  Arc(300, 200, 270, 90, 50);
  Check('kanan ada', Count(301, 150, 350, 250) > 100);
  Check('kiri kosong', Count(240, 150, 299, 250) = 0);
  ClearDevice;

  WriteLn(O, 'Busur 90..180, GetArcCoords');
  Arc(300, 200, 90, 180, 100);
  GetArcCoords(Ac);
  WriteLn(O, 'awal ', Ac.Xstart, ',', Ac.Ystart, ' akhir ', Ac.Xend, ',', Ac.Yend);
  ClearDevice;

  WriteLn(O, 'FillEllipse: isi memakai warna isian, tepi warna garis');
  SetFillStyle(SolidFill, 4);
  FillEllipse(300, 200, 60, 40);
  WriteLn(O, 'pusat ', GetPixel(300, 200), ' tepi kanan ', GetPixel(360, 200), ' tepi atas ', GetPixel(300, 160),
    ' dekat tepi ', GetPixel(350, 200));
  Check('luar kosong', GetPixel(362, 200) = 0);
  ClearDevice;

  WriteLn(O, 'PieSlice 0..90: pusat terisi, dua jari-jari menjadi tepi');
  SetFillStyle(SolidFill, 2);
  PieSlice(300, 200, 0, 90, 80);
  WriteLn(O, 'pusat ', GetPixel(300, 200), ' dalam ', GetPixel(330, 170), ' jari-jari ', GetPixel(340, 200), ',',
    GetPixel(300, 160));
  Check('kiri bawah kosong', Count(200, 205, 299, 280) = 0);
  ClearDevice;

  WriteLn(O, 'Sector 0..360 elips 60 x 20 = elips penuh dengan jari-jari');
  Sector(300, 200, 0, 360, 60, 20);
  WriteLn(O, 'dalam ', GetPixel(320, 200), ' kanan ', GetPixel(360, 200));
  ClearDevice;

  CloseGraph;

  WriteLn(O, 'Mode VGALo (640x200): piksel tinggi, jari-jari vertikal = 100 * 4400 / 10000');
  D := VGA;
  M := VGALo;
  InitGraph(D, M, '');
  SetColor(14);
  Circle(320, 100, 100);
  Check('kanan', GetPixel(420, 100) = 14);
  Check('atas, 44 piksel', GetPixel(320, 56) = 14);
  Check('bukan 45', GetPixel(320, 55) = 0);
  ClearDevice;
  SetAspectRatio(10000, 10000);
  Circle(320, 100, 50);
  Check('aspek 1:1, atas 50 piksel', GetPixel(320, 50) = 14);
  CloseGraph;
  Close(O);
end.
