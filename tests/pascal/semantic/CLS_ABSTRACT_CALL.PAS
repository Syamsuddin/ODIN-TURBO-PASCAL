{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsAbstractCall;
{ inherited call of an abstract method. }
type
  TA = class
    procedure Run; virtual; abstract;
  end;
  TB = class(TA)
    procedure Run; override;
  end;
procedure TB.Run;
begin
  inherited Run;
end;
begin
end.
