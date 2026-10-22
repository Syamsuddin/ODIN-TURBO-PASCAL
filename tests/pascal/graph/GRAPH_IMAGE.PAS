{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Graph: GetImage, PutImage, viewport, halaman. }
program GRAPH_IMAGE;

uses Graph;

var
  O: Text;

procedure Dump(X1, Y1, X2, Y2: Integer);
var
  X, Y: Integer;
  C: Word;
begin
  for Y := Y1 to Y2 do
  begin
    for X := X1 to X2 do
    begin
      C := GetPixel(X, Y);
      if C = 0 then
        Write(O, '.')
      else if C < 10 then
        Write(O, Chr(48 + C))
      else
        Write(O, Chr(55 + C));
    end;
    WriteLn(O);
  end;
  WriteLn(O);
end;

procedure Source;
var
  I: Integer;
begin
  { Kotak 4x3 berisi warna 1, 2, 3, 5 }
  for I := 0 to 3 do
  begin
    PutPixel(10 + I, 10, 1 + I mod 3);
    PutPixel(10 + I, 11, 5);
    PutPixel(10 + I, 12, 15 - I);
  end;
end;

var
  D, M, I: Integer;
  P: Pointer;
  Sz: LongInt;
  Vp: ViewPortType;
  Op: Word;
begin
  Assign(O, '');
  Rewrite(O);
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');

  WriteLn(O, 'ImageSize: ', ImageSize(0, 0, 3, 2), ' ', ImageSize(3, 2, 0, 0), ' ', ImageSize(5, 5, 5, 5));
  Source;
  Sz := ImageSize(10, 10, 13, 12);
  GetMem(P, Sz);
  GetImage(10, 10, 13, 12, P^);
  WriteLn(O, 'Sumber:');
  Dump(9, 9, 14, 13);
  for Op := CopyPut to NotPut do
  begin
    ClearDevice;
    { Tujuan: baris-baris berwarna 3 dan 6, tanpa sumber }
    for I := 0 to 3 do
    begin
      PutPixel(20 + I, 10, 3);
      PutPixel(20 + I, 11, 6);
      PutPixel(20 + I, 12, 12);
    end;
    PutImage(20, 10, P^, Op);
    WriteLn(O, 'PutImage operasi ', Op, ' di atas 3/6/12:');
    Dump(19, 9, 24, 13);
  end;
  ClearDevice;
  PutImage(30, 30, P^, 5);
  WriteLn(O, 'operasi 5: err=', GraphResult);

  WriteLn(O, 'PutImage terpotong di tepi layar');
  Source;
  PutImage(638, 478, P^, CopyPut);
  WriteLn(O, GetPixel(638, 478), GetPixel(639, 478), GetPixel(638, 479), GetPixel(639, 479));
  PutImage(-2, -1, P^, CopyPut);
  Dump(0, 0, 3, 2);
  ClearDevice;

  WriteLn(O, 'GetImage sebagian di luar layar: bagian luar nol');
  PutPixel(0, 0, 7);
  PutPixel(1, 0, 8);
  GetImage(-1, 0, 1, 0, P^);
  PutImage(100, 100, P^, CopyPut);
  Dump(99, 99, 103, 101);
  FreeMem(P, Sz);
  ClearDevice;

  WriteLn(O, 'Viewport (20,10)-(40,20) dengan klip');
  SetViewPort(20, 10, 40, 20, ClipOn);
  GetViewSettings(Vp);
  WriteLn(O, Vp.X1, ',', Vp.Y1, ',', Vp.X2, ',', Vp.Y2, ' klip=', Vp.Clip);
  SetColor(4);
  Line(-5, 0, 30, 0);
  Rectangle(0, 0, 20, 10);
  SetFillStyle(SolidFill, 2);
  Bar(15, 5, 50, 30);
  PutPixel(5, 5, 9);
  WriteLn(O, 'GetPixel(5,5)=', GetPixel(5, 5), ' GetPixel(50,50)=', GetPixel(50, 50));
  MoveTo(3, 4);
  WriteLn(O, 'titik kini ', GetX, ',', GetY);
  SetViewPort(0, 0, 639, 479, ClipOn);
  Dump(18, 8, 44, 22);
  WriteLn(O, 'GetPixel(25,15) layar=', GetPixel(25, 15));

  WriteLn(O, 'Viewport tanpa klip menggambar keluar');
  ClearDevice;
  SetViewPort(10, 10, 20, 20, ClipOff);
  Line(0, 0, 40, 0);
  PutPixel(-5, -5, 3);
  SetViewPort(0, 0, 639, 479, ClipOn);
  WriteLn(O, GetPixel(50, 10), GetPixel(5, 5), GetPixel(60, 10));

  WriteLn(O, 'ClearViewPort hanya membersihkan viewport dan memindahkan titik kini ke 0,0');
  PutPixel(5, 5, 1);
  PutPixel(15, 15, 2);
  SetViewPort(10, 10, 20, 20, ClipOn);
  MoveTo(4, 4);
  ClearViewPort;
  WriteLn(O, 'titik kini ', GetX, ',', GetY);
  SetViewPort(0, 0, 639, 479, ClipOn);
  WriteLn(O, GetPixel(5, 5), GetPixel(15, 15));

  WriteLn(O, 'Viewport tidak sah');
  SetViewPort(10, 10, 5, 20, ClipOn);
  WriteLn(O, 'x2 < x1: ', GraphResult);
  SetViewPort(0, 0, 640, 479, ClipOn);
  WriteLn(O, 'x2 di luar layar: ', GraphResult);
  SetViewPort(-1, 0, 10, 10, ClipOn);
  WriteLn(O, 'x1 negatif: ', GraphResult);
  GetViewSettings(Vp);
  WriteLn(O, 'viewport tetap ', Vp.X1, ',', Vp.Y1, ',', Vp.X2, ',', Vp.Y2);
  CloseGraph;

  WriteLn(O, 'Halaman (EGALo: 4 halaman)');
  D := EGA;
  M := EGALo;
  InitGraph(D, M, '');
  PutPixel(1, 1, 5);
  SetActivePage(1);
  WriteLn(O, 'halaman 1 kosong: ', GetPixel(1, 1));
  PutPixel(1, 1, 6);
  SetActivePage(0);
  WriteLn(O, 'halaman 0: ', GetPixel(1, 1));
  SetActivePage(3);
  SetActivePage(4);
  WriteLn(O, 'halaman 4: ', GraphResult);
  SetVisualPage(4);
  WriteLn(O, 'visual 4: ', GraphResult);
  SetVisualPage(1);
  WriteLn(O, 'GetPixel mengikuti halaman aktif (3): ', GetPixel(1, 1));
  SetActivePage(1);
  ClearDevice;
  WriteLn(O, 'ClearDevice halaman 1: ', GetPixel(1, 1));
  SetActivePage(0);
  WriteLn(O, 'halaman 0 tetap: ', GetPixel(1, 1));
  CloseGraph;
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');
  SetActivePage(1);
  WriteLn(O, 'VGAHi hanya satu halaman: ', GraphResult);
  CloseGraph;
  Close(O);
end.
