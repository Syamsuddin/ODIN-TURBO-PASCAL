{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program RteIntOvf;
{ Overflow checks ($Q+). LongInt arithmetic is done in 64 bits, so
  MaxLongInt + 1 does not overflow; without range checks the store wraps.
  Int64 arithmetic overflows: runtime error 215. }
{$Q+}
var
  I: LongInt;
  J: Int64;
begin
  WriteLn('start');
  I := 2147483647;
  I := I + 1;
  WriteLn(I);
  J := 9223372036854775807;
  J := J + 1;
  WriteLn(J);
  WriteLn('not reached');
end.
