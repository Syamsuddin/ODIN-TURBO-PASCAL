{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngShortStr;
{ string[N] value, const and var parameters under $V+ and $V-, open
  string parameters (OpenString), truncation on assignment. }
type
  Str5 = String[5];
  Str10 = String[10];
  TRec = record
    Code: Str10;
    Tail: Byte;
  end;

var
  A: Str5;
  B: Str10;
  C: String[1];
  S: String;
  Arr: array[1..2] of Str10;
  Rec: TRec;
  I: Integer;

procedure ValueStr5(X: Str5);
begin
  Write('[', X, '] ', Length(X), ' ', High(X), ' ');
  X := 'changed-inside';
  WriteLn('[', X, ']');
end;

procedure ValueStr(X: String);
begin
  WriteLn('vs [', X, '] ', High(X));
end;

procedure AppendExact(var X: Str10; const Suffix: String);
begin
  X := X + Suffix;
end;

procedure AppendLong(var X: String; const Suffix: String);
begin
  X := X + Suffix;
end;

function Five(const X: String): Str5;
begin
  Five := X;
end;

procedure FillOpen(var X: OpenString; Ch: Char);
begin
  X := '';
  while Length(X) < High(X) do X := X + Ch;
end;

procedure AddDigits(var X: OpenString);
begin
  X := X + '0123456789';
  Write('open high=', High(X), ' size=', SizeOf(X), ' ');
end;

{$V-}
procedure UpperInPlace(var X: String);
var K: Integer;
begin
  for K := 1 to Length(X) do X[K] := UpCase(X[K]);
end;

procedure DropFirst(var X: String);
begin
  Delete(X, 1, 1);
end;

procedure Relaxed;
begin
  A := 'abc';
  UpperInPlace(A);
  B := 'mixed Case';
  UpperInPlace(B);
  DropFirst(B);
  Rec.Code := 'record';
  Rec.Tail := 77;
  UpperInPlace(Rec.Code);
  WriteLn('relaxed ', A, ' ', B, ' ', Length(B), ' ', Rec.Code, ' ', Rec.Tail);
end;
{$V+}

begin
  ValueStr5('abcdefgh');
  S := 'longer string';
  ValueStr5(S);
  B := 'tenletters';
  ValueStr5(B);
  ValueStr5('ab');
  A := 'five5';
  ValueStr(A);
  B := 'abc';
  AppendExact(B, 'defghijklmnop');
  WriteLn('exact ', B, ' ', Length(B));
  Arr[2] := 'xy';
  AppendExact(Arr[2], '12345678901');
  WriteLn('element ', Arr[2], ' ', Length(Arr[2]));
  S := 'abc';
  AppendLong(S, 'def');
  WriteLn('long ', S, ' ', Length(S));
  WriteLn('func ', Five('truncate me'), ' ', Length(Five('xyzxyzxyz')), ' ', Five('ab'));
  A := 'abcdefghij';
  B := A + 'XYZXYZXYZXYZ';
  C := B;
  WriteLn('assign ', A, ' ', B, ' ', C, ' ', Length(C));
  WriteLn('compare ', A = 'abcde', ' ', A < B, ' ', C = 'a', ' ', A = Five('abcdefg'));
  WriteLn('sizes ', SizeOf(A), ' ', SizeOf(B), ' ', SizeOf(C), ' ', SizeOf(Rec), ' ', High(A), ' ', High(C));
  FillOpen(A, '*');
  FillOpen(B, '-');
  FillOpen(C, '+');
  WriteLn('fill ', A, ' ', B, ' ', C);
  A := 'xy';
  AddDigits(A);
  WriteLn(A, ' ', Length(A));
  B := 'pq';
  AddDigits(B);
  WriteLn(B, ' ', Length(B));
  S := 'long';
  AddDigits(S);
  WriteLn(S, ' ', Length(S));
  Relaxed;
  S := '';
  for I := 1 to 30 do S := S + '0123456789';
  WriteLn('cap ', Length(S), ' ', S[255], ' ', Copy(S, 251, 10));
  A := 'abc';
  A[0] := #2;
  WriteLn('len byte ', A, ' ', Length(A), ' ', Ord(A[0]));
end.
