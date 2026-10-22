unit AIReward;
interface
uses AITypes,AISearch;
const MaxQStates=MaxGridCells; MaxQActions=4;
type
  TQModel = record
    Ready: Boolean;
    States,Actions: Integer;
    Alpha,Gamma,Epsilon: TFloat;
    Q: array[1..MaxQStates,1..MaxQActions] of TFloat;
  end;
  TQTrainInfo = record
    Episodes,Successes,HistoryCount: Integer;
    TotalSteps: LongInt;
    LastReturn: TFloat;
    Returns: TSeries;
    HistoryEpisode: TIndexList;
  end;
function InitQ(States,Actions: Integer; Alpha,Gamma,Epsilon: TFloat;
  var M: TQModel): Boolean;
function CheckQ(var M: TQModel): Boolean;
function ChooseAction(var M: TQModel; State: Integer; Explore: Boolean;
  var Action: Integer): Boolean;
function UpdateQ(var M: TQModel; State,Action,NextState: Integer;
  Reward: TFloat; Terminal: Boolean): Boolean;
function DecayEpsilon(var M: TQModel; Factor,Minimum: TFloat): Boolean;
function GridStep(var G: TGrid; State,Action,Goal: Integer;
  var NextState: Integer; var Reward: TFloat; var Terminal: Boolean): Boolean;
function TrainGridQ(var M: TQModel; var G: TGrid; Start,Goal,
  Episodes,MaxSteps: Integer; Seed: LongInt; var Info: TQTrainInfo): Boolean;
function GreedyGridPath(var M: TQModel; var G: TGrid; Start,Goal: Integer;
  var Result: TSearchResult): Boolean;
implementation
uses AIMath;
function QShape(var M: TQModel): Boolean;
begin
  ClearAIError; QShape:=False;
  if not M.Ready or (M.States<1) or (M.States>MaxQStates) or
     (M.Actions<1) or (M.Actions>MaxQActions) or
     not ValidNumber(M.Alpha) or not ValidNumber(M.Gamma) or
     not ValidNumber(M.Epsilon) or (M.Alpha<=0) or (M.Alpha>1) or
     (M.Gamma<0) or (M.Gamma>1) or (M.Epsilon<0) or (M.Epsilon>1) then begin
    SetAIError(ErrModel,'Konfigurasi Q-table tidak valid'); Exit
  end;
  QShape:=True
end;
function CheckQ(var M: TQModel): Boolean;
var S,A: Integer;
begin
  CheckQ:=False;
  if not QShape(M) then Exit;
  for S:=1 to M.States do for A:=1 to M.Actions do
    if not ValidNumber(M.Q[S,A]) then begin SetAIError(ErrModel,'Nilai Q tidak valid'); Exit end;
  CheckQ:=True
end;
function InitQ(States,Actions: Integer; Alpha,Gamma,Epsilon: TFloat;
  var M: TQModel): Boolean;
begin
  FillChar(M,SizeOf(M),0); M.States:=States; M.Actions:=Actions;
  M.Alpha:=Alpha; M.Gamma:=Gamma; M.Epsilon:=Epsilon; M.Ready:=True;
  InitQ:=CheckQ(M); if AIErrorCode<>0 then M.Ready:=False
end;
function GoodRow(var M: TQModel; State: Integer): Boolean;
var A: Integer;
begin
  GoodRow:=False;
  if (State<1) or (State>M.States) then begin SetAIError(ErrSize,'State di luar Q-table'); Exit end;
  for A:=1 to M.Actions do if not ValidNumber(M.Q[State,A]) then begin
    SetAIError(ErrModel,'Nilai pada baris Q tidak valid'); Exit
  end;
  GoodRow:=True
end;
function ChooseAction(var M: TQModel; State: Integer; Explore: Boolean;
  var Action: Integer): Boolean;
var A: Integer;
begin
  ChooseAction:=False; Action:=0;
  if not QShape(M) then Exit;
  if not GoodRow(M,State) then Exit;
  if Explore then if AIRandom<M.Epsilon then begin
    Action:=AIRandomInt(M.Actions)+1; ChooseAction:=True; Exit
  end;
  Action:=1;
  for A:=2 to M.Actions do if M.Q[State,A]>M.Q[State,Action] then Action:=A;
  ChooseAction:=True
end;
function UpdateQ(var M: TQModel; State,Action,NextState: Integer;
  Reward: TFloat; Terminal: Boolean): Boolean;
var A: Integer; Best,Target,Value: TFloat;
begin
  UpdateQ:=False;
  if not QShape(M) then Exit;
  if not GoodRow(M,State) then Exit;
  if (Action<1) or (Action>M.Actions) or not ValidNumber(Reward) then begin
    SetAIError(ErrValue,'Aksi/reward tidak valid'); Exit
  end;
  Best:=0;
  if not Terminal then begin
    if not GoodRow(M,NextState) then Exit;
    Best:=M.Q[NextState,1];
    for A:=2 to M.Actions do if M.Q[NextState,A]>Best then Best:=M.Q[NextState,A]
  end;
  Target:=Reward+M.Gamma*Best;
  Value:=M.Q[State,Action]+M.Alpha*(Target-M.Q[State,Action]);
  if not ValidNumber(Value) then begin SetAIError(ErrValue,'Hasil pembaruan Q melampaui batas'); Exit end;
  M.Q[State,Action]:=Value; UpdateQ:=True
