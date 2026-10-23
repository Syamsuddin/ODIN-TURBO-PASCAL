{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 4 - Pewarisan
  Class turunan mewarisi semua field dan method induknya, lalu menambah
  miliknya sendiri. "inherited" memanggil versi milik induk. Anggota
  protected boleh dipakai turunan, tetapi tidak dari luar.
    TKendaraan
      +-- TMobil
      +-- TSepeda }

program oop_04_pewarisan;

type
  TKendaraan = class
  protected
    FRoda: Integer;                      { untuk turunan }
  public
    Merek: String;
    constructor Create(const AMerek: String);
    function Info: String;
  end;

  TMobil = class(TKendaraan)
    Penumpang: Integer;
    constructor Create(const AMerek: String; APenumpang: Integer);
    function InfoLengkap: String;
  end;

  TSepeda = class(TKendaraan)
    constructor Create(const AMerek: String);
  end;

constructor TKendaraan.Create(const AMerek: String);
begin
  inherited Create;
  Merek := AMerek;
  FRoda := 0;
end;

function TKendaraan.Info: String;
var
  S: String;
begin
  Str(FRoda, S);
  Info := Merek + ' beroda ' + S;
end;

constructor TMobil.Create(const AMerek: String; APenumpang: Integer);
begin
  inherited Create(AMerek);              { bagian induk disiapkan induknya }
  FRoda := 4;
  Penumpang := APenumpang;
end;

function TMobil.InfoLengkap: String;
var
  S: String;
begin
  Str(Penumpang, S);
  InfoLengkap := Info + ', muat ' + S + ' orang';
end;

constructor TSepeda.Create(const AMerek: String);
begin
  inherited Create(AMerek);
  FRoda := 2;
end;

var
  M: TMobil;
  S: TSepeda;

begin
  M := TMobil.Create('Kijang', 7);
  S := TSepeda.Create('Onthel');
  WriteLn(M.InfoLengkap);
  WriteLn(S.Info);                       { method warisan TKendaraan }
  WriteLn('Induk TMobil  : ', M.ClassParent.ClassName);
  WriteLn('TMobil turunan TKendaraan? ', TMobil.InheritsFrom(TKendaraan));
  WriteLn('TSepeda turunan TMobil?    ', TSepeda.InheritsFrom(TMobil));
  M.Free;
  S.Free;
end.
