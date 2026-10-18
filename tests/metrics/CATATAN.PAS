program Catatan;
label 9;
var
  x, y, tak: integer;
  total: longint;
  data: array[1..365] of integer;

function TanpaHasil(a: integer): integer;
begin
  WriteLn(a);
end;

function Fakt(n: longint): longint;
begin
  if n <= 1 then
    Fakt := 1
  else
    Fakt := n * Fakt(n - 1);
end;

procedure Tambah(n: integer);
var
  lokal, sisa: integer;
begin
  lokal := n * 365;
  total := total + lokal;
end;

procedure Dalam;
var
  a, b, c, d, e: integer;
begin
  for a := 1 to 3 do
    for b := 1 to 3 do
      if a <> b then
        while c < 3 do
        begin
          c := c + 1;
          if (d > 0) and (e < 7) then
            WriteLn(a, b:4);
        end;
end;

begin
  x := TanpaHasil(3);
  y := 365 + 7;
  data[1] := Fakt(5);
  Tambah(x);
  Dalam;
  goto 9;
  WriteLn('tak terjangkau');
9:
  WriteLn(x, y, total);
end.
