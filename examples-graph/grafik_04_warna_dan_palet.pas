{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 4 - Warna dan palet
  Mode VGA punya 16 warna (nomor 0 sampai 15). Palet bisa diubah:
  SetRGBPalette mengganti warna satu nomor dengan campuran merah, hijau, biru
  (0..63), sehingga seluruh gambar berwarna nomor itu ikut berubah. Di bawah,
  ketujuh warna 1..7 dibuat menjadi gradasi lalu digeser terus menerus. }

program grafik_04_warna_dan_palet;

uses Crt, Graph;

var
  Driver, Mode, I, Geser: Integer;
  Label16: String;

begin
  Driver := VGA;
  Mode := VGAHi;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  { 16 kotak, satu untuk tiap nomor warna }
  for I := 0 to 15 do
  begin
    SetFillStyle(SolidFill, I);
    Bar(40 + (I mod 8) * 70, 40 + (I div 8) * 90, 100 + (I mod 8) * 70, 110 + (I div 8) * 90);
    SetColor(White);
    Rectangle(40 + (I mod 8) * 70, 40 + (I div 8) * 90, 100 + (I mod 8) * 70, 110 + (I div 8) * 90);
    Str(I, Label16);
    OutTextXY(60 + (I mod 8) * 70, 120 + (I div 8) * 90, Label16);
  end;

  { Pita gradasi memakai warna 1..7: tiap nomor jadi satu tingkat abu-abu biru }
  for I := 0 to 6 do
  begin
    SetFillStyle(SolidFill, 1 + I);
    Bar(40 + I * 80, 260, 40 + I * 80 + 79, 330);
  end;
  SetColor(White);
  OutTextXY(40, 350, 'Palet warna 1..7 berubah terus. Tekan tombol untuk berhenti.');

  Geser := 0;
  while not KeyPressed do
  begin
    for I := 1 to 7 do
      SetRGBPalette(I, ((I + Geser) mod 8) * 9, 20 + ((I + Geser) mod 8) * 5, 63 - ((I + Geser) mod 8) * 8);
    Inc(Geser);
    Delay(120);
  end;
  ReadKey;
  CloseGraph;
end.
