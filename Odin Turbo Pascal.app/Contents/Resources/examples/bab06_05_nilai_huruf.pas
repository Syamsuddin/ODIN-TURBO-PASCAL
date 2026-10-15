{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 6.5 - Latihan: nilai angka menjadi nilai huruf
  Nilai 0..100 diubah menjadi A, B, C, D, atau E. Nilai di luar
  rentang ditolak lebih dulu dengan if, baru kemudian dipilih case. }

program bab06_05_nilai_huruf;

var
  Nilai: Integer;
  Huruf: Char;

begin
  Write('Masukkan nilai (0-100): ');
  ReadLn(Nilai);

  if (Nilai < 0) or (Nilai > 100) then
    WriteLn('Nilai tidak sah. Harus antara 0 dan 100.')
  else
  begin
    case Nilai of
      85..100: Huruf := 'A';
      70..84:  Huruf := 'B';
      55..69:  Huruf := 'C';
      40..54:  Huruf := 'D';
    else
      Huruf := 'E';                     { 0..39 }
    end;

    WriteLn('Nilai huruf: ', Huruf);
    case Huruf of
      'A': WriteLn('Keterangan: Sangat baik');
      'B': WriteLn('Keterangan: Baik');
      'C': WriteLn('Keterangan: Cukup');
      'D': WriteLn('Keterangan: Kurang');
      'E': WriteLn('Keterangan: Gagal');
    end;
  end;
end.
