{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 5.4 - Operator logika
  and : benar bila keduanya benar     not : membalik nilai
  or  : benar bila salah satu benar   xor : benar bila keduanya berbeda
  Perbandingan yang digabung harus diberi kurung. }

program bab05_04_operator_logika;

var
  P, Q: Boolean;
  Umur: Integer;
  PunyaTiket: Boolean;

begin
  { Tabel kebenaran: ekspresi yang sama, isi P dan Q yang berganti }
  WriteLn('    P      Q  P and Q  P or Q  P xor Q');
  P := True;  Q := True;
  WriteLn(P:5, Q:7, P and Q:9, P or Q:8, P xor Q:9);
  P := True;  Q := False;
  WriteLn(P:5, Q:7, P and Q:9, P or Q:8, P xor Q:9);
  P := False; Q := True;
  WriteLn(P:5, Q:7, P and Q:9, P or Q:8, P xor Q:9);
  P := False; Q := False;
  WriteLn(P:5, Q:7, P and Q:9, P or Q:8, P xor Q:9);
  WriteLn('not True = ', not True);
  WriteLn;

  Umur := 15;
  PunyaTiket := True;
  { Kurung wajib: tanpa kurung, and dikerjakan lebih dulu dari >= }
  WriteLn('Boleh masuk (umur >= 13 dan punya tiket)? ',
    (Umur >= 13) and PunyaTiket);
  WriteLn('Dapat diskon (umur < 12 atau umur > 60)?  ',
    (Umur < 12) or (Umur > 60));
end.
