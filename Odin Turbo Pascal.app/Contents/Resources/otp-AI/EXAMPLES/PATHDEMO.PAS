program PathDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AISearch;
var G: TGrid; R: TSearchResult; Method,Row: Integer;
{$I COMMON.INC}
begin
  Need(InitGrid(6,6,G));
  for Row:=1 to 5 do if Row<>4 then Need(SetWall(G,Row,3,True));
  for Method:=SearchBFS to SearchAStar do begin
    Need(SearchGrid(G,1,36,Method,R));
    WriteLn('Metode ',Method,': found=',R.Found,' cost=',R.Cost,' expanded=',R.Expanded);
    PrintGrid(G,R,1,36); WriteLn
  end
end.
