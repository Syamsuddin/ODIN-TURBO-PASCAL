{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjsBufStream;
{ Unit Objects: TBufStream with small buffers. Records, numbers and
  strings written, read back with Seek, appended, truncated; positions,
  sizes and status codes, including reads past the end. }
uses Objects;
type
  TEntry = record
    Id: LongInt;
    Score: Real;
    Tag: string[7];
  end;

var
  F: TBufStream;
  E: TEntry;
  I: LongInt;
  W: Word;
  S: PString;

procedure Report(const What: String);
begin
  WriteLn(What, ': size ', F.GetSize, ' pos ', F.GetPos, ' status ', F.Status);
end;

begin
  F.Init('entries.dat', stCreate, 10);
  for I := 1 to 5 do
  begin
    E.Id := I;
    E.Score := I * 1.5;
    Str(I * 11, E.Tag);
    E.Tag := 'tag' + E.Tag;
    F.Write(E, SizeOf(E));
  end;
  Report('written');
  F.WriteStr(NewStr('the end'));
  W := 4660;
  F.Write(W, SizeOf(W));
  Report('more');
  F.Done;

  F.Init('entries.dat', stOpenRead, 6);
  Report('opened');
  F.Seek(2 * SizeOf(E));
  F.Read(E, SizeOf(E));
  WriteLn('third: ', E.Id, ' ', E.Score:0:1, ' ', E.Tag);
  F.Seek(0);
  F.Read(E, SizeOf(E));
  WriteLn('first: ', E.Id, ' ', E.Score:0:1, ' ', E.Tag);
  F.Seek(5 * SizeOf(E));
  S := F.ReadStr;
  F.Read(W, SizeOf(W));
  WriteLn('tail: ', S^, ' ', W);
  Report('at end');
  F.Read(W, SizeOf(W));
  Report('read past end');
  F.Reset;
  Report('after reset');
  F.Done;

  F.Init('entries.dat', stOpen, 4);
  F.Seek(F.GetSize);
  for I := 1 to 3 do
    F.Write(I, SizeOf(I));
  Report('appended');
  F.Seek(SizeOf(E));
  F.Truncate;
  Report('truncated');
  F.Done;

  F.Init('entries.dat', stOpenRead, 8);
  Report('reopened');
  F.Read(E, SizeOf(E));
  WriteLn('only: ', E.Id, ' ', E.Tag);
  F.Done;

  F.Init('no/such/dir/x.dat', stOpenRead, 8);
  WriteLn('missing: status ', F.Status, ' info ', F.ErrorInfo);
  F.Done;
end.
