{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit UCycD;
{ See UCYCA.PAS. }
interface
uses UCycA;
procedure D(N: Integer);
implementation
procedure D(N: Integer);
begin
  Write('d', N, ' ');
  if N > 0 then
    A(N - 1);
end;
end.
