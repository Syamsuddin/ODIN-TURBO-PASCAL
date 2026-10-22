{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit SysUtils dari runtime library Odin. Bukan unit Turbo Pascal 7,
  tetapi subset kecil dari SysUtils Free Pascal/Delphi yang dipakai banyak
  program: konversi angka dan teks, rutin string, nama berkas dan direktori,
  tanggal dan waktu (TDateTime), Sleep.

  Yang tidak ada, karena bahasa Odin belum punya fiturnya: kelas dan
  exception (galat konversi menjadi runtime error 106; pakai versi Try... atau
  ...Def bila galat harus ditangani), Format (butuh array of const), parameter
  bawaan (semua argumen ditulis, mis. BoolToStr(B, True), IncMonth(D, 1)), dan
  overload (FormatDateTime dan IntToStr hanya satu bentuk). String tetap
  String 255 karakter. }
unit SysUtils;

{$R-,Q-,I-,X+}

interface

uses
  Dos;

const
{$IFDEF WINDOWS}
  PathDelim = '\';
  DirectorySeparator = '\';
  PathSeparator = ';';
  LineEnding = #13#10;
{$ELSE}
  PathDelim = '/';
  DirectorySeparator = '/';
  PathSeparator = ':';
  LineEnding = #10;
{$ENDIF}
  MSecsPerDay = 86400000;
  SecsPerDay = 86400;
  HoursPerDay = 24;
  MinsPerDay = 1440;
  DateDelta = 693594;

type
  TDateTime = Double;
  TSysCharSet = set of Char;
  TReplaceFlag = (rfReplaceAll, rfIgnoreCase);
  TReplaceFlags = set of TReplaceFlag;
  TFloatFormat = (ffGeneral, ffExponent, ffFixed, ffNumber, ffCurrency);

var
  DecimalSeparator: Char;
  ThousandSeparator: Char;
  DateSeparator: Char;
  TimeSeparator: Char;
  ShortDateFormat: String;
  LongDateFormat: String;
  ShortTimeFormat: String;
  LongTimeFormat: String;
  CurrencyString: String;
  TimeAMString: String;
  TimePMString: String;
  ShortMonthNames: array[1..12] of String;
  LongMonthNames: array[1..12] of String;
  ShortDayNames: array[1..7] of String;
  LongDayNames: array[1..7] of String;

{ Bilangan dan teks }
function IntToStr(Value: Int64): String;
function IntToHex(Value: Int64; Digits: Integer): String;
function StrToInt(const S: String): LongInt;
function StrToIntDef(const S: String; Default: LongInt): LongInt;
function TryStrToInt(const S: String; var Value: LongInt): Boolean;
function StrToInt64(const S: String): Int64;
function StrToInt64Def(const S: String; Default: Int64): Int64;
function TryStrToInt64(const S: String; var Value: Int64): Boolean;
function StrToFloat(const S: String): Double;
function StrToFloatDef(const S: String; Default: Double): Double;
function TryStrToFloat(const S: String; var Value: Double): Boolean;
function FloatToStr(Value: Double): String;
function FloatToStrF(Value: Double; Format: TFloatFormat; Precision, Digits: Integer): String;
function FormatFloat(const Format: String; Value: Double): String;
function BoolToStr(B: Boolean; UseBoolStrs: Boolean): String;
function StrToBool(const S: String): Boolean;
function StrToBoolDef(const S: String; Default: Boolean): Boolean;

{ String }
function UpperCase(const S: String): String;
function LowerCase(const S: String): String;
function AnsiUpperCase(const S: String): String;
function AnsiLowerCase(const S: String): String;
function Trim(const S: String): String;
function TrimLeft(const S: String): String;
function TrimRight(const S: String): String;
function StringOfChar(Ch: Char; Count: Integer): String;
function CompareStr(const S1, S2: String): Integer;
function CompareText(const S1, S2: String): Integer;
function SameText(const S1, S2: String): Boolean;
function AnsiCompareStr(const S1, S2: String): Integer;
function AnsiCompareText(const S1, S2: String): Integer;
function StringReplace(const S, OldPattern, NewPattern: String; Flags: TReplaceFlags): String;
function QuotedStr(const S: String): String;
function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;

{ Berkas dan direktori }
function FileExists(const FileName: String): Boolean;
function DirectoryExists(const Directory: String): Boolean;
function DeleteFile(const FileName: String): Boolean;
function RenameFile(const OldName, NewName: String): Boolean;
function CreateDir(const Dir: String): Boolean;
function RemoveDir(const Dir: String): Boolean;
function ForceDirectories(const Dir: String): Boolean;
function GetCurrentDir: String;
function SetCurrentDir(const Dir: String): Boolean;
function ExtractFileName(const FileName: String): String;
function ExtractFilePath(const FileName: String): String;
function ExtractFileDir(const FileName: String): String;
function ExtractFileExt(const FileName: String): String;
function ChangeFileExt(const FileName, Extension: String): String;
function ExpandFileName(const FileName: String): String;
function IncludeTrailingPathDelimiter(const S: String): String;
function ExcludeTrailingPathDelimiter(const S: String): String;
function GetEnvironmentVariable(const Name: String): String;

{ Tanggal dan waktu (TDateTime: hari sejak 30-12-1899, pecahannya waktu) }
function Now: TDateTime;
function Date: TDateTime;
function Time: TDateTime;
function IsLeapYear(Year: Word): Boolean;
function DaysInAMonth(Year, Month: Word): Word;
function EncodeDate(Year, Month, Day: Word): TDateTime;
function EncodeTime(Hour, Min, Sec, MSec: Word): TDateTime;
procedure DecodeDate(Date: TDateTime; var Year, Month, Day: Word);
procedure DecodeTime(Time: TDateTime; var Hour, Min, Sec, MSec: Word);
function DayOfWeek(Date: TDateTime): Integer;
function IncMonth(Date: TDateTime; NumberOfMonths: Integer): TDateTime;
function DateToStr(Date: TDateTime): String;
function TimeToStr(Time: TDateTime): String;
function DateTimeToStr(DateTime: TDateTime): String;
function FormatDateTime(const Format: String; DateTime: TDateTime): String;
function TryStrToDate(const S: String; var Value: TDateTime): Boolean;
function StrToDate(const S: String): TDateTime;
function TryStrToTime(const S: String; var Value: TDateTime): Boolean;
function StrToTime(const S: String): TDateTime;
function StrToDateTime(const S: String): TDateTime;

