{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsNoOverload;
{ No overload takes a Real. }
type
  TA = class
    procedure Put(I: Integer); overload;
    procedure Put(const S: String); overload;
  end;
procedure TA.Put(I: Integer);
begin
end;
procedure TA.Put(const S: String);
begin
end;
var
  A: TA;
begin
  A := TA.Create;
  A.Put(1.5);
end.
