{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 8.5 - Bilangan sempurna
  Bilangan sempurna sama dengan jumlah semua pembaginya selain dirinya
  sendiri. Contoh: 6 = 1 + 2 + 3, dan 28 = 1 + 2 + 4 + 7 + 14. }

program bab08_05_bilangan_sempurna;

const
  Batas = 10000;

var
  N, Pembagi: Integer;
  Jumlah: LongInt;                       { bisa melebihi batas Integer }

begin
  WriteLn('Mencari bilangan sempurna dari 2 sampai ', Batas, '...');
  for N := 2 to Batas do
  begin
    Jumlah := 0;
    for Pembagi := 1 to N div 2 do       { pembagi tidak mungkin > N/2 }
      if N mod Pembagi = 0 then
        Jumlah := Jumlah + Pembagi;

    if Jumlah = N then
    begin
      Write(N, ' = 1');                  { tampilkan rinciannya }
      for Pembagi := 2 to N div 2 do
        if N mod Pembagi = 0 then
          Write(' + ', Pembagi);
      WriteLn;
    end;
  end;
  WriteLn('Selesai.');
end.
