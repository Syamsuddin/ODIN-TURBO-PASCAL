{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngFor;
{ for loops over enumerations, Char, Boolean and subranges with to and
  downto, loops ending at the limits of their type, bounds evaluated once. }
type
  TColor = (Red, Orange, Yellow, Green, Blue, Indigo, Violet);
  TWarm = Red..Yellow;
  TDigit = 0..9;
  TUpper = 'A'..'Z';
  TNeg = -3..-1;

var
  C: TColor;
  W: TWarm;
  Ch: Char;
  U: TUpper;
  B: Boolean;
  D: TDigit;
  Ng: TNeg;
  By: Byte;
  Si: ShortInt;
  Wd: Word;
  In16: Integer;
  L: LongInt;
  I, N, Count, Calls: Integer;

function Bound(V: Integer): Integer;
begin
  Inc(Calls);
  Bound := V;
end;

begin
  for C := Red to Violet do Write(Ord(C));
  Write(' ');
  for C := Violet downto Red do Write(Ord(C));
  Write(' ');
  for C := Succ(Red) to Pred(Violet) do Write(Ord(C));
  Write(' ');
  for C := Violet to Red do Write('never');
  for W := Low(TWarm) to High(TWarm) do Write(Ord(W));
  Write(' ');
  for W := High(TWarm) downto Low(TWarm) do Write(Ord(W));
  WriteLn;
  for Ch := 'a' to 'f' do Write(Ch);
  Write(' ');
  for Ch := 'Z' downto 'U' do Write(Ch);
  Write(' ');
  for U := 'X' to High(TUpper) do Write(U);
  Write(' ');
  for Ch := #253 to #255 do Write(Ord(Ch), ',');
  Write(' ');
  for Ch := #2 downto #0 do Write(Ord(Ch), ',');
  WriteLn;
  for B := False to True do Write(B, ' ');
  for B := True downto False do Write(B, ' ');
  for B := True to True do Write('once ');
  for B := True to False do Write('never');
  WriteLn;
  for D := 9 downto 0 do Write(D);
  Write(' ');
  for D := Low(TDigit) to High(TDigit) do Write(D);
  Write(' ');
  for Ng := Low(TNeg) to High(TNeg) do Write(Ng, ' ');
  WriteLn;
  Count := 0;
  for By := 250 to 255 do Inc(Count);
  Write('byte up ', Count, ' ');
  Count := 0;
  for By := 5 downto 0 do Inc(Count);
  Write('byte down ', Count, ' ');
  Count := 0;
  for Si := -128 to -125 do Inc(Count);
  Write('short ', Count, ' ');
  Count := 0;
  for Si := 127 downto 124 do Inc(Count);
  Write(Count, ' ');
  Count := 0;
  for Wd := 65533 to 65535 do Inc(Count);
  Write('word ', Count, ' ');
  Count := 0;
  for In16 := 32765 to 32767 do Inc(Count);
  Write('int ', Count, ' ');
  Count := 0;
  for In16 := -32766 downto -32768 do Inc(Count);
  Write(Count, ' ');
  Count := 0;
  for L := 2147483645 to 2147483647 do Inc(Count);
  Write('long ', Count, ' ');
  Count := 0;
  for L := -2147483646 downto -2147483647 - 1 do Inc(Count);
  WriteLn(Count);
  N := 3;
  Count := 0;
  for I := 1 to N do
  begin
    N := 10;
    Inc(Count);
  end;
  WriteLn('bounds once ', Count, ' N=', N);
  Calls := 0;
  Count := 0;
  for I := Bound(2) to Bound(6) do Inc(Count);
  WriteLn('bound calls ', Calls, ' count ', Count);
  Calls := 0;
  Count := 0;
  for I := Bound(6) downto Bound(2) do Inc(Count);
  WriteLn('bound calls ', Calls, ' count ', Count);
  Count := 0;
  for I := 5 to 4 do Inc(Count);
  for I := 4 downto 5 do Inc(Count);
  WriteLn('empty ', Count);
  Count := 0;
  for I := 0 to 0 do Inc(Count);
  for I := -1 downto -1 do Inc(Count);
  WriteLn('single ', Count);
  Count := 0;
  for C := Red to Violet do
    for Ch := 'a' to 'c' do
      for B := False to True do Inc(Count);
  WriteLn('nested ', Count);
end.
