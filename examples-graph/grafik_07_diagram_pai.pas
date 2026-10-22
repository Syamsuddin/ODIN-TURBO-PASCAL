{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 7 - Diagram pai
  Tiap irisan memakai PieSlice dengan sudut awal dan akhir yang dihitung dari
  persentase: sudut = persen * 360 / 100. Sudut pertama mulai dari arah jam 3. }

program grafik_07_diagram_pai;

uses Crt, Graph;

const
  Jumlah = 5;
  Nama: array[1..Jumlah] of String = ('Makan', 'Sewa', 'Transport', 'Hiburan', 'Tabungan');
  Persen: array[1..Jumlah] of Integer = (35, 25, 15, 10, 15);

var
  Driver, Mode, I, Awal, Akhir: Integer;
  Teks: String;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  SetColor(White);
  OutTextXY(200, 20, 'Pengeluaran bulanan');

  Awal := 0;
  for I := 1 to Jumlah do
  begin
    Akhir := Awal + Persen[I] * 360 div 100;
    if I = Jumlah then Akhir := 360;                  { hindari sisa pembulatan }
    SetFillStyle(SolidFill, 8 + I);
    SetColor(White);
    PieSlice(220, 250, Awal, Akhir, 150);
    Awal := Akhir;

    { Legenda: kotak warna, nama, dan persen }
    Bar(430, 120 + I * 40, 460, 145 + I * 40);
    Str(Persen[I], Teks);
    OutTextXY(475, 128 + I * 40, Nama[I] + ' ' + Teks + '%');
  end;

  OutTextXY(40, 450, 'Tekan sembarang tombol...');
  ReadKey;
  CloseGraph;
end.
