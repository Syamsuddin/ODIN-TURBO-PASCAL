{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 12.2 - Membalik kata
  Dua latihan: membalik urutan huruf, dan membalik urutan kata.
  Fungsi boleh mengembalikan string. }

program bab12_02_balik_kata;

{ Membaca huruf dari belakang ke depan, lalu menyambungnya }
function BalikHuruf(S: string): string;
var
  I: Integer;
  Hasil: string;
begin
  Hasil := '';                           { mulai dari string kosong }
  for I := Length(S) downto 1 do
    Hasil := Hasil + S[I];
  BalikHuruf := Hasil;
end;

{ Memotong kata pertama berulang kali, lalu menaruhnya di depan hasil }
function BalikUrutanKata(S: string): string;
var
  Spasi: Integer;
  Hasil, Kata: string;
begin
  Hasil := '';
  while S <> '' do
  begin
    Spasi := Pos(' ', S);
    if Spasi = 0 then                    { kata terakhir }
    begin
      Kata := S;
      S := '';
    end
    else
    begin
      Kata := Copy(S, 1, Spasi - 1);
      Delete(S, 1, Spasi);               { buang kata dan spasinya }
    end;
    if Kata <> '' then                   { lewati spasi ganda }
      if Hasil = '' then
        Hasil := Kata
      else
        Hasil := Kata + ' ' + Hasil;
  end;
  BalikUrutanKata := Hasil;
end;

var
  Kalimat: string;

begin
  Write('Ketik sebuah kalimat: ');
  ReadLn(Kalimat);
  WriteLn('Huruf dibalik : ', BalikHuruf(Kalimat));
  WriteLn('Kata dibalik  : ', BalikUrutanKata(Kalimat));
end.
