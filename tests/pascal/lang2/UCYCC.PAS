{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit UCycC;
{ See UCYCA.PAS. }
interface
procedure C(N: Integer);
implementation
uses UCycD;
procedure C(N: Integer);
begin
  Write('c', N, ' ');
  if N > 0 then
    D(N - 1);
end;
end.
