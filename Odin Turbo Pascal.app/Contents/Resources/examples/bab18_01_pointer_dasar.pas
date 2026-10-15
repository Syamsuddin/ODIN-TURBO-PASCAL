{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 18.1 - Pointer
  Pointer menyimpan ALAMAT sebuah data di memori, bukan datanya.
    ^Integer   tipe "pointer ke Integer"
    @X         alamat variabel X
    P^         data yang ditunjuk P
    nil        pointer yang tidak menunjuk ke mana pun }

program bab18_01_pointer_dasar;

type
  PInteger = ^Integer;                   { nama tipe pointer, diawali P }

var
  X, Y: Integer;
  P, Q: PInteger;

begin
  X := 10;
  Y := 20;
  P := @X;                               { P menunjuk ke X }
  WriteLn('X = ', X, ', P^ = ', P^);     { P^ membaca isi X }

  P^ := 99;                              { mengubah X lewat pointer }
  WriteLn('Setelah P^ := 99, X = ', X);

  Q := P;                                { Q menunjuk ke tempat yang sama }
  Q^ := Q^ + 1;
  WriteLn('Setelah Q^ := Q^ + 1, X = ', X, ', P^ = ', P^);

  P := @Y;                               { P pindah menunjuk ke Y }
  WriteLn('P sekarang menunjuk Y, P^ = ', P^);
  WriteLn('P dan Q menunjuk tempat yang sama? ', P = Q);

  P := nil;                              { tidak menunjuk ke mana pun }
  if P = nil then
    WriteLn('P bernilai nil. Jangan membaca P^ saat P = nil!');
end.
