{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsTp7Names;
{ The class extension adds no reserved words: a TP7 program that uses its
  words as names (and declares its own TObject) still compiles and runs. }
type
  TObject = object
    Property: Integer;
    procedure Override(Dynamic: Integer);
  end;
  Strict = record
    Class, Published: Char;
  end;

procedure TObject.Override(Dynamic: Integer);
begin
  Property := Dynamic * 2;
end;

function Overload(Abstract: Integer): Integer;
begin
  Overload := Abstract + 1;
end;

var
  Is, As: Integer;
  O: TObject;
  S: Strict;
  Reintroduce: Boolean;
begin
  Is := 3;
  As := Is * 4;
  O.Override(As);
  S.Class := 'c';
  S.Published := 'p';
  Reintroduce := Is < As;
  WriteLn(Is, ' ', As, ' ', O.Property, ' ', S.Class, S.Published, ' ', Overload(Is), ' ', Reintroduce);
end.
