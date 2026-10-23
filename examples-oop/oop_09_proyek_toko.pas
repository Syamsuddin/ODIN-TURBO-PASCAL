{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 9 - Proyek: kasir toko
  Gabungan semua bab OOP. TProduk adalah class abstrak; setiap jenis
  produk menghitung harga jualnya sendiri (polimorfisme). Keranjang
  menyimpan produk dalam TObjectList (Contnrs) yang diurutkan dengan
  Sort, dan mencatat kejadian di TStringList (Classes). Nomor produk
  diambil dari class var, data dilindungi dengan private dan property. }

program oop_09_proyek_toko;

uses
  Classes, Contnrs;

type
  TProduk = class
  private
    FKode: Integer;
    FNama: String;
    FHarga: LongInt;
  public
    class var Nomor: Integer;
    constructor Create(const ANama: String; AHarga: LongInt);
    function HargaJual: LongInt; virtual; abstract;
    function Keterangan: String; virtual;
    property Kode: Integer read FKode;
    property Nama: String read FNama;
    property Harga: LongInt read FHarga;
  end;

  TMakanan = class(TProduk)
  private
    FHampirKedaluwarsa: Boolean;
  public
    constructor Create(const ANama: String; AHarga: LongInt; Hampir: Boolean);
    function HargaJual: LongInt; override;
    function Keterangan: String; override;
  end;

  TElektronik = class(TProduk)
  private
    FGaransi: Integer;
  public
    constructor Create(const ANama: String; AHarga: LongInt; Bulan: Integer);
    function HargaJual: LongInt; override;
    function Keterangan: String; override;
  end;

  TKeranjang = class
  private
    FIsi: TObjectList;
    FCatatan: TStringList;
    function GetProduk(I: Integer): TProduk;
    function GetJumlah: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Masukkan(P: TProduk);
    procedure UrutkanMurah;
    function Total: LongInt;
    procedure CetakStruk;
    property Jumlah: Integer read GetJumlah;
    property Produk[I: Integer]: TProduk read GetProduk; default;
    property Catatan: TStringList read FCatatan;
  end;

{ ---- produk ---- }

constructor TProduk.Create(const ANama: String; AHarga: LongInt);
begin
  inherited Create;
  Inc(Nomor);
  FKode := Nomor;
  FNama := ANama;
  FHarga := AHarga;
end;

function TProduk.Keterangan: String;
begin
  Keterangan := '';
end;

constructor TMakanan.Create(const ANama: String; AHarga: LongInt; Hampir: Boolean);
begin
  inherited Create(ANama, AHarga);
  FHampirKedaluwarsa := Hampir;
end;

function TMakanan.HargaJual: LongInt;
begin
  if FHampirKedaluwarsa then
    HargaJual := Harga div 2             { diskon 50% }
  else
    HargaJual := Harga;
end;

function TMakanan.Keterangan: String;
begin
  if FHampirKedaluwarsa then
    Keterangan := 'diskon 50%'
  else
    Keterangan := inherited Keterangan;
end;

constructor TElektronik.Create(const ANama: String; AHarga: LongInt; Bulan: Integer);
begin
  inherited Create(ANama, AHarga);
  FGaransi := Bulan;
end;

function TElektronik.HargaJual: LongInt;
begin
  HargaJual := Harga + Harga div 10;     { pajak 10% }
end;

function TElektronik.Keterangan: String;
var
  S: String;
begin
  Str(FGaransi, S);
  Keterangan := 'pajak 10%, garansi ' + S + ' bln';
end;

{ ---- keranjang ---- }

{ Pembanding untuk Sort: negatif bila A lebih murah, positif bila lebih
  mahal. Bukan "A - B": Integer hanya sampai 32767, selisih harga bisa
  lebih besar. }
function LebihMurah(A, B: Pointer): Integer;
var
  HA, HB: LongInt;
begin
  HA := TProduk(A).HargaJual;
  HB := TProduk(B).HargaJual;
  if HA < HB then
    LebihMurah := -1
  else if HA > HB then
    LebihMurah := 1
  else
    LebihMurah := 0;
end;

constructor TKeranjang.Create;
begin
  inherited Create;
  FIsi := TObjectList.Create;            { produk ikut dibebaskan }
  FCatatan := TStringList.Create;
end;

destructor TKeranjang.Destroy;
begin
  FIsi.Free;
  FCatatan.Free;
  inherited Destroy;
end;

function TKeranjang.GetProduk(I: Integer): TProduk;
begin
  GetProduk := FIsi[I] as TProduk;
end;

function TKeranjang.GetJumlah: Integer;
begin
  GetJumlah := FIsi.Count;
end;

procedure TKeranjang.Masukkan(P: TProduk);
begin
  FIsi.Add(P);
  FCatatan.Add('masuk: ' + P.Nama + ' (' + P.ClassName + ')');
end;

procedure TKeranjang.UrutkanMurah;
begin
  FIsi.Sort(LebihMurah);
  FCatatan.Add('keranjang diurutkan dari yang termurah');
end;

function TKeranjang.Total: LongInt;
var
  I: Integer;
  T: LongInt;
begin
  T := 0;
  for I := 0 to Jumlah - 1 do
    T := T + Self[I].HargaJual;          { HargaJual milik class produknya }
  Total := T;
end;

procedure TKeranjang.CetakStruk;
var
  I: Integer;
  P: TProduk;
begin
  WriteLn('No  Produk           Harga jual  Keterangan');
  for I := 0 to Jumlah - 1 do
  begin
    P := Self[I];
    WriteLn(P.Kode:2, '  ', P.Nama, '':17 - Length(P.Nama), P.HargaJual:10, '  ', P.Keterangan);
  end;
  WriteLn('Total':19, Total:12);
end;

var
  K: TKeranjang;
  I: Integer;

begin
  TProduk.Nomor := 0;
  K := TKeranjang.Create;
  K.Masukkan(TMakanan.Create('Roti tawar', 15000, True));
  K.Masukkan(TElektronik.Create('Kipas angin', 250000, 12));
  K.Masukkan(TMakanan.Create('Susu', 18000, False));
  K.Masukkan(TElektronik.Create('Lampu LED', 40000, 6));
  K.UrutkanMurah;
  K.CetakStruk;
  WriteLn;
  WriteLn('Catatan:');
  for I := 0 to K.Catatan.Count - 1 do
    WriteLn('  ', K.Catatan[I]);
  K.Free;                                { keranjang, produk, dan catatan }
end.
