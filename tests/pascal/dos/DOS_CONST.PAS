{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosConst;
{ TP7 Dos unit: file attribute, file mode and flag constants, and the
  string and record types the unit declares. }
uses Dos;
var
  P: PathStr;
  D: DirStr;
  N: NameStr;
  E: ExtStr;
  C: ComStr;
  DT: DateTime;
  SR: SearchRec;

function Hex(V: LongInt; Digits: Integer): String;
const
  Digit: array[0..15] of Char = '0123456789ABCDEF';
var
  S: String;
begin
  S := '';
  while Digits > 0 do
  begin
    S := Digit[V and 15] + S;
    V := V shr 4;
    Dec(Digits);
  end;
  Hex := S;
end;

begin
  WriteLn('ReadOnly  = ', ReadOnly);
  WriteLn('Hidden    = ', Hidden);
  WriteLn('SysFile   = ', SysFile);
  WriteLn('VolumeID  = ', VolumeID);
  WriteLn('Directory = ', Directory);
  WriteLn('Archive   = ', Archive);
  WriteLn('AnyFile   = ', AnyFile);
  WriteLn('AnyFile is every attribute: ',
    AnyFile = ReadOnly or Hidden or SysFile or VolumeID or Directory or Archive);

  WriteLn('fmClosed  = $', Hex(fmClosed, 4));
  WriteLn('fmInput   = $', Hex(fmInput, 4));
  WriteLn('fmOutput  = $', Hex(fmOutput, 4));
  WriteLn('fmInOut   = $', Hex(fmInOut, 4));
  WriteLn('fm sequence: ', (fmInput = fmClosed + 1) and (fmOutput = fmClosed + 2)
    and (fmInOut = fmClosed + 3));

  WriteLn('FCarry    = ', FCarry);
  WriteLn('FParity   = ', FParity);
  WriteLn('FAuxiliary= ', FAuxiliary);
  WriteLn('FZero     = ', FZero);
  WriteLn('FSign     = ', FSign);
  WriteLn('FOverflow = ', FOverflow);

  { String types: FPC uses 255 characters for all of them. }
  WriteLn('SizeOf PathStr=', SizeOf(PathStr), ' DirStr=', SizeOf(DirStr),
    ' NameStr=', SizeOf(NameStr), ' ExtStr=', SizeOf(ExtStr), ' ComStr=', SizeOf(ComStr));
  N := 'averylongfilename';
  E := '.extension';
  D := '/a/directory/name/that/is/longer/than/sixty/seven/characters/in/total/';
  P := D + N + E;
  C := '-c "exit 0"';
  WriteLn('NameStr keeps ', Length(N), ' chars, ExtStr keeps ', Length(E), ' chars');
  WriteLn('DirStr keeps ', Length(D), ' chars, PathStr keeps ', Length(P), ' chars');
  WriteLn('ComStr keeps ', Length(C), ' chars');

  { DateTime: six Word fields. }
  WriteLn('SizeOf DateTime=', SizeOf(DateTime), ' field=', SizeOf(DT.Year));
  with DT do
  begin
    Year := 2026; Month := 10; Day := 15; Hour := 23; Min := 59; Sec := 58;
  end;
  WriteLn('DateTime fields: ', DT.Year, ' ', DT.Month, ' ', DT.Day, ' ',
    DT.Hour, ' ', DT.Min, ' ', DT.Sec);

  { SearchRec: the public fields TP7 programs use. }
  WriteLn('SearchRec Attr=', SizeOf(SR.Attr), ' Time=', SizeOf(SR.Time),
    ' Size=', SizeOf(SR.Size), ' Name=', SizeOf(SR.Name));
  SR.Attr := Directory or Hidden;
  SR.Time := 1557095516;
  SR.Size := 123456;
  SR.Name := 'a_name_longer_than_twelve_characters.text';
  WriteLn('SearchRec fields: ', SR.Attr, ' ', SR.Time, ' ', SR.Size, ' ', SR.Name);

  { DosError is an Integer variable that programs may assign. }
  WriteLn('SizeOf DosError=', SizeOf(DosError), ' initial=', DosError);
  DosError := 18;
  WriteLn('DosError assigned=', DosError);
end.
