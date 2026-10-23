{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 3 - Enkapsulasi dan property
  Field private hanya boleh disentuh oleh class itu (dan unit atau
  program tempat ia ditulis); dari luar, data dibaca dan diubah lewat
  property. Property bisa langsung ke field, atau lewat method yang
  memeriksa nilainya dulu. Property tanpa write hanya bisa dibaca. }

program oop_03_enkapsulasi_property;

type
  TRekening = class
  private
    FPemilik: String;
    FSaldo: LongInt;
    FMutasi: Integer;
    procedure SetPemilik(const Nilai: String);
  public
    constructor Create(const APemilik: String);
    procedure Setor(Jumlah: LongInt);
    function Tarik(Jumlah: LongInt): Boolean;
    property Pemilik: String read FPemilik write SetPemilik;
    property Saldo: LongInt read FSaldo;           { hanya bisa dibaca }
    property Mutasi: Integer read FMutasi;
  end;

constructor TRekening.Create(const APemilik: String);
begin
  inherited Create;
  Pemilik := APemilik;                   { lewat setter, jadi ikut diperiksa }
end;

procedure TRekening.SetPemilik(const Nilai: String);
begin
  if Nilai = '' then
    FPemilik := '(tanpa nama)'
  else
    FPemilik := Nilai;
end;

procedure TRekening.Setor(Jumlah: LongInt);
begin
  if Jumlah <= 0 then
    Exit;
  FSaldo := FSaldo + Jumlah;
  Inc(FMutasi);
end;

function TRekening.Tarik(Jumlah: LongInt): Boolean;
begin
  Tarik := False;
  if (Jumlah <= 0) or (Jumlah > FSaldo) then
    Exit;                                { saldo tidak boleh minus }
  FSaldo := FSaldo - Jumlah;
  Inc(FMutasi);
  Tarik := True;
end;

var
  R: TRekening;

begin
  R := TRekening.Create('');
  WriteLn('Pemilik: ', R.Pemilik);
  R.Pemilik := 'Siti';
  R.Setor(150000);
  R.Setor(-5000);                        { ditolak diam-diam }
  if not R.Tarik(200000) then
    WriteLn('Penarikan 200000 ditolak: saldo kurang.');
  if R.Tarik(50000) then
    WriteLn('Penarikan 50000 berhasil.');
  WriteLn(R.Pemilik, ': saldo ', R.Saldo, ', ', R.Mutasi, ' mutasi');
  { R.Saldo := 1000000;  galat: property Saldo hanya bisa dibaca }
  R.Free;
end.
