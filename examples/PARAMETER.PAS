{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Parameter;
var I: Integer;
begin
  WriteLn('Jumlah argumen: ', ParamCount);
  for I := 1 to ParamCount do
    WriteLn(I, ': ', ParamStr(I));
end.
