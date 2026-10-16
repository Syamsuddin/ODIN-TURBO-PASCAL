{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 17.1 - Menulis file teks
  Langkah menulis file: Assign (hubungkan variabel dengan nama file),
  Rewrite (buat file baru), WriteLn(F, ...) (tulis), Close (tutup).
  PERHATIAN: Rewrite menimpa isi file lama yang bernama sama.
  File dibuat di folder kerja program, yaitu folder file .pas ini. }

program bab17_01_tulis_file_teks;

const
  NamaFile = 'catatan.txt';              { satu tempat untuk nama file }

var
  F: Text;                               { variabel file teks }
  Folder, Catatan: string;
  I: Integer;

begin
  Assign(F, NamaFile);
  Rewrite(F);                            { buat baru (atau kosongkan) }
  WriteLn(F, 'CATATAN HARIAN');          { sama seperti WriteLn biasa, }
  WriteLn(F, '==============');          { tetapi ditulis ke file F    }

  for I := 1 to 3 do
  begin
    Write('Catatan ke-', I, ': ');
    ReadLn(Catatan);
    WriteLn(F, I, '. ', Catatan);
  end;
  Close(F);                              { wajib: memastikan isi tersimpan }

  GetDir(0, Folder);                     { folder kerja saat ini }
  WriteLn;
  WriteLn('Tersimpan ke file ', NamaFile);
  WriteLn('di folder ', Folder);
  WriteLn('Jalankan bab17_02_baca_file_teks untuk membacanya.');
end.
