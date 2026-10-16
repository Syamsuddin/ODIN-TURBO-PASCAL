{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 7.4 - Perulangan repeat..until
  repeat menjalankan badannya DULU, baru memeriksa syarat di until.
  Perulangan berhenti saat syarat bernilai True, jadi badannya selalu
  dijalankan paling sedikit sekali. Cocok untuk memvalidasi masukan. }

program bab07_04_repeat_until;

var
  Nilai: Integer;
  Jawab: Char;
  Ulang: Integer;

begin
  { Terus bertanya sampai nilai berada di 0..100 }
  repeat
    Write('Masukkan nilai (0-100): ');
    ReadLn(Nilai);
    if (Nilai < 0) or (Nilai > 100) then
      WriteLn('  Nilai tidak sah, coba lagi.');
  until (Nilai >= 0) and (Nilai <= 100);
  WriteLn('Nilai diterima: ', Nilai);
  WriteLn;

  { repeat..until tidak memerlukan begin..end untuk banyak perintah }
  Ulang := 0;
  repeat
    Ulang := Ulang + 1;
    WriteLn('Putaran ke-', Ulang);
    Write('Lanjut (Y/T)? ');
    ReadLn(Jawab);
  until (Jawab = 'T') or (Jawab = 't');
  WriteLn('Selesai setelah ', Ulang, ' putaran.');
end.
