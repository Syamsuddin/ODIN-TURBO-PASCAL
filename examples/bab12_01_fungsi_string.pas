{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 12.1 - Fungsi dan prosedur string
  Length(S)          panjang string
  Copy(S, Awal, N)   mengambil N karakter mulai posisi Awal
  Pos(Cari, S)       posisi pertama Cari di S, 0 bila tidak ada
  Insert(T, S, P)    menyisipkan T ke S pada posisi P
  Delete(S, P, N)    menghapus N karakter mulai posisi P
  UpCase(C)          huruf kecil menjadi huruf besar (satu Char) }

program bab12_01_fungsi_string;

var
  Kalimat, Kata: string;
  I, Posisi: Integer;

begin
  Kalimat := 'Belajar Pascal itu menyenangkan';
  WriteLn('Kalimat   : ', Kalimat);
  WriteLn('Panjang   : ', Length(Kalimat));
  WriteLn('Copy 9..14: ', Copy(Kalimat, 9, 6));     { 'Pascal' }

  Posisi := Pos('itu', Kalimat);
  WriteLn('Pos "itu" : ', Posisi);
  WriteLn('Pos "Java": ', Pos('Java', Kalimat));    { 0: tidak ditemukan }

  { Insert dan Delete mengubah variabelnya langsung }
  Insert('sangat ', Kalimat, Pos('menyenangkan', Kalimat));
  WriteLn('Insert    : ', Kalimat);
  Delete(Kalimat, 1, 8);                            { buang 'Belajar ' }
  WriteLn('Delete    : ', Kalimat);

  { Mengubah seluruh huruf menjadi kapital, satu per satu }
  Kata := Kalimat;
  for I := 1 to Length(Kata) do
    Kata[I] := UpCase(Kata[I]);
  WriteLn('Kapital   : ', Kata);

  { Menyambung string: operator + atau fungsi Concat }
  WriteLn('Sambung   : ', Concat('Turbo', ' ', 'Pascal'), ' ' + '7');
end.
