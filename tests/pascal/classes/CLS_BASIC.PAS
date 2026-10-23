{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsBasic;
{ Classes are references: Create allocates a zeroed instance, assignment
  copies the reference, Free calls the destructor and frees the memory
  (nil is fine). Also Self, class names, sizes, comparisons, typecasts,
  classes in arrays and records, var parameters and function results. }
type
  TCounter = class
    Count: Integer;
    Name: String[20];
    Ready: Boolean;
    constructor Create(const AName: String);
    procedure Tick;
    function Twice: TCounter;
    function IsSame(Other: TCounter): Boolean;
  end;
  THolder = record
    Tag: Char;
    Item: TCounter;
  end;

constructor TCounter.Create(const AName: String);
begin
  inherited Create;
  Name := AName;
end;

procedure TCounter.Tick;
begin
  Count := Count + 1;
end;

function TCounter.Twice: TCounter;
begin
  Tick;
  Self.Tick;
  Twice := Self;
end;

function TCounter.IsSame(Other: TCounter): Boolean;
begin
  IsSame := Other = Self;
end;

procedure Swap(var A, B: TCounter);
var
  T: TCounter;
begin
  T := A;
  A := B;
  B := T;
end;

function Make(const N: String; Ticks: Integer): TCounter;
var
  I: Integer;
  C: TCounter;
begin
  C := TCounter.Create(N);
  for I := 1 to Ticks do
    C.Tick;
  Make := C;
end;

var
  A, B, C: TCounter;
  List: array[1..3] of TCounter;
  H: THolder;
  O: TObject;
  I: Integer;
begin
  A := TCounter.Create('a');
  WriteLn('fresh ', A.Count, ' ', A.Ready, ' [', A.Name, ']');
  A.Tick;
  A.Twice.Twice.Tick;
  WriteLn('ticks ', A.Count);
  B := A;
  B.Tick;
  WriteLn('alias ', A.Count, ' ', A = B, ' ', A.IsSame(B));
  C := Make('c', 3);
  Swap(A, C);
  WriteLn('swapped ', A.Name, ' ', A.Count, ' ', C.Name, ' ', C.Count);
  WriteLn('class ', A.ClassName, ' ', TCounter.ClassName, ' ', A.ClassParent.ClassName);
  WriteLn('size ', SizeOf(A), ' ', A.InstanceSize, ' ', TObject.InstanceSize);
  WriteLn('nil ', Assigned(A), ' ', A <> nil, ' ', A = nil);
  for I := 1 to 3 do
    List[I] := Make(Chr(Ord('x') + I - 1), I * 2);
  for I := 1 to 3 do
    Write(List[I].Name, '=', List[I].Count, ' ');
  WriteLn;
  H.Tag := 'h';
  H.Item := List[2];
  H.Item.Tick;
  WriteLn('record ', H.Tag, ' ', H.Item.Name, ' ', List[2].Count);
  O := A;
  WriteLn('object ', O.ClassName, ' ', TCounter(O).Count, ' ', O.ToString);
  WriteLn('pointer ', Pointer(A) = Pointer(O));
  A.Free;
  C.Free;
  for I := 1 to 3 do
    List[I].Free;
  A := nil;
  A.Free;
  WriteLn('done');
end.
