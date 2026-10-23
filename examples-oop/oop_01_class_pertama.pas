{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 1 - Class pertama
  Class adalah cetakan objek: ia menggabungkan data (field) dan
  perilaku (method). Variabel bertipe class hanya menyimpan RUJUKAN ke
  objek; objeknya dibuat dengan Create dan dibuang dengan Free.
    Kucing := TKucing.Create;   membuat objek baru
    Kucing.Free;                membebaskan memorinya }

program oop_01_class_pertama;

type
  TKucing = class
    Nama: String;                        { field: data milik objek }
    Umur: Integer;
    procedure Perkenalan;                { method: perilaku objek }
    procedure UlangTahun;
  end;

procedure TKucing.Perkenalan;
begin
  WriteLn('Meong! Aku ', Nama, ', umurku ', Umur, ' tahun.');
end;

procedure TKucing.UlangTahun;
begin
  Umur := Umur + 1;                      { field objek ini sendiri }
  WriteLn(Nama, ' berulang tahun.');
end;

var
  Kucing, Sama: TKucing;

begin
  Kucing := TKucing.Create;              { objek baru, semua field nol }
  WriteLn('Umur awal: ', Kucing.Umur);
  Kucing.Nama := 'Belang';
  Kucing.Umur := 2;
  Kucing.Perkenalan;
  Kucing.UlangTahun;
  Kucing.Perkenalan;

  Sama := Kucing;                        { menyalin rujukan, bukan objek }
  Sama.Nama := 'Si Belang';
  Kucing.Perkenalan;                     { objeknya satu, namanya ikut berubah }

  WriteLn('Nama class: ', Kucing.ClassName);
  Kucing.Free;                           { kembalikan memorinya }
end.
