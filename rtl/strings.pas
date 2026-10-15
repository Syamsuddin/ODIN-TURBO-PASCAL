{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Strings dari runtime library Odin: rutin untuk string berakhiran #0
  (PChar). Implementasi clean-room berdasarkan perilaku API yang
  terdokumentasi dan pengamatan keluaran program. }
unit Strings;

{$R-,Q-,I-,X+}

interface

function StrLen(Str: PChar): LongInt;
function StrEnd(Str: PChar): PChar;
function StrMove(Dest, Source: PChar; Count: LongInt): PChar;
function StrCopy(Dest, Source: PChar): PChar;
function StrECopy(Dest, Source: PChar): PChar;
function StrLCopy(Dest, Source: PChar; MaxLen: LongInt): PChar;
function StrPCopy(Dest: PChar; const Source: String): PChar;
function StrCat(Dest, Source: PChar): PChar;
function StrLCat(Dest, Source: PChar; MaxLen: LongInt): PChar;
function StrComp(Str1, Str2: PChar): LongInt;
function StrIComp(Str1, Str2: PChar): LongInt;
function StrLComp(Str1, Str2: PChar; MaxLen: LongInt): LongInt;
function StrLIComp(Str1, Str2: PChar; MaxLen: LongInt): LongInt;
function StrScan(Str: PChar; Chr: Char): PChar;
function StrRScan(Str: PChar; Chr: Char): PChar;
function StrPos(Str1, Str2: PChar): PChar;
function StrUpper(Str: PChar): PChar;
function StrLower(Str: PChar): PChar;
function StrPas(Str: PChar): String;
function StrNew(Str: PChar): PChar;
procedure StrDispose(Str: PChar);

implementation

function StrLen(Str: PChar): LongInt;
var
  N: LongInt;
begin
  N := 0;
  if Str <> nil then
    while Str[N] <> #0 do
      Inc(N);
  StrLen := N;
end;

function StrEnd(Str: PChar): PChar;
begin
  StrEnd := Str + StrLen(Str);
end;

function StrMove(Dest, Source: PChar; Count: LongInt): PChar;
begin
  if Count > 0 then
    Move(Source^, Dest^, Count);
  StrMove := Dest;
end;

function StrCopy(Dest, Source: PChar): PChar;
begin
  StrMove(Dest, Source, StrLen(Source) + 1);
  StrCopy := Dest;
end;

function StrECopy(Dest, Source: PChar): PChar;
var
  N: LongInt;
begin
  N := StrLen(Source);
  StrMove(Dest, Source, N + 1);
  StrECopy := Dest + N;
end;

function StrLCopy(Dest, Source: PChar; MaxLen: LongInt): PChar;
var
  N: LongInt;
