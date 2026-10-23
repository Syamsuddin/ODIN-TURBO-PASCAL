{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsReadOnly;
{ Assignment to a property without write. }
type
  TA = class
  private
    FX: Integer;
  public
    property X: Integer read FX;
  end;
var
  A: TA;
begin
  A := TA.Create;
  A.X := 1;
end.
