{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Math: galat domain menjadi runtime error 207 (tidak ada exception). }
program MATH_DOMAIN;

uses Math;

begin
  WriteLn('ArcSin(1) = ', ArcSin(1):0:4);
  WriteLn('sebelum');
  WriteLn(ArcSin(1.5):0:4);
  WriteLn('tidak sampai sini');
end.
