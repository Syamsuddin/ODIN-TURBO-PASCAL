{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsOverride;
{ override without an inherited virtual method. }
type
  TA = class
    procedure Run; override;
  end;
procedure TA.Run;
begin
end;
begin
end.
