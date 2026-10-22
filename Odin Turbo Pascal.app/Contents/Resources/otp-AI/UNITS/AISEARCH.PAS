unit AISearch;
interface
uses AITypes;
const MaxGridSide=16; MaxGridCells=256;
      SearchBFS=1; SearchDFS=2; SearchAStar=3;
type
  TGrid = record
    Rows,Cols: Integer;
    Blocked: array[1..MaxGridSide,1..MaxGridSide] of Boolean;
  end;
  TGridPath = array[1..MaxGridCells] of Integer;
  TSearchResult = record
    Found: Boolean;
    Count,Cost,Expanded: Integer;
    Cells: TGridPath;
  end;
function InitGrid(Rows,Cols: Integer; var G: TGrid): Boolean;
function CheckGrid(var G: TGrid): Boolean;
function CellID(var G: TGrid; Row,Col: Integer): Integer;
function CellPosition(var G: TGrid; ID: Integer; var Row,Col: Integer): Boolean;
function SetWall(var G: TGrid; Row,Col: Integer; Blocked: Boolean): Boolean;
function GridNeighbor(var G: TGrid; State,Action: Integer;
  var NextState: Integer): Boolean;
function SearchGrid(var G: TGrid; Start,Goal,Method: Integer;
  var Result: TSearchResult): Boolean;
procedure PrintGrid(var G: TGrid; var Result: TSearchResult; Start,Goal: Integer);
implementation
function CheckGrid(var G: TGrid): Boolean;
begin
  ClearAIError; CheckGrid:=False;
  if (G.Rows<1) or (G.Rows>MaxGridSide) or (G.Cols<1) or
     (G.Cols>MaxGridSide) then begin SetAIError(ErrSize,'Grid harus 1..16 x 1..16'); Exit end;
  CheckGrid:=True
end;
function InitGrid(Rows,Cols: Integer; var G: TGrid): Boolean;
begin
  FillChar(G,SizeOf(G),0); G.Rows:=Rows; G.Cols:=Cols; InitGrid:=CheckGrid(G)
end;
function CellID(var G: TGrid; Row,Col: Integer): Integer;
begin
  CellID:=0;
  if not CheckGrid(G) then Exit;
  if (Row<1) or (Row>G.Rows) or (Col<1) or (Col>G.Cols) then begin
    SetAIError(ErrSize,'Posisi di luar grid'); Exit
  end;
  CellID:=(Row-1)*G.Cols+Col
end;
function CellPosition(var G: TGrid; ID: Integer; var Row,Col: Integer): Boolean;
begin
  Row:=0; Col:=0; CellPosition:=False;
  if not CheckGrid(G) then Exit;
  if (ID<1) or (ID>G.Rows*G.Cols) then begin SetAIError(ErrSize,'ID sel di luar grid'); Exit end;
  Row:=(ID-1) div G.Cols+1; Col:=(ID-1) mod G.Cols+1; CellPosition:=True
end;
function SetWall(var G: TGrid; Row,Col: Integer; Blocked: Boolean): Boolean;
begin
  SetWall:=False;
  if CellID(G,Row,Col)=0 then Exit;
  G.Blocked[Row,Col]:=Blocked; SetWall:=True
end;
function GridNeighbor(var G: TGrid; State,Action: Integer;
  var NextState: Integer): Boolean;
var R,C: Integer;
begin
  NextState:=State; GridNeighbor:=False;
  if not CellPosition(G,State,R,C) then Exit;
  if G.Blocked[R,C] then begin SetAIError(ErrValue,'State berada pada dinding'); Exit end;
  case Action of
    1: Dec(R); 2: Inc(C); 3: Inc(R); 4: Dec(C);
    else begin SetAIError(ErrValue,'Aksi harus 1=atas,2=kanan,3=bawah,4=kiri'); Exit end
  end;
  if (R>=1) and (R<=G.Rows) and (C>=1) and (C<=G.Cols) then
    if not G.Blocked[R,C] then NextState:=(R-1)*G.Cols+C;
  GridNeighbor:=True
