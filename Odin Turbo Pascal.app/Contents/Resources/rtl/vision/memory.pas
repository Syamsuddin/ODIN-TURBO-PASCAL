{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Memory dari Odin Vision. Di DOS unit ini mengatur kolam pengaman
  (safety pool) dan buffer yang bisa dipindah; di Odin heap tidak terbatas
  640 KB, jadi buffer dialokasikan biasa dengan ukuran tersimpan di depan
  blok, dan LowMemory selalu False. }
unit Memory;

{$R-,Q-,I-,X+}

interface

uses Objects;

const
  MaxHeapSize: Sw_Word = 655360 div 16;
  LowMemSize: Sw_Word = 4096 div 16;
  MaxBufMem: Sw_Word = 65536 div 16;

procedure InitMemory;
procedure DoneMemory;
procedure InitDosMem;
procedure DoneDosMem;
function LowMemory: Boolean;
function MemAlloc(Size: Sw_Word): Pointer;
function MemAllocSeg(Size: Sw_Word): Pointer;
procedure NewCache(var P: Pointer; Size: Sw_Word);
procedure DisposeCache(P: Pointer);
procedure NewBuffer(var P: Pointer; Size: Sw_Word);
procedure DisposeBuffer(P: Pointer);
function GetBufferSize(P: Pointer): Sw_Word;
function SetBufferSize(var P: Pointer; Size: Sw_Word): Boolean;

implementation

type
  PPtrUInt = ^PtrUInt;

const
  Header = SizeOf(PtrUInt);

procedure InitMemory;
begin
end;

procedure DoneMemory;
begin
end;

procedure InitDosMem;
begin
end;

procedure DoneDosMem;
begin
end;

function LowMemory: Boolean;
begin
  LowMemory := False;
end;

function MemAlloc(Size: Sw_Word): Pointer;
var
  P: Pointer;
begin
  GetMem(P, Size);
  MemAlloc := P;
end;

function MemAllocSeg(Size: Sw_Word): Pointer;
begin
  MemAllocSeg := MemAlloc(Size);
end;

procedure NewBuffer(var P: Pointer; Size: Sw_Word);
var
  Q: PByteArray;
begin
  GetMem(Q, Size + Header);
  PPtrUInt(Q)^ := Size;
  P := @Q^[Header];
end;

procedure DisposeBuffer(P: Pointer);
var
  Q: PByteArray;
begin
  if P = nil then
    Exit;
  Q := PByteArray(PtrUInt(P) - Header);
  FreeMem(Q, PPtrUInt(Q)^ + Header);
end;

function GetBufferSize(P: Pointer): Sw_Word;
begin
  if P = nil then
    GetBufferSize := 0
  else
    GetBufferSize := PPtrUInt(PtrUInt(P) - Header)^;
end;

{ Odin: P is a var parameter, because the buffer may move. }
function SetBufferSize(var P: Pointer; Size: Sw_Word): Boolean;
var
  Q: Pointer;
  N: Sw_Word;
begin
  NewBuffer(Q, Size);
  N := GetBufferSize(P);
  if N > Size then
    N := Size;
  if (P <> nil) and (N > 0) then
    Move(P^, Q^, N);
  DisposeBuffer(P);
  P := Q;
  SetBufferSize := True;
end;

procedure NewCache(var P: Pointer; Size: Sw_Word);
begin
  NewBuffer(P, Size);
end;

procedure DisposeCache(P: Pointer);
begin
  DisposeBuffer(P);
end;

end.
