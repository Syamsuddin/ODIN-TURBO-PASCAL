{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 5.3 - Operator relasional (perbandingan)
  =  sama dengan          <>  tidak sama dengan
  <  kurang dari          <=  kurang dari atau sama dengan
  >  lebih dari           >=  lebih dari atau sama dengan
  Hasil perbandingan selalu Boolean: TRUE atau FALSE. }

program bab05_03_operator_relasional;

var
  A, B: Integer;

begin
  A := 10;
  B := 7;
  WriteLn('A = ', A, ', B = ', B);
  WriteLn('A =  B : ', A = B);       { di Pascal, = berarti membandingkan }
  WriteLn('A <> B : ', A <> B);
  WriteLn('A <  B : ', A < B);
  WriteLn('A >  B : ', A > B);
  WriteLn('A <= 10: ', A <= 10);
  WriteLn('B >= 10: ', B >= 10);
  WriteLn;

  { Karakter dibandingkan menurut kode ASCII-nya }
  WriteLn('''a'' < ''b''  : ', 'a' < 'b');
  WriteLn('''Z'' < ''a''  : ', 'Z' < 'a');     { huruf besar lebih kecil }

  { String dibandingkan huruf demi huruf, seperti urutan kamus }
  WriteLn('''Ani'' < ''Budi'' : ', 'Ani' < 'Budi');
  WriteLn('''Pascal'' = ''pascal'' : ', 'Pascal' = 'pascal');
end.
