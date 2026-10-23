{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 7 - Daftar objek, is, dan as
  TObjectList (unit Contnrs) menampung objek class apa saja dan, karena
  memilikinya, ikut membebaskan objek itu. Isinya bertipe TObject, jadi:
    X is TBuku    memeriksa apakah X sebuah TBuku (atau turunannya)
    X as TBuku    memakai X sebagai TBuku (runtime error 219 bila bukan) }

program oop_07_is_as_daftar_objek;

uses
  Contnrs;

type
  TBarang = class
    Judul: String;
    Harga: LongInt;
    constructor Create(const AJudul: String; AHarga: LongInt);
  end;
  TBuku = class(TBarang)
    Halaman: Integer;
  end;
  TMajalah = class(TBarang)
    Edisi: String;
  end;

constructor TBarang.Create(const AJudul: String; AHarga: LongInt);
begin
  inherited Create;
  Judul := AJudul;
  Harga := AHarga;
end;

function BuatBuku(const Judul: String; Harga: LongInt; Halaman: Integer): TBuku;
var
  B: TBuku;
begin
  B := TBuku.Create(Judul, Harga);
  B.Halaman := Halaman;
  BuatBuku := B;
end;

function BuatMajalah(const Judul: String; Harga: LongInt; const Edisi: String): TMajalah;
var
  M: TMajalah;
begin
  M := TMajalah.Create(Judul, Harga);
  M.Edisi := Edisi;
  BuatMajalah := M;
end;

var
  Rak: TObjectList;
  I, Buku: Integer;
  Total: LongInt;
  X: TObject;

begin
  Rak := TObjectList.Create;             { OwnsObjects = True }
  Rak.Add(BuatBuku('Algoritma', 85000, 320));
  Rak.Add(BuatMajalah('Info Komputer', 30000, 'Mei'));
  Rak.Add(BuatBuku('Pascal Dasar', 60000, 210));
  Total := 0;
  Buku := 0;
  for I := 0 to Rak.Count - 1 do
  begin
    X := Rak[I];
    Write(I + 1, '. ', (X as TBarang).Judul);
    if X is TBuku then
    begin
      Write(' (buku, ', TBuku(X).Halaman, ' hlm)');
      Inc(Buku);
    end
    else if X is TMajalah then
      Write(' (majalah edisi ', (X as TMajalah).Edisi, ')');
    WriteLn;
    Total := Total + TBarang(X).Harga;
  end;
  WriteLn(Rak.Count, ' barang, ', Buku, ' buku, total Rp ', Total);
  Rak.Delete(1);                         { majalahnya ikut dibebaskan }
  WriteLn('Sisa: ', Rak.Count, ' barang');
  Rak.Free;                              { semua objek di dalamnya juga }
end.
