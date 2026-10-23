{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 6 - Class var, class method, dan class of
  class var adalah satu variabel milik class (bukan milik tiap objek);
  semua field sesudah "class var" sampai bagian berikutnya (public,
  private, ...) ikut menjadi class var, jadi tulis field biasa lebih
  dulu. class function dipanggil lewat nama class tanpa perlu objek. Tipe
  "class of TInduk" menyimpan sebuah CLASS, sehingga program bisa memilih
  class mana yang dibuat saat berjalan. Constructor virtual memastikan
  constructor milik class terpilih yang dijalankan. }

program oop_06_class_method_dan_class_of;

type
  THewan = class;
  THewanClass = class of THewan;         { variabel berisi sebuah class }

  THewan = class
  public
    Nama: String;                        { satu per objek }
    class var Jumlah: Integer;           { satu untuk semua objek }
  public
    constructor Create; virtual;
    destructor Destroy; override;
    class function Suara: String; virtual;
    class function Buat(Jenis: THewanClass; const ANama: String): THewan;
  end;

  TAnjing = class(THewan)
    class function Suara: String; override;
  end;

  TKucing = class(THewan)
    constructor Create; override;
    class function Suara: String; override;
  end;

constructor THewan.Create;
begin
  inherited Create;
  Inc(Jumlah);
end;

destructor THewan.Destroy;
begin
  Dec(Jumlah);
  inherited Destroy;
end;

class function THewan.Suara: String;
begin
  Suara := '...';
end;

class function THewan.Buat(Jenis: THewanClass; const ANama: String): THewan;
var
  H: THewan;
begin
  H := Jenis.Create;                     { class-nya ditentukan pemanggil }
  H.Nama := ANama;
  Buat := H;
end;

class function TAnjing.Suara: String;
begin
  Suara := 'guk guk';
end;

constructor TKucing.Create;
begin
  inherited Create;
  WriteLn('  (kucing baru lahir)');
end;

class function TKucing.Suara: String;
begin
  Suara := 'meong';
end;

const
  Pilihan: array[1..4] of Char = ('a', 'k', 'k', 'h');
var
  Kandang: array[1..4] of THewan;
  Jenis: THewanClass;
  I: Integer;

begin
  THewan.Jumlah := 0;
  WriteLn('Suara anjing tanpa objek: ', TAnjing.Suara);
  for I := 1 to 4 do
  begin
    case Pilihan[I] of
      'a': Jenis := TAnjing;
      'k': Jenis := TKucing;
    else
      Jenis := THewan;
    end;
    Kandang[I] := THewan.Buat(Jenis, Jenis.ClassName);
  end;
  WriteLn('Jumlah hewan: ', THewan.Jumlah);
  for I := 1 to 4 do
    WriteLn(I, '. ', Kandang[I].Nama, ' bersuara ', Kandang[I].Suara);
  for I := 1 to 4 do
    Kandang[I].Free;
  WriteLn('Jumlah hewan: ', THewan.Jumlah);
end.
