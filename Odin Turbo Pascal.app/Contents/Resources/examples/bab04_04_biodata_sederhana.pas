{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 4.4 - Latihan: biodata sederhana
  Menggabungkan masukan (ReadLn) dan keluaran berformat (WriteLn)
  untuk mencetak kartu biodata. }

program bab04_04_biodata_sederhana;

var
  Nama, Alamat, Hobi: string;
  TahunLahir, Umur: Integer;
  Tinggi, Berat: Real;

const
  TahunIni = 2026;

begin
  WriteLn('ISI BIODATA');
  Write('Nama lengkap : '); ReadLn(Nama);
  Write('Alamat       : '); ReadLn(Alamat);
  Write('Tahun lahir  : '); ReadLn(TahunLahir);
  Write('Tinggi (cm)  : '); ReadLn(Tinggi);
  Write('Berat (kg)   : '); ReadLn(Berat);
  Write('Hobi         : '); ReadLn(Hobi);

  Umur := TahunIni - TahunLahir;   { umur dihitung, tidak ditanyakan }

  WriteLn;
  WriteLn('+--------------------------------------+');
  WriteLn('|            KARTU BIODATA             |');
  WriteLn('+--------------------------------------+');
  WriteLn('  Nama   : ', Nama);
  WriteLn('  Alamat : ', Alamat);
  WriteLn('  Umur   : ', Umur, ' tahun');
  WriteLn('  Tinggi : ', Tinggi:0:1, ' cm');
  WriteLn('  Berat  : ', Berat:0:1, ' kg');
  WriteLn('  Hobi   : ', Hobi);
  WriteLn('+--------------------------------------+');
end.
