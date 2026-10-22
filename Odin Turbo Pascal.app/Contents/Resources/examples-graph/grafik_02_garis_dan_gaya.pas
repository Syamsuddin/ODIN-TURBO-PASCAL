{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 2 - Garis, gaya garis, dan titik kini
  SetLineStyle mengatur pola garis (solid, titik-titik, tengah, putus-putus,
  atau pola 16 bit buatan sendiri) dan ketebalannya (1 atau 3 piksel).
  LineTo, LineRel, dan MoveTo memakai titik kini, seperti pena. }

program grafik_02_garis_dan_gaya;

uses Crt, Graph;

const
  Nama: array[0..3] of String = ('SolidLn', 'DottedLn', 'CenterLn', 'DashedLn');

var
  Driver, Mode, I: Integer;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  OutTextXY(20, 10, 'Gaya garis bawaan, tipis dan tebal');
  for I := 0 to 3 do
  begin
    SetColor(White);
    OutTextXY(20, 50 + I * 40, Nama[I]);
    SetColor(LightGreen);
    SetLineStyle(I, 0, NormWidth);      { gaya, pola (hanya UserBitLn), tebal }
    Line(150, 55 + I * 40, 400, 55 + I * 40);
    SetColor(LightRed);
    SetLineStyle(I, 0, ThickWidth);
    Line(420, 55 + I * 40, 620, 55 + I * 40);
  end;

  { Pola buatan sendiri: tiap bit 1 menyalakan piksel, 0 mematikannya }
  SetColor(Yellow);
  SetLineStyle(UserBitLn, $F0F0, NormWidth);
  Line(150, 230, 620, 230);
  SetLineStyle(UserBitLn, $AAAA, NormWidth);
  Line(150, 240, 620, 240);
  SetLineStyle(SolidLn, 0, NormWidth);
  SetColor(White);
  OutTextXY(20, 228, 'UserBitLn');

  { Titik kini: MoveTo pindah tanpa menggambar, LineTo menggambar }
  SetColor(LightCyan);
  MoveTo(150, 300);
  for I := 1 to 8 do
    if Odd(I) then LineRel(60, 90) else LineRel(60, -90);
  SetColor(White);
  OutTextXY(20, 440, 'Tekan sembarang tombol...');

  ReadKey;
  CloseGraph;
end.