end;
function SearchGrid(var G: TGrid; Start,Goal,Method: Integer;
  var Result: TSearchResult): Boolean;
var Parent,Dist,Queue: TGridPath;
    State: array[1..MaxGridCells] of Byte;
    N,I,R,C,GR,GC,Head,Tail,Current,Next,A,BestF,F,T: Integer;
begin
  FillChar(Result,SizeOf(Result),0); SearchGrid:=False;
  if not CellPosition(G,Start,R,C) then Exit;
  if G.Blocked[R,C] then begin SetAIError(ErrValue,'Start berada pada dinding'); Exit end;
  if not CellPosition(G,Goal,GR,GC) then Exit;
  if G.Blocked[GR,GC] then begin SetAIError(ErrValue,'Goal berada pada dinding'); Exit end;
  if (Method<SearchBFS) or (Method>SearchAStar) then begin SetAIError(ErrValue,'Metode search tidak dikenal'); Exit end;
  N:=G.Rows*G.Cols; FillChar(Parent,SizeOf(Parent),0);
  FillChar(Dist,SizeOf(Dist),0); FillChar(State,SizeOf(State),0);
  Head:=1; Tail:=1; Queue[1]:=Start; State[Start]:=1;
  repeat
    Current:=0;
    if Method=SearchAStar then begin
      BestF:=32767;
      for I:=1 to N do if State[I]=1 then begin
        R:=(I-1) div G.Cols+1; C:=(I-1) mod G.Cols+1;
        F:=Dist[I]+Abs(R-GR)+Abs(C-GC);
        if F<BestF then begin BestF:=F; Current:=I end
      end
    end else if Method=SearchBFS then begin
      if Head<=Tail then begin Current:=Queue[Head]; Inc(Head) end
    end else if Tail>0 then begin Current:=Queue[Tail]; Dec(Tail) end;
    if Current=0 then Break;
    State[Current]:=2; Inc(Result.Expanded);
    if Current=Goal then begin
      Result.Found:=True; Result.Cost:=Dist[Goal]; I:=Goal;
      while I<>0 do begin Inc(Result.Count); Result.Cells[Result.Count]:=I; I:=Parent[I] end;
      for I:=1 to Result.Count div 2 do begin
        T:=Result.Cells[I]; Result.Cells[I]:=Result.Cells[Result.Count-I+1];
        Result.Cells[Result.Count-I+1]:=T
      end;
      Break
    end;
    for A:=1 to 4 do begin
      if not GridNeighbor(G,Current,A,Next) then Exit;
      if Next<>Current then begin
        if State[Next]=0 then begin
          Parent[Next]:=Current; Dist[Next]:=Dist[Current]+1; State[Next]:=1;
          if Method<>SearchAStar then begin Inc(Tail); Queue[Tail]:=Next end
        end else if (Method=SearchAStar) and (State[Next]=1) and
                    (Dist[Current]+1<Dist[Next]) then begin
          Parent[Next]:=Current; Dist[Next]:=Dist[Current]+1
        end
      end
    end
  until False;
  SearchGrid:=True
end;
procedure PrintGrid(var G: TGrid; var Result: TSearchResult; Start,Goal: Integer);
var R,C,I,ID: Integer; Ch: Char;
begin
  if not CheckGrid(G) then Exit;
  if (Result.Count<0) or (Result.Count>MaxGridCells) then begin SetAIError(ErrSize,'Panjang rute tidak valid'); Exit end;
  for R:=1 to G.Rows do begin
    for C:=1 to G.Cols do begin
      ID:=(R-1)*G.Cols+C; Ch:='.';
      if G.Blocked[R,C] then Ch:='#';
      for I:=1 to Result.Count do if Result.Cells[I]=ID then Ch:='*';
      if ID=Start then Ch:='S'; if ID=Goal then Ch:='G';
      Write(Ch,' ')
    end;
    WriteLn
  end
end;
end.
