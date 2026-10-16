{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 9.5 - Variabel lokal dan global
  Variabel global dideklarasikan di program utama dan dikenal di mana
  saja sesudahnya. Variabel lokal dideklarasikan di dalam prosedur,
  hanya dikenal di sana, dan hilang begitu prosedur selesai. }

program bab09_05_lokal_global;

var
  Hitungan: Integer;                     { global }

procedure Tambah;
begin
  Hitungan := Hitungan + 1;              { memakai variabel global }
end;

procedure Coba;
var
  Hitungan: Integer;                     { lokal, menutupi yang global }
begin
  Hitungan := 100;
  WriteLn('  Di dalam Coba, Hitungan lokal = ', Hitungan);
end;

procedure Sapa;
var
  Kali: Integer;                         { lokal: dibuat baru tiap dipanggil }
begin
  Kali := 1;
  WriteLn('  Halo! Variabel lokal Kali selalu mulai dari ', Kali);
end;

begin
  Hitungan := 0;
  Tambah;
  Tambah;
  WriteLn('Setelah dua kali Tambah, Hitungan = ', Hitungan);

  Coba;                                  { tidak mengubah Hitungan global }
  WriteLn('Kembali di program utama, Hitungan = ', Hitungan);

  Sapa;
  Sapa;
  { Kali tidak dikenal di sini. WriteLn(Kali) akan ditolak kompiler.
    Sebisa mungkin pakai parameter daripada variabel global. }
end.
