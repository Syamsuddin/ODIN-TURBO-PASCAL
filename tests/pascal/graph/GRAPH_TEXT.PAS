{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Graph: teks (font 8x8), ukuran, arah, perataan, titik kini. }
program GRAPH_TEXT;

uses Graph;

var
  O: Text;

procedure Dump(X1, Y1, X2, Y2: Integer);
var
  X, Y: Integer;
begin
  for Y := Y1 to Y2 do
  begin
    for X := X1 to X2 do
      if GetPixel(X, Y) <> 0 then
        Write(O, '#')
      else
        Write(O, '.');
    WriteLn(O);
  end;
  WriteLn(O);
end;

{ Kotak pembatas piksel yang menyala. }
procedure Box(const What: String);
var
  X, Y, X1, Y1, X2, Y2: Integer;
begin
  X1 := 9999;
  Y1 := 9999;
  X2 := -1;
  Y2 := -1;
  for Y := 0 to 100 do
    for X := 0 to 200 do
      if GetPixel(X, Y) <> 0 then
      begin
        if X < X1 then
          X1 := X;
        if X > X2 then
          X2 := X;
        if Y < Y1 then
          Y1 := Y;
        if Y > Y2 then
          Y2 := Y;
      end;
  WriteLn(O, What, ': x ', X1, '..', X2, ' y ', Y1, '..', Y2);
  ClearDevice;
end;

var
  D, M, I: Integer;
  Ts: TextSettingsType;
begin
  Assign(O, '');
  Rewrite(O);
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');
  SetColor(7);

  WriteLn(O, 'Semua huruf ASCII, ukuran 1, tiga baris');
  OutTextXY(0, 0, '!"#$%&''()*+,-./0123456789:;<=>?');
  OutTextXY(0, 8, '@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_');
  OutTextXY(0, 16, '`abcdefghijklmnopqrstuvwxyz{|}~ ');
  Dump(0, 0, 255, 23);
  ClearDevice;

  WriteLn(O, 'Ukuran 2 dan 3: "Ag"');
  SetTextStyle(DefaultFont, HorizDir, 2);
  OutTextXY(0, 0, 'Ag');
  Dump(0, 0, 31, 15);
  ClearDevice;
  SetTextStyle(DefaultFont, HorizDir, 3);
  OutTextXY(0, 0, 'E');
  Dump(0, 0, 23, 23);
  ClearDevice;

  WriteLn(O, 'Teks vertikal "AB": dibaca dari bawah ke atas');
  SetTextStyle(DefaultFont, VertDir, 1);
  OutTextXY(0, 0, 'AB');
  Dump(0, 0, 8, 15);
  ClearDevice;

  WriteLn(O, 'Ukuran huruf');
  SetTextStyle(DefaultFont, HorizDir, 1);
  WriteLn(O, 'ukuran 1: ', TextWidth('Halo'), 'x', TextHeight('Halo'));
  SetTextStyle(DefaultFont, HorizDir, 4);
  WriteLn(O, 'ukuran 4: ', TextWidth('Halo'), 'x', TextHeight('Halo'));
  SetTextStyle(DefaultFont, VertDir, 2);
  WriteLn(O, 'vertikal 2: ', TextWidth('Halo'), 'x', TextHeight('Halo'));
  SetTextStyle(DefaultFont, HorizDir, 0);
  SetUserCharSize(3, 2, 1, 1);
  WriteLn(O, 'pemakai 3/2,1/1: ', TextWidth('Halo'), 'x', TextHeight('Halo'));
  SetTextStyle(DefaultFont, HorizDir, 11);
  GetTextSettings(Ts);
  WriteLn(O, 'ukuran 11 dipotong jadi ', Ts.CharSize);
  SetTextStyle(5, HorizDir, 1);
  WriteLn(O, 'font 5: ', GraphResult);
  SetTextStyle(GothicFont, HorizDir, 1);
  GetTextSettings(Ts);
  WriteLn(O, 'Gothic: font=', Ts.Font, ' arah=', Ts.Direction, ' ukuran=', Ts.CharSize);

  WriteLn(O, 'Perataan teks "ABCD" (32 x 8) di titik (100,50)');
  SetTextStyle(DefaultFont, HorizDir, 1);
  SetTextJustify(LeftText, TopText);
  OutTextXY(100, 50, 'ABCD');
  Box('kiri/atas');
  SetTextJustify(CenterText, CenterText);
  OutTextXY(100, 50, 'ABCD');
  Box('tengah/tengah');
  SetTextJustify(RightText, BottomText);
  OutTextXY(100, 50, 'ABCD');
  Box('kanan/bawah');
  SetTextJustify(LeftText, BottomText);
  OutTextXY(100, 50, 'ABCD');
  Box('kiri/bawah');
  SetTextJustify(3, 0);
  WriteLn(O, 'justify 3: ', GraphResult);
  SetTextJustify(LeftText, TopText);

  WriteLn(O, 'OutText memajukan titik kini, OutTextXY tidak');
  MoveTo(10, 20);
  OutText('ABC');
  WriteLn(O, 'sesudah OutText: ', GetX, ',', GetY);
  OutText('D');
  WriteLn(O, 'sesudah OutText: ', GetX, ',', GetY);
  OutTextXY(50, 50, 'XYZ');
  WriteLn(O, 'sesudah OutTextXY: ', GetX, ',', GetY);
  Box('teks');
  SetTextJustify(RightText, TopText);
  MoveTo(60, 20);
  OutText('AB');
  WriteLn(O, 'rata kanan: ', GetX, ',', GetY);
  SetTextJustify(LeftText, TopText);
  SetTextStyle(DefaultFont, VertDir, 1);
  MoveTo(60, 30);
  OutText('AB');
  WriteLn(O, 'vertikal: ', GetX, ',', GetY);
  ClearDevice;

  WriteLn(O, 'Teks di viewport dengan klip');
  SetTextStyle(DefaultFont, HorizDir, 1);
  SetViewPort(20, 20, 35, 27, ClipOn);
  OutTextXY(0, 0, 'ABCD');
  SetViewPort(0, 0, 639, 479, ClipOn);
  Dump(18, 18, 38, 29);
  ClearDevice;

  WriteLn(O, 'Karakter di luar ASCII 32..126 tidak menggambar apa-apa');
  OutTextXY(0, 0, #1#127#200);
  Box('kosong');
  CloseGraph;
  Close(O);
end.
