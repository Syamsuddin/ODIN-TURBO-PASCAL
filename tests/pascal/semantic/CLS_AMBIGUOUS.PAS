{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsAmbiguous;
{ Two overloads fit equally well. }
type
  TA = class
    procedure Put(A: Integer; B: Real); overload;
    procedure Put(A: Real; B: Integer); overload;
  end;
procedure TA.Put(A: Integer; B: Real);
begin
end;
procedure TA.Put(A: Real; B: Integer);
begin
end;
var
  A: TA;
begin
  A := TA.Create;
  A.Put(1, 2);
end.
