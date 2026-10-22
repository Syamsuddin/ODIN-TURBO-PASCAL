{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 5 - Isian, pola, dan FloodFill
  SetFillStyle memilih pola isian (12 bawaan) dan warnanya. Bar mengisi
  persegi panjang, FillEllipse dan PieSlice mengisi bentuk lengkung, dan
  FloodFill mengisi daerah tertutup sampai bertemu warna batas. }

program grafik_05_isian_dan_pola;

uses Crt, Graph;

const
  Nama: array[0..11] of String = ('Empty', 'Solid', 'Line', 'LtSlash', 'Slash', 'BkSlash',
                                  'LtBkSlash', 'Hatch', 'XHatch', 'Interleave', 'WideDot', 'CloseDot');
var
  Driver, Mode, I, X, Y: Integer;
  Pola: FillPatternType;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  for I := 0 to 11 do
  begin
    X := 30 + (I mod 6) * 100;
    Y := 30 + (I div 6) * 110;
    SetFillStyle(I, 1 + I mod 15);
    Bar(X, Y, X + 80, Y + 70);
    SetColor(White);
    Rectangle(X, Y, X + 80, Y + 70);
    OutTextXY(X, Y + 76, Nama[I]);
  end;

  { Pola buatan sendiri: 8 byte = 8 baris, bit 1 = piksel berwarna }
  Pola[1] := $FF; Pola[2] := $81; Pola[3] := $BD; Pola[4] := $A5;
  Pola[5] := $A5; Pola[6] := $BD; Pola[7] := $81; Pola[8] := $FF;
  SetFillPattern(Pola, LightCyan);
  Bar(30, 270, 110, 340);
  OutTextXY(30, 346, 'UserFill');

  { FloodFill: gambar batas dulu, lalu isi dari titik di dalamnya }
  SetColor(Yellow);
  Circle(230, 305, 40);
  Line(190, 305, 270, 305);
  SetFillStyle(SolidFill, Red);
  FloodFill(230, 280, Yellow);          { hanya setengah atas }
  SetFillStyle(XHatchFill, LightGreen);
  FloodFill(230, 330, Yellow);          { setengah bawah }
  SetColor(White);
  OutTextXY(190, 356, 'FloodFill');

  SetFillStyle(SolidFill, Brown);
  SetColor(White);
  FillEllipse(380, 305, 60, 35);
  OutTextXY(340, 346, 'FillEllipse');

  SetFillStyle(SolidFill, LightMagenta);
  PieSlice(520, 305, 30, 330, 45);
  OutTextXY(480, 356, 'PieSlice');

  OutTextXY(30, 440, 'Tekan sembarang tombol...');
  ReadKey;
  CloseGraph;
end.
