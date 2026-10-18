{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bagian unit System: laporan metrik untuk build --count-steps. Kode program
  yang diinstrumentasi menambah penghitung pernyataannya di larik milik
  compiler dan mengurangi ODIN_STEP_BUDGET; RTL membaca batas dari
  lingkungan, mencatat pemakaian heap, lalu menulis laporan ke
  $ODIN_STATS_FILE saat program berakhir. Angkanya sama di setiap OS dan CPU
  untuk sumber, masukan, dan versi odinpc yang sama. Variabel lingkungan dan
  bentuk laporan ada di rtl/COMPILER_INTERFACE.md. }

type
  PStatCounts = ^TStatCounts;
  TStatCounts = array[0..99999999] of Int64;

var
  { True after ODIN_STEPS_INIT: a step-counting build. }
  StatOn: Boolean;
  StatCounts: PStatCounts;
  StatPoints: LongInt;
  StatPath: PChar;
  { Bytes requested through ODIN_GETMEM and not yet freed, their maximum,
    and the limit (0: none). Sizes are the requested ones, never what the C
    library rounds them to, so they do not depend on the OS. }
  HeapNow, HeapPeak, HeapLimit: Int64;

procedure RunErrorAt(Code: LongInt; Addr: Pointer); forward;

{ The decimal number in environment variable Name, or Default when it is
  unset, empty, or not a plain non-negative number of at most 18 digits. }
function EnvNumber(Name: PChar; Default: Int64): Int64;
var
  P: PChar;
  V: Int64;
  Digits: LongInt;
begin
  EnvNumber := Default;
  P := c_getenv(Name);
  if P = nil then
    Exit;
  V := 0;
  Digits := 0;
  while P^ <> #0 do
  begin
    if (P^ < '0') or (P^ > '9') or (Digits >= 18) then
      Exit;
    V := V * 10 + (Ord(P^) - Ord('0'));
    Inc(Digits);
    Inc(P);
  end;
  if Digits > 0 then
    EnvNumber := V;
end;

procedure ODIN_STEPS_INIT(PointCount: LongInt; Counts: Pointer);
const
  StatsVar: array[0..15] of Char = 'ODIN_STATS_FILE'#0;
  StepVar: array[0..15] of Char = 'ODIN_STEP_LIMIT'#0;
  HeapVar: array[0..15] of Char = 'ODIN_HEAP_LIMIT'#0;
  DepthVar: array[0..16] of Char = 'ODIN_DEPTH_LIMIT'#0;
  SeedVar: array[0..13] of Char = 'ODIN_RANDSEED'#0;
begin
  StatOn := True;
  StatPoints := PointCount;
  StatCounts := PStatCounts(Counts);
  StatPath := c_getenv(@StatsVar);
  ODIN_STEP_BUDGET := EnvNumber(@StepVar, 0);
  if ODIN_STEP_BUDGET = 0 then
    ODIN_STEP_BUDGET := High(Int64);
  ODIN_STAT_DEPTHLIMIT := LongInt(EnvNumber(@DepthVar, 0));
  if ODIN_STAT_DEPTHLIMIT <= 0 then
    ODIN_STAT_DEPTHLIMIT := High(LongInt);
  HeapLimit := EnvNumber(@HeapVar, 0);
  { Randomize keeps this seed in step-counting builds, so runs repeat. }
  RandSeed := LongInt(EnvNumber(@SeedVar, 0));
end;

{ Move and FillChar of Bytes bytes, called from Addr: one step per 64 bytes,
  like a structured assignment in the compiled program, so that one call
  over a large buffer is not one step. }
procedure StatWeigh(Bytes: Int64; Addr: Pointer);
var
  Steps: Int64;
begin
  if not StatOn or (Bytes < 64) then
    Exit;
  Steps := Bytes div 64;
  ODIN_STEP_WEIGHT := ODIN_STEP_WEIGHT + Steps;
  ODIN_STEP_BUDGET := ODIN_STEP_BUDGET - Steps;
  if ODIN_STEP_BUDGET < 0 then
  begin
    ODIN_STEP_BUDGET := High(Int64);
    RunErrorAt(240, Addr);
  end;
end;

procedure StatsLine(Fd: LongInt; const Key: String; V: Int64);
var
  S: String;
begin
  IntToStr(V, S);
  S := Key + ' ' + S + #10;
  c_write(Fd, @S[1], Length(S));
end;

{ The report, written once by DoExit: a header line, one "key value" line
  per figure, then "p ID COUNT" for every statement id that ran. "steps" is
  the sum of the statement counts plus "weight", the steps charged for
  copying data. }
procedure StatsReport(Code: LongInt);
const
  Header: array[0..11] of Char = 'otp-stats 1'#10;
var
  Fd, I: LongInt;
  Total: Int64;
  S, T: String;
begin
  if not StatOn or (StatPath = nil) then
    Exit;
  Fd := c_open(StatPath, O_WRONLY or O_CREAT or O_TRUNC, 420);
  if Fd < 0 then
    Exit;
  Total := ODIN_STEP_WEIGHT;
  for I := 0 to StatPoints - 1 do
    Total := Total + StatCounts^[I];
  c_write(Fd, @Header, 12);
  StatsLine(Fd, 'exit', Code);
  StatsLine(Fd, 'steps', Total);
  StatsLine(Fd, 'weight', ODIN_STEP_WEIGHT);
  StatsLine(Fd, 'heap_peak', HeapPeak);
  StatsLine(Fd, 'heap_end', HeapNow);
  StatsLine(Fd, 'depth_max', ODIN_STAT_MAXDEPTH);
  StatsLine(Fd, 'points', StatPoints);
  for I := 0 to StatPoints - 1 do
    if StatCounts^[I] <> 0 then
    begin
      IntToStr(I, S);
      IntToStr(StatCounts^[I], T);
      S := 'p ' + S + ' ' + T + #10;
      c_write(Fd, @S[1], Length(S));
    end;
  c_close(Fd);
end;
