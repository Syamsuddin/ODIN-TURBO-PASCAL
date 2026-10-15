{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
unit Shapes;
{ Object type in a unit: private fields are visible in this unit only. }
interface

type
  PCounter = ^TCounter;
  TCounter = object
    constructor Init(AStep: Integer);
    procedure Tick; virtual;
    function Value: Integer;
  private
    Count, Step: Integer;
    procedure Bump;
  end;
  TDouble = object(TCounter)
    procedure Tick; virtual;
  end;

implementation

constructor TCounter.Init(AStep: Integer);
begin
  Count := 0;
  Step := AStep;
end;

procedure TCounter.Bump;
begin
  Count := Count + Step;
end;

procedure TCounter.Tick;
begin
  Bump;
end;

function TCounter.Value: Integer;
begin
  Value := Count;
end;

procedure TDouble.Tick;
begin
  Bump;
  Bump;
end;

end.
