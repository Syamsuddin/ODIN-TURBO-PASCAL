{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsProperty;
{ Properties read and written through fields and methods, read-only ones,
  array properties, the default array property, class variables, with
  statements on instances, and properties of class type in a chain. }
type
  TPerson = class
  private
    FName: String;
    FAge: Integer;
    FFriend: TPerson;
    procedure SetAge(Value: Integer);
    function GetAdult: Boolean;
  public
    class var Population: Integer;
    constructor Create(const AName: String; AAge: Integer);
    property Name: String read FName write FName;
    property Age: Integer read FAge write SetAge;
    property Adult: Boolean read GetAdult;
    property Friend: TPerson read FFriend write FFriend;
  end;

  TMatrix = class
  private
    FCells: array[1..3, 1..3] of Integer;
    FWrites: Integer;
    function GetCell(Row, Col: Integer): Integer;
    procedure SetCell(Row, Col: Integer; Value: Integer);
    function GetRow(Row: Integer): String;
  public
    property Cells[Row, Col: Integer]: Integer read GetCell write SetCell; default;
    property Rows[Row: Integer]: String read GetRow;
    property Writes: Integer read FWrites;
  end;

constructor TPerson.Create(const AName: String; AAge: Integer);
begin
  FName := AName;
  Age := AAge;
  Inc(Population);
end;

procedure TPerson.SetAge(Value: Integer);
begin
  if Value < 0 then
    Value := 0;
  FAge := Value;
end;

function TPerson.GetAdult: Boolean;
begin
  GetAdult := FAge >= 18;
end;

function TMatrix.GetCell(Row, Col: Integer): Integer;
begin
  GetCell := FCells[Row, Col];
end;

procedure TMatrix.SetCell(Row, Col: Integer; Value: Integer);
begin
  FCells[Row, Col] := Value;
  Inc(FWrites);
end;

function TMatrix.GetRow(Row: Integer): String;
var
  S, Part: String;
  C: Integer;
begin
  S := '';
  for C := 1 to 3 do
  begin
    Str(Self[Row, C]:3, Part);
    S := S + Part;
  end;
  GetRow := S;
end;

var
  P, Q: TPerson;
  M: TMatrix;
  R, C: Integer;
begin
  TPerson.Population := 0;
  P := TPerson.Create('Ani', 17);
  Q := TPerson.Create('Budi', -5);
  WriteLn(P.Name, ' ', P.Age, ' ', P.Adult, ' / ', Q.Name, ' ', Q.Age);
  P.Age := P.Age + 1;
  Q.Name := Q.Name + ' S.';
  WriteLn(P.Name, ' ', P.Age, ' ', P.Adult, ' / ', Q.Name);
  P.Friend := Q;
  Q.Friend := P;
  P.Friend.Age := 30;
  WriteLn('friend ', P.Friend.Name, ' ', Q.Age, ' ', P.Friend.Friend.Name);
  with P do
  begin
    Name := 'Ani W.';
    WriteLn('with ', Name, ' ', Age, ' ', Adult);
  end;
  WriteLn('population ', TPerson.Population, ' ', P.Population);
  M := TMatrix.Create;
  for R := 1 to 3 do
    for C := 1 to 3 do
      M[R, C] := R * 10 + C;
  M.Cells[2, 2] := -1;
  M[3, 3] := M[3, 3] + M.Cells[1, 1];
  for R := 1 to 3 do
    WriteLn(M.Rows[R]);
  WriteLn('writes ', M.Writes);
  M.Free;
  P.Free;
  Q.Free;
end.
