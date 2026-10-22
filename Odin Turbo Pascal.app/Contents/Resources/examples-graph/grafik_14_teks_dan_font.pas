{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 14 - Teks di layar grafik
  OutTextXY menulis teks di titik tertentu. SetTextStyle mengatur font, arah
  (HorizDir atau VertDir), dan ukuran 1..10; SetTextJustify mengatur titik
  tumpu teks. Odin memakai satu font bitmap 8 x 8 untuk semua font, yang
  diskalakan sesuai ukuran. TextWidth dan TextHeight memberi ukuran teks
  dalam piksel, berguna untuk menengahkan atau membuat kotak. }

program grafik_14_teks_dan_font;

uses Crt, Graph;

var
  Driver, Mode, I, Lebar: Integer;
  Teks: String;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  { Ukuran 1 sampai 5 }
  SetColor(LightGreen);
  for I := 1 to 5 do
  begin
    SetTextStyle(DefaultFont, HorizDir, I);
    OutTextXY(20, 10 + (I - 1) * I * 4 + I * 8, 'Ukuran ' + Chr(48 + I));
  end;

  { Teks tegak dari bawah ke atas }
  SetColor(LightCyan);
  SetTextStyle(DefaultFont, VertDir, 2);
  OutTextXY(600, 200, 'Teks vertikal');   { y = bagian atas teks; dibaca ke atas }

  { Teks di tengah kotak: ukur lebarnya dulu }
  SetTextStyle(DefaultFont, HorizDir, 3);
  Teks := 'Di Tengah';
  Lebar := TextWidth(Teks);
  SetColor(Yellow);
  Rectangle(320 - Lebar div 2 - 10, 300, 320 + Lebar div 2 + 10, 300 + TextHeight(Teks) + 20);
  OutTextXY(320 - Lebar div 2, 310, Teks);

  { Perataan: titik tumpu (320, 400) sama, tiga perataan berbeda }
  SetTextStyle(DefaultFont, HorizDir, 1);
  SetColor(LightRed);
  Line(320, 380, 320, 440);
  SetColor(White);
  SetTextJustify(LeftText, TopText);
  OutTextXY(320, 385, 'LeftText');
  SetTextJustify(CenterText, TopText);
  OutTextXY(320, 400, 'CenterText');
  SetTextJustify(RightText, TopText);
  OutTextXY(320, 415, 'RightText');
  SetTextJustify(LeftText, TopText);

  OutTextXY(20, 460, 'Tekan sembarang tombol...');
  ReadKey;
  CloseGraph;
end.
