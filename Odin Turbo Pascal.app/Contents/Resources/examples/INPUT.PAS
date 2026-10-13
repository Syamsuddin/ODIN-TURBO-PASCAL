{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program InputNama;
var
  Nama: string;
  Umur: Integer;
begin
  Write('Nama Anda: ');
  ReadLn(Nama);
  Write('Umur Anda: ');
  ReadLn(Umur);
  WriteLn;
  WriteLn('Halo, ', Nama, '!');
  WriteLn('Tahun depan umur Anda ', Umur + 1, ' tahun.');
end.
