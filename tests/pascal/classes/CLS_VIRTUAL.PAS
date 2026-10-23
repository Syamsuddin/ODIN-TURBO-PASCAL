{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsVirtual;
{ Virtual, override and abstract methods; inherited with and without a
  name; destructors running through the chain from Free; virtual calls
  from constructors and through TObject; static methods hidden by
  reintroduce; ToString overridden. }
type
  TShape = class
  private
    FName: String;
  public
    constructor Create(const AName: String);
    destructor Destroy; override;
    function Area: Real; virtual; abstract;
    function Describe: String; virtual;
    function ToString: String; override;
    procedure Hello;
  end;
  TRect = class(TShape)
    W, H: Real;
    constructor Create(AW, AH: Real);
    destructor Destroy; override;
    function Area: Real; override;
  end;
  TSquare = class(TRect)
    constructor Create(ASide: Real);
    function Describe: String; override;
    procedure Hello; reintroduce;
  end;
  TCircle = class(TShape)
    R: Real;
    constructor Create(AR: Real);
    function Area: Real; override;
    function Describe: String; override;
  end;

constructor TShape.Create(const AName: String);
begin
  inherited Create;
  FName := AName;
  WriteLn('  create ', FName, ' area ', Area:0:2);
end;

destructor TShape.Destroy;
begin
  WriteLn('  destroy ', FName);
  inherited;
end;

function TShape.Describe: String;
var
  S: String;
begin
  Str(Area:0:2, S);
  Describe := FName + ' with area ' + S;
end;

function TShape.ToString: String;
begin
  ToString := '<' + ClassName + ' ' + FName + '>';
end;

procedure TShape.Hello;
begin
  WriteLn('  hello from shape');
end;

constructor TRect.Create(AW, AH: Real);
begin
  W := AW;
  H := AH;
  inherited Create('rect');
end;

destructor TRect.Destroy;
begin
  WriteLn('  destroy rect part');
  inherited Destroy;
end;

function TRect.Area: Real;
begin
  Area := W * H;
end;

constructor TSquare.Create(ASide: Real);
begin
  inherited Create(ASide, ASide);
  FName := 'square';
end;

function TSquare.Describe: String;
begin
  Describe := 'a square: ' + inherited Describe;
end;

procedure TSquare.Hello;
begin
  WriteLn('  hello from square');
  inherited Hello;
end;

constructor TCircle.Create(AR: Real);
begin
  R := AR;
  inherited Create('circle');
end;

function TCircle.Area: Real;
begin
  Area := 3.14159 * R * R;
end;

function TCircle.Describe: String;
var
  S: String;
begin
  Str(R:0:1, S);
  Describe := inherited Describe + ' and radius ' + S;
end;

var
  Shapes: array[1..3] of TShape;
  O: TObject;
  Q: TSquare;
  Total: Real;
  I: Integer;
begin
  WriteLn('build');
  Shapes[1] := TRect.Create(2, 3);
  Shapes[2] := TSquare.Create(4);
  Shapes[3] := TCircle.Create(1);
  Total := 0;
  for I := 1 to 3 do
  begin
    WriteLn(Shapes[I].Describe);
    Total := Total + Shapes[I].Area;
  end;
  WriteLn('total ', Total:0:3);
  for I := 1 to 3 do
  begin
    O := Shapes[I];
    WriteLn(O.ToString);
  end;
  Shapes[2].Hello;
  Q := TSquare(Shapes[2]);
  Q.Hello;
  WriteLn('free');
  for I := 1 to 3 do
    Shapes[I].Free;
  Q := TSquare.Create(1);
  Q.Destroy;
end.
