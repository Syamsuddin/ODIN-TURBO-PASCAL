{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsAbstractError;
{ Calling an abstract method that no descendant implemented: runtime
  error 211. }
type
  TShape = class
    function Area: Real; virtual; abstract;
  end;
  TSquare = class(TShape)
    function Area: Real; override;
  end;

function TSquare.Area: Real;
begin
  Area := 4;
end;

var
  S: TShape;
begin
  S := TSquare.Create;
  WriteLn(S.Area:0:1);
  S.Free;
  S := TShape.Create;
  WriteLn(S.Area:0:1);
  WriteLn('not reached');
end.
