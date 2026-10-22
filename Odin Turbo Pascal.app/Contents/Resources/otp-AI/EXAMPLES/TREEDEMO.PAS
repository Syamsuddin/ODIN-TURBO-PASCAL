program DecisionTreeDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AITree,AIModel;
var D: PDataSet; M: TTreeModel; Path: TIndexList;
    I,J,N,L,Node: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('XOR.CSV'),True,TargetClass,D^));
  Need(FitTree(D^,4,1,0,M));
  WriteLn('Pohon XOR, min-gain=0. Node=',M.NodeCount);
  for I:=1 to D^.Count do begin
    Need(TraceTree(M,D^.X[I],Path,N,L));
    WriteLn('Input ',D^.X[I,1]:0:0,',',D^.X[I,2]:0:0,' => ',L);
    for J:=1 to N do begin
      Node:=Path[J]; Write('  node ',Node);
      if M.Nodes[Node].Feature=0 then WriteLn(' daun kelas ',M.Nodes[Node].LabelValue)
      else WriteLn(' X',M.Nodes[Node].Feature,' <= ',M.Nodes[Node].Threshold:0:3)
    end
  end;
  Need(SaveTree('TREE.TPM',M)); FreeData(D)
end.
