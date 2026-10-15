{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 2.3 - Blok begin..end
  begin..end mengelompokkan beberapa pernyataan menjadi satu blok.
  Titik koma memisahkan pernyataan; sebelum end boleh tanpa titik koma. }

program bab02_03_blok_begin_end;

var
  Nilai: Integer;

begin
  Nilai := 80;

  { Tanpa begin..end, if hanya menguasai SATU pernyataan sesudahnya }
  if Nilai >= 75 then
    WriteLn('Satu pernyataan: Lulus');

  { Dengan begin..end, semua pernyataan di dalam blok ikut if }
  if Nilai >= 75 then
  begin
    WriteLn('Blok dimulai');
    WriteLn('Nilai Anda ', Nilai);
    WriteLn('Blok selesai');
  end;

  { Blok boleh bersarang. Rapikan dengan indentasi agar mudah dibaca. }
  begin
    WriteLn('Blok luar');
    begin
      WriteLn('  Blok dalam')
    end                          { tanpa titik koma sebelum end: tetap sah }
  end;
end.
