{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit HistList dari Odin Vision: daftar riwayat input line per nomor Id.
  Blok riwayat berisi entri [Id, panjang, teks] berurutan dari yang
  terlama; bila HistorySize terlampaui, entri terlama dibuang.
  HistoryStr(Id, 0) adalah entri terbaru. }
unit HistList;

{$R-,Q-,I-,X+}

interface

uses Objects;

const
  HistorySize: Sw_Word = 1024;

var
  HistoryBlock: Pointer;
  HistoryUsed: Sw_Word;

procedure HistoryAdd(Id: Byte; const Str: String);
function HistoryCount(Id: Byte): Word;
function HistoryStr(Id: Byte; Index: Sw_Integer): String;
procedure ClearHistory;
procedure InitHistory;
procedure DoneHistory;
procedure StoreHistory(var S: TStream);
procedure LoadHistory(var S: TStream);

implementation

function Block: PByteArray;
begin
  Block := PByteArray(HistoryBlock);
end;

{ Removes the entry at offset At. }
procedure DeleteAt(At: Sw_Word);
var
  N: Sw_Word;
begin
  N := Block^[At + 1] + 2;
  Move(Block^[At + N], Block^[At], HistoryUsed - At - N);
  Dec(HistoryUsed, N);
end;

function SameAt(At: Sw_Word; const Str: String): Boolean;
var
  I: Integer;
begin
  SameAt := False;
  if Block^[At + 1] <> Length(Str) then
    Exit;
  for I := 1 to Length(Str) do
    if Block^[At + 1 + I] <> Ord(Str[I]) then
      Exit;
  SameAt := True;
end;

procedure HistoryAdd(Id: Byte; const Str: String);
var
  At, N: Sw_Word;
begin
  if (HistoryBlock = nil) or (Str = '') then
    Exit;
  { The same string moves to the end. }
  At := 0;
  while At < HistoryUsed do
    if (Block^[At] = Id) and SameAt(At, Str) then
      DeleteAt(At)
    else
      Inc(At, Block^[At + 1] + 2);
  N := Length(Str) + 2;
  if N > HistorySize then
    Exit;
  while HistoryUsed + N > HistorySize do
    DeleteAt(0);
  Block^[HistoryUsed] := Id;
  Block^[HistoryUsed + 1] := Length(Str);
  Move(Str[1], Block^[HistoryUsed + 2], Length(Str));
  Inc(HistoryUsed, N);
end;

function HistoryCount(Id: Byte): Word;
var
  At: Sw_Word;
  N: Word;
begin
  N := 0;
  At := 0;
  while At < HistoryUsed do
  begin
    if Block^[At] = Id then
      Inc(N);
    Inc(At, Block^[At + 1] + 2);
  end;
  HistoryCount := N;
end;

function HistoryStr(Id: Byte; Index: Sw_Integer): String;
var
  At: Sw_Word;
  N, Want: Sw_Integer;
  S: String;
begin
  HistoryStr := '';
  Want := HistoryCount(Id) - 1 - Index;
  if Want < 0 then
    Exit;
  N := 0;
  At := 0;
  while At < HistoryUsed do
  begin
    if Block^[At] = Id then
    begin
      if N = Want then
      begin
        S[0] := Chr(Block^[At + 1]);
        Move(Block^[At + 2], S[1], Length(S));
        HistoryStr := S;
        Exit;
      end;
      Inc(N);
    end;
    Inc(At, Block^[At + 1] + 2);
  end;
end;

procedure ClearHistory;
begin
  HistoryUsed := 0;
end;

procedure InitHistory;
begin
  if HistoryBlock = nil then
    GetMem(HistoryBlock, HistorySize);
  HistoryUsed := 0;
end;

procedure DoneHistory;
begin
  if HistoryBlock <> nil then
    FreeMem(HistoryBlock, HistorySize);
  HistoryBlock := nil;
  HistoryUsed := 0;
end;

procedure StoreHistory(var S: TStream);
var
  Size: Sw_Word;
begin
  Size := HistoryUsed;
  S.Write(Size, SizeOf(Size));
  if Size > 0 then
    S.Write(HistoryBlock^, Size);
end;

procedure LoadHistory(var S: TStream);
var
  Size: Sw_Word;
begin
  Size := 0;
  S.Read(Size, SizeOf(Size));
  if (HistoryBlock = nil) or (Size > HistorySize) then
  begin
    S.Seek(S.GetPos + Size);
    Exit;
  end;
  if Size > 0 then
    S.Read(HistoryBlock^, Size);
  HistoryUsed := Size;
end;

end.