begin
  N := 0;
  while (N < MaxLen) and (Source[N] <> #0) do
  begin
    Dest[N] := Source[N];
    Inc(N);
  end;
  Dest[N] := #0;
  StrLCopy := Dest;
end;

function StrPCopy(Dest: PChar; const Source: String): PChar;
var
  I: Integer;
begin
  for I := 1 to Length(Source) do
    Dest[I - 1] := Source[I];
  Dest[Length(Source)] := #0;
  StrPCopy := Dest;
end;

function StrCat(Dest, Source: PChar): PChar;
begin
  StrCopy(StrEnd(Dest), Source);
  StrCat := Dest;
end;

function StrLCat(Dest, Source: PChar; MaxLen: LongInt): PChar;
var
  N: LongInt;
begin
  N := StrLen(Dest);
  if N < MaxLen then
    StrLCopy(Dest + N, Source, MaxLen - N);
  StrLCat := Dest;
end;

function Lower(C: Char): Char;
begin
  if (C >= 'A') and (C <= 'Z') then
    Lower := Chr(Ord(C) + 32)
  else
    Lower := C;
end;

function Upper(C: Char): Char;
begin
  if (C >= 'a') and (C <= 'z') then
    Upper := Chr(Ord(C) - 32)
  else
    Upper := C;
end;

{ Compares at most MaxLen characters (MaxLen < 0: no limit). The result
  is the difference of the first differing bytes, as unsigned values. }
function Compare(Str1, Str2: PChar; MaxLen: LongInt; IgnoreCase: Boolean): LongInt;
var
  I: LongInt;
  A, B: Char;
begin
  I := 0;
  while (MaxLen < 0) or (I < MaxLen) do
  begin
    A := Str1[I];
    B := Str2[I];
    if IgnoreCase then
    begin
      A := Lower(A);
      B := Lower(B);
    end;
    if (A <> B) or (A = #0) then
    begin
      Compare := Ord(A) - Ord(B);
      Exit;
    end;
    Inc(I);
  end;
  Compare := 0;
end;

function StrComp(Str1, Str2: PChar): LongInt;
begin
  StrComp := Compare(Str1, Str2, -1, False);
end;

function StrIComp(Str1, Str2: PChar): LongInt;
begin
  StrIComp := Compare(Str1, Str2, -1, True);
end;

function StrLComp(Str1, Str2: PChar; MaxLen: LongInt): LongInt;
begin
  StrLComp := Compare(Str1, Str2, MaxLen, False);
end;

function StrLIComp(Str1, Str2: PChar; MaxLen: LongInt): LongInt;
begin
  StrLIComp := Compare(Str1, Str2, MaxLen, True);
end;

function StrScan(Str: PChar; Chr: Char): PChar;
var
  I: LongInt;
begin
  StrScan := nil;
  I := 0;
  while True do
  begin
    if Str[I] = Chr then
    begin
      StrScan := Str + I;
      Exit;
    end;
    if Str[I] = #0 then
      Exit;
    Inc(I);
  end;
end;

function StrRScan(Str: PChar; Chr: Char): PChar;
var
  I: LongInt;
begin
  StrRScan := nil;
  I := StrLen(Str);
  while I >= 0 do
  begin
    if Str[I] = Chr then
    begin
      StrRScan := Str + I;
      Exit;
    end;
    Dec(I);
  end;
end;

function StrPos(Str1, Str2: PChar): PChar;
var
  I, J, L1, L2: LongInt;
begin
  StrPos := nil;
  L1 := StrLen(Str1);
  L2 := StrLen(Str2);
  if L2 = 0 then
  begin
    StrPos := Str1 + L1;
    Exit;
  end;
  for I := 0 to L1 - L2 do
  begin
    J := 0;
    while (J < L2) and (Str1[I + J] = Str2[J]) do
      Inc(J);
    if J = L2 then
    begin
      StrPos := Str1 + I;
      Exit;
    end;
  end;
end;

function StrUpper(Str: PChar): PChar;
var
  I: LongInt;
begin
  I := 0;
  while Str[I] <> #0 do
  begin
    Str[I] := Upper(Str[I]);
    Inc(I);
  end;
  StrUpper := Str;
end;

function StrLower(Str: PChar): PChar;
var
  I: LongInt;
begin
  I := 0;
  while Str[I] <> #0 do
  begin
    Str[I] := Lower(Str[I]);
    Inc(I);
  end;
  StrLower := Str;
end;

function StrPas(Str: PChar): String;
var
  S: String;
  N: Integer;
begin
  N := 0;
  if Str <> nil then
    while (Str[N] <> #0) and (N < 255) do
    begin
      S[N + 1] := Str[N];
      Inc(N);
    end;
  S[0] := Chr(N);
  StrPas := S;
end;

function StrNew(Str: PChar): PChar;
var
  N: LongInt;
  P: PChar;
begin
  StrNew := nil;
  if Str = nil then
    Exit;
  N := StrLen(Str);
  if N = 0 then
    Exit;
  GetMem(P, N + 1);
  StrMove(P, Str, N + 1);
  StrNew := P;
end;

procedure StrDispose(Str: PChar);
begin
  if Str <> nil then
    FreeMem(Str, StrLen(Str) + 1);
end;

end.
