{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit Zoo;
{ Classes in a unit, for CLS_UNIT: private fields behind properties,
  protected members for descendants, a strict private field, a class
  variable set up by the unit's initialization. }
interface

type
  TAnimal = class
  strict private
    FId: Integer;
  private
    FName: String;
  protected
    FLegs: Integer;
    function Noise: String; virtual;
  public
    class var Born: Integer;
    constructor Create(const AName: String);
    function Describe: String;
    property Name: String read FName;
    property Id: Integer read FId;
  end;

procedure Rename(A: TAnimal; const NewName: String);

implementation

constructor TAnimal.Create(const AName: String);
begin
  Inc(Born);
  FId := Born;
  FName := AName;
  FLegs := 4;
end;

function TAnimal.Noise: String;
begin
  Noise := '...';
end;

function TAnimal.Describe: String;
var
  S, N: String;
begin
  Str(FLegs, S);
  Str(FId, N);
  Describe := '#' + N + ' ' + FName + ' (' + S + ' legs) ' + Noise;
end;

{ Private members are visible to the whole unit. }
procedure Rename(A: TAnimal; const NewName: String);
begin
  A.FName := NewName;
end;

begin
  TAnimal.Born := 100;
end.
