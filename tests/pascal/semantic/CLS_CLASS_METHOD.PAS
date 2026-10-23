{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsClassMethod;
{ A class method has no instance fields. }
type
  TA = class
    X: Integer;
    class function Get: Integer;
  end;
class function TA.Get: Integer;
begin
  Get := X;
end;
begin
end.
