{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 12 - Jam analog
  Jarum jam digambar dari titik pusat. Sudut 0 derajat ada di atas (jam 12)
  dan bertambah searah jarum jam, jadi titik ujung jarum:
  x = Pusat + Panjang * Sin(sudut), y = Pusat - Panjang * Cos(sudut).
  GetTime dari unit Dos memberi jam, menit, dan detik sistem. }

program grafik_12_jam_analog;

uses Crt, Dos, Graph;

const
  PusatX = 320;
  PusatY = 240;
  Jari = 200;

var
  Driver, Mode, I: Integer;
  H, M, S, S100: Word;
  Detik: Word;

{ Ujung jarum sepanjang Panjang pada Sudut derajat dari jam 12 }
procedure Jarum(Sudut: Real; Panjang, Warna, Tebal: Integer);
var
  Rad: Real;
begin
  Rad := Sudut * Pi / 180;
  SetColor(Warna);
  SetLineStyle(SolidLn, 0, Tebal);
  Line(PusatX, PusatY, PusatX + Round(Panjang * Sin(Rad)), PusatY - Round(Panjang * Cos(Rad)));
  SetLineStyle(SolidLn, 0, NormWidth);
end;

procedure Muka;
var
  K, Dalam: Integer;
  Rad: Real;
begin
  SetColor(LightCyan);
  Circle(PusatX, PusatY, Jari + 10);
  for K := 0 to 59 do
  begin
    Rad := K * 6 * Pi / 180;
    if K mod 5 = 0 then Dalam := 20 else Dalam := 8;
    if K mod 5 = 0 then SetColor(Yellow) else SetColor(LightGray);
    Line(PusatX + Round(Jari * Sin(Rad)), PusatY - Round(Jari * Cos(Rad)),
         PusatX + Round((Jari - Dalam) * Sin(Rad)), PusatY - Round((Jari - Dalam) * Cos(Rad)));
  end;
end;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  Detik := 99;
  while not KeyPressed do
  begin
    GetTime(H, M, S, S100);
    if S <> Detik then                 { gambar ulang hanya saat detik berganti }
    begin
      Detik := S;
      ClearDevice;
      Muka;
      Jarum((H mod 12) * 30 + M / 2, Jari - 90, White, ThickWidth);
      Jarum(M * 6 + S / 10, Jari - 40, LightGreen, ThickWidth);
      Jarum(S * 6, Jari - 20, LightRed, NormWidth);
      SetColor(White);
      OutTextXY(240, 460, 'Tekan sembarang tombol untuk berhenti');
    end;
    Delay(100);
  end;
  ReadKey;
  CloseGraph;
end.
