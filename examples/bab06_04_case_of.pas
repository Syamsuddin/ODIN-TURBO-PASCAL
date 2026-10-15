{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 6.4 - case..of
  case memilih cabang berdasarkan nilai ordinal (Integer, Char, dst).
  Satu cabang boleh berisi daftar nilai (1, 7) atau rentang (2..6).
  Cabang else dipakai bila tidak ada nilai yang cocok. }

program bab06_04_case_of;

var
  NomorHari: Integer;
  Huruf: Char;

begin
  Write('Nomor hari (1 = Minggu ... 7 = Sabtu): ');
  ReadLn(NomorHari);
  case NomorHari of
    1: WriteLn('Minggu');
    2: WriteLn('Senin');
    3: WriteLn('Selasa');
    4: WriteLn('Rabu');
    5: WriteLn('Kamis');
    6: WriteLn('Jumat');
    7: WriteLn('Sabtu');
  else
    WriteLn('Nomor hari harus 1 sampai 7.');
  end;                                   { case selalu ditutup end }

  case NomorHari of
    1, 7: WriteLn('Hari libur akhir pekan.');   { daftar nilai }
    2..6: WriteLn('Hari sekolah.');             { rentang nilai }
  end;

  Write('Ketik sebuah huruf: ');
  ReadLn(Huruf);
  Huruf := UpCase(Huruf);                { a..z diubah menjadi A..Z }
  { Setiap nilai hanya boleh muncul di SATU cabang. Rentang 'B'..'Z'
    akan bentrok dengan vokal, jadi konsonan ditulis per potongan. }
  case Huruf of
    'A', 'I', 'U', 'E', 'O':
      WriteLn('Huruf vokal');
    'B'..'D', 'F'..'H', 'J'..'N', 'P'..'T', 'V'..'Z':
      WriteLn('Huruf konsonan');
    '0'..'9':
      WriteLn('Itu angka, bukan huruf');
  else
    WriteLn('Bukan huruf');
  end;
end.
