{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 17.4 - File bertipe
  File bertipe (file of ...) menyimpan data dalam bentuk biner, bukan
  teks. Setiap elemen berukuran sama, jadi elemen mana pun bisa
  langsung didatangi dengan Seek. Nomor elemen dimulai dari 0.
    FileSize(F)  banyak elemen     FilePos(F)  posisi saat ini
    Seek(F, N)   pindah ke elemen N }

program bab17_04_file_bertipe;

const
  NamaFile = 'angka.dat';

var
  F: file of LongInt;                    { setiap elemen satu LongInt }
  X: LongInt;
  I: Integer;
  Folder: string;

begin
  Assign(F, NamaFile);
  Rewrite(F);
  for I := 1 to 10 do
  begin
    X := I * I;
    Write(F, X);                         { file bertipe memakai Write }
  end;
  WriteLn('Ditulis ', FileSize(F), ' elemen (kuadrat 1 sampai 10).');

  Seek(F, 4);                            { elemen ke-5, karena mulai 0 }
  Read(F, X);
  WriteLn('Elemen nomor 4 berisi ', X);
  WriteLn('Posisi sekarang: ', FilePos(F));

  Seek(F, 0);                            { ubah elemen pertama }
  X := 1000;
  Write(F, X);

  WriteLn('Isi file sekarang:');
  Seek(F, 0);
  while not Eof(F) do
  begin
    Read(F, X);
    Write(X, ' ');
  end;
  WriteLn;
  Close(F);

  GetDir(0, Folder);
  WriteLn('File ', NamaFile, ' ada di folder ', Folder);
  WriteLn('Coba buka dengan editor teks: isinya bukan tulisan biasa.');
end.
