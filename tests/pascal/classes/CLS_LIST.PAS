{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsList;
{ Linked structures of classes: a forward class declaration for two
  classes that refer to each other, a sorted binary tree built and walked
  recursively, and a stack whose nodes are freed by the owner. }
type
  TTree = class;
  TNode = class
    Key: Integer;
    Left, Right: TNode;
    Owner: TTree;
    constructor Create(AKey: Integer; AOwner: TTree);
    destructor Destroy; override;
  end;
  TTree = class
  private
    FRoot: TNode;
    FCount: Integer;
    procedure Walk(N: TNode);
  public
    destructor Destroy; override;
    procedure Insert(Key: Integer);
    procedure Print;
    property Count: Integer read FCount;
  end;
  TStack = class
  private
    FTop: TNode;
  public
    destructor Destroy; override;
    procedure Push(V: Integer);
    function Pop: Integer;
    function Empty: Boolean;
  end;

var
  Freed: Integer;

constructor TNode.Create(AKey: Integer; AOwner: TTree);
begin
  Key := AKey;
  Owner := AOwner;
  if Owner <> nil then
    Inc(Owner.FCount);
end;

destructor TNode.Destroy;
begin
  Left.Free;
  Right.Free;
  Inc(Freed);
  inherited Destroy;
end;

destructor TTree.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

procedure TTree.Insert(Key: Integer);
var
  P: TNode;
begin
  if FRoot = nil then
  begin
    FRoot := TNode.Create(Key, Self);
    Exit;
  end;
  P := FRoot;
  while True do
    if Key < P.Key then
    begin
      if P.Left = nil then
      begin
        P.Left := TNode.Create(Key, Self);
        Exit;
      end;
      P := P.Left;
    end
    else
    begin
      if P.Right = nil then
      begin
        P.Right := TNode.Create(Key, Self);
        Exit;
      end;
      P := P.Right;
    end;
end;

procedure TTree.Walk(N: TNode);
begin
  if N = nil then
    Exit;
  Walk(N.Left);
  Write(N.Key, ' ');
  Walk(N.Right);
end;

procedure TTree.Print;
begin
  Walk(FRoot);
  WriteLn('(', Count, ')');
end;

destructor TStack.Destroy;
begin
  while not Empty do
    Pop;
  inherited Destroy;
end;

procedure TStack.Push(V: Integer);
var
  N: TNode;
begin
  N := TNode.Create(V, nil);
  N.Left := FTop;
  FTop := N;
end;

function TStack.Pop: Integer;
var
  N: TNode;
begin
  N := FTop;
  FTop := N.Left;
  N.Left := nil;
  Pop := N.Key;
  N.Free;
end;

function TStack.Empty: Boolean;
begin
  Empty := FTop = nil;
end;

const
  Keys: array[1..9] of Integer = (50, 30, 70, 20, 40, 60, 80, 35, 65);
var
  T: TTree;
  S: TStack;
  I: Integer;
begin
  Freed := 0;
  T := TTree.Create;
  for I := 1 to 9 do
    T.Insert(Keys[I]);
  T.Print;
  T.Free;
  WriteLn('freed ', Freed);
  S := TStack.Create;
  for I := 1 to 5 do
    S.Push(I * I);
  Write(S.Pop, ' ', S.Pop, ' ');
  S.Push(99);
  while not S.Empty do
    Write(S.Pop, ' ');
  WriteLn;
  S.Push(1);
  S.Push(2);
  S.Free;
  WriteLn('freed ', Freed);
end.
