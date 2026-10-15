{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 5.1 - Operator aritmetika
  + tambah, - kurang, * kali, / bagi. Hasil / selalu Real, sedangkan
  +, -, * dari dua bilangan bulat tetap bilangan bulat. }

program bab05_01_operator_aritmetika;

var
  A, B: Integer;
  X, Y: Real;

begin
  A := 17;
  B := 5;
  WriteLn('A = ', A, ', B = ', B);
  WriteLn('A + B = ', A + B);
  WriteLn('A - B = ', A - B);
  WriteLn('A * B = ', A * B);
  WriteLn('A / B = ', A / B:0:2);      { hasil Real, perlu format }
  WriteLn('-A    = ', -A);              { minus di depan: lawan bilangan }
  WriteLn;

  X := 7.5;
  Y := 2.5;
  WriteLn('X = ', X:0:1, ', Y = ', Y:0:1);
  WriteLn('X + Y = ', X + Y:0:2);
  WriteLn('X * Y = ', X * Y:0:2);
  WriteLn('X / Y = ', X / Y:0:2);

  { Campuran Integer dan Real menghasilkan Real }
  WriteLn('A + X = ', A + X:0:2);

  { Fungsi bantu: Sqr (kuadrat), Sqrt (akar), Abs (nilai mutlak) }
  WriteLn('Sqr(B)   = ', Sqr(B));
  WriteLn('Sqrt(81) = ', Sqrt(81):0:1);
  WriteLn('Abs(-12) = ', Abs(-12));
end.
