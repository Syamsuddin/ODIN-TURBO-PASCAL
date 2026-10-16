{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 8.6 - Permainan tebak angka
  Komputer memilih angka acak 1..100, pemain menebak sampai benar.
  Randomize mengacak benih bilangan acak; Random(100) memberi 0..99. }

program bab08_06_tebak_angka;

var
  Rahasia, Tebakan, Percobaan: Integer;

begin
  Randomize;                             { panggil sekali di awal program }
  Rahasia := Random(100) + 1;            { 0..99 digeser menjadi 1..100 }
  Percobaan := 0;

  WriteLn('Saya memilih angka 1 sampai 100. Tebaklah!');
  repeat
    Write('Tebakan Anda: ');
    ReadLn(Tebakan);
    Percobaan := Percobaan + 1;
    if Tebakan < Rahasia then
      WriteLn('  Terlalu kecil.')
    else if Tebakan > Rahasia then
      WriteLn('  Terlalu besar.');
  until Tebakan = Rahasia;

  WriteLn('Benar! Angkanya ', Rahasia, '.');
  WriteLn('Anda menebak dalam ', Percobaan, ' kali percobaan.');
  if Percobaan <= 7 then
    WriteLn('Hebat, strategi yang jitu!');  { pencarian biner: maks 7 kali }
end.
