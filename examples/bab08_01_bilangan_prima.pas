{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 8.1 - Bilangan prima
  Bilangan prima hanya habis dibagi 1 dan dirinya sendiri (2, 3, 5,
  7, 11, ...). Cukup periksa pembagi sampai akar bilangan itu: bila
  N = A x B, salah satu dari A atau B pasti tidak lebih dari akar N. }

program bab08_01_bilangan_prima;

var
  N, Calon, Pembagi, Banyak: Integer;
  Prima: Boolean;

begin
  Write('Periksa bilangan: ');
  ReadLn(N);
  Prima := N >= 2;                       { 0 dan 1 bukan prima }
  Pembagi := 2;
  while Prima and (Pembagi * Pembagi <= N) do
  begin
    if N mod Pembagi = 0 then
      Prima := False;                    { ketemu pembagi: bukan prima }
    Pembagi := Pembagi + 1;
  end;
  if Prima then
    WriteLn(N, ' adalah bilangan prima.')
  else
    WriteLn(N, ' bukan bilangan prima.');
  WriteLn;

  { Cara yang sama, diulang untuk setiap bilangan 2..100 }
  WriteLn('Bilangan prima sampai 100:');
  Banyak := 0;
  for Calon := 2 to 100 do
  begin
    Prima := True;
    Pembagi := 2;
    while Prima and (Pembagi * Pembagi <= Calon) do
    begin
      if Calon mod Pembagi = 0 then
        Prima := False;
      Pembagi := Pembagi + 1;
    end;
    if Prima then
    begin
      Write(Calon:4);
      Banyak := Banyak + 1;
      if Banyak mod 10 = 0 then WriteLn;   { 10 bilangan per baris }
    end;
  end;
  WriteLn;
  WriteLn('Ada ', Banyak, ' bilangan prima.');
end.
