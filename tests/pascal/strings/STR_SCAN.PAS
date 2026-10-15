{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{$X+}
program StrScans;
{ StrScan and StrRScan: first and last occurrence of a character, nil
  when absent. Searching for #0 finds the terminator. Nothing after the
  terminator is searched. }
uses Strings;
type
  TBuf = array[0..31] of Char;
var
  A: TBuf;
  Base, P: PChar;
  Count: Integer;

procedure Show(const Lbl: String; R: PChar);
begin
  Write(Lbl, ' ');
  if R = nil then WriteLn('nil') else WriteLn(R - Base, ' ', R);
end;

begin
  StrCopy(A, 'Hello, World');
  Base := A;
  Show('scan o', StrScan(A, 'o'));
  Show('scan H', StrScan(A, 'H'));
  Show('scan d', StrScan(A, 'd'));
  Show('scan comma', StrScan(A, ','));
  Show('scan z', StrScan(A, 'z'));
  Show('scan case', StrScan(A, 'h'));
  Show('scan null', StrScan(A, #0));
  Show('scan from middle', StrScan(Base + 5, 'o'));

  Show('rscan o', StrRScan(A, 'o'));
  Show('rscan l', StrRScan(A, 'l'));
  Show('rscan H', StrRScan(A, 'H'));
  Show('rscan d', StrRScan(A, 'd'));
  Show('rscan z', StrRScan(A, 'z'));
  Show('rscan null', StrRScan(A, #0));

  A[0] := #0;
  Show('scan empty a', StrScan(A, 'a'));
  Show('scan empty null', StrScan(A, #0));
  Show('rscan empty a', StrRScan(A, 'a'));
  Show('rscan empty null', StrRScan(A, #0));

  StrCopy(A, 'ab');
  A[3] := 'c';
  A[4] := 'b';
  A[5] := #0;
  Show('scan stops at null', StrScan(A, 'c'));
  Show('rscan stops at null', StrRScan(A, 'b'));

  StrCopy(A, 'x'#200'y'#255'z'#200);
  P := StrScan(A, #200);
  WriteLn('scan high ', P - Base);
  P := StrRScan(A, #200);
  WriteLn('rscan high ', P - Base);
  P := StrScan(A, #255);
  WriteLn('scan 255 ', P - Base);
  WriteLn('scan 128 nil ', StrScan(A, #128) = nil);

  StrCopy(A, 'a,b,,c');
  P := StrScan(A, ',');
  while P <> nil do
  begin
    P^ := ';';
    P := StrScan(P + 1, ',');
  end;
  WriteLn('replace all ', A);

  StrCopy(A, 'mississippi');
  Count := 0;
  P := StrScan(A, 's');
  while P <> nil do
  begin
    Inc(Count);
    P := StrScan(P + 1, 's');
  end;
  WriteLn('count s ', Count);
  P := StrRScan(A, 's');
  WriteLn('last s ', P - Base, ' ', P + 1);
  P := StrScan('literal', 't');
  WriteLn('scan literal ', P);
end.
