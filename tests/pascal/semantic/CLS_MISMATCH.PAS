{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsMismatch;
{ Unrelated classes are not assignment compatible. }
type
  TA = class end;
  TB = class end;
var
  A: TA;
  B: TB;
begin
  B := TB.Create;
  A := B;
end.
