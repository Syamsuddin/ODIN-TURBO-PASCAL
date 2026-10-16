{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 12.3 - Palindrom
  Palindrom terbaca sama dari depan dan dari belakang, misalnya
  "kakak", "katak", atau "Kasur ini rusak". Spasi dan huruf besar/
  kecil diabaikan, jadi teks dibersihkan dulu sebelum diperiksa. }

program bab12_03_palindrom;

{ Hanya menyimpan huruf dan angka, semuanya dijadikan kapital }
function Bersihkan(S: string): string;
var
  I: Integer;
  C: Char;
  Hasil: string;
begin
  Hasil := '';
  for I := 1 to Length(S) do
  begin
    C := UpCase(S[I]);
    if ((C >= 'A') and (C <= 'Z')) or ((C >= '0') and (C <= '9')) then
      Hasil := Hasil + C;
  end;
  Bersihkan := Hasil;
end;

{ Bandingkan huruf ke-1 dengan terakhir, ke-2 dengan kedua terakhir, ... }
function Palindrom(S: string): Boolean;
var
  Kiri, Kanan: Integer;
begin
  Palindrom := True;
  Kiri := 1;
  Kanan := Length(S);
  while Kiri < Kanan do
  begin
    if S[Kiri] <> S[Kanan] then
    begin
      Palindrom := False;
      Exit;                              { satu beda sudah cukup }
    end;
    Kiri := Kiri + 1;
    Kanan := Kanan - 1;
  end;
end;

var
  Teks, Bersih: string;

begin
  repeat
    Write('Ketik kata/kalimat (kosong = selesai): ');
    ReadLn(Teks);
    if Teks <> '' then
    begin
      Bersih := Bersihkan(Teks);
      if Palindrom(Bersih) then
        WriteLn('  "', Teks, '" adalah palindrom.')
      else
        WriteLn('  "', Teks, '" bukan palindrom.');
    end;
  until Teks = '';
end.
