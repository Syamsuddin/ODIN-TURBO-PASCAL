{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 5 - Polimorfisme: virtual, override, abstract
  Method virtual dipilih saat program berjalan menurut class objek yang
  sebenarnya, bukan menurut tipe variabelnya. Jadi satu larik TBangun
  bisa berisi lingkaran, persegi, dan segitiga, dan Luas memanggil rumus
  yang tepat untuk masing-masing. Method abstract tidak punya isi: setiap
  turunan wajib mengisinya dengan override. }

program oop_05_polimorfisme;

type
  TBangun = class
    function Nama: String; virtual; abstract;
    function Luas: Real; virtual; abstract;
    function Keliling: Real; virtual; abstract;
    procedure Cetak;
  end;

  TLingkaran = class(TBangun)
    R: Real;
    constructor Create(AR: Real);
    function Nama: String; override;
    function Luas: Real; override;
    function Keliling: Real; override;
  end;

  TPersegi = class(TBangun)
    Sisi: Real;
    constructor Create(ASisi: Real);
    function Nama: String; override;
    function Luas: Real; override;
    function Keliling: Real; override;
  end;

  TSegitigaSiku = class(TBangun)
    Alas, Tinggi: Real;
    constructor Create(AAlas, ATinggi: Real);
    function Nama: String; override;
    function Luas: Real; override;
    function Keliling: Real; override;
  end;

procedure TBangun.Cetak;
begin
  { Cetak ditulis sekali di induk, tetapi Nama, Luas, dan Keliling yang
    terpanggil adalah milik class objeknya. }
  WriteLn(Nama:16, Luas:10:2, Keliling:10:2);
end;

constructor TLingkaran.Create(AR: Real);
begin
  inherited Create;
  R := AR;
end;

function TLingkaran.Nama: String;
begin
  Nama := 'Lingkaran';
end;

function TLingkaran.Luas: Real;
begin
  Luas := Pi * R * R;
end;

function TLingkaran.Keliling: Real;
begin
  Keliling := 2 * Pi * R;
end;

constructor TPersegi.Create(ASisi: Real);
begin
  inherited Create;
  Sisi := ASisi;
end;

function TPersegi.Nama: String;
begin
  Nama := 'Persegi';
end;

function TPersegi.Luas: Real;
begin
  Luas := Sisi * Sisi;
end;

function TPersegi.Keliling: Real;
begin
  Keliling := 4 * Sisi;
end;

constructor TSegitigaSiku.Create(AAlas, ATinggi: Real);
begin
  inherited Create;
  Alas := AAlas;
  Tinggi := ATinggi;
end;

function TSegitigaSiku.Nama: String;
begin
  Nama := 'Segitiga siku';
end;

function TSegitigaSiku.Luas: Real;
begin
  Luas := Alas * Tinggi / 2;
end;

function TSegitigaSiku.Keliling: Real;
begin
  Keliling := Alas + Tinggi + Sqrt(Alas * Alas + Tinggi * Tinggi);
end;

var
  Bangun: array[1..3] of TBangun;        { satu tipe, tiga bentuk }
  I: Integer;
  Total: Real;

begin
  Bangun[1] := TLingkaran.Create(7);
  Bangun[2] := TPersegi.Create(5);
  Bangun[3] := TSegitigaSiku.Create(3, 4);
  WriteLn('Bangun':16, 'Luas':10, 'Keliling':10);
  Total := 0;
  for I := 1 to 3 do
  begin
    Bangun[I].Cetak;
    Total := Total + Bangun[I].Luas;
  end;
  WriteLn('Total luas':16, Total:10:2);
  for I := 1 to 3 do
    Bangun[I].Free;
end.