{ Waktu sistem }
procedure Sleep(Milliseconds: LongInt);
function GetTickCount64: Int64;
function GetTickCount: Cardinal;

implementation

{$IFDEF WINDOWS}
procedure WinSleep(Ms: LongInt); external 'kernel32' name 'Sleep';
function WinTickCount64: Int64; external 'kernel32' name 'GetTickCount64';
{$ELSE}
type
  TTimeVal = record
    Sec: Int64;
    USec: LongInt;
    Pad: LongInt;
  end;

function c_usleep(Us: LongWord): LongInt; cdecl; external 'c' name 'usleep';
function c_gettimeofday(var TV: TTimeVal; TZ: Pointer): LongInt; cdecl; external 'c' name 'gettimeofday';
{$ENDIF}

procedure ConvertError;
begin
  { Invalid numeric format, seperti Read gagal membaca bilangan. }
  RunError(106);
end;

{ ---- bilangan dan teks --------------------------------------------------------------- }

function IntToStr(Value: Int64): String;
var
  S: String;
begin
  Str(Value, S);
  IntToStr := S;
end;

function IntToHex(Value: Int64; Digits: Integer): String;
const
  Hex: array[0..15] of Char = '0123456789ABCDEF';
var
  S: String;
  I: Integer;
begin
  S := '';
  for I := 15 downto 0 do
    S := S + Hex[(Value shr (4 * I)) and $F];
  { Buang nol di depan, tetapi sisakan sebanyak Digits (minimal satu). }
  I := 1;
  while (I < Length(S)) and (S[I] = '0') and (Length(S) - I + 1 > Digits) do
    Inc(I);
  IntToHex := Copy(S, I, 255);
end;

function TryStrToInt64(const S: String; var Value: Int64): Boolean;
var
  V: Int64;
  Code: LongInt;
  T: String;
begin
  T := Trim(S);
  if T = '' then
  begin
    TryStrToInt64 := False;
    Exit;
  end;
  Val(T, V, Code);
  if Code = 0 then
  begin
    Value := V;
    TryStrToInt64 := True;
  end
  else
    TryStrToInt64 := False;
end;

function StrToInt64(const S: String): Int64;
var
  V: Int64;
begin
  if not TryStrToInt64(S, V) then
    ConvertError;
  StrToInt64 := V;
end;

function StrToInt64Def(const S: String; Default: Int64): Int64;
var
  V: Int64;
begin
  if TryStrToInt64(S, V) then
    StrToInt64Def := V
  else
    StrToInt64Def := Default;
end;

function TryStrToInt(const S: String; var Value: LongInt): Boolean;
var
  V: Int64;
begin
  if TryStrToInt64(S, V) and (V >= -2147483648) and (V <= 2147483647) then
  begin
    Value := V;
    TryStrToInt := True;
  end
  else
    TryStrToInt := False;
end;

function StrToInt(const S: String): LongInt;
var
  V: LongInt;
begin
  if not TryStrToInt(S, V) then
    ConvertError;
  StrToInt := V;
end;

function StrToIntDef(const S: String; Default: LongInt): LongInt;
var
  V: LongInt;
begin
  if TryStrToInt(S, V) then
    StrToIntDef := V
  else
    StrToIntDef := Default;
end;

function TryStrToFloat(const S: String; var Value: Double): Boolean;
var
  V: Double;
  Code: LongInt;
  T: String;
  I: Integer;
begin
  T := Trim(S);
  if T = '' then
  begin
    TryStrToFloat := False;
    Exit;
  end;
  { Val hanya mengenal titik; pemisah desimal yang dipilih diganti dulu. }
  if DecimalSeparator <> '.' then
    for I := 1 to Length(T) do
      if T[I] = DecimalSeparator then
        T[I] := '.'
      else if T[I] = '.' then
        T[I] := #1;
  Val(T, V, Code);
  if Code = 0 then
  begin
    Value := V;
    TryStrToFloat := True;
  end
  else
    TryStrToFloat := False;
end;

function StrToFloat(const S: String): Double;
var
  V: Double;
begin
  if not TryStrToFloat(S, V) then
    ConvertError;
  StrToFloat := V;
end;

function StrToFloatDef(const S: String; Default: Double): Double;
var
  V: Double;
begin
  if TryStrToFloat(S, V) then
    StrToFloatDef := V
  else
    StrToFloatDef := Default;
end;

{ Angka-angka Abs(V) dibulatkan ke Prec (1..17) angka berarti. Nilainya
  D1.D2D3... x 10^E; Digs berisi tepat Prec karakter. V = 0 memberi nol semua
  dan E = 0. }
procedure FloatDigits(V: Double; Prec: Integer; var Digs: String; var E: Integer);
var
  S, Mant: String;
  I, J, Code: Integer;
  Ex: LongInt;
  Carry: Boolean;
begin
  if Prec < 1 then
    Prec := 1;
  if Prec > 17 then
    Prec := 17;
  if V < 0 then
    V := -V;
  Str(V:25, S);
  Mant := '';
  I := 1;
  while (I <= Length(S)) and (S[I] <> 'E') do
  begin
    if (S[I] >= '0') and (S[I] <= '9') then
      Mant := Mant + S[I];
    Inc(I);
  end;
  Ex := 0;
  if I < Length(S) then
    Val(Copy(S, I + 1, 255), Ex, Code);
  if V = 0 then
    Ex := 0;
  if Length(Mant) > Prec then
  begin
    Carry := Mant[Prec + 1] >= '5';
    Mant := Copy(Mant, 1, Prec);
    J := Prec;
    while Carry and (J >= 1) do
    begin
      if Mant[J] = '9' then
      begin
        Mant[J] := '0';
        Dec(J);
      end
      else
      begin
        Mant[J] := Chr(Ord(Mant[J]) + 1);
        Carry := False;
      end;
    end;
    if Carry then
    begin
      Mant := '1' + Copy(Mant, 1, Prec - 1);
      Inc(Ex);
    end;
  end;
  while Length(Mant) < Prec do
    Mant := Mant + '0';
  Digs := Mant;
  E := Ex;
end;

function SpecialFloat(V: Double; var S: String): Boolean;
var
  B: Int64;
begin
  Move(V, B, 8);
  SpecialFloat := False;
  if (B shr 52) and $7FF = $7FF then
  begin
    SpecialFloat := True;
    if B and $000FFFFFFFFFFFFF <> 0 then
      S := 'NAN'
    else if B < 0 then
      S := '-INF'
    else
      S := 'INF';
  end;
end;

{ Menyisipkan pemisah ribuan ke bagian bulat I (hanya angka). }
function Group(const I: String): String;
var
  R: String;
  K, N: Integer;
