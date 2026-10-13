{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program BerkasTeks;
var
  F: Text;
  Baris, NamaFile: string;
begin
  Write('Nama berkas baru (misal catatan.txt): ');
  ReadLn(NamaFile);
  Assign(F, NamaFile);
  {$I-} Reset(F); {$I+}
  if IOResult = 0 then
  begin
    Close(F);
    WriteLn('Berkas sudah ada. Gunakan nama baru agar data tidak tertimpa.');
    Halt(1);
  end;
  {$I-} Rewrite(F); {$I+}
  if IOResult <> 0 then
  begin
    WriteLn('Berkas tidak bisa dibuat pada direktori ini.');
    Halt(1);
  end;
  WriteLn(F, 'Belajar Pascal dengan Odin.');
  Close(F);
  Reset(F);
  while not Eof(F) do
  begin
    ReadLn(F, Baris);
    WriteLn(Baris);
  end;
  Close(F);
  WriteLn('Berkas tersimpan: ', NamaFile);
end.
