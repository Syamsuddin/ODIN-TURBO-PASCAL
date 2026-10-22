{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Overlay dari runtime library Odin. Executable Odin selalu memuat
  seluruh kodenya, jadi tidak ada overlay yang perlu dimuat: unit ini hanya
  menyediakan nama dan perilaku antarmuka TP7 supaya program yang memakai
  `uses Overlay`, OvrInit, dan direktif $O tetap bisa dikompilasi dan jalan.
  OvrInit selalu berhasil, OvrInitEMS melapor tidak ada driver EMS, dan
  pengaturan buffer hanya dicatat. }
unit Overlay;

{$R-,Q-,I-,X+}

interface

const
  ovrOk = 0;
  ovrError = -1;
  ovrNotFound = -2;
  ovrNoMemory = -3;
  ovrIOError = -4;
  ovrNoEMSDriver = -5;
  ovrNoEMSMemory = -6;

type
  OvrReadFunc = function(OvrSeg: Word): Integer;

var
  OvrResult: Integer;
  OvrTrapCount: Word;
  OvrLoadCount: Word;
  OvrFileMode: Byte;
  OvrReadBuf: OvrReadFunc;
  OvrCodeList: Word;
  OvrHeapSize: Word;
  OvrDebugPtr: Word;
  OvrHeapOrg: Word;
  OvrHeapPtr: Word;
  OvrHeapEnd: Word;
  OvrLoadList: Word;
  OvrDosHandle: Word;
  OvrEmsHandle: Word;

procedure OvrInit(FileName: String);
procedure OvrInitEMS;
procedure OvrSetBuf(Size: LongInt);
function OvrGetBuf: LongInt;
procedure OvrSetRetry(Size: LongInt);
function OvrGetRetry: LongInt;
procedure OvrClearBuf;

implementation

var
  BufSize: LongInt;
  RetrySize: LongInt;

{ Semua kode sudah ada di memori, jadi berkas overlay tidak pernah dibuka. }
procedure OvrInit(FileName: String);
begin
  OvrResult := ovrOk;
end;

procedure OvrInitEMS;
begin
  OvrResult := ovrNoEMSDriver;
end;

procedure OvrSetBuf(Size: LongInt);
begin
  if Size < 0 then
    OvrResult := ovrError
  else
  begin
    BufSize := Size;
    OvrResult := ovrOk;
  end;
end;

function OvrGetBuf: LongInt;
begin
  OvrGetBuf := BufSize;
end;

procedure OvrSetRetry(Size: LongInt);
begin
  RetrySize := Size;
end;

function OvrGetRetry: LongInt;
begin
  OvrGetRetry := RetrySize;
end;

procedure OvrClearBuf;
begin
  OvrResult := ovrOk;
end;

begin
  OvrResult := ovrOk;
  OvrTrapCount := 0;
  OvrLoadCount := 0;
  OvrFileMode := 0;
  OvrReadBuf := nil;
  BufSize := 65536;
  RetrySize := BufSize div 2;
end.