begin
  R := '';
  N := 0;
  for K := Length(I) downto 1 do
  begin
    if (N > 0) and (N mod 3 = 0) then
      R := ThousandSeparator + R;
    R := I[K] + R;
    Inc(N);
  end;
  Group := R;
end;

function FixedStr(V: Double; Decimals: Integer; Thousands: Boolean): String;
var
  S, I, F: String;
  P: Integer;
  Neg: Boolean;
begin
  if Decimals < 0 then
    Decimals := 0;
  if Decimals > 18 then
    Decimals := 18;
  Neg := V < 0;
  if Neg then
    V := -V;
  Str(V:0:Decimals, S);
  P := Pos('.', S);
  if P > 0 then
  begin
    I := Copy(S, 1, P - 1);
    F := Copy(S, P + 1, 255);
  end
  else
  begin
    I := S;
    F := '';
  end;
  if Thousands then
    I := Group(I);
  S := I;
  if F <> '' then
    S := S + DecimalSeparator + F;
  { Hasil yang dibulatkan ke nol tidak diberi tanda minus. }
  if Neg then
  begin
    P := 1;
    while (P <= Length(S)) and ((S[P] = '0') or (S[P] = DecimalSeparator) or (S[P] = ThousandSeparator)) do
      Inc(P);
    if P <= Length(S) then
      S := '-' + S;
  end;
  FixedStr := S;
end;

function ExpStr(V: Double; Prec, Digits: Integer; Plus: Boolean): String;
var
  Digs, S, ES: String;
  E: Integer;
begin
  FloatDigits(V, Prec, Digs, E);
  S := Digs[1];
  if Length(Digs) > 1 then
    S := S + DecimalSeparator + Copy(Digs, 2, 255);
  Str(Abs(E), ES);
  while Length(ES) < Digits do
    ES := '0' + ES;
  if E < 0 then
    S := S + 'E-' + ES
  else if Plus then
    S := S + 'E+' + ES
  else
    S := S + 'E' + ES;
  if V < 0 then
    S := '-' + S;
  ExpStr := S;
end;

function GeneralStr(V: Double; Prec: Integer): String;
var
  Digs, S: String;
  E, N, K: Integer;
begin
  if Prec < 1 then
    Prec := 15;
  FloatDigits(V, Prec, Digs, E);
  { Nol di belakang tidak ikut. }
  N := Length(Digs);
  while (N > 1) and (Digs[N] = '0') do
    Dec(N);
  Digs := Copy(Digs, 1, N);
  if (E < -4) or (E >= Prec) then
  begin
    S := Digs[1];
    if N > 1 then
      S := S + DecimalSeparator + Copy(Digs, 2, 255);
    S := S + 'E';
    if E < 0 then
      S := S + '-';
    Str(Abs(E), Digs);
    S := S + Digs;
  end
  else if E < 0 then
  begin
    S := '0' + DecimalSeparator;
    for K := 1 to -E - 1 do
      S := S + '0';
    S := S + Digs;
  end
  else
  begin
    while Length(Digs) < E + 1 do
      Digs := Digs + '0';
    S := Copy(Digs, 1, E + 1);
    if Length(Digs) > E + 1 then
      S := S + DecimalSeparator + Copy(Digs, E + 2, 255);
  end;
  if V < 0 then
    S := '-' + S;
  GeneralStr := S;
end;

function FloatToStr(Value: Double): String;
var
  S: String;
begin
  if SpecialFloat(Value, S) then
    FloatToStr := S
  else
    FloatToStr := GeneralStr(Value, 15);
end;

function FloatToStrF(Value: Double; Format: TFloatFormat; Precision, Digits: Integer): String;
var
  S: String;
begin
  if SpecialFloat(Value, S) then
  begin
    FloatToStrF := S;
    Exit;
  end;
  case Format of
    ffGeneral:
      S := GeneralStr(Value, Precision);
    ffExponent:
      S := ExpStr(Value, Precision, Digits, True);
    ffFixed:
      S := FixedStr(Value, Digits, False);
    ffNumber:
      S := FixedStr(Value, Digits, True);
    ffCurrency:
      begin
        S := FixedStr(Abs(Value), Digits, True);
        S := CurrencyString + S;
        if (Value < 0) and (Pos('-', FixedStr(Value, Digits, False)) = 1) then
          S := '-' + S;
      end;
  end;
  FloatToStrF := S;
end;

{ FormatFloat: bagian dipisah ';' (positif;negatif;nol); 0 # , . dan % serta
  teks di antara tanda kutip; E+00 / E-00 untuk bentuk ilmiah. }
function FormatFloat(const Format: String; Value: Double): String;
var
  Secs: array[1..3] of String;
  NSec, K, Start: Integer;
  Quote: Char;
  Sec: String;
  Prefix, Suffix, Pat, S, IntP, FracP, ExpPat: String;
  I, J, IntZeros, FracZeros, FracMax: Integer;
  Thousands, Percent, Sci, Neg, Zero, SciPlus: Boolean;
  Digs, ES: String;
  E, P: Integer;
  Lit: String;
  C: Char;
