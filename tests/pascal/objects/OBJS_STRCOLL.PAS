{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjsStrColl;
{ Unit Objects: TStringCollection (sorted, with and without duplicates),
  Search, IndexOf, ForEach/FirstThat/LastThat with nested procedures, and
  a round trip through a TMemoryStream and a TBufStream file. }
uses Objects;

procedure List(const Title: String; C: PCollection);
var
  N: Integer;

  procedure Show(P: PString); far;
  begin
    Inc(N);
    Write(' ', N, ':', P^);
  end;

begin
  N := 0;
  Write(Title, ' (', C^.Count, ')');
  C^.ForEach(@Show);
  WriteLn;
end;

procedure Run;
var
  Words: PStringCollection;
  Copy: PCollection;
  M: TMemoryStream;
  F: TBufStream;
  Index: Sw_Integer;
  MinLen: Integer;
  P: PString;

  function LongWord(P: PString): Boolean; far;
  begin
    LongWord := Length(P^) >= MinLen;
  end;

begin
  RegisterObjects;
  Words := New(PStringCollection, Init(3, 2));
  Words^.Insert(NewStr('pear'));
  Words^.Insert(NewStr('apple'));
  Words^.Insert(NewStr('fig'));
  Words^.Insert(NewStr('banana'));
  P := NewStr('apple');
  Words^.Insert(P);
  List('sorted', Words);
  WriteLn('limit ', Words^.Limit, ' delta ', Words^.Delta);
  WriteLn('search fig ', Words^.Search(NewStr('fig'), Index), ' at ', Index);
  WriteLn('search kiwi ', Words^.Search(NewStr('kiwi'), Index), ' at ', Index);
  WriteLn('indexof banana ', Words^.IndexOf(Words^.At(1)));
  MinLen := 5;
  WriteLn('first long ', PString(Words^.FirstThat(@LongWord))^, ' last long ', PString(Words^.LastThat(@LongWord))^);
  MinLen := 10;
  WriteLn('none long ', Words^.FirstThat(@LongWord) = nil);
  Words^.Duplicates := True;
  Words^.Insert(NewStr('fig'));
  Words^.Insert(NewStr('apple'));
  List('duplicates', Words);
  Words^.AtFree(0);
  Words^.Free(Words^.At(Words^.Count - 1));
  List('after free', Words);

  M.Init(64, 32);
  M.Put(Words);
  WriteLn('memory size ', M.GetSize, ' status ', M.Status);
  M.Seek(0);
  Copy := PCollection(M.Get);
  List('from memory', Copy);
  WriteLn('same type ', TypeOf(Copy^) = TypeOf(TStringCollection),
    ' duplicates ', PStringCollection(Copy)^.Duplicates);
  Dispose(Copy, Done);
  M.Done;

  F.Init('words.dat', stCreate, 16);
  F.Put(Words);
  WriteLn('file size ', F.GetSize, ' pos ', F.GetPos, ' status ', F.Status);
  F.Done;
  Dispose(Words, Done);
  F.Init('words.dat', stOpenRead, 7);
  Copy := PCollection(F.Get);
  List('from file', Copy);
  WriteLn('file status ', F.Status, ' pos ', F.GetPos);
  F.Done;
  Dispose(Copy, Done);
end;

begin
  Run;
end.
