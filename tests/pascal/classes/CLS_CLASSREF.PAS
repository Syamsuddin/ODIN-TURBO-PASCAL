{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsClassRef;
{ Class references (class of), virtual constructors called through them,
  class methods (also virtual, and called on instances), class names as
  values, ClassParent chains, InheritsFrom, ClassNameIs, and is/as with a
  class reference on the right. }
type
  TAnimal = class;
  TAnimalClass = class of TAnimal;
  TAnimal = class
    Name: String;
    constructor Create; virtual;
    class function Sound: String; virtual;
    class function Make(const AName: String): TAnimal;
    function Speak: String;
  end;
  TDog = class(TAnimal)
    constructor Create; override;
    class function Sound: String; override;
  end;
  TPuppy = class(TDog)
    class function Sound: String; override;
  end;
  TCat = class(TAnimal)
    class function Sound: String; override;
  end;

constructor TAnimal.Create;
begin
  Name := 'animal';
end;

class function TAnimal.Sound: String;
begin
  Sound := '...';
end;

class function TAnimal.Make(const AName: String): TAnimal;
var
  A: TAnimal;
begin
  A := Create;
  A.Name := AName;
  Make := A;
end;

function TAnimal.Speak: String;
begin
  Speak := Name + ' (' + ClassName + ') says ' + Sound;
end;

constructor TDog.Create;
begin
  inherited Create;
  Name := 'dog';
end;

class function TDog.Sound: String;
begin
  Sound := 'woof';
end;

class function TPuppy.Sound: String;
begin
  Sound := 'yip ' + inherited Sound;
end;

class function TCat.Sound: String;
begin
  Sound := 'meow';
end;

procedure Chain(C: TClass);
begin
  while C <> nil do
  begin
    Write(C.ClassName, ' ');
    C := C.ClassParent;
  end;
  WriteLn;
end;

const
  Kinds: array[1..4] of String[10] = ('TAnimal', 'TDog', 'TPuppy', 'TCat');
var
  Classes: array[1..4] of TAnimalClass;
  C: TAnimalClass;
  A: TAnimal;
  O: TObject;
  I, J: Integer;
begin
  Classes[1] := TAnimal;
  Classes[2] := TDog;
  Classes[3] := TPuppy;
  Classes[4] := TCat;
  for I := 1 to 4 do
  begin
    A := Classes[I].Create;
    WriteLn(A.Speak);
    A.Free;
  end;
  for I := 1 to 4 do
    WriteLn(Classes[I].ClassName, ' ', Classes[I].Sound, ' ', Classes[I].InheritsFrom(TDog));
  A := TPuppy.Make('rex');
  WriteLn(A.Speak, ' / ', A.Sound, ' / ', TAnimal.Sound);
  Chain(A.ClassType);
  Chain(TCat);
  C := TDog;
  WriteLn(C = TDog, ' ', C = TPuppy, ' ', A.ClassType = TPuppy, ' ', A.ClassNameIs('tpuppy'));
  O := A;
  for I := 1 to 4 do
    Write(O is Classes[I], ' ');
  WriteLn;
  WriteLn((O as TDog).Name, ' ', (O as Classes[2]).Sound);
  for I := 1 to 4 do
    for J := 1 to 4 do
      if Classes[I].ClassNameIs(Kinds[J]) and (I <> J) then
        WriteLn('wrong name');
  A.Free;
end.