begin
  { Pisahkan bagian di luar tanda kutip. }
  NSec := 1;
  Secs[1] := '';
  Quote := #0;
  for K := 1 to Length(Format) do
  begin
    C := Format[K];
    if Quote <> #0 then
    begin
      if C = Quote then
        Quote := #0;
      Secs[NSec] := Secs[NSec] + C;
    end
    else if (C = '''') or (C = '"') then
    begin
      Quote := C;
      Secs[NSec] := Secs[NSec] + C;
    end
    else if (C = ';') and (NSec < 3) then
    begin
      Inc(NSec);
      Secs[NSec] := '';
    end
    else
      Secs[NSec] := Secs[NSec] + C;
  end;
  Neg := Value < 0;
  Zero := Value = 0;
  if Zero and (NSec >= 3) then
  begin
    Sec := Secs[3];
    Neg := False;
  end
  else if Neg and (NSec >= 2) then
  begin
    Sec := Secs[2];
    Value := -Value;
    Neg := False;
  end
  else
    Sec := Secs[1];
  if Neg then
    Value := -Value;

  { Bagi bagian menjadi awalan, pola angka, dan akhiran. }
  Prefix := '';
  Suffix := '';
  Pat := '';
  IntZeros := 0;
  FracZeros := 0;
  FracMax := 0;
  Thousands := False;
  Percent := False;
  Sci := False;
  SciPlus := False;
  ExpPat := '';
  K := 1;
  Quote := #0;
  Start := 0;     { 0 = awalan, 1 = pola angka, 2 = akhiran }
  while K <= Length(Sec) do
  begin
    C := Sec[K];
    if Quote <> #0 then
    begin
      if C = Quote then
        Quote := #0
      else if Start = 0 then
        Prefix := Prefix + C
      else
        Suffix := Suffix + C;
    end
    else if (C = '''') or (C = '"') then
      Quote := C
    else if (Start < 2) and ((C = '0') or (C = '#') or (C = ',') or (C = '.')) then
    begin
      Start := 1;
      Pat := Pat + C;
    end
    else if (Start = 1) and ((C = 'E') or (C = 'e')) and (K < Length(Sec)) and
      ((Sec[K + 1] = '+') or (Sec[K + 1] = '-')) then
    begin
      Sci := True;
      SciPlus := Sec[K + 1] = '+';
      Inc(K, 2);
      while (K <= Length(Sec)) and (Sec[K] = '0') do
      begin
        ExpPat := ExpPat + '0';
        Inc(K);
      end;
      Dec(K);
      Start := 2;
    end
    else
    begin
      if Start = 1 then
        Start := 2;
      if C = '%' then
        Percent := True;
      if Start = 0 then
        Prefix := Prefix + C
      else
        Suffix := Suffix + C;
    end;
    Inc(K);
  end;

  { Pola angka: bagian bulat dan pecahan. }
  P := Pos('.', Pat);
  if P > 0 then
  begin
    IntP := Copy(Pat, 1, P - 1);
    FracP := Copy(Pat, P + 1, 255);
  end
  else
  begin
    IntP := Pat;
    FracP := '';
  end;
  for I := 1 to Length(IntP) do
  begin
    if IntP[I] = '0' then
      Inc(IntZeros)
    else if IntP[I] = ',' then
      Thousands := True;
  end;
  for I := 1 to Length(FracP) do
  begin
    if FracP[I] = '0' then
    begin
      Inc(FracMax);
      FracZeros := FracMax;
    end
    else if FracP[I] = '#' then
      Inc(FracMax);
  end;
  if Percent then
    Value := Value * 100;

  if Sci then
  begin
    { Mantisa punya IntZeros angka bulat (paling sedikit satu). }
    if IntZeros < 1 then
      IntZeros := 1;
    FloatDigits(Value, IntZeros + FracMax, Digs, E);
    if Value = 0 then
      E := 0;
    S := Copy(Digs, 1, IntZeros);
    FracP := Copy(Digs, IntZeros + 1, 255);
    J := Length(FracP);
    while (J > FracZeros) and (FracP[J] = '0') do
      Dec(J);
    FracP := Copy(FracP, 1, J);
    if FracP <> '' then
      S := S + DecimalSeparator + FracP;
    E := E - (IntZeros - 1);
    Str(Abs(E), ES);
    while Length(ES) < Length(ExpPat) do
      ES := '0' + ES;
    if E < 0 then
      S := S + 'E-' + ES
    else if SciPlus then
      S := S + 'E+' + ES
    else
      S := S + 'E' + ES;
  end
  else
  begin
    Str(Value:0:FracMax, S);
    P := Pos('.', S);
    if P > 0 then
    begin
      FracP := Copy(S, P + 1, 255);
      S := Copy(S, 1, P - 1);
    end
    else
      FracP := '';
    J := Length(FracP);
    while (J > FracZeros) and (FracP[J] = '0') do
      Dec(J);
    FracP := Copy(FracP, 1, J);
    { Bagian bulat: nol di depan hanya sebanyak pola '0'. }
    while (Length(S) > IntZeros) and (S[1] = '0') do
      S := Copy(S, 2, 255);
    while Length(S) < IntZeros do
      S := '0' + S;
    if S = '' then
      if FracP = '' then
        S := '0';
    if Thousands then
      S := Group(S);
    if FracP <> '' then
      S := S + DecimalSeparator + FracP;
  end;
  { Tanpa tanda minus bila semua angkanya nol. }
  if Neg then
  begin
    Neg := False;
    for I := 1 to Length(S) do
      if (S[I] >= '1') and (S[I] <= '9') then
        Neg := True;
  end;
  Lit := Prefix + S + Suffix;
  if Neg then
    Lit := '-' + Lit;
  FormatFloat := Lit;
end;

function BoolToStr(B: Boolean; UseBoolStrs: Boolean): String;
begin
  if UseBoolStrs then
  begin
    if B then
      BoolToStr := 'True'
    else
      BoolToStr := 'False';
  end
  else if B then
    BoolToStr := '-1'
  else
    BoolToStr := '0';
end;

function StrToBoolDef(const S: String; Default: Boolean): Boolean;
var
  T: String;
  V: Double;
begin
  T := UpperCase(Trim(S));
  if (T = 'TRUE') or (T = 'YES') or (T = 'T') or (T = 'Y') then
    StrToBoolDef := True
  else if (T = 'FALSE') or (T = 'NO') or (T = 'F') or (T = 'N') then
    StrToBoolDef := False
  else if TryStrToFloat(T, V) then
    StrToBoolDef := V <> 0
  else
    StrToBoolDef := Default;
end;

function StrToBool(const S: String): Boolean;
var
  T: String;
  V: Double;
begin
  T := UpperCase(Trim(S));
  if (T = 'TRUE') or (T = 'YES') or (T = 'T') or (T = 'Y') then
    StrToBool := True
  else if (T = 'FALSE') or (T = 'NO') or (T = 'F') or (T = 'N') then
    StrToBool := False
  else if TryStrToFloat(T, V) then
    StrToBool := V <> 0
  else
  begin
    ConvertError;
    StrToBool := False;
  end;
end;

{ ---- string --------------------------------------------------------------------------- }

function UpperCase(const S: String): String;
var
  R: String;
  I: Integer;
begin
  R := S;
  for I := 1 to Length(R) do
    R[I] := UpCase(R[I]);
  UpperCase := R;
end;

function LowerCase(const S: String): String;
var
  R: String;
  I: Integer;
begin
  R := S;
  for I := 1 to Length(R) do
    if (R[I] >= 'A') and (R[I] <= 'Z') then
      R[I] := Chr(Ord(R[I]) + 32);
  LowerCase := R;
end;

function AnsiUpperCase(const S: String): String;
begin
  AnsiUpperCase := UpperCase(S);
end;

function AnsiLowerCase(const S: String): String;
begin
  AnsiLowerCase := LowerCase(S);
end;

function TrimLeft(const S: String): String;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] <= ' ') do
    Inc(I);
  TrimLeft := Copy(S, I, 255);
