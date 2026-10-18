{ Nama dan tata letak berbeda, bentuknya sama dengan ANTRE_A. }
program KantinSekolah;
var m, k, jam, total: longint;
    tiba, lama: array[1..1000] of longint;
begin
  ReadLn(m);
  for k := 1 to m do ReadLn(tiba[k], lama[k]);
  jam := 0; total := 0;
  for k := 1 to m do begin
    if jam < tiba[k] then jam := tiba[k];   { menunggu kedatangan }
    total := total + jam - tiba[k];
    jam := jam + lama[k]
  end;
  WriteLn(total)
end.
