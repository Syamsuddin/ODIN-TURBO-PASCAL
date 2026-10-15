{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngProc;
{ Procedural types: variables, parameters, @, arrays and records of
  procedural values, typed constants, nil. }
{$F+}
type
  TIntOp = function(A, B: Integer): Integer;
  TRealFn = function(X: Real): Real;
  TShow = procedure(const S: String; N: Integer);
  TCounter = procedure(var C: LongInt);
  TStrFn = function(S: String): String;
  TNoArg = procedure;
  TOpRec = record
    Name: String[8];
    Op: TIntOp;
  end;

var
  Ops: array[1..4] of TIntOp;
  Recs: array[0..2] of TOpRec;
  F, F2: TIntOp;
  RF: TRealFn;
  Sh: TShow;
  Ct: TCounter;
  SF: TStrFn;
  NA: TNoArg;
  Cnt: LongInt;
  I: Integer;
  R: Real;
  Ptr: Pointer;

function Add(A, B: Integer): Integer; begin Add := A + B; end;
function Sub(A, B: Integer): Integer; begin Sub := A - B; end;
function Mul(A, B: Integer): Integer; begin Mul := A * B; end;
function MaxOf(A, B: Integer): Integer;
begin
  if A > B then MaxOf := A else MaxOf := B;
end;

function Half(X: Real): Real; begin Half := X / 2; end;
function Square(X: Real): Real; begin Square := X * X; end;
procedure Show(const S: String; N: Integer); begin WriteLn(S, '=', N); end;
procedure ShowBr(const S: String; N: Integer); begin WriteLn('[', S, '] ', N); end;
procedure Bump(var C: LongInt); begin C := C + 10; end;
procedure Twice(var C: LongInt); begin C := C * 2; end;

function Rev(S: String): String;
var
  K: Integer;
  T: String;
begin
  T := '';
  for K := Length(S) downto 1 do T := T + S[K];
  Rev := T;
end;

function Up(S: String): String;
var K: Integer;
begin
  for K := 1 to Length(S) do S[K] := UpCase(S[K]);
  Up := S;
end;

procedure Hello; begin Write('hello '); end;

const
  Table: array[1..3] of TIntOp = (Add, Sub, Mul);
  NoOp: TIntOp = nil;

function Fold(Op: TIntOp; const Data: array of Integer): Integer;
var
  K, Acc: Integer;
begin
  Acc := Data[0];
  for K := 1 to High(Data) do Acc := Op(Acc, Data[K]);
  Fold := Acc;
end;

function Apply2(G: TRealFn; X: Real): Real;
begin
  Apply2 := G(G(X));
end;

procedure Repeat3(Proc: TNoArg);
var K: Integer;
begin
  for K := 1 to 3 do Proc;
end;

function Compose(A, B: TStrFn; S: String): String;
begin
  Compose := A(B(S));
end;

const
  Data: array[1..5] of Integer = (3, 9, 4, 7, 5);

begin
  Ops[1] := Add; Ops[2] := Sub; Ops[3] := Mul; Ops[4] := MaxOf;
  for I := 1 to 4 do Write(Ops[I](12, 5), ' ');
  WriteLn;
  for I := 1 to 4 do Write(Fold(Ops[I], Data), ' ');
  WriteLn;
  WriteLn('fold add ', Fold(Add, Data), ' max ', Fold(MaxOf, Data));
  Recs[0].Name := 'plus'; Recs[0].Op := Add;
  Recs[1].Name := 'minus'; Recs[1].Op := Sub;
  Recs[2].Name := 'times'; Recs[2].Op := Mul;
  for I := 0 to 2 do WriteLn(Recs[I].Name, ' ', Recs[I].Op(7, 3));
  for I := 1 to 3 do Write(Table[I](10, 4), ' ');
  WriteLn;
  F := Sub;
  F2 := F;
  WriteLn('copy ', F2(1, 10));
  F := MaxOf;
  WriteLn('reassigned ', F(-3, -8), ' copy still ', F2(1, 10));
  RF := Half;
  R := Apply2(RF, 10);
  WriteLn('half twice ', R:0:3);
  R := Apply2(Square, 3);
  WriteLn('square twice ', R:0:1);
  Sh := Show; Sh('n', 5);
  Sh := ShowBr; Sh('m', 6);
  Cnt := 1;
  Ct := Bump; Ct(Cnt);
  Ct := Twice; Ct(Cnt); Ct(Cnt);
  WriteLn('counter ', Cnt);
  SF := Rev;
  WriteLn(SF('pascal'), ' ', Compose(Up, Rev, 'odin'), ' ', Compose(Rev, Rev, 'same'));
  NA := Hello;
  Repeat3(NA);
  Repeat3(Hello);
  WriteLn;
  F := Add;
  Ptr := @F;
  WriteLn('ptr=@Add ', Ptr = @Add, ' ', Ptr = @Sub);
  WriteLn('@F=@Add ', @F = @Add, ' @F=@Mul ', @F = @Mul);
  @F2 := @Mul;
  WriteLn('via @ ', F2(6, 7));
  WriteLn('assigned ', Assigned(F), ' ', Assigned(NoOp));
  F := nil;
  WriteLn('after nil ', Assigned(F), ' ', @F = nil);
  @F := Ptr;
  WriteLn('restored ', F(20, 22));
end.
