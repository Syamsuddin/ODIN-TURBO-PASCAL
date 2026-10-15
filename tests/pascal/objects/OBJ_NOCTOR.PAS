{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjNoCtor;
{ A virtual method called on an object whose constructor never ran:
  runtime error 210 under range checks. }
{$R+}
type
  TThing = object
    N: Integer;
    constructor Init;
    procedure Speak; virtual;
  end;

constructor TThing.Init;
begin
  N := 1;
end;

procedure TThing.Speak;
begin
  WriteLn('speak ', N);
end;

var
  A, B: TThing;
begin
  A.Init;
  A.Speak;
  B.Speak;
  WriteLn('not reached');
end.