end;

function TrimRight(const S: String): String;
var
  I: Integer;
begin
  I := Length(S);
  while (I >= 1) and (S[I] <= ' ') do
    Dec(I);
  TrimRight := Copy(S, 1, I);
end;

function Trim(const S: String): String;
begin
  Trim := TrimLeft(TrimRight(S));
end;

function StringOfChar(Ch: Char; Count: Integer): String;
var
  R: String;
  I: Integer;
begin
  R := '';
  if Count > 255 then
    Count := 255;
  for I := 1 to Count do
    R := R + Ch;
  StringOfChar := R;
end;

function CompareStr(const S1, S2: String): Integer;
var
  I, N: Integer;
begin
  N := Length(S1);
  if Length(S2) < N then
    N := Length(S2);
  for I := 1 to N do
    if S1[I] <> S2[I] then
    begin
      CompareStr := Ord(S1[I]) - Ord(S2[I]);
      Exit;
    end;
  CompareStr := Length(S1) - Length(S2);
end;

function CompareText(const S1, S2: String): Integer;
begin
  CompareText := CompareStr(UpperCase(S1), UpperCase(S2));
end;

function SameText(const S1, S2: String): Boolean;
begin
  SameText := CompareText(S1, S2) = 0;
end;

function AnsiCompareStr(const S1, S2: String): Integer;
begin
  AnsiCompareStr := CompareStr(S1, S2);
end;

function AnsiCompareText(const S1, S2: String): Integer;
begin
  AnsiCompareText := CompareText(S1, S2);
end;

function StringReplace(const S, OldPattern, NewPattern: String; Flags: TReplaceFlags): String;
var
  Src, Pat, R: String;
  I, N: Integer;
begin
  if OldPattern = '' then
  begin
    StringReplace := S;
    Exit;
  end;
  Src := S;
  Pat := OldPattern;
  if rfIgnoreCase in Flags then
  begin
    Src := UpperCase(Src);
    Pat := UpperCase(Pat);
  end;
  R := '';
  I := 1;
  N := Length(Pat);
  while I <= Length(S) do
  begin
    if Copy(Src, I, N) = Pat then
    begin
      R := R + NewPattern;
      Inc(I, N);
      if not (rfReplaceAll in Flags) then
      begin
        R := R + Copy(S, I, 255);
        I := Length(S) + 1;
      end;
    end
    else
    begin
      R := R + S[I];
      Inc(I);
    end;
  end;
  StringReplace := R;
end;

function QuotedStr(const S: String): String;
var
  R: String;
  I: Integer;
begin
  R := '''';
  for I := 1 to Length(S) do
  begin
    if S[I] = '''' then
      R := R + '''';
    R := R + S[I];
  end;
  QuotedStr := R + '''';
end;

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  CharInSet := C in CharSet;
end;

{ ---- berkas dan direktori -------------------------------------------------------------- }

function FileAttr(const Name: String; var Attr: Word): Boolean;
var
  F: File;
begin
  Attr := 0;
  FileAttr := False;
  if Name = '' then
    Exit;
  Assign(F, Name);
  GetFAttr(F, Attr);
  FileAttr := DosError = 0;
end;

function FileExists(const FileName: String): Boolean;
var
  A: Word;
begin
  FileExists := FileAttr(FileName, A) and (A and Directory = 0);
end;

function DirectoryExists(const Directory: String): Boolean;
var
  A: Word;
  D: String;
