{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsOverload;
{ Overloaded methods and constructors: the argument types pick the
  version (integer sizes, Real, Char and String, classes and their
  descendants, nil, no arguments); overloads inherited and extended in a
  descendant; inherited calls to an overloaded constructor. }
type
  TBase = class
    constructor Create; overload;
    constructor Create(N: Integer); overload;
    constructor Create(const S: String); overload;
  end;
  TPrinter = class
    procedure Show(B: Byte); overload;
    procedure Show(L: LongInt); overload;
    procedure Show(R: Real); overload;
    procedure Show(C: Char); overload;
    procedure Show(const S: String); overload;
    procedure Show(O: TObject); overload;
    procedure Show(B: TBase); overload;
    procedure Show; overload;
    procedure Show(A, B: Integer); overload;
  end;
  TBetter = class(TPrinter)
    procedure Show(Flag: Boolean); overload;
  end;
  TChild = class(TBase)
    constructor Create(N: Integer); overload;
  end;

constructor TBase.Create;
begin
  WriteLn('TBase.Create');
end;

constructor TBase.Create(N: Integer);
begin
  WriteLn('TBase.Create(', N, ')');
end;

constructor TBase.Create(const S: String);
begin
  WriteLn('TBase.Create(''', S, ''')');
end;

constructor TChild.Create(N: Integer);
begin
  inherited Create('child');
  inherited Create(N * 2);
  WriteLn('TChild.Create(', N, ')');
end;

procedure TPrinter.Show(B: Byte);
begin
  WriteLn('byte ', B);
end;

procedure TPrinter.Show(L: LongInt);
begin
  WriteLn('longint ', L);
end;

procedure TPrinter.Show(R: Real);
begin
  WriteLn('real ', R:0:2);
end;

procedure TPrinter.Show(C: Char);
begin
  WriteLn('char ', C);
end;

procedure TPrinter.Show(const S: String);
begin
  WriteLn('string ', S);
end;

procedure TPrinter.Show(O: TObject);
begin
  if O = nil then
    WriteLn('object nil')
  else
    WriteLn('object ', O.ClassName);
end;

procedure TPrinter.Show(B: TBase);
begin
  WriteLn('base ', B.ClassName);
end;

procedure TPrinter.Show;
begin
  WriteLn('nothing');
end;

procedure TPrinter.Show(A, B: Integer);
begin
  WriteLn('pair ', A, ' ', B);
end;

procedure TBetter.Show(Flag: Boolean);
begin
  WriteLn('boolean ', Flag);
end;

var
  P: TBetter;
  B: TBase;
  BB: Byte;
  W: Word;
  I64: Int64;
begin
  P := TBetter.Create;
  BB := 7;
  W := 1000;
  I64 := 5;
  P.Show(BB);
  P.Show(W);
  P.Show(100000);
  P.Show(2.5);
  P.Show('x');
  P.Show('text');
  P.Show(P);
  B := TChild.Create(3);
  P.Show(B);
  P.Show(TObject(B));
  P.Show;
  P.Show(1, 2);
  P.Show(True);
  P.Show(I64 * 1.0);
  B.Free;
  TBase.Create.Free;
  TBase.Create(1).Free;
  P.Free;
end.
