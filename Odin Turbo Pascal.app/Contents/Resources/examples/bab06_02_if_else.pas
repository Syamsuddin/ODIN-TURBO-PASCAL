{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 6.2 - if..then..else
  else berisi perintah untuk keadaan sebaliknya. Ingat: TIDAK ADA
  titik koma tepat sebelum else. }

program bab06_02_if_else;

var
  Bilangan: Integer;
  Nilai: Integer;

begin
  Write('Masukkan bilangan bulat: ');
  ReadLn(Bilangan);
  if Bilangan mod 2 = 0 then
    WriteLn(Bilangan, ' adalah bilangan genap')   { tanpa titik koma }
  else
    WriteLn(Bilangan, ' adalah bilangan ganjil');

  Write('Masukkan nilai ujian: ');
  ReadLn(Nilai);
  if Nilai >= 75 then
  begin
    WriteLn('Selamat, Anda LULUS.');
    WriteLn('Nilai Anda melewati KKM 75.');
  end                                    { end tanpa titik koma juga }
  else
  begin
    WriteLn('Anda belum lulus.');
    WriteLn('Kurang ', 75 - Nilai, ' poin lagi.');
  end;
end.
