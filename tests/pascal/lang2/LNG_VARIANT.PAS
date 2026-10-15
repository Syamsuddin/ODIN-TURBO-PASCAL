{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngVariant;
{ Variant records: write one variant, read another (little-endian),
  tag fields, nested variants, variant records in arrays and on the heap. }
type
  TOverlay = record
    case Integer of
      0: (L: LongInt);
      1: (B: array[0..3] of Byte);
      2: (W: array[0..1] of Word);
      3: (Lo16, Hi16: Integer);
      4: (C: array[0..3] of Char);
      5: (S: ShortInt);
  end;
  TShape = record
    Name: String[7];
    case Kind: Byte of
      1: (Radius: Real);
      2: (Wd, Ht: Integer);
      3: (Bytes: array[1..8] of Byte);
      4: (Halves: array[0..1] of LongInt);
  end;
  TSingleBits = record
    case Boolean of
      False: (F: Single);
      True: (Bits: LongInt);
  end;
  TNested = record
    Head: Byte;
    case Outer: Byte of
      0: (A: Word;
          case Inner: Byte of
            0: (P: LongInt);
            1: (Q: array[0..3] of Byte));
      1: (Z: array[0..7] of Byte);
  end;
  PShape = ^TShape;

var
  O: TOverlay;
  Sh: TShape;
  SB: TSingleBits;
  N: TNested;
  Arr: array[1..2] of TOverlay;
  P: PShape;
  I: Integer;

procedure DumpO(const Tag: String; const X: TOverlay);
var K: Integer;
begin
  Write(Tag, ' L=', X.L, ' B=');
  for K := 0 to 3 do Write(X.B[K], ' ');
  WriteLn('W=', X.W[0], ' ', X.W[1], ' Lo=', X.Lo16, ' Hi=', X.Hi16, ' S=', X.S);
end;

procedure DumpBytes(const X: TShape);
var K: Integer;
begin
  for K := 1 to 8 do Write(X.Bytes[K], ' ');
  WriteLn('| ', X.Halves[0], ' ', X.Halves[1], ' | ', X.Wd, ' ', X.Ht);
end;

begin
  O.L := $12345678;
  DumpO('hex', O);
  O.L := -2;
  DumpO('neg', O);
  O.B[0] := Ord('A'); O.B[1] := Ord('B'); O.B[2] := Ord('C'); O.B[3] := Ord('D');
  DumpO('abcd', O);
  WriteLn('chars ', O.C[0], O.C[1], O.C[2], O.C[3]);
  O.W[0] := 65535; O.W[1] := 0;
  DumpO('word', O);
  O.Lo16 := -1; O.Hi16 := 32767;
  DumpO('ints', O);
  O.L := 0; O.S := -128;
  DumpO('short', O);
  Sh.Name := 'circle';
  Sh.Kind := 1;
  Sh.Radius := 1.0;
  Write('one ');
  DumpBytes(Sh);
  Sh.Radius := -2.5;
  Write('-2.5 ');
  DumpBytes(Sh);
  Sh.Kind := 4;
  Sh.Halves[0] := 0;
  Sh.Halves[1] := 1073741824;
  WriteLn('two ', Sh.Radius:0:3, ' kind ', Sh.Kind, ' ', Sh.Name);
  Sh.Bytes[7] := $59; Sh.Bytes[8] := $40;
  WriteLn('100 ', Sh.Radius:0:3);
  SB.F := 1.0;
  WriteLn('single 1.0 bits ', SB.Bits);
  SB.Bits := 1078530011;
  WriteLn('single pi ', SB.F:0:5);
  SB.Bits := -1082130432;
  WriteLn('single ', SB.F:0:2);
  for I := 0 to 7 do N.Z[I] := 0;
  N.P := 0;
  N.Head := 1;
  N.Outer := 0;
  N.A := $0201;
  N.Inner := 1;
  N.Q[0] := 3; N.Q[1] := 4; N.Q[2] := 5; N.Q[3] := 6;
  Write('nested P=', N.P, ' Z=');
  for I := 0 to 7 do Write(N.Z[I], ' ');
  WriteLn;
  Arr[1].L := 258;
  Arr[2].L := 65536 * 3 + 4;
  WriteLn('arr ', Arr[1].B[0], ' ', Arr[1].B[1], ' ', Arr[2].W[0], ' ', Arr[2].W[1]);
  New(P);
  P^.Kind := 2;
  P^.Wd := 300;
  P^.Ht := -300;
  WriteLn('heap ', P^.Bytes[1], ' ', P^.Bytes[2], ' ', P^.Bytes[3], ' ', P^.Bytes[4], ' ', P^.Halves[0]);
  Dispose(P);
  WriteLn('sizes ', SizeOf(TOverlay), ' ', SizeOf(TShape), ' ', SizeOf(TSingleBits), ' ', SizeOf(TNested));
end.