begin
  D := Directory;
{$IFDEF WINDOWS}
  if (Length(D) > 3) and ((D[Length(D)] = '\') or (D[Length(D)] = '/')) then
    D := Copy(D, 1, Length(D) - 1);
{$ENDIF}
  DirectoryExists := FileAttr(D, A) and (A and Dos.Directory <> 0);
end;

function DeleteFile(const FileName: String): Boolean;
var
  F: File;
begin
  Assign(F, FileName);
  Erase(F);
  DeleteFile := IOResult = 0;
end;

function RenameFile(const OldName, NewName: String): Boolean;
var
  F: File;
begin
  Assign(F, OldName);
  Rename(F, NewName);
  RenameFile := IOResult = 0;
end;

function CreateDir(const Dir: String): Boolean;
begin
  MkDir(Dir);
  CreateDir := IOResult = 0;
end;

function RemoveDir(const Dir: String): Boolean;
begin
  RmDir(Dir);
  RemoveDir := IOResult = 0;
end;

function IsDelim(C: Char): Boolean;
begin
{$IFDEF WINDOWS}
  IsDelim := (C = '\') or (C = '/') or (C = ':');
{$ELSE}
  IsDelim := C = '/';
{$ENDIF}
end;

function ForceDirectories(const Dir: String): Boolean;
var
  I: Integer;
  D: String;
begin
  D := ExcludeTrailingPathDelimiter(Dir);
  if D = '' then
  begin
    ForceDirectories := False;
    Exit;
  end;
  if DirectoryExists(D) then
  begin
    ForceDirectories := True;
    Exit;
  end;
  for I := 2 to Length(D) do
    if IsDelim(D[I]) and not IsDelim(D[I - 1]) and (D[I - 1] <> ':') then
      if not DirectoryExists(Copy(D, 1, I - 1)) then
        CreateDir(Copy(D, 1, I - 1));
  if not DirectoryExists(D) then
    CreateDir(D);
  ForceDirectories := DirectoryExists(D);
end;

function GetCurrentDir: String;
var
  S: String;
begin
  GetDir(0, S);
  GetCurrentDir := S;
end;

function SetCurrentDir(const Dir: String): Boolean;
begin
  ChDir(Dir);
  SetCurrentDir := IOResult = 0;
end;

function LastDelim(const S: String): Integer;
var
  I: Integer;
begin
  I := Length(S);
  while (I >= 1) and not IsDelim(S[I]) do
    Dec(I);
  LastDelim := I;
end;

function ExtractFileName(const FileName: String): String;
begin
  ExtractFileName := Copy(FileName, LastDelim(FileName) + 1, 255);
end;

function ExtractFilePath(const FileName: String): String;
begin
  ExtractFilePath := Copy(FileName, 1, LastDelim(FileName));
end;

function ExtractFileDir(const FileName: String): String;
var
  I: Integer;
begin
  I := LastDelim(FileName);
  { Pertahankan akar ('/' atau 'C:\'). }
  if (I > 1) and IsDelim(FileName[I]) and (FileName[I - 1] <> ':') then
    Dec(I);
  ExtractFileDir := Copy(FileName, 1, I);
end;

function ExtractFileExt(const FileName: String): String;
var
  I, D: Integer;
begin
  D := LastDelim(FileName);
  I := Length(FileName);
  while (I > D) and (FileName[I] <> '.') do
    Dec(I);
  if I > D then
    ExtractFileExt := Copy(FileName, I, 255)
  else
    ExtractFileExt := '';
end;

function ChangeFileExt(const FileName, Extension: String): String;
var
  I, D: Integer;
begin
  D := LastDelim(FileName);
  I := Length(FileName);
  while (I > D) and (FileName[I] <> '.') do
    Dec(I);
  if I <= D then
    I := Length(FileName) + 1;
  ChangeFileExt := Copy(FileName, 1, I - 1) + Extension;
end;

function ExpandFileName(const FileName: String): String;
begin
  ExpandFileName := FExpand(FileName);
end;

function IncludeTrailingPathDelimiter(const S: String): String;
begin
  if (S <> '') and IsDelim(S[Length(S)]) then
    IncludeTrailingPathDelimiter := S
  else
    IncludeTrailingPathDelimiter := S + PathDelim;
end;

function ExcludeTrailingPathDelimiter(const S: String): String;
var
  N: Integer;
begin
  N := Length(S);
  while (N > 1) and IsDelim(S[N]) and (S[N - 1] <> ':') do
    Dec(N);
  ExcludeTrailingPathDelimiter := Copy(S, 1, N);
end;

function GetEnvironmentVariable(const Name: String): String;
begin
  GetEnvironmentVariable := GetEnv(Name);
end;

{ ---- tanggal dan waktu ------------------------------------------------------------------- }

function IsLeapYear(Year: Word): Boolean;
begin
  IsLeapYear := (Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0));
end;

function DaysInAMonth(Year, Month: Word): Word;
const
  Days: array[1..12] of Byte = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  if (Month < 1) or (Month > 12) then
    DaysInAMonth := 0
  else if (Month = 2) and IsLeapYear(Year) then
    DaysInAMonth := 29
  else
    DaysInAMonth := Days[Month];
end;

{ Hari ke-n sejak 0001-01-01 (kalender Gregorian proleptik), hari pertama = 1. }
function DaysBefore(Year, Month, Day: LongInt): LongInt;
const
  Cum: array[1..12] of Integer = (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);
var
  Y, R: LongInt;
begin
  Y := Year - 1;
  R := Y * 365 + Y div 4 - Y div 100 + Y div 400 + Cum[Month] + Day;
  if (Month > 2) and IsLeapYear(Year) then
    R := R + 1;
  DaysBefore := R;
end;

function EncodeDate(Year, Month, Day: Word): TDateTime;
begin
  if (Year < 1) or (Year > 9999) or (Month < 1) or (Month > 12) or (Day < 1) or (Day > DaysInAMonth(Year, Month)) then
    RunError(106);
  EncodeDate := DaysBefore(Year, Month, Day) - DateDelta;
end;

function EncodeTime(Hour, Min, Sec, MSec: Word): TDateTime;
begin
  if (Hour > 23) or (Min > 59) or (Sec > 59) or (MSec > 999) then
    RunError(106);
  EncodeTime := (Hour * 3600000.0 + Min * 60000.0 + Sec * 1000.0 + MSec) / MSecsPerDay;
end;

procedure DecodeDate(Date: TDateTime; var Year, Month, Day: Word);
var
  T, Y, M, D: LongInt;
begin
  T := Trunc(Date);
  if Date < T then
    Dec(T);
  T := T + DateDelta;
  if T < 1 then
  begin
    Year := 0;
    Month := 0;
    Day := 0;
    Exit;
  end;
  { Perkirakan tahun, lalu koreksi. }
  Y := (T - 1) * 400 div 146097 + 1;
  while DaysBefore(Y + 1, 1, 1) <= T do
    Inc(Y);
  while DaysBefore(Y, 1, 1) > T do
    Dec(Y);
  D := T - DaysBefore(Y, 1, 1) + 1;
  M := 1;
  while (M < 12) and (D > DaysInAMonth(Y, M)) do
  begin
    D := D - DaysInAMonth(Y, M);
    Inc(M);
  end;
  Year := Y;
  Month := M;
  Day := D;
end;

procedure DecodeTime(Time: TDateTime; var Hour, Min, Sec, MSec: Word);
var
  T: Int64;
begin
  T := Round(Frac(Abs(Time)) * MSecsPerDay);
  if T >= MSecsPerDay then
    T := MSecsPerDay - 1;
  Hour := T div 3600000;
  Min := (T div 60000) mod 60;
  Sec := (T div 1000) mod 60;
  MSec := T mod 1000;
end;

function DayOfWeek(Date: TDateTime): Integer;
var
  T: LongInt;
begin
  T := Trunc(Date);
  if Date < T then
    Dec(T);
  DayOfWeek := ((T mod 7 + 7 + 6) mod 7) + 1;
end;

function IncMonth(Date: TDateTime; NumberOfMonths: Integer): TDateTime;
var
  Y, M, D: Word;
  Total, Last: LongInt;
begin
  DecodeDate(Date, Y, M, D);
  Total := Y * 12 + (M - 1) + NumberOfMonths;
  Y := Total div 12;
  M := Total mod 12 + 1;
  Last := DaysInAMonth(Y, M);
  if D > Last then
    D := Last;
  IncMonth := EncodeDate(Y, M, D) + Frac(Date);
end;

function Now: TDateTime;
var
  Y, M, D, W, H, N, S, S100: Word;
begin
  GetDate(Y, M, D, W);
  GetTime(H, N, S, S100);
  Now := EncodeDate(Y, M, D) + EncodeTime(H, N, S, S100 * 10);
end;

function Date: TDateTime;
begin
  Date := Int(Now);
end;

function Time: TDateTime;
begin
  Time := Frac(Now);
end;

function Pad(N: LongInt; Width: Integer): String;
var
  S: String;
begin
  Str(N, S);
  while Length(S) < Width do
    S := '0' + S;
  Pad := S;
end;

function FormatDateTime(const Format: String; DateTime: TDateTime): String;
var
  Y, Mo, D, H, N, S, Ms: Word;
  R, Fmt, Lit: String;
  I, Cnt: Integer;
  C: Char;
  Quote: Char;
  LastWasHour, NextIsSec: Boolean;
  H12: Word;
  K: Integer;
begin
  DecodeDate(DateTime, Y, Mo, D);
  DecodeTime(DateTime, H, N, S, Ms);
  Fmt := Format;
  if Fmt = '' then
    Fmt := 'c';
  R := '';
  I := 1;
  LastWasHour := False;
  while I <= Length(Fmt) do
  begin
    C := UpCase(Fmt[I]);
    Cnt := 1;
    if (Fmt[I] = '''') or (Fmt[I] = '"') then
    begin
      Quote := Fmt[I];
      Inc(I);
      while (I <= Length(Fmt)) and (Fmt[I] <> Quote) do
      begin
        R := R + Fmt[I];
        Inc(I);
      end;
      Inc(I);
      Continue;
    end;
    if C in ['Y', 'M', 'D', 'H', 'N', 'S', 'Z', 'T'] then
      while (I + Cnt <= Length(Fmt)) and (UpCase(Fmt[I + Cnt]) = C) do
        Inc(Cnt);
    case C of
      'Y':
        begin
          if Cnt <= 2 then
            R := R + Pad(Y mod 100, 2)
          else
            R := R + Pad(Y, 4);
          LastWasHour := False;
        end;
      'M':
        begin
          { m sesudah h, atau sebelum s, berarti menit. }
          K := I + Cnt;
          NextIsSec := (K <= Length(Fmt)) and (UpCase(Fmt[K]) = 'S');
          if LastWasHour or NextIsSec then
          begin
            if Cnt = 1 then
              R := R + Pad(N, 1)
            else
              R := R + Pad(N, 2);
          end
          else
            case Cnt of
              1: R := R + Pad(Mo, 1);
              2: R := R + Pad(Mo, 2);
              3: R := R + ShortMonthNames[Mo];
            else
              R := R + LongMonthNames[Mo];
            end;
          LastWasHour := False;
        end;
      'D':
        begin
          case Cnt of
            1: R := R + Pad(D, 1);
            2: R := R + Pad(D, 2);
            3: R := R + ShortDayNames[DayOfWeek(DateTime)];
            4: R := R + LongDayNames[DayOfWeek(DateTime)];
          else
            R := R + DateToStr(DateTime);
          end;
          LastWasHour := False;
        end;
      'H':
        begin
          H12 := H;
          { Jam 12-an bila ada penanda AM/PM di format. }
          if (Pos('AM/PM', UpperCase(Fmt)) > 0) or (Pos('A/P', UpperCase(Fmt)) > 0) or
            (Pos('AMPM', UpperCase(Fmt)) > 0) then
          begin
            H12 := H mod 12;
            if H12 = 0 then
              H12 := 12;
          end;
          if Cnt = 1 then
            R := R + Pad(H12, 1)
          else
            R := R + Pad(H12, 2);
          LastWasHour := True;
        end;
      'N':
        begin
          if Cnt = 1 then
            R := R + Pad(N, 1)
          else
            R := R + Pad(N, 2);
          LastWasHour := False;
        end;
      'S':
        begin
          if Cnt = 1 then
            R := R + Pad(S, 1)
          else
            R := R + Pad(S, 2);
          LastWasHour := False;
        end;
      'Z':
        begin
          if Cnt >= 3 then
            R := R + Pad(Ms, 3)
          else
            R := R + Pad(Ms, 1);
          LastWasHour := False;
        end;
      'A':
        begin
          if UpperCase(Copy(Fmt, I, 5)) = 'AM/PM' then
          begin
            if H < 12 then
              R := R + 'AM'
            else
              R := R + 'PM';
            Cnt := 5;
          end
          else if UpperCase(Copy(Fmt, I, 4)) = 'AMPM' then
          begin
            if H < 12 then
              R := R + TimeAMString
            else
              R := R + TimePMString;
            Cnt := 4;
          end
          else if UpperCase(Copy(Fmt, I, 3)) = 'A/P' then
          begin
            if H < 12 then
              R := R + 'a'
            else
              R := R + 'p';
            Cnt := 3;
          end
          else
            R := R + Fmt[I];
        end;
      'C':
        begin
          if (Frac(DateTime) = 0) or (Trunc(DateTime) <> 0) then
            R := R + FormatDateTime(ShortDateFormat, DateTime);
          if Frac(DateTime) <> 0 then
          begin
            if Trunc(DateTime) <> 0 then
              R := R + ' ';
            R := R + FormatDateTime(LongTimeFormat, DateTime);
          end;
        end;
      'T':
        begin
          if Cnt >= 2 then
            R := R + FormatDateTime(LongTimeFormat, DateTime)
          else
            R := R + FormatDateTime(ShortTimeFormat, DateTime);
        end;
      '/':
        R := R + DateSeparator;
      ':':
        R := R + TimeSeparator;
    else
      R := R + Fmt[I];
    end;
    Inc(I, Cnt);
  end;
  FormatDateTime := R;
end;

function DateToStr(Date: TDateTime): String;
begin
  DateToStr := FormatDateTime(ShortDateFormat, Date);
end;

function TimeToStr(Time: TDateTime): String;
begin
  TimeToStr := FormatDateTime(LongTimeFormat, Time);
end;

function DateTimeToStr(DateTime: TDateTime): String;
begin
  DateTimeToStr := FormatDateTime('c', DateTime);
end;

{ Memecah S menjadi bilangan-bilangan yang dipisah selain angka. N bilangan
  ditaruh di Parts; Seps menunjukkan jumlah pemisah. }
function SplitNumbers(const S: String; var Parts: array of LongInt): Integer;
var
  I, N: Integer;
  InNum: Boolean;
begin
  N := 0;
  InNum := False;
  for I := 1 to Length(S) do
    if (S[I] >= '0') and (S[I] <= '9') then
    begin
      if not InNum then
      begin
        if N > High(Parts) then
        begin
          SplitNumbers := -1;
          Exit;
        end;
        Parts[N] := 0;
        Inc(N);
        InNum := True;
      end;
      Parts[N - 1] := Parts[N - 1] * 10 + Ord(S[I]) - 48;
    end
    else
      InNum := False;
  SplitNumbers := N;
end;

function TryStrToDate(const S: String; var Value: TDateTime): Boolean;
var
  P: array[0..2] of LongInt;
  I, N, Pd, Pm, Py, Order: Integer;
  F: String;
  Y, Cur, Dummy1, Dummy2: Word;
begin
  TryStrToDate := False;
  N := SplitNumbers(S, P);
  if N <> 3 then
    Exit;
  { Urutan bagian menurut ShortDateFormat: d, m, y }
  Pd := -1;
  Pm := -1;
  Py := -1;
  Order := 0;
  F := LowerCase(ShortDateFormat);
  for I := 1 to Length(F) do
    if (F[I] = 'd') and (Pd < 0) then
    begin
      Pd := Order;
      Inc(Order);
    end
    else if (F[I] = 'm') and (Pm < 0) then
    begin
      Pm := Order;
      Inc(Order);
    end
    else if (F[I] = 'y') and (Py < 0) then
    begin
      Py := Order;
      Inc(Order);
    end;
  if (Pd < 0) or (Pm < 0) or (Py < 0) then
  begin
    Pd := 0;
    Pm := 1;
    Py := 2;
  end;
  Y := P[Py];
  if (Y < 100) and (Length(S) > 0) then
  begin
    DecodeDate(Now, Cur, Dummy1, Dummy2);
    Y := Y + (Cur div 100) * 100;
    if Y > Cur + 50 then
      Y := Y - 100;
  end;
  if (Y < 1) or (P[Pm] < 1) or (P[Pm] > 12) or (P[Pd] < 1) or (P[Pd] > DaysInAMonth(Y, P[Pm])) then
    Exit;
  Value := EncodeDate(Y, P[Pm], P[Pd]);
  TryStrToDate := True;
end;

function StrToDate(const S: String): TDateTime;
var
  V: TDateTime;
begin
  if not TryStrToDate(S, V) then
    ConvertError;
  StrToDate := V;
end;

function TryStrToTime(const S: String; var Value: TDateTime): Boolean;
var
  P: array[0..3] of LongInt;
  N: Integer;
  U: String;
  H: LongInt;
begin
  TryStrToTime := False;
  N := SplitNumbers(S, P);
  if (N < 2) or (N > 4) then
    Exit;
  if N < 3 then
    P[2] := 0;
  if N < 4 then
    P[3] := 0;
  H := P[0];
  U := UpperCase(S);
  if Pos('PM', U) > 0 then
  begin
    if H < 12 then
      H := H + 12;
  end
  else if (Pos('AM', U) > 0) and (H = 12) then
    H := 0;
  if (H > 23) or (P[1] > 59) or (P[2] > 59) or (P[3] > 999) then
    Exit;
  Value := EncodeTime(H, P[1], P[2], P[3]);
  TryStrToTime := True;
end;

function StrToTime(const S: String): TDateTime;
var
  V: TDateTime;
begin
  if not TryStrToTime(S, V) then
    ConvertError;
  StrToTime := V;
end;

{ "tanggal waktu": bagian tanggal dan waktu dipisah spasi. }
function StrToDateTime(const S: String): TDateTime;
var
  T: String;
  P: Integer;
  D, Tm: TDateTime;
begin
  T := Trim(S);
  P := Pos(' ', T);
  if P = 0 then
  begin
    if Pos(TimeSeparator, T) > 0 then
      StrToDateTime := StrToTime(T)
    else
      StrToDateTime := StrToDate(T);
    Exit;
  end;
  D := StrToDate(Copy(T, 1, P - 1));
  Tm := StrToTime(Copy(T, P + 1, 255));
  StrToDateTime := D + Tm;
end;

{ ---- waktu sistem ------------------------------------------------------------------------- }

procedure Sleep(Milliseconds: LongInt);
begin
  if Milliseconds <= 0 then
    Exit;
{$IFDEF WINDOWS}
  WinSleep(Milliseconds);
{$ELSE}
  while Milliseconds > 0 do
  begin
    if Milliseconds > 500 then
    begin
      c_usleep(500000);
      Milliseconds := Milliseconds - 500;
    end
    else
    begin
      c_usleep(Milliseconds * 1000);
      Milliseconds := 0;
    end;
  end;
{$ENDIF}
end;

function GetTickCount64: Int64;
{$IFNDEF WINDOWS}
var
  TV: TTimeVal;
{$ENDIF}
begin
{$IFDEF WINDOWS}
  GetTickCount64 := WinTickCount64;
{$ELSE}
  c_gettimeofday(TV, nil);
  GetTickCount64 := TV.Sec * 1000 + TV.USec div 1000;
{$ENDIF}
end;

function GetTickCount: Cardinal;
begin
  GetTickCount := GetTickCount64 and $FFFFFFFF;
end;

var
  K: Integer;

begin
  DecimalSeparator := '.';
  ThousandSeparator := ',';
  DateSeparator := '/';
  TimeSeparator := ':';
  ShortDateFormat := 'dd/mm/yyyy';
  LongDateFormat := 'dddd, d mmmm yyyy';
  ShortTimeFormat := 'hh:nn';
  LongTimeFormat := 'hh:nn:ss';
  CurrencyString := '$';
  TimeAMString := 'AM';
  TimePMString := 'PM';
  ShortMonthNames[1] := 'Jan';
  ShortMonthNames[2] := 'Feb';
  ShortMonthNames[3] := 'Mar';
  ShortMonthNames[4] := 'Apr';
  ShortMonthNames[5] := 'May';
  ShortMonthNames[6] := 'Jun';
  ShortMonthNames[7] := 'Jul';
  ShortMonthNames[8] := 'Aug';
  ShortMonthNames[9] := 'Sep';
  ShortMonthNames[10] := 'Oct';
  ShortMonthNames[11] := 'Nov';
  ShortMonthNames[12] := 'Dec';
  LongMonthNames[1] := 'January';
  LongMonthNames[2] := 'February';
  LongMonthNames[3] := 'March';
  LongMonthNames[4] := 'April';
  LongMonthNames[5] := 'May';
  LongMonthNames[6] := 'June';
  LongMonthNames[7] := 'July';
  LongMonthNames[8] := 'August';
  LongMonthNames[9] := 'September';
  LongMonthNames[10] := 'October';
  LongMonthNames[11] := 'November';
  LongMonthNames[12] := 'December';
  ShortDayNames[1] := 'Sun';
  ShortDayNames[2] := 'Mon';
  ShortDayNames[3] := 'Tue';
  ShortDayNames[4] := 'Wed';
  ShortDayNames[5] := 'Thu';
  ShortDayNames[6] := 'Fri';
  ShortDayNames[7] := 'Sat';
  LongDayNames[1] := 'Sunday';
  LongDayNames[2] := 'Monday';
  LongDayNames[3] := 'Tuesday';
  LongDayNames[4] := 'Wednesday';
  LongDayNames[5] := 'Thursday';
  LongDayNames[6] := 'Friday';
  LongDayNames[7] := 'Saturday';
  K := 0;
end.
