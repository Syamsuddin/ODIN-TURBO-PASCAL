{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit SysUtils: konversi bilangan dan teks, rutin string. }
program SYSUTILS_CONV;

uses SysUtils;

var
  L: LongInt;
  I64: Int64;
  F: Double;
begin
  WriteLn('IntToStr: ', IntToStr(0), ' ', IntToStr(-42), ' ', IntToStr(123456789012));
  WriteLn('IntToHex: ', IntToHex(255, 0), ' ', IntToHex(255, 4), ' ', IntToHex(0, 1), ' ', IntToHex(4096, 2), ' ',
    IntToHex(-1, 0));
  WriteLn('StrToInt: ', StrToInt('123'), ' ', StrToInt(' -45 '), ' ', StrToInt('$FF'));
  WriteLn('StrToIntDef: ', StrToIntDef('x', 7), ' ', StrToIntDef('', 8), ' ', StrToIntDef('99999999999', 9), ' ',
    StrToIntDef('12', 0));
  WriteLn('TryStrToInt: ', TryStrToInt('77', L), ' ', L, ' ', TryStrToInt('7a', L), ' ', TryStrToInt('2147483648', L));
  WriteLn('StrToInt64: ', StrToInt64('9876543210'), ' ', StrToInt64Def('zz', -1), ' ', TryStrToInt64('-5', I64), ' ',
    I64);
  WriteLn('StrToFloat: ', StrToFloat('3.25'):0:3, ' ', StrToFloat(' -0.5 '):0:2, ' ', StrToFloat('1e3'):0:1);
  WriteLn('StrToFloatDef: ', StrToFloatDef('abc', 1.5):0:2, ' ', TryStrToFloat('2.5', F), ' ', F:0:1, ' ',
    TryStrToFloat('', F));
  WriteLn('FloatToStr: ', FloatToStr(1234.5), ' ', FloatToStr(0.1), ' ', FloatToStr(-2.5), ' ', FloatToStr(0), ' ',
    FloatToStr(100));
  WriteLn('FloatToStr: ', FloatToStr(1e20), ' ', FloatToStr(0.00001), ' ', FloatToStr(0.0001), ' ', FloatToStr(1/3));
  WriteLn('FloatToStr: ', FloatToStr(123456789012345.0), ' ', FloatToStr(1e15), ' ', FloatToStr(1.5e-7));
  WriteLn('FloatToStrF: ', FloatToStrF(1234.567, ffFixed, 15, 2), ' ', FloatToStrF(1234567.891, ffNumber, 15, 2), ' ',
    FloatToStrF(-1234.5, ffNumber, 15, 0));
  WriteLn('FloatToStrF: ', FloatToStrF(1234.5, ffExponent, 5, 2), ' ', FloatToStrF(0.000123, ffExponent, 3, 3), ' ',
    FloatToStrF(1234.5, ffCurrency, 15, 2), ' ', FloatToStrF(1234.5, ffGeneral, 3, 0));
  WriteLn('FormatFloat: ', FormatFloat('0.00', 3.14159), ' ', FormatFloat('#,##0.00', 1234567.891), ' ',
    FormatFloat('0.###', 2.5), ' ', FormatFloat('00', 5), ' ', FormatFloat('0.0%', 0.256));
  WriteLn('FormatFloat: ', FormatFloat('0.00;(0.00)', -3.5), ' ', FormatFloat('0.00E+00', 12345.678), ' ',
    FormatFloat('"Rp "#,##0', 1500000), ' ', FormatFloat('0.00', -0.001), ' ', FormatFloat('000.0', 5.25));
  WriteLn('BoolToStr: ', BoolToStr(True, True), ' ', BoolToStr(False, True), ' ', BoolToStr(True, False), ' ',
    BoolToStr(False, False));
  WriteLn('StrToBool: ', StrToBool('true'), ' ', StrToBool('No'), ' ', StrToBool('1'), ' ', StrToBoolDef('?', True));
  WriteLn('Case: ', UpperCase('abc xyz 123'), ' ', LowerCase('ABC Xyz'));
  WriteLn('Trim: [', Trim('  hi there  '), '] [', TrimLeft('  x '), '] [', TrimRight(' x  '), '] [', Trim('   '), ']');
  WriteLn('StringOfChar: ', StringOfChar('*', 5), ' ', StringOfChar('a', 0), '|');
  WriteLn('Compare: ', CompareStr('a', 'b'), ' ', CompareStr('b', 'a'), ' ', CompareStr('abc', 'abc'), ' ',
    CompareStr('abc', 'ab'), ' ', CompareText('ABC', 'abc'), ' ', SameText('Abc', 'aBC'), ' ', SameText('a', 'b'));
  WriteLn('StringReplace: ', StringReplace('a-b-c', '-', '+', [rfReplaceAll]), ' ',
    StringReplace('a-b-c', '-', '+', []), ' ', StringReplace('A-b-C', 'b', 'X', [rfIgnoreCase]), ' ',
    StringReplace('aaa', 'a', 'bb', [rfReplaceAll]), ' ', StringReplace('abc', '', 'x', [rfReplaceAll]));
  WriteLn('QuotedStr: ', QuotedStr('it''s'), ' ', QuotedStr(''));
  WriteLn('CharInSet: ', CharInSet('a', ['a'..'z']), ' ', CharInSet('A', ['a'..'z']));
  WriteLn('LineEnding: ', Length(LineEnding) > 0);
  WriteLn('Format desimal: ', DecimalSeparator, ThousandSeparator);
  DecimalSeparator := ',';
  ThousandSeparator := '.';
  WriteLn('Pemisah Indonesia: ', FloatToStr(1234.5), ' ', FormatFloat('#,##0.00', 1234567.891), ' ', StrToFloat('2,5'):0:1);
  DecimalSeparator := '.';
  ThousandSeparator := ',';
end.
