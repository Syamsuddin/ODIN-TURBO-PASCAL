{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngTConst;
{ Typed constants: multi-dimensional arrays, arrays of records, records
  with arrays and sets, pointer constants, Char arrays from strings,
  writable and static behaviour. }
type
  TColor = (Red, Green, Blue);
  TPoint = record
    X, Y: Integer;
  end;
  TItem = record
    Name: String[6];
    Qty: Integer;
    Price: Real;
  end;
  TShape = record
    Id: Byte;
    Pts: array[1..3] of TPoint;
    Colors: set of TColor;
    Flags: set of Char;
    Title: String[8];
  end;
  PInteger = ^Integer;

const
  Matrix: array[1..2, 1..3] of Integer = ((1, 2, 3), (4, 5, 6));
  Cube: array[0..1, 0..1, 0..1] of Byte = (((1, 2), (3, 4)), ((5, 6), (7, 8)));
  Items: array[1..3] of TItem = (
    (Name: 'apel'; Qty: 3; Price: 1.5),
    (Name: 'jeruk'; Qty: 0; Price: 2.25),
    (Name: 'mangga'; Qty: 7; Price: 0.75));
  Shape: TShape = (Id: 9; Pts: ((X: 0; Y: 0), (X: 4; Y: 0), (X: 0; Y: 3));
    Colors: [Red, Blue]; Flags: ['a'..'c', 'z']; Title: 'segitiga');
  Letters: array[1..5] of Char = 'HELLO';
  Grid: array[1..2] of array[1..4] of Char = ('abcd', 'efgh');
  Target: Integer = 42;
  PTarget: PInteger = @Target;
  PNil: Pointer = nil;
  PCube: Pointer = @Cube;
  Names: array[TColor] of String[5] = ('merah', 'hijau', 'biru');
  Primes: set of Byte = [2, 3, 5, 7, 11, 13, 200, 255];
  Reals: array[1..3] of Real = (1.5, -2.25, 1E3);
  Exprs: array[1..5] of Integer = (10 div 3, -5 mod 3, Ord('A') + 1, SizeOf(LongInt), 1 shl 4);
  Ch: Char = 'Q';
  Ok: Boolean = True;
  Greeting: String[10] = 'halo';
  Big: LongInt = -123456789;
  Origin: TPoint = (X: -1; Y: -2);
  Bools: array[Boolean] of String[3] = ('no', 'yes');
  Ctrl: array[1..3] of Char = (#9, 'x', #255);

var
  I, J, K: Integer;
  Total: LongInt;
  C: TColor;

procedure Tick;
const
  Calls: Integer = 0;
  History: String[10] = '';
begin
  Inc(Calls);
  History := History + Chr(Ord('0') + Calls);
  WriteLn('tick ', Calls, ' ', History);
end;

procedure AddTo(var V: Integer; N: Integer);
begin
  V := V + N;
end;

begin
  for I := 1 to 2 do
  begin
    for J := 1 to 3 do Write(Matrix[I, J], ' ');
    Write('| ');
  end;
  WriteLn;
  Total := 0;
  for I := 0 to 1 do
    for J := 0 to 1 do
      for K := 0 to 1 do Total := Total * 10 + Cube[I, J, K];
  WriteLn('cube ', Total, ' ', Cube[1, 0, 1]);
  for I := 1 to 3 do
    with Items[I] do WriteLn(Name, ' ', Qty, ' ', Price:0:2, ' ', Qty * Price:0:2);
  with Shape do
  begin
    Write('shape ', Id, ' ', Title, ' ');
    for I := 1 to 3 do Write('(', Pts[I].X, ',', Pts[I].Y, ')');
    WriteLn(' ', Red in Colors, ' ', Green in Colors, ' ', Blue in Colors,
      ' ', 'b' in Flags, ' ', 'd' in Flags, ' ', 'z' in Flags);
  end;
  for I := 1 to 5 do Write(Letters[I]);
  Write(' ');
  for I := 5 downto 1 do Write(Letters[I]);
  WriteLn(' ', Grid[2, 3], Grid[1, 4], ' ', Ord(Ctrl[1]), ' ', Ctrl[2], ' ', Ord(Ctrl[3]));
  WriteLn('ptr ', PTarget^, ' ', PNil = nil, ' ', PTarget = @Target, ' ', PCube = @Cube);
  PTarget^ := 7;
  WriteLn('through ptr ', Target);
  for C := Red to Blue do Write(Names[C], ' ');
  WriteLn;
  for I := 0 to 255 do
    if I in Primes then Write(I, ' ');
  WriteLn;
  for I := 1 to 3 do Write(Reals[I]:0:2, ' ');
  WriteLn;
  for I := 1 to 5 do Write(Exprs[I], ' ');
  WriteLn;
  WriteLn(Ch, ' ', Ok, ' ', Greeting, ' ', Length(Greeting), ' ', Big, ' ', Origin.X, ' ', Origin.Y,
    ' ', Bools[False], ' ', Bools[True]);
  Matrix[1, 1] := 100;
  Items[2].Qty := 5;
  Shape.Colors := Shape.Colors + [Green];
  Greeting := Greeting + '!';
  Ch := Succ(Ch);
  Letters[1] := 'J';
  AddTo(Target, 3);
  AddTo(Matrix[2, 3], 10);
  WriteLn('modified ', Matrix[1, 1], ' ', Items[2].Qty, ' ', Green in Shape.Colors, ' ', Greeting,
    ' ', Ch, ' ', Letters[1], Letters[2], ' ', Target, ' ', Matrix[2, 3]);
  Tick;
  Tick;
  Tick;
end.
