{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Numbers;
var
  a, b, c: Integer;
  l, m: LongInt;
  by: Byte;
  w: Word;
  si: ShortInt;
  i64: Int64;
  r, s: Real;
  sg: Single;
begin
  a := 30000; b := 30000;
  WriteLn('i16+i16=', a + b);
  c := a + b; WriteLn('wrap=', c);
  l := 2000000000; m := 2000000000;
  WriteLn('i32+i32=', l + m);
  by := 200; WriteLn('byte+100=', by + 100);
  WriteLn('div ', -7 div 2, ' mod ', -7 mod 2, ' ', 7 mod -2, ' ', 17 div 5, ' ', 17 mod 5);
  WriteLn('shl ', 1 shl 10, ' ', a shl 2, ' ', l shl 1, ' shr ', 1024 shr 3, ' ', -1 shr 28);
  w := 65535; WriteLn('w+1=', w + 1);
  si := -128; WriteLn('-si=', -si);
  i64 := 9223372036854775807; WriteLn('i64=', i64);
  WriteLn('hi/lo ', Hi($1234), ' ', Lo($1234), ' odd ', Odd(7), ' ', Odd(8));
  WriteLn('abs ', Abs(-5), ' ', Abs(5), ' sqr ', Sqr(12), ' ', Sqr(-3));
  WriteLn('and/or/xor ', 12 and 10, ' ', 12 or 10, ' ', 12 xor 10, ' not ', not 0);
  r := 10; s := 4;
  WriteLn('real ', r / s:0:3, ' ', r * s:0:1, ' ', r - s:6:2, ' ', -r:0:0);
  WriteLn('round ', Round(2.5), ' ', Round(3.5), ' ', Round(-2.5), ' ', Round(2.4), ' trunc ', Trunc(-2.7), ' ', Trunc(2.7));
  WriteLn('int/frac ', Int(3.75):0:2, ' ', Frac(3.75):0:2, ' sqrt ', Sqrt(16):0:3, ' ', Sqrt(2):0:6);
  WriteLn('mix ', 1 + 2.5:0:1, ' ', 7 / 2:0:2, ' ', 1/3:0:5, ' ', 2/3:0:5);
  WriteLn('fixed ', 3.14159:8:2, '|', 123.456:0:1, '|', 0.5:0:0, '|', 1.5:0:0, '|', 0.005:0:2, '|', 99.995:0:2);
  sg := 1.25; WriteLn('single ', sg:0:2, ' ', sg * 2:0:3);
  WriteLn('cmp ', 3 > 2, ' ', 2.5 < 2, ' ', a = b, ' ', l <> m);
  WriteLn('maxint ', MaxInt, ' ', MaxLongInt, ' ', High(Integer), ' ', Low(Integer), ' ', High(Byte));
  WriteLn('ord ', Ord('A'), ' chr ', Chr(66), ' succ ', Succ('a'), ' pred ', Pred(10));
  WriteLn(-5:4, '|', 42:2, '|', 7:-3, '|', 'x':3, '|', 'abc':2, '|');
end.
