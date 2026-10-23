{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsForward;
{ A forward class declaration must be completed in its type section. }
type
  TA = class;
  TB = class
    Other: TA;
  end;
begin
end.
