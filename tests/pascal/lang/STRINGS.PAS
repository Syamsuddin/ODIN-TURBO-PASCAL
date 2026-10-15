{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Strings1;
var
  s, t: String;
  short: String[5];
  c: Char;
  i: Integer;
begin
  s := 'Hello';
  t := s + ', ' + 'World' + '!';
  WriteLn(t, ' ', Length(t));
  WriteLn(Copy(t, 1, 5), '|', Copy(t, 8, 100), '|', Copy(t, 50, 2), '|');
  WriteLn(Pos('World', t), ' ', Pos('xyz', t), ' ', Pos('l', t));
  Delete(t, 6, 7); WriteLn(t);
  Insert(' there', t, 6); WriteLn(t);
  short := 'abcdefgh'; WriteLn(short, ' ', Length(short));
  c := 'q'; s := c; WriteLn(s, Length(s));
  s := 'a'; s := s + c + 'z'; WriteLn(s);
  WriteLn(UpCase('a'), UpCase('Z'), UpCase('5'));
  s := 'pascal';
  for i := 1 to Length(s) do s[i] := UpCase(s[i]);
  WriteLn(s);
  WriteLn('abc' < 'abd', ' ', 'abc' = 'abc', ' ', 'b' > 'abc', ' ', 'ab' < 'abc', ' ', '' < 'a');
  s := '';
  for c := 'a' to 'e' do s := s + c;
  WriteLn(s, ' ', Ord(s[0]));
  s := Concat('x', 'y', 'z'); WriteLn(s);
  Str(123:6, s); WriteLn('[', s, ']');
  Str(-45, s); WriteLn('[', s, ']');
  Str(3.14159:0:3, s); WriteLn('[', s, ']');

end.
