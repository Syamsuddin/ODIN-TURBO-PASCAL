{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 8.2 - FPB dan KPK
  FPB (faktor persekutuan terbesar) dicari dengan algoritma Euclid:
  ganti (A, B) menjadi (B, A mod B) sampai B bernilai 0; A adalah FPB.
  KPK (kelipatan persekutuan terkecil) = A x B / FPB. }

program bab08_02_fpb_kpk;

var
  A, B, X, Y, Sisa, FPB, KPK: LongInt;

begin
  Write('Bilangan pertama: '); ReadLn(A);
  Write('Bilangan kedua  : '); ReadLn(B);

  X := A;                                { salin, agar A dan B tetap utuh }
  Y := B;
  WriteLn('Langkah algoritma Euclid:');
  while Y <> 0 do
  begin
    Sisa := X mod Y;
    WriteLn('  ', X, ' mod ', Y, ' = ', Sisa);
    X := Y;
    Y := Sisa;
  end;
  FPB := X;

  KPK := A div FPB * B;                  { bagi dulu agar tidak meluap }
  WriteLn('FPB(', A, ', ', B, ') = ', FPB);
  WriteLn('KPK(', A, ', ', B, ') = ', KPK);
end.
