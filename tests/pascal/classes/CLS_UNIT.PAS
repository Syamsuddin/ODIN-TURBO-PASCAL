{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsUnit;
{ Classes from a unit (ZOO.PAS): descendants use protected members and
  override protected virtual methods; private state is reached through
  properties and the unit's own routines. }
uses Zoo;
type
  TBird = class(TAnimal)
  protected
    function Noise: String; override;
  public
    constructor Create(const AName: String);
  end;

constructor TBird.Create(const AName: String);
begin
  inherited Create(AName);
  FLegs := 2;
end;

function TBird.Noise: String;
begin
  Noise := 'tweet, not ' + inherited Noise;
end;

var
  A, B: TAnimal;
begin
  A := TAnimal.Create('cow');
  B := TBird.Create('robin');
  WriteLn(A.Describe);
  WriteLn(B.Describe);
  Rename(B, 'sparrow');
  WriteLn(B.Name, ' ', B.Id, ' ', TAnimal.Born, ' ', B is TBird);
  A.Free;
  B.Free;
end.
