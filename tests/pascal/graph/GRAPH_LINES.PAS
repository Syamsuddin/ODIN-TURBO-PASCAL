{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Graph: piksel, garis (semua arah, gaya, tebal), persegi panjang, titik kini, mode XOR. }
program GRAPH_LINES;

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

procedure Count(const What: String; X1, Y1, X2, Y2: Integer);
var
  X, Y, N: Integer;
begin
  N := 0;
  for Y := Y1 to Y2 do
    for X := X1 to X2 do
      if GetPixel(X, Y) <> 0 then
        Inc(N);
  WriteLn(O, What, ': ', N, ' piksel');
end;

var
  D, M, I: Integer;
  Pts: array[1..4] of PointType;
  Li: LineSettingsType;
begin
  Assign(O, '');
  Rewrite(O);
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');

  WriteLn(O, 'PutPixel dan GetPixel');
  PutPixel(2, 2, 5);
  PutPixel(0, 0, 15);
  PutPixel(639, 479, 9);
  PutPixel(640, 479, 3);
  PutPixel(-1, 0, 3);
  WriteLn(O, GetPixel(2, 2), ' ', GetPixel(0, 0), ' ', GetPixel(639, 479), ' ', GetPixel(640, 479), ' ', GetPixel(1, 1));
  ClearDevice;

  WriteLn(O, 'Garis ke delapan arah dari (8,8)');
  SetColor(1);
  Line(8, 8, 16, 8);
  SetColor(2);
  Line(8, 8, 16, 16);
  SetColor(3);
  Line(8, 8, 8, 16);
  SetColor(4);
  Line(8, 8, 0, 16);
  SetColor(5);
  Line(8, 8, 0, 8);
  SetColor(6);
  Line(8, 8, 0, 0);
  SetColor(7);
  Line(8, 8, 8, 0);
  SetColor(9);
  Line(8, 8, 16, 0);
  Dump(0, 0, 16, 16);
  ClearDevice;

  WriteLn(O, 'Garis landai dan curam');
  SetColor(14);
  Line(0, 0, 20, 5);
  Line(0, 8, 5, 20);
  Line(24, 0, 24, 0);
  Dump(0, 0, 25, 20);
  ClearDevice;

  WriteLn(O, 'Gaya garis: solid, dotted, center, dashed, user $F0F0');
  SetColor(15);
  for I := 0 to 3 do
  begin
    SetLineStyle(I, 0, NormWidth);
    Line(0, I * 2, 39, I * 2);
  end;
  SetLineStyle(UserBitLn, $F0F0, NormWidth);
  Line(0, 8, 39, 8);
  GetLineSettings(Li);
  WriteLn(O, 'style=', Li.LineStyle, ' pattern=', Li.Pattern, ' tebal=', Li.Thickness);
  Dump(0, 0, 39, 8);
  ClearDevice;

  WriteLn(O, 'Garis tebal');
  SetLineStyle(SolidLn, 0, ThickWidth);
  SetColor(10);
  Line(2, 2, 18, 2);
  Line(2, 6, 2, 14);
  Line(6, 6, 16, 14);
  Dump(0, 0, 19, 15);
  ClearDevice;
  SetLineStyle(SolidLn, 0, NormWidth);
  SetLineStyle(5, 0, NormWidth);
  WriteLn(O, 'style 5: err=', GraphResult);
  SetLineStyle(SolidLn, 0, 2);
  WriteLn(O, 'tebal 2: err=', GraphResult);
  GetLineSettings(Li);
  WriteLn(O, 'tetap style=', Li.LineStyle, ' tebal=', Li.Thickness);

  WriteLn(O, 'Persegi panjang, LineTo, LineRel, MoveTo, MoveRel');
  SetColor(12);
  Rectangle(1, 1, 10, 6);
  MoveTo(12, 1);
  WriteLn(O, 'GetX,GetY=', GetX, ',', GetY);
  LineTo(20, 5);
  LineRel(-4, 3);
  WriteLn(O, 'GetX,GetY=', GetX, ',', GetY);
  MoveRel(2, 2);
  LineRel(5, 0);
  WriteLn(O, 'GetX,GetY=', GetX, ',', GetY);
  Dump(0, 0, 27, 12);
  ClearDevice;

  WriteLn(O, 'DrawPoly');
  Pts[1].X := 1;
  Pts[1].Y := 1;
  Pts[2].X := 9;
  Pts[2].Y := 3;
  Pts[3].X := 4;
  Pts[3].Y := 9;
  Pts[4].X := 1;
  Pts[4].Y := 1;
  SetColor(11);
  DrawPoly(4, Pts);
  Dump(0, 0, 10, 10);
  ClearDevice;

  WriteLn(O, 'Mode XOR: dua garis bersilang, lalu garis pertama dihapus');
  SetWriteMode(XORPut);
  SetColor(3);
  Line(0, 0, 8, 8);
  SetColor(5);
  Line(0, 8, 8, 0);
  Dump(0, 0, 8, 8);
  SetColor(3);
  Line(0, 0, 8, 8);
  Dump(0, 0, 8, 8);
  SetWriteMode(CopyPut);
  SetWriteMode(OrPut);
  WriteLn(O, 'SetWriteMode(OrPut): err=', GraphResult);

  WriteLn(O, 'Klip ke layar: garis keluar layar');
  ClearDevice;
  SetColor(8);
  Line(-10, 5, 10, 5);
  Line(630, 470, 700, 500);
  Count('kiri', 0, 0, 20, 10);
  Count('kanan bawah', 620, 460, 639, 479);
  Line(-100, -100, -50, -50);
  Count('seluruh layar', 0, 0, 639, 479);
  CloseGraph;
  Close(O);
end.
