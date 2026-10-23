{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Contnrs dari runtime library Odin. Bukan unit Turbo Pascal 7,
  tetapi subset dari Contnrs Free Pascal/Delphi: TObjectList, daftar objek
  yang (bila OwnsObjects) membebaskan objeknya sendiri saat dihapus, diganti,
  atau saat daftarnya dibebaskan. Ambil objeknya kembali dengan is dan as. }
unit Contnrs;

{$R-,Q-,X+}

interface

uses
  Classes;

type
  TObjectList = class(TList)
  private
    FOwnsObjects: Boolean;
    function GetItem(Index: Integer): TObject;
    procedure SetItem(Index: Integer; AObject: TObject);
  protected
    procedure Notify(Ptr: Pointer; Action: TListNotification); override;
  public
    constructor Create; overload;
    constructor Create(AOwnsObjects: Boolean); overload;
    function Add(AObject: TObject): Integer;
    procedure Insert(Index: Integer; AObject: TObject);
    function Extract(Item: TObject): TObject;
    function Remove(AObject: TObject): Integer;
    function IndexOf(AObject: TObject): Integer;
    function First: TObject;
    function Last: TObject;
    property OwnsObjects: Boolean read FOwnsObjects write FOwnsObjects;
    property Items[Index: Integer]: TObject read GetItem write SetItem; default;
  end;

implementation

constructor TObjectList.Create;
begin
  inherited Create;
  FOwnsObjects := True;
end;

constructor TObjectList.Create(AOwnsObjects: Boolean);
begin
  inherited Create;
  FOwnsObjects := AOwnsObjects;
end;

{ An owned object goes with its entry. }
procedure TObjectList.Notify(Ptr: Pointer; Action: TListNotification);
begin
  if FOwnsObjects and (Action = lnDeleted) then
    TObject(Ptr).Free;
  inherited Notify(Ptr, Action);
end;

function TObjectList.GetItem(Index: Integer): TObject;
begin
  GetItem := TObject(inherited Items[Index]);
end;

procedure TObjectList.SetItem(Index: Integer; AObject: TObject);
begin
  inherited Items[Index] := AObject;
end;

function TObjectList.Add(AObject: TObject): Integer;
begin
  Add := inherited Add(AObject);
end;

procedure TObjectList.Insert(Index: Integer; AObject: TObject);
begin
  inherited Insert(Index, AObject);
end;

function TObjectList.Extract(Item: TObject): TObject;
begin
  Extract := TObject(inherited Extract(Item));
end;

function TObjectList.Remove(AObject: TObject): Integer;
begin
  Remove := inherited Remove(AObject);
end;

function TObjectList.IndexOf(AObject: TObject): Integer;
begin
  IndexOf := inherited IndexOf(AObject);
end;

function TObjectList.First: TObject;
begin
  First := TObject(inherited First);
end;

function TObjectList.Last: TObject;
begin
  Last := TObject(inherited Last);
end;

end.