end;
function DecayEpsilon(var M: TQModel; Factor,Minimum: TFloat): Boolean;
begin
  DecayEpsilon:=False;
  if not QShape(M) then Exit;
  if not ValidNumber(Factor) or not ValidNumber(Minimum) or
     (Factor<0) or (Factor>1) or (Minimum<0) or (Minimum>M.Epsilon) then begin
    SetAIError(ErrValue,'Decay/floor epsilon tidak valid'); Exit
  end;
  M.Epsilon:=M.Epsilon*Factor; if M.Epsilon<Minimum then M.Epsilon:=Minimum;
  DecayEpsilon:=True
end;
function GridStep(var G: TGrid; State,Action,Goal: Integer;
  var NextState: Integer; var Reward: TFloat; var Terminal: Boolean): Boolean;
var R,C: Integer;
begin
  NextState:=State; Reward:=0; Terminal:=False; GridStep:=False;
  if not CellPosition(G,Goal,R,C) then Exit;
  if G.Blocked[R,C] then begin SetAIError(ErrValue,'Goal berada pada dinding'); Exit end;
  if not GridNeighbor(G,State,Action,NextState) then Exit;
  if State=Goal then begin NextState:=Goal; Terminal:=True; GridStep:=True; Exit end;
  if NextState=State then Reward:=-2 else Reward:=-1;
  Terminal:=NextState=Goal; if Terminal then Reward:=10;
  GridStep:=True
end;
function Compatible(var M: TQModel; var G: TGrid; Start,Goal: Integer): Boolean;
var Next: Integer; Reward: TFloat; Terminal: Boolean;
begin
  Compatible:=False;
  if not CheckQ(M) then Exit;
  if not CheckGrid(G) then Exit;
  if (M.States<>G.Rows*G.Cols) or (M.Actions<>4) then begin
    SetAIError(ErrSize,'Q-table tidak sesuai grid'); Exit
  end;
  if not GridStep(G,Start,1,Goal,Next,Reward,Terminal) then Exit;
  Compatible:=True
end;
function TrainGridQ(var M: TQModel; var G: TGrid; Start,Goal,
  Episodes,MaxSteps: Integer; Seed: LongInt; var Info: TQTrainInfo): Boolean;
var Ep,Step,State,Next,Action,Stride,P: Integer;
    Reward,Return: TFloat; Terminal: Boolean;
begin
  FillChar(Info,SizeOf(Info),0); TrainGridQ:=False;
  if not Compatible(M,G,Start,Goal) then Exit;
  if (Episodes<1) or (Episodes>10000) or (MaxSteps<1) or (MaxSteps>2000) then begin
    SetAIError(ErrSize,'Episode 1..10000 dan langkah 1..2000 diperlukan'); Exit
  end;
  AISetSeed(Seed); Stride:=(Episodes+MaxSamples-1) div MaxSamples;
  for Ep:=1 to Episodes do begin
    State:=Start; Return:=0; Terminal:=Start=Goal; Step:=0;
    while not Terminal and (Step<MaxSteps) do begin
      if not ChooseAction(M,State,True,Action) then Exit;
      if not GridStep(G,State,Action,Goal,Next,Reward,Terminal) then Exit;
      if not UpdateQ(M,State,Action,Next,Reward,Terminal) then Exit;
      Return:=Return+Reward; State:=Next; Inc(Step); Inc(Info.TotalSteps)
    end;
    if Terminal then Inc(Info.Successes);
    if (Ep=1) or (Ep mod Stride=0) or (Ep=Episodes) then begin
      P:=Info.HistoryCount; if P<MaxSamples then Inc(P);
      Info.Returns[P]:=Return; Info.HistoryEpisode[P]:=Ep; Info.HistoryCount:=P
    end;
    Info.LastReturn:=Return; Info.Episodes:=Ep
  end;
  TrainGridQ:=True
end;
function GreedyGridPath(var M: TQModel; var G: TGrid; Start,Goal: Integer;
  var Result: TSearchResult): Boolean;
var Seen: array[1..MaxQStates] of Boolean;
    State,Next,Action: Integer; Reward: TFloat; Terminal: Boolean;
begin
  FillChar(Result,SizeOf(Result),0); GreedyGridPath:=False;
  if not Compatible(M,G,Start,Goal) then Exit;
  FillChar(Seen,SizeOf(Seen),0); State:=Start;
  repeat
    if Seen[State] then Break;
    Seen[State]:=True; Inc(Result.Count); Result.Cells[Result.Count]:=State;
    if State=Goal then begin Result.Found:=True; Break end;
    if not ChooseAction(M,State,False,Action) then Exit;
    if not GridStep(G,State,Action,Goal,Next,Reward,Terminal) then Exit;
    State:=Next; Inc(Result.Expanded)
  until Result.Count=MaxGridCells;
  if Result.Found then Result.Cost:=Result.Count-1;
  GreedyGridPath:=True
end;
end.
