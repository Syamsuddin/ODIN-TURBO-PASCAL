program Lain;
var
  n, i, s: longint;
begin
  ReadLn(n);
  s := 0;
  i := 1;
  while i <= n do
  begin
    s := s + i * i;
    i := i + 1;
  end;
  WriteLn(s);
end.
