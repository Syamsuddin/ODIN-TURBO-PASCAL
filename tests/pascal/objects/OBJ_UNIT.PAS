{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjUnit;
{ Objects declared in a unit; methods called on instances and pointers. }
uses Shapes;
var
  C: TCounter;
  D: TDouble;
  P: PCounter;
  I: Integer;
begin
  C.Init(2);
  D.Init(3);
  P := @D;
  for I := 1 to 4 do
  begin
    C.Tick;
    P^.Tick;
  end;
  WriteLn('counter ', C.Value, ' double ', D.Value, ' via pointer ', P^.Value);
end.
