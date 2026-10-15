{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit UCycA;
{ Unit cycle through implementation uses (LNG_UCYCLE): UCycA's interface
  uses UCycB, whose implementation uses UCycC, whose implementation uses
  UCycD, whose interface uses UCycA. }
interface
uses UCycB;
procedure A(N: Integer);
implementation
procedure A(N: Integer);
begin
  Write('a', N, ' ');
  if N > 0 then
    B(N - 1);
end;
end.
