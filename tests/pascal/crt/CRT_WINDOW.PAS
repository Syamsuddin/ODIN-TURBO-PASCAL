{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program CrtWindow;
{ Crt: windows, scrolling inside full-width and partial windows, InsLine,
  DelLine, ClrEol, wrapping at the window edge, invalid GotoXY, colors and
  WhereX inside one Write. tests/test_core.py runs it on a PTY with both
  backends and compares the screens cell by cell. }
uses Crt;
var
  I: Integer;
  C: Char;
begin
  TextBackground(Blue); TextColor(Yellow);
  ClrScr;
  for I := 1 to 30 do WriteLn('line ', I);
  Write('tail');
  TextBackground(Green); TextColor(White);
  Window(5, 3, 20, 8);
  ClrScr;
  for I := 1 to 9 do WriteLn('win ', I, ' abcdefghijklmnop');
  Write('X=', WhereX, ' Y=', WhereY);
  GotoXY(30, 2); Write('bad');
  GotoXY(2, 2); InsLine; Write('ins');
  GotoXY(1, 4); DelLine;
  TextBackground(Red);
  Window(1, 15, 80, 20);
  ClrScr;
  for I := 1 to 8 do WriteLn('full width ', I);
  GotoXY(10, 2); ClrEol;
  GotoXY(1, 3); InsLine; Write('inserted');
  GotoXY(1, 5); DelLine;
  Window(60, 2, 70, 4);
  TextBackground(Cyan); TextColor(Black);
  ClrScr;
  Write('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ');
  GotoXY(5, 1); ClrEol;
  Window(1, 1, 80, 25);
  NormVideo; LowVideo;
  GotoXY(1, 25); Write('LV', WhereX, ',', WhereY, ' attr ', TextAttr);
  HighVideo; Write(' HV ', TextAttr);
  TextColor(LightGreen + Blink); Write(' blink ', TextAttr);
  C := ReadKey;
end.
