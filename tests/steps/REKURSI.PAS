program Rekursi;

function Dalam(n: LongInt): LongInt;
begin
  if n = 0 then
    Dalam := 0
  else
    Dalam := 1 + Dalam(n - 1);
end;

begin
  WriteLn(Dalam(100));
  WriteLn(Dalam(1000000));
end.
