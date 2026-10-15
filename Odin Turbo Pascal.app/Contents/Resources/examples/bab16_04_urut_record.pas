{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 16.4 - Mengurutkan array of record
  Yang dibandingkan adalah satu field (misalnya Nilai), tetapi yang
  dipindahkan adalah record utuh, supaya nama tetap bersama nilainya.
  Urutan: nilai tertinggi dulu; bila nilainya sama, urut nama A-Z. }

program bab16_04_urut_record;

type
  TSiswa = record
    Nama: string[15];
    Nilai: Integer;
  end;

const
  N = 7;
  Awal: array[1..N] of TSiswa = (
    (Nama: 'Dimas'; Nilai: 78), (Nama: 'Ayu';   Nilai: 92),
    (Nama: 'Fajar'; Nilai: 85), (Nama: 'Citra'; Nilai: 92),
    (Nama: 'Bayu';  Nilai: 70), (Nama: 'Eka';   Nilai: 85),
    (Nama: 'Gita';  Nilai: 88));

{ True bila A harus berada di depan B }
function LebihDulu(A, B: TSiswa): Boolean;
begin
  if A.Nilai <> B.Nilai then
    LebihDulu := A.Nilai > B.Nilai       { nilai besar di depan }
  else
    LebihDulu := A.Nama < B.Nama;        { nilai sama: urut abjad }
end;

var
  Siswa: array[1..N] of TSiswa;
  Kunci: TSiswa;
  I, J, Peringkat: Integer;

begin
  for I := 1 to N do
    Siswa[I] := Awal[I];                 { salin record utuh }

  { Insertion sort dari Bab 16.3, memakai LebihDulu sebagai pembanding }
  for I := 2 to N do
  begin
    Kunci := Siswa[I];
    J := I - 1;
    while (J >= 1) and LebihDulu(Kunci, Siswa[J]) do
    begin
      Siswa[J + 1] := Siswa[J];
      J := J - 1;
    end;
    Siswa[J + 1] := Kunci;
  end;

  WriteLn('Peringkat  Nama           Nilai');
  for I := 1 to N do
  begin
    { Nilai sama mendapat peringkat yang sama }
    if (I = 1) or (Siswa[I].Nilai <> Siswa[I - 1].Nilai) then
      Peringkat := I;
    WriteLn(Peringkat:5, '      ', Siswa[I].Nama,
      '':15 - Length(Siswa[I].Nama), Siswa[I].Nilai:5);
  end;
end.
