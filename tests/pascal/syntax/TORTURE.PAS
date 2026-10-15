{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grammar coverage for the Odin parser. Also compiled by FPC -Mtp. }
program Torture(Input, Output);
{$R+,Q-}
{$IFDEF FPC} {$ELSE} {$ENDIF}
uses Crt, Dos;

label 10, Selesai;

const
  Max = 10;
  Neg = -5;
  Pesan = 'Halo'#13#10'dunia';
  Bel = ^G;
  Mask = [1, 3..5];
  Hex = $FF and not $0F;
  Nyata: Real = 2.5E-3;
  Tabel: array[1..3] of Integer = (10, 20, 30);
  Matriks: array[1..2, 1..2] of Byte = ((1, 2), (3, 4));
  Titik: record X, Y: Integer end = (X: 1; Y: 2);

type
  TWarna = (Merah, Hijau, Biru);
  TKecil = 0..Max - 1;
  THuruf = 'A'..'Z';
  PNode = ^TNode;
  TNode = record
    Nilai: Integer;
    Berikut: PNode;
  end;
  TBentuk = record
    Nama: string[20];
    case Jenis: Byte of
      0: (Jari: Real);
      1, 2: (Lebar, Tinggi: Integer);
  end;
  TVarian = packed record
    case Integer of
      0: (B: array[0..3] of Byte);
      1: (L: LongInt);
  end;
  TSetWarna = set of TWarna;
  TBerkas = file of TNode;
  TFungsi = function(A, B: Integer): Integer;
  TProsedur = procedure;
  PString = ^string;
  TBuffer = array[Char] of Boolean;

  PShape = ^TShape;
  TShape = object
    X, Y: Integer;
    constructor Init(AX, AY: Integer);
    destructor Done; virtual;
    procedure Draw; virtual;
    function Area: Real; virtual;
  private
    Tersembunyi: Word;
    procedure Rahasia;
  public
    procedure Pindah(DX, DY: Integer);
  end;

  TCircle = object(TShape)
    R: Real;
    constructor Init(AX, AY: Integer; AR: Real);
    function Area: Real; virtual;
  end;

var
  I, J: Integer;
  Huruf: Char;
  Warna: TWarna;
  Daftar: PNode;
  Bentuk: TBentuk;
  S: string;
  F: Text;
  Fn: TFungsi;
  Shape: PShape;
  Alias: Word absolute I;
  Himpunan: TSetWarna;

constructor TShape.Init(AX, AY: Integer);
begin
  X := AX; Y := AY;
end;

destructor TShape.Done;
begin
end;

procedure TShape.Draw;
begin
  WriteLn('Shape at ', X, ',', Y);
end;

function TShape.Area: Real;
begin
  Area := 0;
end;

procedure TShape.Rahasia;
begin
end;

procedure TShape.Pindah(DX, DY: Integer);
begin
  Inc(X, DX); Inc(Y, DY);
end;

constructor TCircle.Init(AX, AY: Integer; AR: Real);
begin
  inherited Init(AX, AY);
  R := AR;
end;

function TCircle.Area: Real;
begin
  Area := Pi * Sqr(R);
end;

function Tambah(A, B: Integer): Integer; far;
begin
  Tambah := A + B;
end;

procedure Maju; forward;

procedure Luar(var Total: LongInt; const Nama: string; Data: array of Integer);
var K: Integer;
  procedure Dalam;
  begin
    Total := Total + Length(Nama);
  end;
begin
  for K := Low(Data) to High(Data) do
    Total := Total + Data[K];
  Dalam;
end;

procedure Maju;
begin
end;

procedure Tanpa(var Apa; const Juga);
begin
end;

begin
  I := 0;
  J := -I * 2 + (I div 3) mod 4 shl 1;
  if (I > 0) and not (J <= 0) or (I in [1..3]) then
    WriteLn('ya')
  else if I <> J then
    WriteLn('tidak':10)
  else
    ;
  case I of
    0: WriteLn('nol');
    1, 2: begin WriteLn('kecil') end;
    3..9: ;
  else
    WriteLn('besar');
    WriteLn(I:5);
  end;
  while I < Max do Inc(I);
  repeat Dec(I) until I = 0;
  for Warna := Merah to Biru do Himpunan := Himpunan + [Warna];
  for I := 10 downto 1 do ;
  New(Daftar);
  Daftar^.Nilai := 1;
  Daftar^.Berikut := nil;
  with Daftar^, Bentuk do
  begin
    Nilai := 2;
    Nama := 'kotak';
  end;
  Dispose(Daftar);
  Fn := Tambah;
  I := Fn(1, 2);
  Shape := New(PShape, Init(1, 2));
  Shape^.Draw;
  Dispose(Shape, Done);
  S := Pesan + Chr(65) + #65 + ^M;
  Huruf := S[1];
  WriteLn(Nyata:8:3, ' ', Tabel[2], ' ', Matriks[2, 1]);
  Assign(F, 'x.txt');
  {$I-} Reset(F); {$I+}
  if IOResult <> 0 then goto Selesai;
  Close(F);
10:
  I := Ord(Huruf) + Integer(Warna) + SizeOf(TNode);
Selesai:
  Writeln(@Tambah <> nil);
end.
