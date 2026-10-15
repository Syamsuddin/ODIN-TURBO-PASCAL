{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjLayout;
{ Object layout: inherited fields first, the VMT pointer after the fields of
  the first type that needs one (constructor, destructor or virtual method),
  natural alignment. Static methods, Self, with, and method calls inside
  methods. }
type
  TPlain = object
    A: Byte;
    B: LongInt;
    procedure Show;
    function Sum: LongInt;
  end;
  TMore = object(TPlain)
    C: Word;
    procedure Show;
    procedure Twice;
  end;
  TLater = object(TMore)
    D: Byte;
    procedure V; virtual;
  end;
  TCtorOnly = object
    E: Char;
    constructor Init;
  end;
  TEmpty = object
    procedure Hello;
  end;

procedure TPlain.Show;
begin
  WriteLn('plain A=', A, ' B=', Self.B, ' sum=', Sum);
end;

function TPlain.Sum: LongInt;
begin
  Sum := A + B;
end;

procedure TMore.Show;
begin
  Write('more C=', C, ' / ');
  TPlain.Show;
end;

procedure TMore.Twice;
begin
  Show;
  with Self do
    WriteLn('with: ', A, ' ', B, ' ', C);
end;

procedure TLater.V;
begin
end;

constructor TCtorOnly.Init;
begin
  E := 'e';
end;

procedure TEmpty.Hello;
begin
  WriteLn('empty object, size ', SizeOf(Self));
end;

var
  P: TPlain;
  M: TMore;
  L: TLater;
  K: TCtorOnly;
  Z: TEmpty;
begin
  WriteLn('sizes ', SizeOf(TPlain), ' ', SizeOf(TMore), ' ', SizeOf(TLater), ' ', SizeOf(TCtorOnly), ' ', SizeOf(TEmpty));
  WriteLn('TLater A=', PtrUInt(@L.A) - PtrUInt(@L), ' B=', PtrUInt(@L.B) - PtrUInt(@L),
    ' C=', PtrUInt(@L.C) - PtrUInt(@L), ' D=', PtrUInt(@L.D) - PtrUInt(@L));
  P.A := 1;
  P.B := 2;
  P.Show;
  M.A := 3;
  M.B := 4;
  M.C := 5;
  M.Show;
  M.Twice;
  with M do
  begin
    C := 6;
    Show;
  end;
  K.Init;
  WriteLn('K.E=', K.E);
  Z.Hello;
end.
