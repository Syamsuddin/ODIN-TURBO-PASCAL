program DecisionTreeDemo;
{ TREEDEMO - pohon keputusan dengan AITREE, menyelesaikan XOR.
  Melatih FitTree pada XOR.CSV dengan MinGain=0: split pertama pada
  XOR sendiri tidak memberi information gain, jadi MinGain harus nol
  supaya pohon tetap boleh membelah dan split BERIKUTNYA baru memberi
  informasi. Untuk setiap baris input, TraceTree menampilkan jalur dari
  akar sampai daun: tiap node mencetak fitur dan ambang batasnya, atau
  kelas daun bila node tersebut daun. Model pohon disimpan ke TREE.TPM.
  Latihan (DOCS/GUIDE2.TXT bagian 18, urutan #5): bandingkan jumlah
  node dan kedalaman pohon ini dengan asumsi probabilistik BAYDEMO. }
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
  Need(FitTree(D^,4,1,0,M));                 { DepthLimit=4, MinLeaf=1, MinGain=0 (wajib untuk XOR) }
  WriteLn('Pohon XOR, min-gain=0. Node=',M.NodeCount);
  for I:=1 to D^.Count do begin
    Need(TraceTree(M,D^.X[I],Path,N,L));     { Path: indeks node akar..daun; N: panjangnya; L: kelas daun }
    WriteLn('Input ',D^.X[I,1]:0:0,',',D^.X[I,2]:0:0,' => ',L);
    for J:=1 to N do begin
      Node:=Path[J]; Write('  node ',Node);
      if M.Nodes[Node].Feature=0 then WriteLn(' daun kelas ',M.Nodes[Node].LabelValue)  { Feature=0 => daun }
      else WriteLn(' X',M.Nodes[Node].Feature,' <= ',M.Nodes[Node].Threshold:0:3)
    end
  end;
  Need(SaveTree('TREE.TPM',M)); FreeData(D)
end.
