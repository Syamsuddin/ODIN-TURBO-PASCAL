{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VUnits;
{ ColorSel and TextView without a screen: the TTerminal buffer (wrap,
  dropped lines, a line longer than the buffer, tabs), AssignDevice for
  output and input, and TColorDialog through a stream, with SetData,
  GetData, the mono selector and ColorIndexes. Views are not exposed, so
  nothing is drawn. }
uses Objects, Drivers, Views, Dialogs, ColorSel, TextView;

type
  PFeed = ^TFeed;
  TFeed = object(TTextDevice)
    Calls: Integer;
    function StrRead(var S: TextBuf): Byte; virtual;
  end;

function TFeed.StrRead(var S: TextBuf): Byte;
const
  Data: String[20] = 'satu 12'#10'dua'#10;
var
  I: Integer;
begin
  Inc(Calls);
  StrRead := 0;
  if Calls > 1 then
    Exit;
  for I := 1 to Length(Data) do
    S[I - 1] := Data[I];
  StrRead := Length(Data);
end;

{ The buffer from QueBack to QueFront, '|' for each line end. }
procedure Dump(P: PTerminal);
var
  Q: Word;
  S: String;
begin
  S := '';
  Q := P^.QueBack;
  while Q <> P^.QueFront do
  begin
    if P^.Buffer^[Q] = #10 then
      S := S + '|'
    else
      S := S + P^.Buffer^[Q];
    P^.BufInc(Q);
  end;
  WriteLn('[', S, '] lines ', P^.Limit.Y, ' width ', P^.Limit.X, ' calc ', P^.CalcWidth, ' front ', P^.QueFront,
    ' back ', P^.QueBack, ' top ', P^.Delta.Y);
end;

function NewDialog: PColorDialog;
begin
  NewDialog := New(PColorDialog, Init('',
    ColorGroup('Desktop', DesktopColorItems(nil),
    ColorGroup('Menus', MenuColorItems(nil),
    ColorGroup('Dialogs', DialogColorItems(dpBlueDialog, nil),
    ColorGroup('Windows', WindowColorItems(wpGrayWindow, nil), nil))))));
end;

var
  R: TRect;
  Term: PTerminal;
  F: PFeed;
  T, U: Text;
  I, N: Integer;
  W: String[4];
  D: PColorDialog;
  S: TMemoryStream;
  Pal: TPalette;
  G: PColorGroup;
  P: PColorItem;
begin
  { ---- TTerminal through AssignDevice ---- }
  R.Assign(0, 0, 10, 3);
  Term := New(PTerminal, Init(R, nil, nil, 32));
  Dump(Term);
  AssignDevice(T, Term);
  Rewrite(T);
  WriteLn(T, 'abc');
  Dump(Term);
  Write(T, 'x'#9'y');
  Dump(Term);
  WriteLn(T);
  for I := 1 to 6 do
    WriteLn(T, 'baris ', I);
  Dump(Term);
  WriteLn(T, 'panjang sekali sampai lebih dari tiga puluh dua');
  Dump(Term);
  WriteLn(T, 'pendek');
  Dump(Term);
  WriteLn('prev ', Term^.PrevLines(Term^.QueFront, 0), ' ', Term^.PrevLines(Term^.QueFront, 1), ' ',
    Term^.PrevLines(Term^.QueFront, 2), ' ', Term^.PrevLines(Term^.QueFront, 9), ' next ',
    Term^.NextLine(Term^.QueBack), ' ', Term^.NextLine(Term^.QueFront));
  WriteLn('insert ', Term^.CanInsert(24), ' ', Term^.CanInsert(25), ' empty ', Term^.QueEmpty);
  Close(T);
  Dispose(Term, Done);

  { ---- input through StrRead ---- }
  F := New(PFeed, Init(R, nil, nil));
  F^.Calls := 0;
  AssignDevice(U, F);
  Reset(U);
  ReadLn(U, W, N);
  WriteLn('read ', W, ' ', N);
  ReadLn(U, W);
  WriteLn('read ', W, ' eof ', Eof(U));
  Close(U);
  Dispose(F, Done);

  { ---- TColorDialog ---- }
  RegisterViews;
  RegisterDialogs;
  RegisterColorSel;
  D := NewDialog;
  WriteLn('size ', D^.DataSize, ' groups ', D^.Groups^.GetNumGroups, ' mono ', D^.MonoSel^.State and sfVisible <> 0,
    ' fore ', D^.ForSel^.State and sfVisible <> 0);
  Pal := #$13#$70#$78#$74;
  D^.SetData(Pal);
  WriteLn('display ', D^.Display^.Color^, ' fore ', D^.ForSel^.Color, ' back ', D^.BakSel^.Color);
  S.Init(0, 256);
  S.Put(D);
  Dispose(D, Done);
  S.Seek(0);
  D := PColorDialog(S.Get);
  WriteLn('stream ', S.Status, ' ', D <> nil);
  S.Done;
  WriteLn('loaded pal ', Length(D^.Pal), ' groups ', D^.Groups^.GetNumGroups, ' display ', D^.Display^.Color^,
    ' fore ', D^.ForSel^.Color);
  G := D^.Groups^.GetGroup(2);
  P := G^.Items;
  N := 0;
  while P^.Next <> nil do
  begin
    P := P^.Next;
    Inc(N);
  end;
  WriteLn(G^.Name^, ' ', G^.Items^.Name^, ' ', G^.Items^.Index, ' ... ', P^.Name^, ' ', P^.Index, ' (', N + 1, ')');
  G := D^.Groups^.GetGroup(3);
  WriteLn(G^.Name^, ' ', G^.Items^.Name^, ' ', G^.Items^.Index);
  { Menus opens at its first item, Normal (palette index 2). }
  D^.Groups^.FocusItem(1);
  WriteLn('menus display ', D^.Display^.Color^);
  D^.ForSel^.SelectColor(9);
  D^.BakSel^.SelectColor(4);
  D^.GetData(Pal);
  WriteLn('pal ', Ord(Pal[1]), ' ', Ord(Pal[2]), ' indexes ', ColorIndexes^.GroupIndex, ' ', ColorIndexes^.ColorSize,
    ' ', ColorIndexes^.ColorIndex[1]);
  { An index past the end of this short palette points the sample nowhere. }
  Message(D, evBroadcast, cmNewColorIndex, Pointer(PtrUInt(5)));
  WriteLn('past ', D^.Display^.Color = nil);
  Dispose(D, Done);

  { ColorIndexes through a stream: the next dialog opens at Menus. }
  S.Init(0, 64);
  StoreIndexes(S);
  FreeMem(ColorIndexes, 2 + ColorIndexes^.ColorSize);
  ColorIndexes := nil;
  S.Seek(0);
  LoadIndexes(S);
  S.Done;
  D := NewDialog;
  D^.SetData(Pal);
  WriteLn('reopen group ', D^.Groups^.Focused, ' display ', D^.Display^.Color^);
  Dispose(D, Done);

  { A monochrome screen shows the mono selector instead. }
  ScreenMode := smMono;
  D := NewDialog;
  D^.SetData(Pal);
  WriteLn('mono ', D^.MonoSel^.State and sfVisible <> 0, ' fore ', D^.ForSel^.State and sfVisible <> 0,
    ' value ', D^.MonoSel^.Value);
  D^.MonoSel^.Press(3);
  D^.GetData(Pal);
  WriteLn('inverse ', Ord(Pal[2]));
  Dispose(D, Done);
  WriteLn('VUNITS selesai');
end.
