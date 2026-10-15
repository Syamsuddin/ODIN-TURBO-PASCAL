{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 11.5 - Perkalian matriks
  A (2 x 3) dikali B (3 x 2) menghasilkan C (2 x 2). Syaratnya:
  jumlah kolom A sama dengan jumlah baris B. Setiap C[i, j] adalah
  jumlah perkalian baris i dari A dengan kolom j dari B. }

program bab11_05_perkalian_matriks;

const
  BarisA = 2;
  KolomA = 3;                            { sama dengan baris B }
  KolomB = 2;
  A: array[1..BarisA, 1..KolomA] of Integer = ((1, 2, 3),
                                               (4, 5, 6));
  B: array[1..KolomA, 1..KolomB] of Integer = ((7, 8),
                                               (9, 10),
                                               (11, 12));

var
  C: array[1..BarisA, 1..KolomB] of Integer;
  I, J, K: Integer;

begin
  for I := 1 to BarisA do
    for J := 1 to KolomB do
    begin
      C[I, J] := 0;
      for K := 1 to KolomA do            { baris I dari A x kolom J dari B }
        C[I, J] := C[I, J] + A[I, K] * B[K, J];
    end;

  WriteLn('Hasil A x B:');
  for I := 1 to BarisA do
  begin
    for J := 1 to KolomB do
      Write(C[I, J]:6);
    WriteLn;
  end;

  { Rincian satu elemen agar polanya terlihat }
  WriteLn('C[1,1] = 1x7 + 2x9 + 3x11 = ', C[1, 1]);
end.
