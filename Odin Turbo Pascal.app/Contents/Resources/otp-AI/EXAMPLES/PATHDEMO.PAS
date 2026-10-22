program PathDemo;
{ PATHDEMO - pencarian jalur di grid (BFS/DFS/A-star) dengan AISEARCH.
  Membuat grid 6x6, memasang dinding di sepanjang kolom 3 pada baris
  1,2,3,5 (baris 4 dibiarkan terbuka sebagai satu-satunya jalan tembus),
  lalu mencari rute dari sel 1 (pojok kiri atas) ke sel 36 (pojok kanan
  bawah) dengan tiga metode secara berurutan: BFS, DFS dan A-star.
  Untuk setiap metode dicetak apakah rute ditemukan, biayanya (jumlah
  langkah) dan jumlah sel yang dieksplorasi (Expanded), lalu gridnya
  digambar di terminal dengan rute tersebut ditandai.
  Latihan (DOCS/GUIDE2.TXT bagian 22, urutan #9): bandingkan Cost dan
  Expanded ketiga metode - BFS dan A-star menjamin rute terpendek,
  DFS tidak. }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AISearch;
var G: TGrid; R: TSearchResult; Method,Row: Integer;
{$I COMMON.INC}
begin
  Need(InitGrid(6,6,G));
  for Row:=1 to 5 do if Row<>4 then Need(SetWall(G,Row,3,True));  { dinding kolom 3, celah di baris 4 }
  for Method:=SearchBFS to SearchAStar do begin        { SearchBFS=1, SearchDFS=2, SearchAStar=3 }
    Need(SearchGrid(G,1,36,Method,R));
    WriteLn('Metode ',Method,': found=',R.Found,' cost=',R.Cost,' expanded=',R.Expanded);
    PrintGrid(G,R,1,36); WriteLn
  end
end.
