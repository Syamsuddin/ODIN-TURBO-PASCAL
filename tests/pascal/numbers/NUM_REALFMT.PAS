{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Real formatting: exact 17-digit expansion, 15-digit pre-rounding for fixed format, exponent widths. }
program NumRealFmt;
var x: Real;
begin
  x := 1/3; writeln(x:0:17); writeln(x:0:20); writeln(x:0:15); writeln(x:0:16);
  x := 2.675; writeln(x:0:2); writeln(x:0:15); writeln(x:0:16); writeln(x:0:17);
  x := 0.1; writeln(x:0:20);
  x := 123456789.123456789; writeln(x:0:6); writeln(x:0:9);
  x := 1e20; writeln(x:0:2);
  x := 12345678901234567890.0; writeln(x:0:0);
  x := 0.000123456789012345678; writeln(x:0:20);
  x := 1.0000000000000002; writeln(x:0:16);
  x := 0.5; writeln(x:0:0); x := 1.5; writeln(x:0:0); x := 2.5; writeln(x:0:0); x := 0.125; writeln(x:0:2); x := 0.375; writeln(x:0:2);
  x := 1/3; writeln(x); writeln(x:25); writeln(x:30); writeln(x:8); writeln(x:1);
  x := 5e-324; writeln(x); x := 1.7976931348623157e308; writeln(x);
  x := 100; writeln(x); x := -0.0; writeln(x:0:2); writeln(x);
end.
