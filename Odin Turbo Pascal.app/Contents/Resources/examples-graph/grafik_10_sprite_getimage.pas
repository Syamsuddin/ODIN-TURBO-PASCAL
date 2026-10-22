{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 10 - Menyalin gambar dengan GetImage dan PutImage
  GetImage menyimpan sebuah daerah layar ke memori (ukurannya dari ImageSize),
  PutImage menempelkannya di mana saja. Dengan XORPut, menempel dua kali di
  tempat yang sama menghapus gambar tanpa merusak latar: cara klasik
  menggerakkan sprite di atas latar bergambar. }

program grafik_10_sprite_getimage;

uses Crt, Graph;

var
  Driver, Mode, I, X, Y: Integer;
  Sprite: Pointer;
  Ukuran: LongInt;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  { Latar: garis-garis berwarna }
  for I := 0 to 47 do
  begin
    SetColor(1 + I mod 6);
    Line(0, I * 10, 639, 479 - I * 10);
  end;

  { Menggambar sprite sekali di pojok, menyalinnya, lalu menghapusnya }
  SetColor(White);
  SetFillStyle(SolidFill, Yellow);
  FillEllipse(30, 30, 24, 24);
  SetFillStyle(SolidFill, Black);
  FillEllipse(20, 24, 4, 4);
  FillEllipse(40, 24, 4, 4);
  Arc(30, 34, 200, 340, 12);
  Ukuran := ImageSize(0, 0, 59, 59);
  GetMem(Sprite, Ukuran);
  GetImage(0, 0, 59, 59, Sprite^);
  PutImage(0, 0, Sprite^, XORPut);     { menghapus: XOR dengan dirinya sendiri }

  X := 0;
  Y := 200;
  while (X < 580) and not KeyPressed do
  begin
    PutImage(X, Y, Sprite^, XORPut);   { tampil }
    Delay(15);
    PutImage(X, Y, Sprite^, XORPut);   { hapus, latar kembali utuh }
    X := X + 4;
    Y := 200 + Round(80 * Sin(X / 40));
  end;

  SetColor(White);
  OutTextXY(200, 450, 'Tekan sembarang tombol...');
  ReadKey;
  FreeMem(Sprite, Ukuran);
  CloseGraph;
end.
