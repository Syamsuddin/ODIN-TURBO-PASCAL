{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjsCollection;
{ Unit Objects: TCollection of TObject descendants. Init clears fields,
  growth by Delta, AtInsert/AtPut/AtDelete/Delete/IndexOf, Pack, FreeAll
  and Done (items freed last to first, through their virtual destructor),
  ForEach with a nested procedure, TObject.Free. Ends with an index
  error: runtime error 213. }
uses Objects;
type
  PNode = ^TNode;
  TNode = object(TObject)
    Value: Integer;
    Name: string[8];
    constructor Init(AValue: Integer);
    destructor Done; virtual;
  end;
  PTagged = ^TTagged;
  TTagged = object(TNode)
    Tag: Char;
    constructor Init(AValue: Integer; ATag: Char);
    destructor Done; virtual;
  end;

constructor TNode.Init(AValue: Integer);
begin
  inherited Init;
  Value := AValue;
end;

destructor TNode.Done;
begin
  Write(' -', Value);
  inherited Done;
end;

constructor TTagged.Init(AValue: Integer; ATag: Char);
begin
  inherited Init(AValue);
  Tag := ATag;
end;

destructor TTagged.Done;
begin
  Write(' ', Tag);
  inherited Done;
end;

var
  C: PCollection;
  N: PNode;
  Total: LongInt;

procedure Dump;

  procedure One(P: PNode); far;
  begin
    if P = nil then
      Write(' nil')
    else
    begin
      Write(' ', P^.Value);
      Inc(Total, P^.Value);
    end;
  end;

begin
  Total := 0;
  Write('[', C^.Count, '/', C^.Limit, ']');
  C^.ForEach(@One);
  WriteLn(' total ', Total);
end;

begin
  N := New(PNode, Init(0));
  WriteLn('cleared name length ', Length(N^.Name), ' value ', N^.Value);
  Dispose(N, Done);
  WriteLn;
  C := New(PCollection, Init(2, 3));
  C^.Insert(New(PNode, Init(10)));
  C^.Insert(New(PTagged, Init(20, 'a')));
  Dump;
  C^.Insert(New(PNode, Init(30)));
  C^.AtInsert(0, New(PNode, Init(5)));
  C^.AtInsert(2, nil);
  Dump;
  N := C^.At(1);
  C^.AtPut(1, New(PTagged, Init(15, 'b')));
  Dispose(N, Done);
  WriteLn;
  C^.Pack;
  Dump;
  N := C^.At(2);
  WriteLn('index of 20 ', C^.IndexOf(N), ', of nil ', C^.IndexOf(nil), ', of stranger ', C^.IndexOf(@Total));
  C^.Delete(N);
  Dispose(N, Done);
  WriteLn;
  Dump;
  Write('free all:');
  C^.FreeAll;
  WriteLn;
  Dump;
  C^.Insert(New(PTagged, Init(1, 'x')));
  C^.Insert(New(PNode, Init(2)));
  N := New(PNode, Init(3));
  Write('free one:');
  N^.Free;
  WriteLn;
  Write('done:');
  C^.Done;
  WriteLn;
  C^.Init(1, 1);
  C^.Insert(nil);
  WriteLn('at 0 nil ', C^.At(0) = nil);
  C^.At(1);
  WriteLn('not reached');
end.
