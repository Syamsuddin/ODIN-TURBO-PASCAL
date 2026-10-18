program Antrean;
var
  n, i, waktu, tunggu: longint;
  datang, layan: array[1..1000] of longint;
begin
  ReadLn(n);
  for i := 1 to n do
    ReadLn(datang[i], layan[i]);
  waktu := 0;
  tunggu := 0;
  for i := 1 to n do
  begin
    if waktu < datang[i] then
      waktu := datang[i];
    tunggu := tunggu + waktu - datang[i];
    waktu := waktu + layan[i];
  end;
  WriteLn(tunggu);
end.
