{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsRtlLists;
{ The class units of the RTL: TList and TStringList (Classes), TObjectList
  (Contnrs) owning its objects, FreeAndNil (SysUtils). }
uses Classes, Contnrs, SysUtils;
type
  TItem = class
    Name: String;
    Price: LongInt;
    constructor Create(const AName: String; APrice: LongInt);
    destructor Destroy; override;
  end;

var
  Freed: Integer;

constructor TItem.Create(const AName: String; APrice: LongInt);
begin
  Name := AName;
  Price := APrice;
end;

destructor TItem.Destroy;
begin
  Inc(Freed);
  inherited Destroy;
end;

function ByPrice(A, B: Pointer): Integer;
begin
  ByPrice := TItem(A).Price - TItem(B).Price;
end;

var
  P: TList;
  L: TObjectList;
  S: TStringList;
  T: TItem;
  I, At: Integer;
  N: array[1..5] of LongInt;
begin
  P := TList.Create;
  for I := 1 to 5 do
  begin
    N[I] := I * 11;
    P.Add(@N[I]);
  end;
  P.Exchange(0, 4);
  P.Move(1, 3);
  P.Delete(2);
  P.Insert(0, nil);
  for I := 0 to P.Count - 1 do
    if P[I] = nil then
      Write('nil ')
    else
      Write(PLongInt(P[I])^, ' ');
  WriteLn('| ', P.IndexOf(@N[5]), ' ', P.Count, ' ', P.Capacity >= P.Count);
  P.Pack;
  WriteLn('packed ', P.Count, ' ', PLongInt(P.First)^, ' ', PLongInt(P.Last)^);
  P.Free;

  Freed := 0;
  L := TObjectList.Create;
  L.Add(TItem.Create('tea', 5000));
  L.Add(TItem.Create('coffee', 8000));
  L.Add(TItem.Create('water', 3000));
  L.Add(TItem.Create('juice', 9000));
  L.Sort(ByPrice);
  for I := 0 to L.Count - 1 do
    Write((L[I] as TItem).Name, '=', TItem(L.Items[I]).Price, ' ');
  WriteLn;
  L.Delete(0);
  L.Remove(L.Last);
  WriteLn('freed ', Freed, ' count ', L.Count, ' first ', TItem(L.First).Name);
  T := TItem(L.Extract(L.Last));
  WriteLn('extracted ', T.Name, ' count ', L.Count, ' freed ', Freed);
  L[0] := T;
  WriteLn('replaced, freed ', Freed, ' ', (L[0] as TItem).Name);
  FreeAndNil(L);
  WriteLn('freed ', Freed, ' ', L = nil);

  S := TStringList.Create;
  S.Add('pisang');
  S.Add('Apel');
  S.Add('mangga');
  S.Add('apel');
  S.Sorted := True;
  for I := 0 to S.Count - 1 do
    Write(S[I], ' ');
  WriteLn;
  S.Add('jeruk');
  WriteLn(S.IndexOf('MANGGA'), ' ', S.Find('kiwi', At), ' ', At, ' ', S.Strings[At]);
  S.CaseSensitive := True;
  WriteLn(S.IndexOf('MANGGA'), ' ', S.IndexOf('mangga'), ' ', S[0], ' ', S[1]);
  S.SaveToFile('fruit.txt');
  S.Clear;
  S.Sorted := False;
  S.LoadFromFile('fruit.txt');
  S.Delete(0);
  S[0] := 'APEL';
  S.Insert(1, 'durian');
  S.AddObject('self', S);
  for I := 0 to S.Count - 1 do
    Write(S[I], ' ');
  WriteLn(S.Objects[S.Count - 1] = S, ' ', S.IndexOfObject(S), ' ', S.Objects[0] = nil);
  S.Free;
end.
