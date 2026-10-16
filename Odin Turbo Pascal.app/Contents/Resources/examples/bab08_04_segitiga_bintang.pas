{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 8.4 - Segitiga bintang
  Pola gambar dibuat dengan perulangan bersarang: perulangan luar
  memilih baris, perulangan dalam menulis spasi dan bintang. Kuncinya
  adalah mencari hubungan nomor baris dengan jumlah bintang. }

program bab08_04_segitiga_bintang;

var
  Tinggi, Baris, I: Integer;

begin
  Write('Tinggi segitiga (1-20): ');
  ReadLn(Tinggi);
  if (Tinggi < 1) or (Tinggi > 20) then
    Tinggi := 5;                         { nilai bawaan bila tidak sah }

  WriteLn('Segitiga siku-siku:');        { baris ke-B berisi B bintang }
  for Baris := 1 to Tinggi do
  begin
    for I := 1 to Baris do Write('*');
    WriteLn;
  end;

  WriteLn('Segitiga terbalik:');         { bintang berkurang tiap baris }
  for Baris := Tinggi downto 1 do
  begin
    for I := 1 to Baris do Write('*');
    WriteLn;
  end;

  WriteLn('Piramida:');                  { spasi T-B, bintang 2B-1 }
  for Baris := 1 to Tinggi do
  begin
    for I := 1 to Tinggi - Baris do Write(' ');
    for I := 1 to 2 * Baris - 1 do Write('*');
    WriteLn;
  end;
end.
