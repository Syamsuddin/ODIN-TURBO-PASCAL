{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit SysUtils: galat konversi menjadi runtime error 106 (tidak ada exception). }
program SYSUTILS_ERROR;

uses SysUtils;

begin
  WriteLn('StrToInt(12) = ', StrToInt('12'));
  WriteLn(StrToInt('dua belas'));
  WriteLn('tidak sampai sini');
end.
