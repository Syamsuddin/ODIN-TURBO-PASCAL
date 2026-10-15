{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ObjsStreams;
{ Unit Objects: registering own types (TStreamRec with Ofs(TypeOf(T)^) and
  method addresses), Put/Get of objects, nil and nested collections,
  TStrCollection, StrRead/StrWrite, CopyFrom, error statuses and the
  StreamError hook. }
uses Objects, Strings;
type
  PPoint3 = ^TPoint3;
  TPoint3 = object(TObject)
    X, Y, Z: Integer;
    constructor Init(AX, AY, AZ: Integer);
    constructor Load(var S: TStream);
    procedure Store(var S: TStream);
    function Text: String;
  end;
  PLabel = ^TLabel;
  TLabel = object(TPoint3)
    Caption: PString;
    constructor Init(AX, AY, AZ: Integer; const ACaption: String);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Store(var S: TStream);
  end;

constructor TPoint3.Init(AX, AY, AZ: Integer);
begin
  inherited Init;
  X := AX;
  Y := AY;
  Z := AZ;
end;

constructor TPoint3.Load(var S: TStream);
begin
  S.Read(X, SizeOf(Integer) * 3);
end;

procedure TPoint3.Store(var S: TStream);
begin
  S.Write(X, SizeOf(Integer) * 3);
end;

function TPoint3.Text: String;
var
  A, B, C: String;
begin
  Str(X, A);
  Str(Y, B);
  Str(Z, C);
  Text := '(' + A + ',' + B + ',' + C + ')';
end;

constructor TLabel.Init(AX, AY, AZ: Integer; const ACaption: String);
begin
  inherited Init(AX, AY, AZ);
  Caption := NewStr(ACaption);
end;

constructor TLabel.Load(var S: TStream);
begin
  inherited Load(S);
  Caption := S.ReadStr;
end;

destructor TLabel.Done;
begin
  DisposeStr(Caption);
  inherited Done;
end;

procedure TLabel.Store(var S: TStream);
begin
  inherited Store(S);
  S.WriteStr(Caption);
end;

const
  RPoint3: TStreamRec = (
    ObjType: 1000;
    VmtLink: Ofs(TypeOf(TPoint3)^);
    Load: @TPoint3.Load;
    Store: @TPoint3.Store);
  RLabel: TStreamRec = (
    ObjType: 1001;
    VmtLink: Ofs(TypeOf(TLabel)^);
    Load: @TLabel.Load;
    Store: @TLabel.Store);

var
  Errors: Integer;

procedure OnError(var S: TStream); far;
begin
  Inc(Errors);
  WriteLn('  [stream error ', S.Status, ' info ', S.ErrorInfo, ']');
end;

procedure Run;
var
  M, M2: TMemoryStream;
  Outer, Inner, Back: PCollection;
  Names: PStrCollection;
  P: PChar;
  O: PObject;

  procedure ShowItem(Item: PObject); far;
  begin
    if Item = nil then
      Write(' nil')
    else if TypeOf(Item^) = TypeOf(TLabel) then
      Write(' ', PLabel(Item)^.Caption^, PLabel(Item)^.Text)
    else if TypeOf(Item^) = TypeOf(TPoint3) then
      Write(' ', PPoint3(Item)^.Text)
    else
      Write(' collection of ', PCollection(Item)^.Count);
  end;

  procedure ShowName(Item: PChar); far;
  begin
    Write(' ', Item);
  end;

begin
  RegisterObjects;
  RegisterType(RPoint3);
  RegisterType(RLabel);
  M.Init(16, 16);
  Inner := New(PCollection, Init(2, 2));
  Inner^.Insert(New(PPoint3, Init(7, 8, 9)));
  Outer := New(PCollection, Init(4, 4));
  Outer^.Insert(New(PPoint3, Init(1, 2, 3)));
  Outer^.Insert(nil);
  Outer^.Insert(New(PLabel, Init(4, 5, 6, 'home')));
  Outer^.Insert(Inner);
  M.Put(Outer);
  WriteLn('stored ', M.GetSize, ' bytes, status ', M.Status);
  M.Seek(0);
  Back := PCollection(M.Get);
  Write('loaded');
  Back^.ForEach(@ShowItem);
  WriteLn;
  Write('inner');
  PCollection(Back^.At(3))^.ForEach(@ShowItem);
  WriteLn;
  Dispose(Back, Done);
  Dispose(Outer, Done);

  Names := New(PStrCollection, Init(4, 4));
  Names^.Insert(StrNew('zeta'));
  Names^.Insert(StrNew('alpha'));
  Names^.Insert(StrNew('mu'));
  M.Seek(0);
  M.Truncate;
  M.Put(Names);
  M.StrWrite('trailer');
  M.StrWrite(nil);
  WriteLn('pchar stream ', M.GetSize);
  M.Seek(0);
  Dispose(Names, Done);
  Names := PStrCollection(M.Get);
  Write('names');
  Names^.ForEach(@ShowName);
  WriteLn;
  P := M.StrRead;
  WriteLn('trailer ', P, ' then nil ', M.StrRead = nil);
  StrDispose(P);
  Dispose(Names, Done);

  M2.Init(8, 8);
  M.Seek(0);
  M2.CopyFrom(M, M.GetSize);
  WriteLn('copy ', M2.GetSize, ' status ', M2.Status);
  M2.Done;

  Errors := 0;
  StreamError := @OnError;
  M.Seek(0);
  M.Truncate;
  O := New(PObject, Init);
  M.Put(O);
  WriteLn('put unregistered: status ', M.Status, ' size ', M.GetSize);
  M.Reset;
  M.Seek(0);
  M.Truncate;
  M.Write(Errors, 2);
  M.Seek(0);
  WriteLn('get unknown nil ', M.Get = nil, ' status ', M.Status, ' info ', M.ErrorInfo);
  M.Reset;
  M.Seek(1000);
  WriteLn('seek beyond: status ', M.Status, ' pos ', M.GetPos, ' errors ', Errors);
  StreamError := nil;
  Dispose(O, Done);
  M.Done;
end;

begin
  Run;
end.
