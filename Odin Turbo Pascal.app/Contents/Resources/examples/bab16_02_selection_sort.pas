{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 16.2 - Selection sort
  Pada putaran ke-I, cari elemen terkecil di bagian yang belum
  terurut (I..N), lalu tukar dengan elemen ke-I. Hanya satu
  pertukaran per putaran. }

program bab16_02_selection_sort;

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
  I, J, PosisiMin, Sementara: Integer;

begin
  for I := 1 to N do
    Data[I] := Awal[I];
  Tampilkan('Awal      :', Data);

  for I := 1 to N - 1 do
  begin
    PosisiMin := I;                      { anggap elemen ke-I terkecil }
    for J := I + 1 to N do
      if Data[J] < Data[PosisiMin] then
        PosisiMin := J;                  { ketemu yang lebih kecil }
    if PosisiMin <> I then
    begin
      Sementara := Data[I];
      Data[I] := Data[PosisiMin];
      Data[PosisiMin] := Sementara;
    end;
    Write('Putaran ', I, ' :');
    Tampilkan('', Data);
  end;

  Tampilkan('Hasil     :', Data);
end.
