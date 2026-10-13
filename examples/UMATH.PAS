{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit UMath;
interface
function Kuadrat(X: Integer): LongInt;
implementation
function Kuadrat(X: Integer): LongInt;
begin
  Kuadrat := LongInt(X) * X;
end;
end.
