{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 5.5 - Prioritas operator
  Urutan pengerjaan, dari yang paling dulu:
    1. not  dan  minus di depan bilangan
    2. *  /  div  mod  and
    3. +  -  or  xor
    4. =  <>  <  >  <=  >=  in
  Operator setingkat dikerjakan dari kiri ke kanan. Kurung didahulukan. }

program bab05_05_prioritas_operator;

var
  X: Integer;

begin
  WriteLn('2 + 3 * 4       = ', 2 + 3 * 4);       { kali dulu: 14 }
  WriteLn('(2 + 3) * 4     = ', (2 + 3) * 4);     { kurung dulu: 20 }
  WriteLn('20 - 6 - 4      = ', 20 - 6 - 4);      { kiri ke kanan: 10 }
  WriteLn('20 div 4 * 2    = ', 20 div 4 * 2);    { (20 div 4) * 2 = 10 }
  WriteLn('20 div (4 * 2)  = ', 20 div (4 * 2));  { 20 div 8 = 2 }
  WriteLn('-2 * 3 + 10     = ', -2 * 3 + 10);     { minus depan dulu: 4 }
  WriteLn('10 / 4 * 2      = ', 10 / 4 * 2:0:2);  { (10 / 4) * 2 = 5 }
  WriteLn;

  X := 5;
  { and lebih tinggi dari >, jadi perbandingan WAJIB diberi kurung.
    Tanpa kurung, X > 0 and X < 10 dibaca X > (0 and X) < 10 dan
    kompiler menolaknya. }
  WriteLn('(X > 0) and (X < 10)  = ', (X > 0) and (X < 10));
  WriteLn('not (X = 5)           = ', not (X = 5));
end.
