{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 3.3 - Tipe Boolean
  Boolean hanya punya dua nilai: True (benar) dan False (salah).
  Hasil perbandingan seperti Umur >= 17 adalah nilai Boolean. }

program bab03_03_tipe_boolean;

var
  Umur: Integer;
  SudahDewasa: Boolean;
  PunyaKTP: Boolean;
  Hujan: Boolean;

begin
  Umur := 19;
  SudahDewasa := Umur >= 17;     { hasil perbandingan disimpan }
  PunyaKTP := True;
  Hujan := False;

  WriteLn('Umur          : ', Umur);
  WriteLn('Sudah dewasa? : ', SudahDewasa);    { tampil TRUE atau FALSE }
  WriteLn('Punya KTP?    : ', PunyaKTP);
  WriteLn('Hujan?        : ', Hujan);

  { Variabel Boolean bisa langsung dipakai sebagai syarat }
  if SudahDewasa then
    WriteLn('Boleh membuat SIM.');
  if not Hujan then                { not membalik True <-> False }
    WriteLn('Tidak perlu membawa payung.');
end.
