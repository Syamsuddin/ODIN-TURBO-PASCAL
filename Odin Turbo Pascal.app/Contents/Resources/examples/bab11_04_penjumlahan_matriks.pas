{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 11.4 - Penjumlahan matriks
  Dua matriks berukuran sama dijumlahkan elemen demi elemen:
  C[i, j] = A[i, j] + B[i, j]. Tipe TMatriks dibuat sekali, lalu
  dipakai untuk variabel dan parameter prosedur. }

program bab11_04_penjumlahan_matriks;

const
  Ukuran = 3;

type
  TMatriks = array[1..Ukuran, 1..Ukuran] of Integer;

const
  A: TMatriks = ((1, 2, 3),
                 (4, 5, 6),
                 (7, 8, 9));
  B: TMatriks = ((9, 8, 7),
                 (6, 5, 4),
                 (3, 2, 1));

procedure Tampilkan(Judul: string; M: TMatriks);
var
  I, J: Integer;
begin
  WriteLn(Judul);
  for I := 1 to Ukuran do
  begin
    for J := 1 to Ukuran do
      Write(M[I, J]:5);
    WriteLn;
  end;
end;

var
  C: TMatriks;
  I, J: Integer;

begin
  for I := 1 to Ukuran do                { setiap baris }
    for J := 1 to Ukuran do              { setiap kolom }
      C[I, J] := A[I, J] + B[I, J];

  Tampilkan('Matriks A:', A);
  Tampilkan('Matriks B:', B);
  Tampilkan('A + B:', C);
end.
