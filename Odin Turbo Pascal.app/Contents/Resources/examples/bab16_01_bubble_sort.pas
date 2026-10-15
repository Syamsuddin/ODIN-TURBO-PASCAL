{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 16.1 - Bubble sort
  Bandingkan dua elemen bersebelahan, tukar bila urutannya salah.
  Setiap putaran membawa elemen terbesar ke ujung kanan, seperti
  gelembung yang naik. Bila satu putaran tanpa pertukaran, data
  sudah terurut dan proses boleh berhenti lebih awal. }

program bab16_01_bubble_sort;

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
  I, Putaran, Sementara: Integer;
  AdaTukar: Boolean;

begin
  for I := 1 to N do
    Data[I] := Awal[I];                  { salin data awal }
  Tampilkan('Awal      :', Data);

  Putaran := 0;
  repeat
    AdaTukar := False;
    Putaran := Putaran + 1;
    for I := 1 to N - Putaran do         { ujung kanan sudah terurut }
      if Data[I] > Data[I + 1] then
      begin
        Sementara := Data[I];            { tukar dua elemen }
        Data[I] := Data[I + 1];
        Data[I + 1] := Sementara;
        AdaTukar := True;
      end;
    Write('Putaran ', Putaran, ' :');
    Tampilkan('', Data);
  until not AdaTukar;

  Tampilkan('Hasil     :', Data);
end.
