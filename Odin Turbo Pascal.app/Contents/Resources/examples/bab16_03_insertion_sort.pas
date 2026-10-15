{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 16.3 - Insertion sort
  Seperti menyusun kartu di tangan: ambil elemen berikutnya, geser
  elemen yang lebih besar ke kanan, lalu sisipkan elemen itu di
  tempat yang kosong. Bagian kiri selalu sudah terurut. }

program bab16_03_insertion_sort;

const
  N = 8;
  Awal: array[1..N] of Integer = (29, 10, 14, 37, 13, 5, 42, 21);

type
  TData = array[1..N] of Integer;

procedure Tampilkan(Judul: string; D: TData);
var
  I: Integer;
begin
  Write(Judul);
  for I := 1 to N do
    Write(D[I]:4);
  WriteLn;
end;

var
  Data: TData;
  I, J, Kunci: Integer;

begin
  for I := 1 to N do
    Data[I] := Awal[I];
  Tampilkan('Awal      :', Data);

  for I := 2 to N do
  begin
    Kunci := Data[I];                    { kartu yang akan disisipkan }
    J := I - 1;
    while (J >= 1) and (Data[J] > Kunci) do
    begin
      Data[J + 1] := Data[J];            { geser ke kanan }
      J := J - 1;
    end;
    Data[J + 1] := Kunci;                { sisipkan di tempat kosong }
    Write('Sisip ', Kunci:2, '  :');
    Tampilkan('', Data);
  end;

  Tampilkan('Hasil     :', Data);
end.
