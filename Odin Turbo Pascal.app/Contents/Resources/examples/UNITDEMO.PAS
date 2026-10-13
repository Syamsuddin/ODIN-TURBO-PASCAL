{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program UnitDemo;
uses UMath;
var I: Integer;
begin
  for I := 1 to 5 do
    WriteLn(I, ' kuadrat = ', Kuadrat(I));
end.
