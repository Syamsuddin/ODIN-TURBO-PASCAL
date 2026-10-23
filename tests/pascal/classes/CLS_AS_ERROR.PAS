{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsAsError;
{ An "as" to a class the instance does not belong to: runtime error 219.
  "as" on nil gives nil. }
type
  TA = class end;
  TB = class(TA) end;
  TC = class(TA) end;
var
  A: TA;
  N: TObject;
begin
  A := TB.Create;
  WriteLn((A as TB).ClassName, ' ', (A as TA).ClassName);
  N := nil;
  WriteLn(N as TC = nil);
  WriteLn((A as TC).ClassName);
  WriteLn('not reached');
end.
