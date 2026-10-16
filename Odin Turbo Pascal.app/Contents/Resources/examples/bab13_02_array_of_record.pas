{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 13.2 - Array of record
  Array yang setiap elemennya berupa record, cocok untuk tabel data:
  satu elemen array = satu baris, satu field = satu kolom.
  Field elemen ke-I diakses dengan Siswa[I].Nama. }

program bab13_02_array_of_record;

const
  MaksSiswa = 30;

type
  TSiswa = record
    Nama: string[20];
    Kelas: string[5];
    Nilai: Integer;
  end;

var
  Siswa: array[1..MaksSiswa] of TSiswa;
  N, I, Terbaik: Integer;

begin
  repeat
    Write('Jumlah siswa (1-', MaksSiswa, '): ');
    ReadLn(N);
  until (N >= 1) and (N <= MaksSiswa);

  for I := 1 to N do
  begin
    WriteLn('Siswa ke-', I);
    Write('  Nama  : '); ReadLn(Siswa[I].Nama);
    Write('  Kelas : '); ReadLn(Siswa[I].Kelas);
    Write('  Nilai : '); ReadLn(Siswa[I].Nilai);
  end;

  WriteLn;
  WriteLn('No  Nama                  Kelas  Nilai');
  WriteLn('--------------------------------------');
  Terbaik := 1;
  for I := 1 to N do
  begin
    { '':N menulis N spasi, agar teks rata kiri dalam kolomnya }
    with Siswa[I] do                     { with juga berlaku untuk elemen }
      WriteLn(I:2, '  ', Nama, '':22 - Length(Nama), Kelas,
        '':7 - Length(Kelas), Nilai:5);
    if Siswa[I].Nilai > Siswa[Terbaik].Nilai then
      Terbaik := I;
  end;
  WriteLn('--------------------------------------');
  WriteLn('Nilai tertinggi: ', Siswa[Terbaik].Nama,
    ' (', Siswa[Terbaik].Nilai, ')');
end.
