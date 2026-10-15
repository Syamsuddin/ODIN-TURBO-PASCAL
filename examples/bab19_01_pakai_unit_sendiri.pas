{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 19.1 - Memakai unit buatan sendiri
  "uses matematika;" membuat semua yang ada di bagian interface unit
  matematika.pas bisa dipakai di sini. Kompiler mencari file unit di
  folder yang sama dengan program ini. }

program bab19_01_pakai_unit_sendiri;

uses
  matematika;                            { unit dari file matematika.pas }

var
  I: Integer;

begin
  WriteLn('Unit matematika versi ', VersiUnit);   { konstanta dari unit }
  WriteLn('Kuadrat(25)     = ', Kuadrat(25));
  WriteLn('Pangkat(2, 10)  = ', Pangkat(2, 10));
  WriteLn('Faktorial(10)   = ', Faktorial(10));
  WriteLn('FPB(48, 18)     = ', FPB(48, 18));
  WriteLn('KPK(4, 6)       = ', KPK(4, 6));

  Write('Bilangan prima di bawah 50: ');
  for I := 1 to 50 do
    if Prima(I) then
      Write(I, ' ');
  WriteLn;

  { Nama unit boleh ditulis di depan, berguna bila ada nama yang sama }
  WriteLn('matematika.Kuadrat(12) = ', matematika.Kuadrat(12));
end.
