{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 17.2 - Membaca file teks
  Reset membuka file untuk dibaca. Eof(F) bernilai True bila sudah di
  akhir file. Membuka file yang tidak ada biasanya menghentikan
  program; dengan $I- pemeriksaan otomatis dimatikan sementara, lalu
  hasilnya dibaca lewat IOResult (0 berarti berhasil). }

program bab17_02_baca_file_teks;

const
  NamaFile = 'catatan.txt';              { dibuat oleh bab17_01 }

var
  F: Text;
  Baris: string;
  NomorBaris: Integer;

begin
  Assign(F, NamaFile);
  {$I-}                                  { matikan pemeriksaan galat I/O }
  Reset(F);
  {$I+}                                  { nyalakan lagi }
  if IOResult <> 0 then
  begin
    WriteLn('File ', NamaFile, ' belum ada.');
    WriteLn('Jalankan bab17_01_tulis_file_teks lebih dulu.');
  end
  else
  begin
    NomorBaris := 0;
    while not Eof(F) do                  { ulangi sampai akhir file }
    begin
      ReadLn(F, Baris);                  { baca satu baris dari file }
      NomorBaris := NomorBaris + 1;
      WriteLn(NomorBaris:3, ' | ', Baris);
    end;
    Close(F);
    WriteLn('Jumlah baris: ', NomorBaris);
  end;
end.
