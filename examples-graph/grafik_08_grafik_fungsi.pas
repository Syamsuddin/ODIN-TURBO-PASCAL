{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 8 - Grafik fungsi matematika
  Sumbu koordinat dipindah ke tengah layar. Untuk titik (x, y) matematika,
  piksel layarnya (PusatX + x * Skala, PusatY - y * Skala): sumbu y layar
  mengarah ke bawah, jadi dikurangi. Grafik sin, cos, dan x kuadrat. }

program grafik_08_grafik_fungsi;

uses Crt, Graph;

const
  PusatX = 320;
  PusatY = 240;
  Skala = 50;                           { piksel per satuan }

var
  Driver, Mode, I, Px, Py: Integer;
  X: Real;

procedure Kurva(Warna: Integer; Jenis: Integer);
var
  Awal: Boolean;
  Y: Real;
begin
  SetColor(Warna);
  Awal := True;
  X := -6.0;
  while X <= 6.0 do
  begin
    case Jenis of
      1: Y := Sin(X);
      2: Y := Cos(X);
    else
      Y := X * X / 6 - 2;
    end;
    Px := PusatX + Round(X * Skala);
    Py := PusatY - Round(Y * Skala);
    if Awal then MoveTo(Px, Py) else LineTo(Px, Py);
    Awal := False;
    X := X + 0.05;
  end;
end;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  { Sumbu dan garis bantu tiap satuan }
  SetColor(DarkGray);
  for I := -6 to 6 do
    Line(PusatX + I * Skala, 20, PusatX + I * Skala, 460);
  for I := -4 to 4 do
    Line(10, PusatY + I * Skala, 630, PusatY + I * Skala);
  SetColor(White);
  Line(10, PusatY, 630, PusatY);
  Line(PusatX, 20, PusatX, 460);

  Kurva(LightRed, 1);
  Kurva(LightGreen, 2);
  Kurva(LightCyan, 3);

  SetColor(LightRed);   OutTextXY(20, 10, 'sin x');
  SetColor(LightGreen); OutTextXY(90, 10, 'cos x');
  SetColor(LightCyan);  OutTextXY(160, 10, 'x*x/6 - 2');
  SetColor(White);
  OutTextXY(220, 465, 'Tekan sembarang tombol...');

  ReadKey;
  CloseGraph;
end.
