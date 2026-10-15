{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjsAbstract;
{ Unit Objects: Abstract ends the program with runtime error 211. }
uses Objects;
type
  TShape = object(TObject)
    function Area: Real; virtual;
  end;
function TShape.Area: Real;
begin
  Abstract;
end;
var
  S: TShape;
begin
  S.Init;
  WriteLn('calling abstract');
  WriteLn(S.Area:0:2);
end.
