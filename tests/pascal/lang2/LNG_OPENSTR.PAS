{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$P+}
program LngOpenStr;
{ With $P+ every var parameter of type String is an open string
  parameter: High and SizeOf follow the actual variable and assignments
  truncate to its declared length. }
type
  Str5 = String[5];
  TRec = record
    Name: String[4];
    Guard: Byte;
  end;

var
  A: Str5;
  B: String[12];
  C: String[1];
  S: String;
  Arr: array[1..2] of String[3];
  Rec: TRec;

procedure Append(var X: String; const Tail: String);
begin
  X := X + Tail;
  Write('high=', High(X), ' size=', SizeOf(X), ' ');
end;

procedure Pad(var X: String; Ch: Char);
begin
  while Length(X) < High(X) do X := X + Ch;
end;

procedure Exact(var X: Str5);
begin
  X := X + '!!!!!!!!';
end;

procedure Forward2(var X: String);
begin
  Append(X, '-forwarded-');
end;

begin
  A := 'ab';
  Append(A, '0123456789');
  WriteLn(A, ' ', Length(A));
  B := 'cd';
  Append(B, '0123456789');
  WriteLn(B, ' ', Length(B));
  C := '';
  Append(C, 'xyz');
  WriteLn(C, ' ', Length(C));
  S := 'ef';
  Append(S, '0123456789');
  WriteLn(S, ' ', Length(S));
  Arr[1] := 'k';
  Arr[2] := '';
  Pad(Arr[2], '#');
  Pad(Arr[1], '=');
  WriteLn(Arr[1], ' ', Arr[2]);
  Rec.Name := 'n';
  Rec.Guard := 201;
  Pad(Rec.Name, '?');
  WriteLn(Rec.Name, ' ', Rec.Guard);
  A := 'abc';
  Exact(A);
  WriteLn(A);
  B := 'fw';
  Forward2(B);
  WriteLn(B);
end.
