{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Records;
type
  TWarna = (Merah, Hijau, Biru);
  TTitik = record
    X, Y: Integer;
  end;
  TBentuk = record
    Nama: String[10];
    Pusat: TTitik;
    case Jenis: Byte of
      0: (Jari: Real);
      1: (Lebar, Tinggi: Integer);
  end;
  TDaftar = array[1..3] of TTitik;
  TGrid = array[0..2, 0..2] of Char;
  TSetWarna = set of TWarna;
var
  P, Q: TTitik;
  B: TBentuk;
  D: TDaftar;
  G: TGrid;
  i, j: Integer;
  W: TWarna;
  S: TSetWarna;
  Huruf: set of Char;

function Geser(T: TTitik; DX: Integer): TTitik;
begin
  T.X := T.X + DX;
  Geser := T;
end;

procedure Tukar(var A, B: TTitik);
var Tmp: TTitik;
begin
  Tmp := A; A := B; B := Tmp;
end;

begin
  P.X := 1; P.Y := 2;
  Q := P;
  Q.X := 10;
  WriteLn(P.X, ' ', P.Y, ' ', Q.X, ' ', Q.Y);
  Q := Geser(P, 5);
  WriteLn(P.X, ' ', Q.X);
  Tukar(P, Q);
  WriteLn(P.X, ' ', Q.X);
  with B do
  begin
    Nama := 'persegi panjang';
    Pusat.X := 3;
    Jenis := 1;
    Lebar := 4;
    Tinggi := 5;
  end;
  WriteLn(B.Nama, ' ', B.Pusat.X, ' ', B.Lebar * B.Tinggi);
  for i := 1 to 3 do
    with D[i] do
    begin
      X := i;
      Y := i * i;
    end;
  for i := 1 to 3 do Write(D[i].X, ':', D[i].Y, ' ');
  WriteLn;
  for i := 0 to 2 do
    for j := 0 to 2 do
      if i = j then G[i, j] := 'x' else G[i, j] := '.';
  for i := 0 to 2 do
  begin
    for j := 0 to 2 do Write(G[i][j]);
    WriteLn;
  end;
  S := [];
  for W := Merah to Biru do
    if W <> Hijau then S := S + [W];
  WriteLn(Merah in S, ' ', Hijau in S, ' ', Biru in S);
  Include(S, Hijau); Exclude(S, Merah);
  WriteLn(Merah in S, ' ', Hijau in S, ' ', S = [Hijau, Biru], ' ', [Biru] <= S);
  Huruf := ['a'..'e', 'x'];
  for i := Ord('a') to Ord('z') do
    if Chr(i) in Huruf then Write(Chr(i));
  WriteLn;
  WriteLn(Ord(Biru), ' ', Ord(Succ(Merah)), ' ', SizeOf(TTitik), ' ', SizeOf(TBentuk), ' ', SizeOf(TSetWarna), ' ', SizeOf(Huruf));
  WriteLn(High(TDaftar), ' ', Low(TGrid), ' ', High(TWarna) = Biru);
end.
