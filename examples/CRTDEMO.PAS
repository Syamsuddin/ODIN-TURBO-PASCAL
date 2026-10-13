{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program CRTDemo;
uses Crt;
var
  I: Integer;
  Tombol: Char;
begin
  TextBackground(Blue);
  ClrScr;
  TextColor(Yellow);
  GotoXY(23, 3);
  Write('ODIN TURBO PASCAL');
  TextColor(White);
  GotoXY(18, 6);
  Write('Demo CRT: warna, posisi, dan ReadKey.');
  for I := 1 to 15 do
  begin
    TextColor(I);
    GotoXY(20, I + 7);
    Write('Warna nomor ', I:2, '  Pascal native');
  end;
  TextColor(Yellow);
  GotoXY(18, 24);
  Write('Tekan sembarang tombol untuk selesai...');
  Tombol := ReadKey;
  TextColor(LightGray);
  TextBackground(Black);
  ClrScr;
  WriteLn('Demo selesai.');
end.
