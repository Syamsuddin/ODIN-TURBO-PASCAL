{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 14.1 - Tipe enumerasi
  Enumerasi adalah tipe yang nilainya kita daftar sendiri, misalnya
  nama hari. Program jadi lebih mudah dibaca daripada memakai angka
  1..7. Urutannya bernomor 0, 1, 2, ... dan bisa dipakai di for/case. }

program bab14_01_tipe_enumerasi;

type
  THari = (Senin, Selasa, Rabu, Kamis, Jumat, Sabtu, Minggu);

const
  { Turbo Pascal tidak bisa menulis nilai enumerasi langsung dengan
    WriteLn, jadi namanya disimpan dalam array berindeks THari }
  NamaHari: array[THari] of string[6] =
    ('Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu');

var
  Hari: THari;

begin
  for Hari := Senin to Minggu do         { enumerasi sebagai pencacah }
  begin
    Write(Ord(Hari), '. ', NamaHari[Hari]:6, ' : ');
    case Hari of
      Senin..Kamis: WriteLn('hari sekolah');
      Jumat:        WriteLn('hari sekolah, pulang lebih awal');
      Sabtu, Minggu: WriteLn('libur');
    end;
  end;
  WriteLn;

  Hari := Rabu;
  WriteLn('Hari ini    : ', NamaHari[Hari]);
  WriteLn('Besok       : ', NamaHari[Succ(Hari)]);   { nilai sesudahnya }
  WriteLn('Kemarin     : ', NamaHari[Pred(Hari)]);   { nilai sebelumnya }
  WriteLn('Urutan Rabu : ', Ord(Rabu));               { dihitung dari 0 }
  WriteLn('Jumat sesudah Rabu? ', Jumat > Rabu);       { bisa dibandingkan }
  { Succ(Minggu) tidak ada: range checking menghentikan program }
end.
