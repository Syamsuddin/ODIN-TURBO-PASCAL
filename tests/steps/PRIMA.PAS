program Prima;
const
  N = 2000;
var
  i, j, jumlah, tak: longint;
  prima: boolean;

begin
  jumlah := 0;
  for i := 2 to N do
  begin
    prima := true;
    for j := 2 to i - 1 do
      if i mod j = 0 then
        prima := false;
    if prima then
      jumlah := jumlah + 1;
  end;
  WriteLn(jumlah);
end.
