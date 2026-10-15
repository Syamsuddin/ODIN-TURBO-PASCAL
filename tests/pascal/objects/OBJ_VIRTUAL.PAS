{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjVirtual;
{ Virtual methods: dispatch through pointers and var parameters of the
  ancestor type, inherited calls, virtual calls from inside methods and
  constructors, TypeOf. }
type
  PShape = ^TShape;
  TShape = object
    Name: string[10];
    constructor Init(const AName: String);
    function Area: Real; virtual;
    procedure Describe; virtual;
    procedure Report;
  end;
  PRect = ^TRect;
  TRect = object(TShape)
    W, H: Real;
    constructor Init(AW, AH: Real);
    function Area: Real; virtual;
  end;
  PSquare = ^TSquare;
  TSquare = object(TRect)
    constructor Init(S: Real);
    procedure Describe; virtual;
  end;
  PCircle = ^TCircle;
  TCircle = object(TShape)
    R: Real;
    constructor Init(AR: Real);
    function Area: Real; virtual;
    procedure Describe; virtual;
  end;

constructor TShape.Init(const AName: String);
begin
  Name := AName;
  WriteLn('init ', Name, ' area now ', Area:0:2);
end;

function TShape.Area: Real;
begin
  Area := 0;
end;

procedure TShape.Describe;
begin
  WriteLn(Name, ': area ', Area:0:2);
end;

procedure TShape.Report;
begin
  Write('[report] ');
  Describe;
end;

constructor TRect.Init(AW, AH: Real);
begin
  W := AW;
  H := AH;
  inherited Init('rect');
end;

function TRect.Area: Real;
begin
  Area := W * H;
end;

constructor TSquare.Init(S: Real);
begin
  TRect.Init(S, S);
  Name := 'square';
end;

procedure TSquare.Describe;
begin
  Write('a square! ');
  inherited Describe;
end;

constructor TCircle.Init(AR: Real);
begin
  R := AR;
  inherited Init('circle');
end;

function TCircle.Area: Real;
begin
  Area := 3.14159 * R * R;
end;

procedure TCircle.Describe;
begin
  WriteLn('circle with radius ', R:0:1, ' and area ', Area:0:3);
end;

procedure Show(var S: TShape);
begin
  S.Describe;
end;

var
  Shapes: array[1..4] of PShape;
  I: Integer;
  Total: Real;
  Sq: TSquare;
begin
  Shapes[1] := New(PRect, Init(2, 3));
  Shapes[2] := New(PSquare, Init(4));
  Shapes[3] := New(PCircle, Init(1));
  New(Shapes[4], Init('plain'));
  Total := 0;
  for I := 1 to 4 do
  begin
    Shapes[I]^.Report;
    Total := Total + Shapes[I]^.Area;
  end;
  WriteLn('total ', Total:0:3);
  Sq.Init(5);
  Show(Sq);
  WriteLn('typeof ', TypeOf(Sq) = TypeOf(TSquare), ' ', TypeOf(Shapes[2]^) = TypeOf(TSquare),
    ' ', TypeOf(Shapes[1]^) = TypeOf(TSquare), ' ', TypeOf(TRect) = TypeOf(TShape));
  for I := 1 to 4 do
    Dispose(Shapes[I]);
end.
