{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit UCycB;
{ See UCYCA.PAS. }
interface
procedure B(N: Integer);
implementation
uses UCycC;
procedure B(N: Integer);
begin
  Write('b', N, ' ');
  if N > 0 then
    C(N - 1);
end;
end.
