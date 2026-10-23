{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsStrict;
{ strict private is hidden even from the same program. }
type
  TA = class
  strict private
    FSecret: Integer;
  end;
var
  A: TA;
begin
  A := TA.Create;
  WriteLn(A.FSecret);
end.
