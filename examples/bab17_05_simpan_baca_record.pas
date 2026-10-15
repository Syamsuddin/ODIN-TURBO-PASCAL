{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 17.5 - Menyimpan dan membaca record
  file of TSiswa menyimpan record utuh. Data tetap ada walau program
  ditutup, jadi jalankan program ini beberapa kali dan lihat datanya
  bertambah. Field string memakai panjang tetap, misalnya string[20]. }

program bab17_05_simpan_baca_record;

const
  NamaFile = 'siswa.dat';

type
  TSiswa = record
    Nama: string[20];
    Kelas: string[5];
    Nilai: Integer;
  end;

var
  F: file of TSiswa;
  S: TSiswa;
  Nama: string;
  Nomor: Integer;

begin
  Assign(F, NamaFile);
  {$I-}
  Reset(F);                              { buka file yang sudah ada }
  {$I+}
  if IOResult <> 0 then
    Rewrite(F);                          { belum ada: buat baru }
  WriteLn('Data tersimpan saat ini: ', FileSize(F), ' siswa.');

  Seek(F, FileSize(F));                  { pindah ke akhir untuk menambah }
  WriteLn('Tambah siswa baru (nama kosong = selesai).');
  repeat
    Write('Nama  : ');
    ReadLn(Nama);
    if Nama <> '' then
    begin
      S.Nama := Nama;
      Write('Kelas : '); ReadLn(S.Kelas);
      Write('Nilai : '); ReadLn(S.Nilai);
      Write(F, S);                       { simpan satu record }
    end;
  until Nama = '';

  WriteLn;
  WriteLn('No  Nama                  Kelas  Nilai');
  Seek(F, 0);                            { kembali ke awal untuk membaca }
  Nomor := 0;
  while not Eof(F) do
  begin
    Read(F, S);
    Nomor := Nomor + 1;
    WriteLn(Nomor:2, '  ', S.Nama, '':22 - Length(S.Nama), S.Kelas,
      '':7 - Length(S.Kelas), S.Nilai:5);
  end;
  Close(F);
end.
