{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 14.3 - Tipe set (himpunan)
  Set menyimpan kumpulan nilai ordinal tanpa urutan dan tanpa kembar.
  Operasi himpunan:  +  gabungan     *  irisan     -  selisih
                     in  anggota?    =  sama?      <=  himpunan bagian?
  Include dan Exclude menambah atau membuang satu anggota. }

program bab14_03_tipe_set;

type
  THari = (Senin, Selasa, Rabu, Kamis, Jumat, Sabtu, Minggu);
  TJadwal = set of THari;

const
  NamaHari: array[THari] of string[6] =
    ('Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu');

procedure Tampilkan(Judul: string; Jadwal: TJadwal);
var
  H: THari;
begin
  Write(Judul, ': ');
  if Jadwal = [] then                    { [] adalah himpunan kosong }
    Write('(kosong)');
  for H := Senin to Minggu do
    if H in Jadwal then                  { periksa keanggotaan }
      Write(NamaHari[H], ' ');
  WriteLn;
end;

var
  Andi, Budi: TJadwal;

begin
  Andi := [Senin, Rabu, Jumat];          { jadwal latihan Andi }
  Budi := [Rabu, Kamis, Jumat, Sabtu];   { jadwal latihan Budi }

  Tampilkan('Andi          ', Andi);
  Tampilkan('Budi          ', Budi);
  Tampilkan('Andi + Budi   ', Andi + Budi);   { salah satu latihan }
  Tampilkan('Andi * Budi   ', Andi * Budi);   { latihan bersama }
  Tampilkan('Andi - Budi   ', Andi - Budi);   { hanya Andi }

  Include(Andi, Minggu);                 { Andi menambah hari Minggu }
  Exclude(Andi, Senin);                  { dan berhenti hari Senin }
  Tampilkan('Andi sekarang ', Andi);

  WriteLn('Andi latihan hari Sabtu? ', Sabtu in Andi);
  WriteLn('[Rabu, Jumat] bagian dari jadwal Budi? ', [Rabu, Jumat] <= Budi);
end.
