program Campur;
type
  PNode = ^TNode;
  TNode = record
    Value: LongInt;
    Next: PNode;
  end;
var
  head, p: PNode;
  i, k: LongInt;
  buf: Pointer;

function Fakt(n: LongInt): LongInt;
begin
  if n <= 1 then
    Fakt := 1
  else
    Fakt := n * Fakt(n - 1);
end;

begin
  head := nil;
  for i := 1 to 10 do
  begin
    New(p);
    p^.Value := i;
    p^.Next := head;
    head := p;
  end;
  GetMem(buf, 1000);
  FreeMem(buf, 1000);
  k := 0;
  while head <> nil do
  begin
    p := head;
    head := head^.Next;
    k := k + p^.Value;
    Dispose(p);
  end;
  i := 0;
  repeat
    i := i + 1;
  until i = 5;
  WriteLn(k, ' ', Fakt(10), ' ', i);
  Randomize;
  WriteLn(Random(1000), ' ', Random(1000));
end.
