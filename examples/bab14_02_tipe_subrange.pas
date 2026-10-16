{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 14.2 - Tipe subrange
  Subrange adalah potongan rentang tipe lain, misalnya 0..100 atau
  'A'..'Z'. Variabelnya hanya boleh berisi nilai dalam rentang itu.
  Dengan range checking aktif, nilai di luar rentang menghentikan
  program (runtime error 201), jadi periksa masukan sebelum disimpan. }

program bab14_02_tipe_subrange;

type
  TNilai = 0..100;                       { potongan dari Integer }
  TBulan = 1..12;
  THurufBesar = 'A'..'Z';                { potongan dari Char }
  THari = (Senin, Selasa, Rabu, Kamis, Jumat, Sabtu, Minggu);
  THariKerja = Senin..Jumat;             { potongan dari enumerasi }

const
  JumlahHari: array[TBulan] of Integer =
    (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

var
  Nilai: TNilai;
  Bulan: TBulan;
  Inisial: THurufBesar;
  Masukan: Integer;
  Huruf: Char;

begin
  Write('Nomor bulan (1-12): ');
  ReadLn(Masukan);
  if (Masukan >= 1) and (Masukan <= 12) then
  begin
    Bulan := Masukan;                    { aman: sudah diperiksa }
    WriteLn('Bulan ', Bulan, ' punya ', JumlahHari[Bulan],
      ' hari (tahun biasa).');
  end
  else
    WriteLn('Bulan tidak sah.');

  Write('Nilai ujian (0-100): ');
  ReadLn(Masukan);
  if (Masukan >= Low(TNilai)) and (Masukan <= High(TNilai)) then
  begin
    Nilai := Masukan;
    WriteLn('Nilai ', Nilai, ' disimpan.');
  end
  else
    WriteLn('Nilai harus ', Low(TNilai), ' sampai ', High(TNilai), '.');

  Write('Huruf awal nama: ');
  ReadLn(Huruf);
  Huruf := UpCase(Huruf);
  if (Huruf >= 'A') and (Huruf <= 'Z') then
  begin
    Inisial := Huruf;
    WriteLn('Inisial: ', Inisial);
  end
  else
    WriteLn('Inisial harus berupa huruf.');

  { Low dan High juga berlaku untuk subrange dari enumerasi }
  WriteLn('Hari kerja: ', Ord(High(THariKerja)) - Ord(Low(THariKerja)) + 1,
    ' hari');
end.
