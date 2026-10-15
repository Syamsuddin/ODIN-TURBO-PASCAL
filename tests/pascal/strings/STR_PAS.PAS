{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrPasses;
{ StrPas converts a null-terminated string to a Pascal string, stopping
  at the first #0 and keeping at most 255 characters. }
uses Strings;
type
  TBig = array[0..299] of Char;
var
  Big: TBig;
  Buf: array[0..255] of Char;
  P: PChar;
  S: String;
  T: String[10];
  i, Bad: Integer;
begin
  S := StrPas('Turbo');
  WriteLn('pas literal ', S, ' ', Length(S));
  S := StrPas('');
  WriteLn('pas empty ', Length(S));
  S := StrPas('ab'#0'cd');
  WriteLn('pas embedded null ', S, ' ', Length(S));
  P := 'pointer value';
  WriteLn('pas pchar ', StrPas(P), ' ', StrPas(P + 8));
  S := StrPas(P) + '!';
  WriteLn('pas concat ', S, ' ', Length(S));
  WriteLn('pas compare ', StrPas(P) = 'pointer value', ' ', StrPas(P) < 'pointer valuf');
  S := StrPas(#200#201'x');
  WriteLn('pas high ', Length(S), ' ', Ord(S[1]), ' ', Ord(S[2]), ' ', S[3]);
  S := StrPas(#13#10);
  WriteLn('pas control ', Length(S), ' ', Ord(S[1]), ' ', Ord(S[2]));

  for i := 0 to 298 do Big[i] := Chr(Ord('a') + i mod 26);
  Big[299] := #0;
  S := StrPas(Big);
  WriteLn('pas 299 truncated ', Length(S), ' ', S[1], S[254], S[255]);
  Big[255] := #0;
  S := StrPas(Big);
  WriteLn('pas exactly 255 ', Length(S), ' ', S[255]);
  Big[255] := 'x';
  Big[256] := #0;
  S := StrPas(Big);
  WriteLn('pas 256 truncated ', Length(S), ' ', S[255]);
  Big[254] := #0;
  S := StrPas(Big);
  WriteLn('pas 254 ', Length(S), ' ', S[254]);
  T := StrPas(Big);
  WriteLn('pas to string[10] ', Length(T), ' ', T);
  Big[3] := #0;
  T := StrPas(Big);
  WriteLn('pas short to string[10] ', Length(T), ' ', T);

  S := '';
  for i := 1 to 255 do S := S + Chr(i);
  StrPCopy(Buf, S);
  WriteLn('pcopy all chars length ', StrLen(Buf), ' ', Ord(Buf[254]), ' ', Ord(Buf[255]));
  S := StrPas(Buf);
  Bad := 0;
  for i := 1 to 255 do
    if S[i] <> Chr(i) then Inc(Bad);
  WriteLn('round trip ', Length(S), ' differences ', Bad);

  S := 'some text';
  StrPCopy(Buf, S);
  WriteLn('round trip equal ', StrPas(Buf) = S);
  Buf[4] := #0;
  WriteLn('pas after edit ', StrPas(Buf), '|');
  S := StrPas(Buf) + StrPas(@Buf[5]);
  WriteLn('pas two parts ', S);
end.
