{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 16.5 - Membandingkan jumlah langkah
  Tiga algoritma pengurutan dijalankan pada data yang sama, lalu
  dihitung perbandingan dan pemindahannya. Dicoba tiga keadaan data:
  acak, sudah terurut, dan terurut terbalik. }

program bab16_05_banding_jumlah_langkah;

const
  N = 20;
  Acak: array[1..N] of Integer = (57, 12, 89, 3, 44, 71, 25, 96, 38, 60,
                                  18, 83, 7, 52, 66, 30, 91, 14, 77, 41);

type
  TData = array[1..N] of Integer;

var
  Banding, Pindah: LongInt;              { penghitung langkah }

procedure Tukar(var A, B: Integer);
var
  T: Integer;
begin
  T := A; A := B; B := T;
  Pindah := Pindah + 1;
end;

procedure BubbleSort(var D: TData);
var
  I, Putaran: Integer;
  AdaTukar: Boolean;
begin
  Putaran := 0;
  repeat
    AdaTukar := False;
    Putaran := Putaran + 1;
    for I := 1 to N - Putaran do
    begin
      Banding := Banding + 1;
      if D[I] > D[I + 1] then
      begin
        Tukar(D[I], D[I + 1]);
        AdaTukar := True;
      end;
    end;
  until not AdaTukar;
end;

procedure SelectionSort(var D: TData);
var
  I, J, PosisiMin: Integer;
begin
  for I := 1 to N - 1 do
  begin
    PosisiMin := I;
    for J := I + 1 to N do
    begin
      Banding := Banding + 1;
      if D[J] < D[PosisiMin] then
        PosisiMin := J;
    end;
    if PosisiMin <> I then
      Tukar(D[I], D[PosisiMin]);
  end;
end;

procedure InsertionSort(var D: TData);
var
  I, J, Kunci: Integer;
  Lanjut: Boolean;
begin
  for I := 2 to N do
  begin
    Kunci := D[I];
    J := I - 1;
    Lanjut := True;
    while (J >= 1) and Lanjut do
    begin
      Banding := Banding + 1;
      if D[J] > Kunci then
      begin
        D[J + 1] := D[J];
        Pindah := Pindah + 1;
        J := J - 1;
      end
      else
        Lanjut := False;
    end;
    D[J + 1] := Kunci;
  end;
end;

{ Menyiapkan data: 1 = acak, 2 = terurut, 3 = terbalik }
procedure SiapkanData(Jenis: Integer; var D: TData);
var
  I: Integer;
begin
  for I := 1 to N do
    case Jenis of
      1: D[I] := Acak[I];
      2: D[I] := I * 5;
      3: D[I] := (N - I + 1) * 5;
    end;
end;

var
  D: TData;
  Algoritma, Jenis: Integer;

begin
  WriteLn('Jumlah data: ', N);
  WriteLn('Isi kolom: jumlah perbandingan / jumlah pemindahan');
  WriteLn('Algoritma        Acak    Terurut   Terbalik');
  for Algoritma := 1 to 3 do
  begin
    case Algoritma of
      1: Write('Bubble sort   ');
      2: Write('Selection sort');
      3: Write('Insertion sort');
    end;
    for Jenis := 1 to 3 do
    begin
      SiapkanData(Jenis, D);
      Banding := 0;
      Pindah := 0;
      case Algoritma of
        1: BubbleSort(D);
        2: SelectionSort(D);
        3: InsertionSort(D);
      end;
      Write(Banding:5, '/', Pindah:4);
    end;
    WriteLn;
  end;
  WriteLn;
  WriteLn('Perhatikan: pada data terurut, bubble dan insertion sort');
  WriteLn('selesai sangat cepat, selection sort tetap membandingkan semua.');
end.
