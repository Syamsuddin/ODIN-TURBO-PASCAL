{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 8 - Overload
  Beberapa method boleh bernama sama asal daftar parameternya berbeda
  dan semuanya ditandai overload. Compiler memilih versi yang paling
  cocok dengan argumen yang diberikan. Ini sering dipakai untuk
  constructor: beberapa cara membuat objek yang sama. }

program oop_08_overload;

type
  TWaktu = class
    Jam, Menit: Integer;
    constructor Create; overload;
    constructor Create(AJam, AMenit: Integer); overload;
    constructor Create(TotalMenit: LongInt); overload;
    procedure Tambah(M: Integer); overload;
    procedure Tambah(Lain: TWaktu); overload;
    function Teks: String;
  end;

constructor TWaktu.Create;
begin
  Create(0, 0);                          { memakai versi lain }
end;

constructor TWaktu.Create(AJam, AMenit: Integer);
begin
  inherited Create;
  Jam := AJam;
  Menit := AMenit;
end;

constructor TWaktu.Create(TotalMenit: LongInt);
begin
  Create(TotalMenit div 60, TotalMenit mod 60);
end;

procedure TWaktu.Tambah(M: Integer);
var
  Total: LongInt;
begin
  Total := (Jam * 60 + Menit + M) mod (24 * 60);
  Jam := Total div 60;
  Menit := Total mod 60;
end;

procedure TWaktu.Tambah(Lain: TWaktu);
begin
  Tambah(Lain.Jam * 60 + Lain.Menit);
end;

function TWaktu.Teks: String;
var
  J, M: String;
begin
  Str(Jam:2, J);
  Str(Menit:2, M);
  if J[1] = ' ' then J[1] := '0';
  if M[1] = ' ' then M[1] := '0';
  Teks := J + ':' + M;
end;

var
  A, B, C: TWaktu;
  Durasi: LongInt;

begin
  A := TWaktu.Create;                    { 00:00 }
  B := TWaktu.Create(7, 45);             { 07:45 }
  Durasi := 135;
  C := TWaktu.Create(Durasi);            { 135 menit = 02:15 }
  WriteLn('A = ', A.Teks, '  B = ', B.Teks, '  C = ', C.Teks);
  B.Tambah(30);
  WriteLn('B + 30 menit   = ', B.Teks);
  B.Tambah(C);
  WriteLn('B + C          = ', B.Teks);
  A.Tambah(25 * 60);
  WriteLn('A + 25 jam     = ', A.Teks);
  A.Free;
  B.Free;
  C.Free;
end.
