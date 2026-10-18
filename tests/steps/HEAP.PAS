program Heap;
var
  p: Pointer;
  i: LongInt;
begin
  for i := 1 to 100 do
    GetMem(p, 100);
  WriteLn('tidak sampai');
end.
