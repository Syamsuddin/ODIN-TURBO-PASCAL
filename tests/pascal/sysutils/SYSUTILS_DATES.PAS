{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit SysUtils: TDateTime, tanggal dan waktu. }
program SYSUTILS_DATES;

uses SysUtils;

var
  D: TDateTime;
  Y, M, Dd, H, N, S, Ms: Word;
  I: Integer;
begin
  WriteLn('EncodeDate: ', EncodeDate(1899, 12, 30):0:0, ' ', EncodeDate(1900, 1, 1):0:0, ' ', EncodeDate(2000, 1, 1):0:0,
    ' ', EncodeDate(2024, 2, 29):0:0, ' ', EncodeDate(1, 1, 1):0:0, ' ', EncodeDate(9999, 12, 31):0:0);
  D := EncodeDate(2024, 2, 29) + EncodeTime(13, 45, 30, 250);
  DecodeDate(D, Y, M, Dd);
  DecodeTime(D, H, N, S, Ms);
  WriteLn('DecodeDate/Time: ', Y, '-', M, '-', Dd, ' ', H, ':', N, ':', S, '.', Ms);
  DecodeDate(EncodeDate(1850, 6, 15), Y, M, Dd);
  WriteLn('Sebelum 1899: ', Y, '-', M, '-', Dd);
  DecodeDate(EncodeDate(1600, 3, 1), Y, M, Dd);
  WriteLn('1600: ', Y, '-', M, '-', Dd);
  WriteLn('Hari: ', DayOfWeek(EncodeDate(2024, 2, 25)), DayOfWeek(EncodeDate(2024, 2, 26)), DayOfWeek(EncodeDate(2024, 3, 2)),
    DayOfWeek(EncodeDate(1899, 12, 30)), DayOfWeek(EncodeDate(1899, 12, 31)), DayOfWeek(EncodeDate(1800, 1, 1)));
  WriteLn('IsLeapYear: ', IsLeapYear(1900), ' ', IsLeapYear(2000), ' ', IsLeapYear(2023), ' ', IsLeapYear(2024));
  Write('DaysInAMonth 2023: ');
  for I := 1 to 12 do
    Write(DaysInAMonth(2023, I), ' ');
  WriteLn(DaysInAMonth(2024, 2), ' ', DaysInAMonth(2023, 13));
  WriteLn('IncMonth: ', DateToStr(IncMonth(EncodeDate(2024, 1, 31), 1)), ' ', DateToStr(IncMonth(EncodeDate(2024, 3, 31), -1)),
    ' ', DateToStr(IncMonth(EncodeDate(2023, 11, 15), 3)), ' ', DateToStr(IncMonth(EncodeDate(2024, 2, 29), 12)));
  WriteLn('DateToStr: ', DateToStr(EncodeDate(2024, 12, 25)), ' TimeToStr: ', TimeToStr(EncodeTime(7, 5, 9, 0)));
  WriteLn('DateTimeToStr: ', DateTimeToStr(D), ' | ', DateTimeToStr(EncodeDate(2000, 1, 1)), ' | ',
    DateTimeToStr(EncodeTime(8, 30, 0, 0)));
  WriteLn(FormatDateTime('dddd, d mmmm yyyy hh:nn:ss', D));
  WriteLn(FormatDateTime('ddd dd/mm/yy h:n:s.zzz', D));
  WriteLn(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', D));
  WriteLn(FormatDateTime('hh:nn AM/PM', EncodeTime(15, 30, 0, 0)), ' ', FormatDateTime('h:nn AM/PM', EncodeTime(0, 5, 0, 0)),
    ' ', FormatDateTime('hh:nn a/p', EncodeTime(9, 0, 0, 0)));
  WriteLn(FormatDateTime('m/d/yyyy mmm', EncodeDate(2024, 7, 4)), ' ', FormatDateTime('mmmm', EncodeDate(2024, 12, 1)));
  WriteLn(FormatDateTime('t', D), ' ', FormatDateTime('tt', D));
  WriteLn('StrToDate: ', DateToStr(StrToDate('25/12/2023')), ' ', DateToStr(StrToDate('1-2-2024')), ' ',
    DateToStr(StrToDate('5.6.99')));
  WriteLn('StrToTime: ', TimeToStr(StrToTime('7:05')), ' ', TimeToStr(StrToTime('19:30:15')), ' ',
    TimeToStr(StrToTime('7:05 PM')), ' ', TimeToStr(StrToTime('12:00 AM')));
  WriteLn('StrToDateTime: ', DateTimeToStr(StrToDateTime('15/08/2024 10:20:30')));
  WriteLn('TryStrToDate: ', TryStrToDate('31/02/2024', D), ' ', TryStrToDate('x', D), ' ', TryStrToDate('1/1/2000', D));
  WriteLn('TryStrToTime: ', TryStrToTime('25:00', D), ' ', TryStrToTime('10:61', D), ' ', TryStrToTime('9:00', D));
  ShortDateFormat := 'yyyy-mm-dd';
  DateSeparator := '-';
  WriteLn('Format pemakai: ', DateToStr(EncodeDate(2024, 3, 9)), ' ', DateToStr(StrToDate('2024-3-9')));
  ShortMonthNames[3] := 'Mar';
  LongDayNames[1] := 'Minggu';
  WriteLn(FormatDateTime('dddd', EncodeDate(2024, 2, 25)));
  WriteLn('Sekarang: ', Date > EncodeDate(2020, 1, 1), ' ', Frac(Time) >= 0, ' ', Now >= Date);
  WriteLn('Tick: ', GetTickCount64 > 0, ' ', GetTickCount > 0);
  Sleep(10);
  Sleep(0);
end.
