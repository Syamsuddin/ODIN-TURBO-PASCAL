{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 20.2 - Proyek: pengolah nilai siswa
  Memasukkan nilai tugas, UTS, dan UAS, menghitung nilai akhir
  berbobot dan nilai huruf, mengurutkan peringkat, menghitung
  statistik kelas, lalu menyimpan rekapnya ke file teks. }

program bab20_02_nilai_siswa;

const
  NamaFileRekap = 'rekap_nilai.txt';
  MaksSiswa = 40;
  KKM = 75;                              { kriteria ketuntasan minimal }
  BobotTugas = 0.3;                      { bobot berjumlah 1.0 }
  BobotUTS = 0.3;
  BobotUAS = 0.4;

type
  TSiswa = record
    Nama: string[20];
    Tugas, UTS, UAS: Integer;
    Akhir: Real;
  end;

var
  Siswa: array[1..MaksSiswa] of TSiswa;
  N: Integer;

{ Membaca bilangan bulat dalam rentang Min..Max, diulang bila salah }
function BacaNilai(Pesan: string; Min, Max: Integer): Integer;
var
  Teks: string;
  Nilai, Kode: Integer;
begin
  repeat
    Write(Pesan);
    ReadLn(Teks);
    Val(Teks, Nilai, Kode);
    if (Kode <> 0) or (Nilai < Min) or (Nilai > Max) then
    begin
      WriteLn('  Harus angka ', Min, ' sampai ', Max, '.');
      Kode := 1;                         { paksa ulang }
    end;
  until Kode = 0;
  BacaNilai := Nilai;
end;

function Huruf(Nilai: Real): Char;
begin
  if Nilai >= 85 then Huruf := 'A'
  else if Nilai >= 70 then Huruf := 'B'
  else if Nilai >= 55 then Huruf := 'C'
  else if Nilai >= 40 then Huruf := 'D'
  else Huruf := 'E';
end;

procedure IsiData;
var
  I: Integer;
begin
  N := BacaNilai('Jumlah siswa (1-40): ', 1, MaksSiswa);
  for I := 1 to N do
    with Siswa[I] do
    begin
      WriteLn('Siswa ke-', I);
      Write('  Nama  : '); ReadLn(Nama);
      Tugas := BacaNilai('  Tugas : ', 0, 100);
      UTS := BacaNilai('  UTS   : ', 0, 100);
      UAS := BacaNilai('  UAS   : ', 0, 100);
      Akhir := BobotTugas * Tugas + BobotUTS * UTS + BobotUAS * UAS;
    end;
end;

procedure UrutkanPeringkat;              { insertion sort, tertinggi dulu }
var
  I, J: Integer;
  Kunci: TSiswa;
begin
  for I := 2 to N do
  begin
    Kunci := Siswa[I];
    J := I - 1;
    while (J >= 1) and (Siswa[J].Akhir < Kunci.Akhir) do
    begin
      Siswa[J + 1] := Siswa[J];
      J := J - 1;
    end;
    Siswa[J + 1] := Kunci;
  end;
end;

procedure CetakRekap(var F: Text);
var
  I, Lulus: Integer;
  Jumlah: Real;
begin
  WriteLn(F, 'REKAP NILAI KELAS');
  WriteLn(F, 'Bobot: tugas 30%, UTS 30%, UAS 40%.  KKM ', KKM);
  WriteLn(F, 'No  Nama                 Tugas  UTS  UAS  Akhir  Huruf  Ket');
  WriteLn(F, '-------------------------------------------------------------');
  Jumlah := 0;
  Lulus := 0;
  for I := 1 to N do
    with Siswa[I] do
    begin
      Write(F, I:2, '  ', Nama, '':20 - Length(Nama), Tugas:6, UTS:5,
        UAS:5, Akhir:7:1, '    ', Huruf(Akhir), '    ');
      if Akhir >= KKM then
      begin
        WriteLn(F, 'Tuntas');
        Lulus := Lulus + 1;
      end
      else
        WriteLn(F, 'Remedial');
      Jumlah := Jumlah + Akhir;
    end;
  WriteLn(F, '-------------------------------------------------------------');
  WriteLn(F, 'Rata-rata kelas : ', Jumlah / N:0:1);
  WriteLn(F, 'Tertinggi       : ', Siswa[1].Akhir:0:1,
    ' (', Siswa[1].Nama, ')');
  WriteLn(F, 'Terendah        : ', Siswa[N].Akhir:0:1,
    ' (', Siswa[N].Nama, ')');
  WriteLn(F, 'Tuntas          : ', Lulus, ' dari ', N, ' siswa');
end;

var
  FileRekap: Text;
  Folder: string;

begin
  IsiData;
  UrutkanPeringkat;                      { sesudah diurut, Siswa[1] terbaik }
  WriteLn;
  CetakRekap(Output);

  Assign(FileRekap, NamaFileRekap);
  Rewrite(FileRekap);
  CetakRekap(FileRekap);
  Close(FileRekap);
  GetDir(0, Folder);
  WriteLn;
  WriteLn('Rekap disimpan ke ', NamaFileRekap, ' di folder ', Folder);
end.
