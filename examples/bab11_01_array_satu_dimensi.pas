{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 11.1 - Array satu dimensi
  Array adalah sederet variabel sejenis dengan satu nama. Setiap
  elemen diakses dengan indeks di dalam kurung siku: Nilai[1],
  Nilai[2], dan seterusnya. Perulangan for cocok untuk mengolahnya. }

program bab11_01_array_satu_dimensi;

const
  Banyak = 5;

var
  Nilai: array[1..Banyak] of Integer;    { 5 elemen, indeks 1 sampai 5 }
  I: Integer;

begin
  { Mengisi array dari keyboard }
  for I := 1 to Banyak do
  begin
    Write('Nilai siswa ke-', I, ': ');
    ReadLn(Nilai[I]);                    { elemen ke-I diisi }
  end;

  WriteLn;
  WriteLn('Isi array:');
  for I := 1 to Banyak do
    WriteLn('  Nilai[', I, '] = ', Nilai[I]);

  Write('Urutan terbalik: ');
  for I := Banyak downto 1 do
    Write(Nilai[I], ' ');
  WriteLn;

  { Elemen bisa diubah satu per satu }
  Nilai[1] := Nilai[1] + 5;
  WriteLn('Nilai pertama setelah ditambah 5: ', Nilai[1]);

  { Indeks di luar 1..5, misalnya Nilai[6], menghentikan program
    dengan runtime error 201 karena range checking aktif. }
end.
