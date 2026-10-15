{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 3.1 - Tipe Integer dan Real
  Integer dan LongInt menyimpan bilangan bulat. Real menyimpan bilangan
  pecahan. Bilangan Real ditampilkan dengan format :lebar:desimal. }

program bab03_01_tipe_integer_real;

var
  JumlahSiswa: Integer;        { bilangan bulat kecil, -32768..32767 }
  Penduduk: LongInt;           { bilangan bulat besar, sampai 2 miliar }
  TinggiBadan: Real;           { bilangan pecahan, memakai titik desimal }
  RataRata: Real;

begin
  JumlahSiswa := 32;
  Penduduk := 2750000;
  TinggiBadan := 165.5;        { pemisah desimal di Pascal adalah titik }

  WriteLn('Jumlah siswa : ', JumlahSiswa);
  WriteLn('Penduduk     : ', Penduduk);
  WriteLn('Tinggi badan : ', TinggiBadan:0:1, ' cm');  { 1 angka desimal }

  { Pembagian dengan / selalu menghasilkan Real, walau angkanya bulat }
  RataRata := 100 / JumlahSiswa;
  WriteLn('100 / 32     = ', RataRata:0:4);

  { Integer boleh dimasukkan ke Real, tetapi Real tidak boleh langsung
    dimasukkan ke Integer. Gunakan Trunc (buang pecahan) atau Round. }
  TinggiBadan := JumlahSiswa;
  WriteLn('Integer jadi Real   : ', TinggiBadan:0:2);
  JumlahSiswa := Trunc(165.9);
  WriteLn('Trunc(165.9)        : ', JumlahSiswa);
  JumlahSiswa := Round(165.9);
  WriteLn('Round(165.9)        : ', JumlahSiswa);
end.
