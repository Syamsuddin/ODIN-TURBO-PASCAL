{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 9.4 - Parameter var
  Parameter yang diawali var tidak menerima salinan, tetapi memakai
  variabel aslinya. Perubahan di dalam prosedur ikut terlihat di luar.
  Dipakai untuk mengubah variabel atau mengembalikan beberapa hasil. }

program bab09_04_parameter_var;

procedure Tukar(var A, B: Integer);      { A dan B adalah variabel asli }
var
  Sementara: Integer;
begin
  Sementara := A;
  A := B;
  B := Sementara;
end;

{ Dua hasil sekaligus: Luas dan Keliling dikirim lewat parameter var }
procedure HitungPersegi(Panjang, Lebar: Real; var Luas, Keliling: Real);
begin
  Luas := Panjang * Lebar;
  Keliling := 2 * (Panjang + Lebar);
end;

var
  X, Y: Integer;
  L, K: Real;

begin
  X := 3;
  Y := 8;
  WriteLn('Sebelum ditukar: X = ', X, ', Y = ', Y);
  Tukar(X, Y);
  WriteLn('Sesudah ditukar: X = ', X, ', Y = ', Y);

  HitungPersegi(6, 4, L, K);
  WriteLn('Persegi panjang 6 x 4: luas ', L:0:1, ', keliling ', K:0:1);

  { Argumen untuk parameter var harus variabel, bukan angka atau
    ekspresi. Tukar(3, 8) akan ditolak kompiler. }
end.
