{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngCase;
{ case on Char, enumerations, Boolean, Byte, Word and LongInt selectors,
  ranges, lists, else with several statements, no match without else. }
type
  TDay = (Sen, Sel, Rab, Kam, Jum, Sab, Min);
  TWork = Sen..Jum;

var
  C: Char;
  D: TDay;
  WD: TWork;
  I: Integer;
  B: Byte;
  W: Word;
  L: LongInt;
  Flag: Boolean;
  Hits: Integer;
  S: String;

function Kind(C: Char): String;
begin
  case C of
    'a', 'e', 'i', 'o', 'u': Kind := 'V';
    'b'..'d', 'f'..'h', 'j'..'n', 'p'..'t', 'v'..'z': Kind := 'K';
    '0'..'9': Kind := 'D';
    #0..#31: Kind := 'C';
    ' ': Kind := '_';
    'A'..'Z': Kind := 'U';
    #128..#255: Kind := 'H';
  else
    Kind := '?';
  end;
end;

function DayKind(D: TDay): Char;
begin
  DayKind := '-';
  case D of
    Sen..Rab: DayKind := 'a';
    Kam, Jum: DayKind := 'b';
    Sab: ;
  end;
end;

function Dense(N: Integer): Integer;
begin
  case N of
    0: Dense := 100;
    1: Dense := 101;
    2: Dense := 102;
    3: Dense := 103;
    4: Dense := 104;
    5: Dense := 105;
    6: Dense := 106;
    7: Dense := 107;
    8: Dense := 108;
    9: Dense := 109;
    10..15: Dense := 110;
    16: Dense := 116;
  else
    Dense := -1;
  end;
end;

function Sparse(L: LongInt): Integer;
begin
  case L of
    -2147483647 - 1: Sparse := 1;
    -100000..-50000: Sparse := 2;
    0: Sparse := 3;
    65535, 65536: Sparse := 4;
    1000000: Sparse := 5;
    2147483647: Sparse := 6;
  else
    Sparse := 0;
  end;
end;

begin
  S := '';
  for I := 0 to 255 do
  begin
    C := Chr(I);
    if (I mod 8 = 0) or (I in [32, 48, 57, 65, 97, 101, 122, 127, 128, 255]) then
      S := S + Kind(C);
  end;
  WriteLn('char ', S);
  for D := Sen to Min do Write(DayKind(D));
  WriteLn;
  for WD := Low(TWork) to High(TWork) do
    case WD of
      Sen: Write('senin ');
      Jum: Write('jumat ');
    else
      Write(Ord(WD), ' ');
    end;
  WriteLn;
  for I := -2 to 18 do Write(Dense(I), ' ');
  WriteLn;
  WriteLn('sparse ', Sparse(-2147483647 - 1), Sparse(-75000), Sparse(-49999), Sparse(0),
    Sparse(65535), Sparse(65536), Sparse(65537), Sparse(1000000), Sparse(2147483647));
  for B := 250 to 255 do
    case B of
      250, 252: Write('even ');
      251, 253..254: Write('rest ');
      255: Write('max ');
    end;
  WriteLn;
  W := 65000;
  case W of
    0..32767: WriteLn('low word');
    32768..65535: WriteLn('high word');
  end;
  for Flag := False to True do
    case Flag of
      True: Write('yes ');
      False: Write('no ');
    end;
  WriteLn;
  I := 42;
  case I of
    1: WriteLn('one');
  else
    Write('else part ');
    Write('has ');
    WriteLn('three statements');
  end;
  Hits := 0;
  for I := 1 to 20 do
  begin
    case I mod 5 of
      0: Inc(Hits, 100);
      1, 3: Inc(Hits);
    end;
    case I of
      7: Break;
    end;
  end;
  WriteLn('hits ', Hits, ' stopped at ', I);
  L := 70000;
  case L div 1000 of
    69..71:
      case L mod 1000 of
        0: WriteLn('nested exact');
      else
        WriteLn('nested other');
      end;
  end;
  C := 'm';
  case UpCase(C) of
    'A'..'L': WriteLn('first half');
    'M'..'Z': WriteLn('second half');
  end;
  I := 1000;
  case I of
    1..999: WriteLn('not here');
  end;
  WriteLn('no match is fine');
end.
