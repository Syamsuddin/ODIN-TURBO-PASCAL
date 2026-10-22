{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Graph: pola isian, Bar, Bar3D, FillPoly, FloodFill. }
program GRAPH_FILL;

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

var
  D, M, I, J: Integer;
  P: FillPatternType;
  Fs: FillSettingsType;
  Tri: array[1..3] of PointType;
  Ell: array[1..6] of PointType;
  Star: array[1..5] of PointType;
begin
  Assign(O, '');
  Rewrite(O);
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');

  WriteLn(O, 'Pola isian bawaan, Bar(0,0,15,7), warna 1 (0 = latar)');
  for I := EmptyFill to CloseDotFill do
  begin
    SetFillStyle(I, 1);
    Bar(0, 0, 15, 7);
    WriteLn(O, 'gaya ', I);
    Dump(0, 0, 15, 7);
    GetFillPattern(P);
    Write(O, 'pola:');
    for J := 1 to 8 do
      Write(O, ' ', P[J]);
    WriteLn(O);
    ClearDevice;
  end;

  WriteLn(O, 'Pola pemakai');
  for J := 1 to 8 do
    P[J] := 0;
  P[1] := $81;
  P[2] := $42;
  P[3] := $24;
  P[4] := $18;
  SetFillPattern(P, 6);
  GetFillSettings(Fs);
  WriteLn(O, 'pola=', Fs.Pattern, ' warna=', Fs.Color);
  Bar(0, 0, 15, 7);
  Dump(0, 0, 15, 7);
  ClearDevice;

  WriteLn(O, 'Pola mengikuti koordinat layar, bukan sudut Bar: Bar(3,3,12,10)');
  SetFillStyle(LtSlashFill, 2);
  Bar(3, 3, 12, 10);
  Dump(0, 0, 15, 12);
  ClearDevice;

  WriteLn(O, 'Bar dengan sudut terbalik dan kasus tepi');
  SetFillStyle(SolidFill, 4);
  Bar(8, 5, 2, 1);
  Bar(10, 10, 10, 10);
  Dump(0, 0, 11, 11);
  ClearDevice;

  WriteLn(O, 'Galat');
  SetFillStyle(13, 1);
  WriteLn(O, 'gaya 13: ', GraphResult);
  SetFillStyle(SolidFill, 16);
  WriteLn(O, 'warna 16: ', GraphResult);
  GetFillSettings(Fs);
  WriteLn(O, 'tetap ', Fs.Pattern, ',', Fs.Color);

  WriteLn(O, 'Bar3D dengan dan tanpa tutup, kedalaman 4');
  SetFillStyle(SolidFill, 9);
  SetColor(15);
  Bar3D(2, 7, 9, 13, 4, TopOn);
  Bar3D(16, 7, 23, 13, 4, TopOff);
  Dump(0, 0, 29, 14);
  ClearDevice;

  WriteLn(O, 'FillPoly: segitiga dan bentuk cekung');
  SetColor(14);
  SetFillStyle(SolidFill, 2);
  Tri[1].X := 2;
  Tri[1].Y := 1;
  Tri[2].X := 12;
  Tri[2].Y := 1;
  Tri[3].X := 2;
  Tri[3].Y := 9;
  FillPoly(3, Tri);
  Dump(0, 0, 14, 10);
  ClearDevice;
  Ell[1].X := 1;
  Ell[1].Y := 1;
  Ell[2].X := 4;
  Ell[2].Y := 1;
  Ell[3].X := 4;
  Ell[3].Y := 6;
  Ell[4].X := 9;
  Ell[4].Y := 6;
  Ell[5].X := 9;
  Ell[5].Y := 9;
  Ell[6].X := 1;
  Ell[6].Y := 9;
  FillPoly(6, Ell);
  Dump(0, 0, 11, 11);
  ClearDevice;
  WriteLn(O, 'FillPoly bintang (even-odd)');
  Star[1].X := 6;
  Star[1].Y := 0;
  Star[2].X := 10;
  Star[2].Y := 12;
  Star[3].X := 0;
  Star[3].Y := 4;
  Star[4].X := 12;
  Star[4].Y := 4;
  Star[5].X := 2;
  Star[5].Y := 12;
  SetFillStyle(SolidFill, 5);
  FillPoly(5, Star);
  Dump(0, 0, 12, 12);
  ClearDevice;

  WriteLn(O, 'FloodFill di dalam kotak, berhenti di batas warna 12');
  SetColor(12);
  Rectangle(1, 1, 12, 8);
  Line(7, 1, 7, 8);
  SetFillStyle(SolidFill, 3);
  FloodFill(3, 3, 12);
  Dump(0, 0, 14, 10);
  WriteLn(O, 'FloodFill dari titik di batas tidak mengisi apa-apa');
  FloodFill(7, 4, 12);
  Dump(0, 0, 14, 10);
  WriteLn(O, 'FloodFill di luar kotak dengan pola, batas 12');
  SetFillStyle(HatchFill, 6);
  FloodFill(0, 0, 12);
  Dump(0, 0, 14, 10);
  ClearDevice;

  WriteLn(O, 'FloodFill menembus lorong berkelok');
  SetColor(7);
  Line(0, 0, 14, 0);
  Line(14, 0, 14, 8);
  Line(14, 8, 2, 8);
  Line(2, 8, 2, 2);
  Line(2, 2, 11, 2);
  Line(11, 2, 11, 5);
  Line(11, 5, 5, 5);
  SetFillStyle(SolidFill, 1);
  FloodFill(1, 1, 7);
  Dump(0, 0, 15, 9);
  ClearDevice;
  CloseGraph;
  Close(O);
end.
