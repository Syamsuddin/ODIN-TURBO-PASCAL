program Salin;
type
  TArr = array[1..1000] of LongInt;
var
  a, b: TArr;
  c: array[1..2000] of LongInt;

procedure Kosong;
var
  x: LongInt;
  s: String;
begin
  WriteLn(x, ' [', s, ']');
end;

function Jumlah(v: TArr): LongInt;
begin
  Jumlah := v[1] + v[1000];
end;

begin
  FillChar(c, SizeOf(c), 0);
  a[1] := 7;
  a[1000] := 9;
  b := a;
  Move(a, b, SizeOf(a));
  WriteLn(Jumlah(a) + Jumlah(b));
  Kosong;
end.
