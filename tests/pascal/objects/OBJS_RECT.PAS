{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjsRect;
{ Unit Objects: TPoint and TRect. }
uses Objects;
var
  R, S: TRect;
  P: TPoint;

procedure Show(const Name: String; const T: TRect);
begin
  WriteLn(Name, ': (', T.A.X, ',', T.A.Y, ')-(', T.B.X, ',', T.B.Y, ') empty ', T.Empty);
end;

begin
  R.Assign(2, 3, 12, 8);
  Show('assign', R);
  S.Copy(R);
  S.Move(5, -1);
  Show('moved copy', S);
  WriteLn('equals ', R.Equals(S), ' ', S.Equals(S));
  S.Intersect(R);
  Show('intersect', S);
  S.Assign(0, 0, 4, 4);
  S.Union(R);
  Show('union', S);
  R.Grow(-2, -1);
  Show('shrunk', R);
  R.Grow(-10, 0);
  Show('collapsed', R);
  R.Assign(0, 0, 3, 3);
  P.X := 2;
  P.Y := 2;
  Write('contains (2,2) ', R.Contains(P));
  P.X := 3;
  WriteLn(' (3,2) ', R.Contains(P));
  S.Assign(5, 5, 9, 9);
  R.Intersect(S);
  Show('disjoint', R);
  WriteLn('sizes ', SizeOf(TPoint), ' ', SizeOf(TRect), ' ', SizeOf(TObject), ' ', SizeOf(TCollection),
    ' ', SizeOf(TSortedCollection), ' ', SizeOf(TStream), ' ', SizeOf(TStreamRec));
end.
