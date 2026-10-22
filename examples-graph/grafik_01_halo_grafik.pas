{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 1 - Program grafik pertama
  Unit Graph menggambar di jendela grafik: di IDE jendelanya terbuka sendiri
  dan menampilkan piksel sebenarnya (640 x 480, 16 warna). Urutan baku
  program grafik: InitGraph, menggambar, menunggu tombol, CloseGraph. }

program grafik_01_halo_grafik;

uses Crt, Graph;

var
  Driver, Mode: Integer;

begin
  Driver := Detect;                    { Detect: pilih driver terbaik (VGA) }
  InitGraph(Driver, Mode, '');         { alamat driver diabaikan di Odin }
  if GraphResult <> grOk then
  begin
    WriteLn('Mode grafik gagal: ', GraphErrorMsg(GraphResult));
    Halt(1);
  end;

  SetColor(Yellow);                    { warna garis berikutnya }
  Rectangle(100, 80, 540, 400);        { sudut kiri atas dan kanan bawah }
  SetColor(LightGreen);
  Circle(320, 240, 120);               { pusat x, y dan jari-jari }
  SetColor(LightCyan);
  Line(100, 80, 540, 400);             { diagonal }
  Line(540, 80, 100, 400);

  SetColor(White);
  OutTextXY(250, 20, 'Halo, Grafik Pascal!');
  OutTextXY(230, 450, 'Tekan sembarang tombol...');

  ReadKey;                             { tahan gambar sampai ada tombol }
  CloseGraph;                          { kembali ke layar teks }
  WriteLn('Selesai. Maks X = ', GetMaxX, ' dan maks Y = ', GetMaxY);
end.
