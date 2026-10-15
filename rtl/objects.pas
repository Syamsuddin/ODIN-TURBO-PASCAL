{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Objects dari runtime library Odin: TObject, TPoint/TRect, collection,
  stream, dan registrasi tipe untuk Put/Get. Implementasi clean-room
  berdasarkan dokumentasi publik Turbo Vision/Objects TP7 dan pengamatan
  keluaran program. Ukuran dan format stream mengikuti FPC 64-bit:
  Sw_Integer = LongInt, ObjType 4 byte, panjang StrWrite 2 byte. }
unit Objects;

{$R-,Q-,I-,X+}

interface

const
  stCreate = $3C00;
  stOpenRead = $3D00;
  stOpenWrite = $3D01;
  stOpen = $3D02;

  stOk = 0;
  stError = -1;
  stInitError = -2;
  stReadError = -3;
  stWriteError = -4;
  stGetError = -5;
  stPutError = -6;
  stSeekError = -7;

  coIndexError = -1;
  coOverflow = -2;

  MaxBytes = 16777216;
  MaxCollectionSize = MaxBytes div SizeOf(Pointer);

type
  Sw_Word = LongWord;
  Sw_Integer = LongInt;
  FNameStr = String;

  TCharSet = set of Char;
  PCharSet = ^TCharSet;
  TWordArray = array[0..32767] of Word;
  PWordArray = ^TWordArray;

  PObject = ^TObject;
  TObject = object
    constructor Init;
    procedure Free;
    destructor Done; virtual;
  end;

  PPoint = ^TPoint;
  TPoint = object
    X, Y: Sw_Integer;
  end;

  PRect = ^TRect;
  TRect = object
    A, B: TPoint;
    procedure Assign(XA, YA, XB, YB: Sw_Integer);
    procedure Copy(R: TRect);
    procedure Move(ADX, ADY: Sw_Integer);
    procedure Grow(ADX, ADY: Sw_Integer);
    procedure Intersect(R: TRect);
    procedure Union(R: TRect);
    function Contains(P: TPoint): Boolean;
    function Equals(R: TRect): Boolean;
    function Empty: Boolean;
  end;

  PStream = ^TStream;

  PStreamRec = ^TStreamRec;
  TStreamRec = packed record
    ObjType: Sw_Word;
    VmtLink: PtrUInt;
    Load: Pointer;
    Store: Pointer;
    Next: PStreamRec;
  end;

  TStream = object(TObject)
    Status: Sw_Integer;
    ErrorInfo: Sw_Integer;
    StreamSize: LongInt;
    Position: LongInt;
    procedure CopyFrom(var S: TStream; Count: LongInt);
    procedure Error(Code, Info: Sw_Integer); virtual;
    procedure Flush; virtual;
    function Get: PObject;
    function GetPos: LongInt; virtual;
    function GetSize: LongInt; virtual;
    procedure Put(P: PObject);
    procedure Read(var Buf; Count: LongInt); virtual;
    function ReadStr: PString;
    procedure Reset;
    procedure Seek(Pos: LongInt); virtual;
    function StrRead: PChar;
    procedure StrWrite(P: PChar);
    procedure Truncate; virtual;
    procedure Write(var Buf; Count: LongInt); virtual;
    procedure WriteStr(P: PString);
  end;

  PDosStream = ^TDosStream;
  TDosStream = object(TStream)
    Handle: LongInt;
    constructor Init(FileName: FNameStr; Mode: Word);
    destructor Done; virtual;
    function GetSize: LongInt; virtual;
    procedure Read(var Buf; Count: LongInt); virtual;
    procedure Seek(Pos: LongInt); virtual;
    procedure Truncate; virtual;
    procedure Write(var Buf; Count: LongInt); virtual;
  end;

  PBufStream = ^TBufStream;
  TBufStream = object(TDosStream)
    Buffer: PByteArray;
    BufSize: LongInt;
    BufPtr: LongInt;
    BufEnd: LongInt;
    BufStart: LongInt;
    Dirty: Boolean;
    constructor Init(FileName: FNameStr; Mode: Word; Size: LongInt);
    destructor Done; virtual;
    procedure Flush; virtual;
    function GetSize: LongInt; virtual;
    procedure Read(var Buf; Count: LongInt); virtual;
    procedure Seek(Pos: LongInt); virtual;
    procedure Truncate; virtual;
    procedure Write(var Buf; Count: LongInt); virtual;
  end;

  PMemoryStream = ^TMemoryStream;
  TMemoryStream = object(TStream)
    Data: PByteArray;
    Capacity: LongInt;
    BlockSize: LongInt;
    constructor Init(ALimit: LongInt; ABlockSize: Word);
    destructor Done; virtual;
    procedure Read(var Buf; Count: LongInt); virtual;
    procedure Seek(Pos: LongInt); virtual;
    procedure Truncate; virtual;
    procedure Write(var Buf; Count: LongInt); virtual;
  end;

  PItemList = ^TItemList;
  TItemList = array[0..MaxCollectionSize - 1] of Pointer;

  PCollection = ^TCollection;
  TCollection = object(TObject)
    Items: PItemList;
    Count: Sw_Integer;
    Limit: Sw_Integer;
    Delta: Sw_Integer;
    constructor Init(ALimit, ADelta: Sw_Integer);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    function At(Index: Sw_Integer): Pointer;
    procedure AtDelete(Index: Sw_Integer);
    procedure AtFree(Index: Sw_Integer);
    procedure AtInsert(Index: Sw_Integer; Item: Pointer);
    procedure AtPut(Index: Sw_Integer; Item: Pointer);
    procedure Delete(Item: Pointer);
    procedure DeleteAll;
    procedure Error(Code, Info: Sw_Integer); virtual;
    function FirstThat(Test: Pointer): Pointer;
    procedure ForEach(Action: Pointer);
    procedure Free(Item: Pointer);
    procedure FreeAll;
    procedure FreeItem(Item: Pointer); virtual;
    function GetItem(var S: TStream): Pointer; virtual;
    function IndexOf(Item: Pointer): Sw_Integer; virtual;
    procedure Insert(Item: Pointer); virtual;
    function LastThat(Test: Pointer): Pointer;
    procedure Pack;
    procedure PutItem(var S: TStream; Item: Pointer); virtual;
    procedure SetLimit(ALimit: Sw_Integer); virtual;
    procedure Store(var S: TStream);
  end;

  PSortedCollection = ^TSortedCollection;
  TSortedCollection = object(TCollection)
    Duplicates: Boolean;
    constructor Init(ALimit, ADelta: Sw_Integer);
    constructor Load(var S: TStream);
    function Compare(Key1, Key2: Pointer): Sw_Integer; virtual;
    function IndexOf(Item: Pointer): Sw_Integer; virtual;
    procedure Insert(Item: Pointer); virtual;
    function KeyOf(Item: Pointer): Pointer; virtual;
    function Search(Key: Pointer; var Index: Sw_Integer): Boolean; virtual;
    procedure Store(var S: TStream);
  end;

  PStringCollection = ^TStringCollection;
  TStringCollection = object(TSortedCollection)
    function Compare(Key1, Key2: Pointer): Sw_Integer; virtual;
    procedure FreeItem(Item: Pointer); virtual;
    function GetItem(var S: TStream): Pointer; virtual;
    procedure PutItem(var S: TStream; Item: Pointer); virtual;
  end;

  PStrCollection = ^TStrCollection;
  TStrCollection = object(TSortedCollection)
    function Compare(Key1, Key2: Pointer): Sw_Integer; virtual;
    procedure FreeItem(Item: Pointer); virtual;
    function GetItem(var S: TStream): Pointer; virtual;
    procedure PutItem(var S: TStream; Item: Pointer); virtual;
  end;

const
  { procedure(var S: TStream), called by TStream.Error }
  StreamError: Pointer = nil;

  RCollection: TStreamRec = (
    ObjType: 50;
    VmtLink: Ofs(TypeOf(TCollection)^);
    Load: @TCollection.Load;
    Store: @TCollection.Store);
  RStringCollection: TStreamRec = (
    ObjType: 51;
    VmtLink: Ofs(TypeOf(TStringCollection)^);
    Load: @TStringCollection.Load;
    Store: @TStringCollection.Store);
  RStrCollection: TStreamRec = (
    ObjType: 69;
    VmtLink: Ofs(TypeOf(TStrCollection)^);
    Load: @TStrCollection.Load;
    Store: @TStrCollection.Store);

procedure Abstract;
function NewStr(const S: String): PString;
procedure DisposeStr(P: PString);
procedure RegisterType(var S: TStreamRec);
procedure RegisterObjects;

implementation

uses Strings;

{ Calling conventions of the Odin compiler (rtl/COMPILER_INTERFACE.md):
  Self is the first parameter, a constructor also gets the VMT and returns
  Self (allocating it when called with nil). }
type
  TLoadCtor = function(Self, Vmt: Pointer; var S: TStream): Pointer;
  TStoreProc = procedure(Self: Pointer; var S: TStream);
  TStreamErrorProc = procedure(var S: TStream);

function CallerFrame: Pointer; external 'odinrtl' name 'ODIN_CALLERFRAME';
procedure CallLocal(Code, Frame, Item: Pointer); external 'odinrtl' name 'ODIN_CALLLOCAL';
function CallLocalTest(Code, Frame, Item: Pointer): Boolean; external 'odinrtl' name 'ODIN_CALLLOCAL';

{$IFDEF WINDOWS}
{ The UCRT's POSIX-style functions: underscored names, 32-bit counts. }
function c_open(Path: PChar; Flags, Mode: LongInt): LongInt; cdecl; external 'c' name '_open';
function c_close(Fd: LongInt): LongInt; cdecl; external 'c' name '_close';
function c_read(Fd: LongInt; Buf: Pointer; Count: LongInt): LongInt; cdecl; external 'c' name '_read';
function c_write(Fd: LongInt; Buf: Pointer; Count: LongInt): LongInt; cdecl; external 'c' name '_write';
function c_lseek(Fd: LongInt; Offset: Int64; Whence: LongInt): Int64; cdecl; external 'c' name '_lseeki64';
function c_ftruncate(Fd: LongInt; Length: Int64): LongInt; cdecl; external 'c' name '_chsize_s';
function c_errno: PLongInt; cdecl; external 'c' name '_errno';
{$ELSE}
function c_open(Path: PChar; Flags, Mode: LongInt): LongInt; cdecl; external 'c' name 'open';
function c_close(Fd: LongInt): LongInt; cdecl; external 'c' name 'close';
function c_read(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'read';
function c_write(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'write';
function c_lseek(Fd: LongInt; Offset: Int64; Whence: LongInt): Int64; cdecl; external 'c' name 'lseek';
function c_ftruncate(Fd: LongInt; Length: Int64): LongInt; cdecl; external 'c' name 'ftruncate';
{$IFDEF DARWIN}
function c_errno: PLongInt; cdecl; external 'c' name '__error';
{$ELSE}
function c_errno: PLongInt; cdecl; external 'c' name '__errno_location';
{$ENDIF}
{$ENDIF}

const
{$IFDEF WINDOWS}
  { _O_BINARY ($8000) in every mode: no newline translation. }
  O_RDONLY = $8000;
  O_WRONLY = $8001;
  O_RDWR = $8002;
  O_CREAT = $100;
  O_TRUNC = $200;
{$ELSE}
  O_RDONLY = 0;
  O_WRONLY = 1;
  O_RDWR = 2;
{$IFDEF DARWIN}
  O_CREAT = $200;
  O_TRUNC = $400;
{$ELSE}
  O_CREAT = $40;
  O_TRUNC = $200;
{$ENDIF}
{$ENDIF}

var
  StreamTypes: PStreamRec;

{ ---- helpers ---------------------------------------------------------------- }

procedure Abstract;
begin
  RunError(211);
end;

function NewStr(const S: String): PString;
var
  P: PString;
begin
  if S = '' then
    NewStr := nil
  else
  begin
    GetMem(P, Length(S) + 1);
    P^ := S;
    NewStr := P;
  end;
end;

procedure DisposeStr(P: PString);
begin
  if P <> nil then
    FreeMem(P, Length(P^) + 1);
end;

procedure RegisterType(var S: TStreamRec);
var
  P: PStreamRec;
begin
  P := StreamTypes;
  while P <> nil do
  begin
    if P = @S then
      Exit;
    if P^.ObjType = S.ObjType then
      RunError(212);
    P := P^.Next;
  end;
  S.Next := StreamTypes;
  StreamTypes := @S;
end;

procedure RegisterObjects;
begin
  RegisterType(RCollection);
  RegisterType(RStringCollection);
  RegisterType(RStrCollection);
end;

{ ---- TObject ---------------------------------------------------------------- }

{ Clears every field after the VMT pointer, using the size of the actual
  type from the VMT. }
constructor TObject.Init;
var
  Size: Int64;
begin
  Size := PInt64(TypeOf(Self))^;
  if Size > SizeOf(Pointer) then
    FillChar(PByteArray(@Self)^[SizeOf(Pointer)], Size - SizeOf(Pointer), 0);
end;

procedure TObject.Free;
var
  P: PObject;
begin
  P := @Self;
  Dispose(P, Done);
end;

destructor TObject.Done;
begin
end;

{ ---- TRect ------------------------------------------------------------------ }

procedure TRect.Assign(XA, YA, XB, YB: Sw_Integer);
begin
  A.X := XA;
  A.Y := YA;
  B.X := XB;
  B.Y := YB;
end;

procedure TRect.Copy(R: TRect);
begin
  A := R.A;
  B := R.B;
end;

procedure TRect.Move(ADX, ADY: Sw_Integer);
begin
  Inc(A.X, ADX);
  Inc(A.Y, ADY);
  Inc(B.X, ADX);
  Inc(B.Y, ADY);
end;

procedure CheckEmpty(var R: TRect);
begin
  if (R.A.X >= R.B.X) or (R.A.Y >= R.B.Y) then
    R.Assign(0, 0, 0, 0);
end;

procedure TRect.Grow(ADX, ADY: Sw_Integer);
begin
  Dec(A.X, ADX);
  Dec(A.Y, ADY);
  Inc(B.X, ADX);
  Inc(B.Y, ADY);
  CheckEmpty(Self);
end;

procedure TRect.Intersect(R: TRect);
begin
  if R.A.X > A.X then A.X := R.A.X;
  if R.A.Y > A.Y then A.Y := R.A.Y;
  if R.B.X < B.X then B.X := R.B.X;
  if R.B.Y < B.Y then B.Y := R.B.Y;
  CheckEmpty(Self);
end;

procedure TRect.Union(R: TRect);
begin
  if R.A.X < A.X then A.X := R.A.X;
  if R.A.Y < A.Y then A.Y := R.A.Y;
  if R.B.X > B.X then B.X := R.B.X;
  if R.B.Y > B.Y then B.Y := R.B.Y;
end;

function TRect.Contains(P: TPoint): Boolean;
begin
  Contains := (P.X >= A.X) and (P.X < B.X) and (P.Y >= A.Y) and (P.Y < B.Y);
end;

function TRect.Equals(R: TRect): Boolean;
begin
  Equals := (A.X = R.A.X) and (A.Y = R.A.Y) and (B.X = R.B.X) and (B.Y = R.B.Y);
end;

function TRect.Empty: Boolean;
begin
  Empty := (A.X >= B.X) or (A.Y >= B.Y);
end;

{ ---- TStream ---------------------------------------------------------------- }

procedure TStream.CopyFrom(var S: TStream; Count: LongInt);
var
  Buffer: array[0..1023] of Byte;
  N: LongInt;
begin
  while (Count > 0) and (Status = stOk) and (S.Status = stOk) do
  begin
    N := Count;
    if N > SizeOf(Buffer) then
      N := SizeOf(Buffer);
    S.Read(Buffer, N);
    Write(Buffer, N);
    Dec(Count, N);
  end;
end;

procedure TStream.Error(Code, Info: Sw_Integer);
begin
  Status := Code;
  ErrorInfo := Info;
  if StreamError <> nil then
    TStreamErrorProc(StreamError)(Self);
end;

procedure TStream.Flush;
begin
end;

function TStream.Get: PObject;
var
  ObjType: Sw_Word;
  P: PStreamRec;
begin
  Get := nil;
  ObjType := 0;
  Read(ObjType, SizeOf(ObjType));
  if (ObjType = 0) or (Status <> stOk) then
    Exit;
  P := StreamTypes;
  while (P <> nil) and (P^.ObjType <> ObjType) do
    P := P^.Next;
  if P = nil then
  begin
    Error(stGetError, ObjType);
    Exit;
  end;
  Get := PObject(TLoadCtor(P^.Load)(nil, Pointer(P^.VmtLink), Self));
end;

function TStream.GetPos: LongInt;
begin
  if Status = stOk then
    GetPos := Position
  else
    GetPos := -1;
end;

function TStream.GetSize: LongInt;
begin
  if Status = stOk then
    GetSize := StreamSize
  else
    GetSize := -1;
end;

procedure TStream.Put(P: PObject);
var
  ObjType: Sw_Word;
  R: PStreamRec;
begin
  if P = nil then
  begin
    ObjType := 0;
    Write(ObjType, SizeOf(ObjType));
    Exit;
  end;
  R := StreamTypes;
  while (R <> nil) and (R^.VmtLink <> PtrUInt(TypeOf(P^))) do
    R := R^.Next;
  if R = nil then
  begin
    Error(stPutError, 0);
    Exit;
  end;
  ObjType := R^.ObjType;
  Write(ObjType, SizeOf(ObjType));
  TStoreProc(R^.Store)(P, Self);
end;

procedure TStream.Read(var Buf; Count: LongInt);
begin
  Abstract;
end;

function TStream.ReadStr: PString;
var
  L: Byte;
  P: PString;
begin
  L := 0;
  Read(L, 1);
  if L = 0 then
    ReadStr := nil
  else
  begin
    GetMem(P, L + 1);
    PByteArray(P)^[0] := L;
    Read(PByteArray(P)^[1], L);
    ReadStr := P;
  end;
end;

procedure TStream.Reset;
begin
  Status := stOk;
  ErrorInfo := 0;
end;

procedure TStream.Seek(Pos: LongInt);
begin
  Abstract;
end;

function TStream.StrRead: PChar;
var
  L: Word;
  P: PChar;
begin
  L := 0;
  Read(L, SizeOf(L));
  if L = 0 then
    StrRead := nil
  else
  begin
    GetMem(P, L + 1);
    Read(P^, L);
    P[L] := #0;
    StrRead := P;
  end;
end;

procedure TStream.StrWrite(P: PChar);
var
  L: Word;
begin
  L := 0;
  if P <> nil then
    L := StrLen(P);
  Write(L, SizeOf(L));
  if L > 0 then
    Write(P^, L);
end;

procedure TStream.Truncate;
begin
  Abstract;
end;

procedure TStream.Write(var Buf; Count: LongInt);
begin
  Abstract;
end;

procedure TStream.WriteStr(P: PString);
var
  Zero: Byte;
begin
  if P <> nil then
    Write(P^, Length(P^) + 1)
  else
  begin
    Zero := 0;
    Write(Zero, 1);
  end;
end;

{ ---- TMemoryStream ------------------------------------------------------------ }

constructor TMemoryStream.Init(ALimit: LongInt; ABlockSize: Word);
begin
  inherited Init;
  BlockSize := ABlockSize;
  if BlockSize = 0 then
    BlockSize := 1;
  if ALimit > 0 then
  begin
    Capacity := (ALimit + BlockSize - 1) div BlockSize * BlockSize;
    GetMem(Data, Capacity);
  end;
end;

destructor TMemoryStream.Done;
begin
  if Data <> nil then
    FreeMem(Data, Capacity);
  Data := nil;
  Capacity := 0;
  inherited Done;
end;

procedure TMemoryStream.Read(var Buf; Count: LongInt);
begin
  if (Status <> stOk) or (Position + Count > StreamSize) then
  begin
    FillChar(Buf, Count, 0);
    if Status = stOk then
      Error(stReadError, 0);
    Exit;
  end;
  if Count > 0 then
    System.Move(Data^[Position], Buf, Count);
  Inc(Position, Count);
end;

procedure TMemoryStream.Seek(Pos: LongInt);
begin
  if Status <> stOk then
    Exit;
  if (Pos < 0) or (Pos > StreamSize) then
    Error(stSeekError, Pos)
  else
    Position := Pos;
end;

procedure TMemoryStream.Truncate;
begin
  if Status = stOk then
    StreamSize := Position;
end;

procedure TMemoryStream.Write(var Buf; Count: LongInt);
var
  NewCapacity: LongInt;
  NewData: PByteArray;
begin
  if (Status <> stOk) or (Count <= 0) then
    Exit;
  if Position + Count > Capacity then
  begin
    NewCapacity := (Position + Count + BlockSize - 1) div BlockSize * BlockSize;
    GetMem(NewData, NewCapacity);
    if Data <> nil then
    begin
      System.Move(Data^, NewData^, StreamSize);
      FreeMem(Data, Capacity);
    end;
    Data := NewData;
    Capacity := NewCapacity;
  end;
  System.Move(Buf, Data^[Position], Count);
  Inc(Position, Count);
  if Position > StreamSize then
    StreamSize := Position;
end;

{ ---- TDosStream --------------------------------------------------------------- }

constructor TDosStream.Init(FileName: FNameStr; Mode: Word);
var
  Name: array[0..255] of Char;
  Flags: LongInt;
begin
  inherited Init;
  Handle := -1;
  StrPCopy(Name, FileName);
  case Mode of
    stCreate: Flags := O_RDWR or O_CREAT or O_TRUNC;
    stOpenRead: Flags := O_RDONLY;
    stOpenWrite: Flags := O_WRONLY;
  else
    Flags := O_RDWR;
  end;
  Handle := c_open(Name, Flags, 438);
  if Handle < 0 then
  begin
    Handle := -1;
    Error(stInitError, c_errno^);
    Exit;
  end;
  StreamSize := c_lseek(Handle, 0, 2);
  c_lseek(Handle, 0, 0);
  Position := 0;
end;

destructor TDosStream.Done;
begin
  if Handle >= 0 then
    c_close(Handle);
  Handle := -1;
  inherited Done;
end;

function TDosStream.GetSize: LongInt;
begin
  if Status = stOk then
    GetSize := StreamSize
  else
    GetSize := -1;
end;

procedure TDosStream.Read(var Buf; Count: LongInt);
var
  Done, N: Int64;
  P: PByteArray;
begin
  P := @Buf;
  if Status <> stOk then
  begin
    FillChar(Buf, Count, 0);
    Exit;
  end;
  Done := 0;
  while Done < Count do
  begin
    N := c_read(Handle, @P^[Done], Count - Done);
    if N <= 0 then
      Break;
    Done := Done + N;
  end;
  Inc(Position, Done);
  if Done < Count then
  begin
    FillChar(P^[Done], Count - Done, 0);
    Error(stReadError, 0);
  end;
end;

procedure TDosStream.Seek(Pos: LongInt);
begin
  if Status <> stOk then
    Exit;
  if (Pos < 0) or (c_lseek(Handle, Pos, 0) < 0) then
    Error(stSeekError, Pos)
  else
    Position := Pos;
end;

procedure TDosStream.Truncate;
begin
  if Status <> stOk then
    Exit;
  if c_ftruncate(Handle, Position) <> 0 then
    Error(stError, c_errno^)
  else
    StreamSize := Position;
end;

procedure TDosStream.Write(var Buf; Count: LongInt);
var
  Done, N: Int64;
  P: PByteArray;
begin
  if (Status <> stOk) or (Count <= 0) then
    Exit;
  P := @Buf;
  Done := 0;
  while Done < Count do
  begin
    N := c_write(Handle, @P^[Done], Count - Done);
    if N <= 0 then
    begin
      Error(stWriteError, c_errno^);
      Exit;
    end;
    Done := Done + N;
  end;
  Inc(Position, Done);
  if Position > StreamSize then
    StreamSize := Position;
end;

{ ---- TBufStream ---------------------------------------------------------------- }

{ The buffer holds file bytes BufStart..BufStart + BufEnd - 1; BufPtr is the
  current position inside it. Dirty means it holds written bytes not yet in
  the file. }

constructor TBufStream.Init(FileName: FNameStr; Mode: Word; Size: LongInt);
begin
  inherited Init(FileName, Mode);
  if Size < 1 then
    Size := 1;
  BufSize := Size;
  GetMem(Buffer, BufSize);
end;

destructor TBufStream.Done;
begin
  Flush;
  if Buffer <> nil then
    FreeMem(Buffer, BufSize);
  Buffer := nil;
  inherited Done;
end;

procedure TBufStream.Flush;
var
  Done, N: Int64;
begin
  if Dirty and (Handle >= 0) then
  begin
    c_lseek(Handle, BufStart, 0);
    Done := 0;
    while Done < BufEnd do
    begin
      N := c_write(Handle, @Buffer^[Done], BufEnd - Done);
      if N <= 0 then
      begin
        Error(stWriteError, c_errno^);
        Break;
      end;
      Done := Done + N;
    end;
  end;
  Dirty := False;
  BufStart := Position;
  BufPtr := 0;
  BufEnd := 0;
  if Handle >= 0 then
    c_lseek(Handle, Position, 0);
end;

function TBufStream.GetSize: LongInt;
begin
  GetSize := inherited GetSize;
end;

procedure TBufStream.Read(var Buf; Count: LongInt);
var
  P: PByteArray;
  Done, N: LongInt;
begin
  P := @Buf;
  if (Status <> stOk) or (Position + Count > StreamSize) then
  begin
    FillChar(Buf, Count, 0);
    if Status = stOk then
      Error(stReadError, 0);
    Exit;
  end;
  if Dirty then
    Flush;
  Done := 0;
  while Done < Count do
  begin
    if BufPtr >= BufEnd then
    begin
      BufStart := Position;
      BufPtr := 0;
      c_lseek(Handle, BufStart, 0);
      BufEnd := c_read(Handle, Buffer, BufSize);
      if BufEnd <= 0 then
      begin
        BufEnd := 0;
        FillChar(P^[Done], Count - Done, 0);
        Error(stReadError, 0);
        Exit;
      end;
    end;
    N := BufEnd - BufPtr;
    if N > Count - Done then
      N := Count - Done;
    System.Move(Buffer^[BufPtr], P^[Done], N);
    Inc(BufPtr, N);
    Inc(Done, N);
    Inc(Position, N);
  end;
end;

{ A file stream may be positioned past its end (reading there fails,
  writing there extends the file). }
procedure TBufStream.Seek(Pos: LongInt);
begin
  if Status <> stOk then
    Exit;
  if Pos < 0 then
  begin
    Error(stSeekError, Pos);
    Exit;
  end;
  Flush;
  Position := Pos;
  BufStart := Pos;
  c_lseek(Handle, Pos, 0);
end;

procedure TBufStream.Truncate;
begin
  Flush;
  inherited Truncate;
end;

procedure TBufStream.Write(var Buf; Count: LongInt);
var
  P: PByteArray;
  Done, N: LongInt;
begin
  if (Status <> stOk) or (Count <= 0) then
    Exit;
  if not Dirty then
  begin
    { Drop bytes buffered for reading; writing starts here. }
    BufStart := Position;
    BufPtr := 0;
    BufEnd := 0;
  end;
  P := @Buf;
  Done := 0;
  while Done < Count do
  begin
    if BufPtr >= BufSize then
    begin
      Flush;
      if Status <> stOk then
        Exit;
    end;
    N := BufSize - BufPtr;
    if N > Count - Done then
      N := Count - Done;
    System.Move(P^[Done], Buffer^[BufPtr], N);
    Inc(BufPtr, N);
    if BufPtr > BufEnd then
      BufEnd := BufPtr;
    Dirty := True;
    Inc(Done, N);
    Inc(Position, N);
  end;
  if Position > StreamSize then
    StreamSize := Position;
end;

{ ---- TCollection ------------------------------------------------------------------ }

constructor TCollection.Init(ALimit, ADelta: Sw_Integer);
begin
  inherited Init;
  Delta := ADelta;
  SetLimit(ALimit);
end;

constructor TCollection.Load(var S: TStream);
var
  C, I: Sw_Integer;
begin
  S.Read(Count, SizeOf(Sw_Integer) * 3);
  Items := nil;
  C := Count;
  I := Limit;
  Count := 0;
  Limit := 0;
  SetLimit(I);
  Count := C;
  for I := 0 to C - 1 do
    AtPut(I, GetItem(S));
end;

destructor TCollection.Done;
begin
  FreeAll;
  SetLimit(0);
end;

function TCollection.At(Index: Sw_Integer): Pointer;
begin
  if (Index < 0) or (Index >= Count) then
  begin
    Error(coIndexError, Index);
    At := nil;
  end
  else
    At := Items^[Index];
end;

procedure TCollection.AtDelete(Index: Sw_Integer);
begin
  if (Index < 0) or (Index >= Count) then
  begin
    Error(coIndexError, Index);
    Exit;
  end;
  if Index < Count - 1 then
    System.Move(Items^[Index + 1], Items^[Index], (Count - Index - 1) * SizeOf(Pointer));
  Dec(Count);
end;

procedure TCollection.AtFree(Index: Sw_Integer);
var
  Item: Pointer;
begin
  Item := At(Index);
  AtDelete(Index);
  FreeItem(Item);
end;

procedure TCollection.AtInsert(Index: Sw_Integer; Item: Pointer);
begin
  if (Index < 0) or (Index > Count) then
  begin
    Error(coIndexError, Index);
    Exit;
  end;
  if Count = Limit then
    SetLimit(Limit + Delta);
  if Count = Limit then
  begin
    Error(coOverflow, Index);
    Exit;
  end;
  if Index < Count then
    System.Move(Items^[Index], Items^[Index + 1], (Count - Index) * SizeOf(Pointer));
  Items^[Index] := Item;
  Inc(Count);
end;

procedure TCollection.AtPut(Index: Sw_Integer; Item: Pointer);
begin
  if (Index < 0) or (Index >= Count) then
    Error(coIndexError, Index)
  else
    Items^[Index] := Item;
end;

procedure TCollection.Delete(Item: Pointer);
begin
  AtDelete(IndexOf(Item));
end;

procedure TCollection.DeleteAll;
begin
  Count := 0;
end;

procedure TCollection.Error(Code, Info: Sw_Integer);
begin
  RunError(212 - Code);
end;

{ Test and Action are procedures nested in the caller, as in TP: they are
  called with the caller's frame as their static link. }
function TCollection.FirstThat(Test: Pointer): Pointer;
var
  Frame: Pointer;
  I: Sw_Integer;
begin
  Frame := CallerFrame;
  for I := 0 to Count - 1 do
    if CallLocalTest(Test, Frame, Items^[I]) then
    begin
      FirstThat := Items^[I];
      Exit;
    end;
  FirstThat := nil;
end;

procedure TCollection.ForEach(Action: Pointer);
var
  Frame: Pointer;
  I, N: Sw_Integer;
begin
  Frame := CallerFrame;
  N := Count;
  for I := 0 to N - 1 do
    CallLocal(Action, Frame, Items^[I]);
end;

function TCollection.LastThat(Test: Pointer): Pointer;
var
  Frame: Pointer;
  I: Sw_Integer;
begin
  Frame := CallerFrame;
  for I := Count - 1 downto 0 do
    if CallLocalTest(Test, Frame, Items^[I]) then
    begin
      LastThat := Items^[I];
      Exit;
    end;
  LastThat := nil;
end;

procedure TCollection.Free(Item: Pointer);
begin
  Delete(Item);
  FreeItem(Item);
end;

procedure TCollection.FreeAll;
var
  I: Sw_Integer;
begin
  for I := Count - 1 downto 0 do
    FreeItem(At(I));
  Count := 0;
end;

procedure TCollection.FreeItem(Item: Pointer);
var
  P: PObject;
begin
  if Item <> nil then
  begin
    P := Item;
    Dispose(P, Done);
  end;
end;

function TCollection.GetItem(var S: TStream): Pointer;
begin
  GetItem := S.Get;
end;

function TCollection.IndexOf(Item: Pointer): Sw_Integer;
var
  I: Sw_Integer;
begin
  for I := 0 to Count - 1 do
    if Items^[I] = Item then
    begin
      IndexOf := I;
      Exit;
    end;
  IndexOf := -1;
end;

procedure TCollection.Insert(Item: Pointer);
begin
  AtInsert(Count, Item);
end;

procedure TCollection.Pack;
var
  I, J: Sw_Integer;
begin
  J := 0;
  for I := 0 to Count - 1 do
    if Items^[I] <> nil then
    begin
      Items^[J] := Items^[I];
      Inc(J);
    end;
  Count := J;
end;

procedure TCollection.PutItem(var S: TStream; Item: Pointer);
begin
  S.Put(Item);
end;

procedure TCollection.SetLimit(ALimit: Sw_Integer);
var
  NewItems: PItemList;
begin
  if ALimit < Count then
    ALimit := Count;
  if ALimit > MaxCollectionSize then
    ALimit := MaxCollectionSize;
  if ALimit = Limit then
    Exit;
  NewItems := nil;
  if ALimit > 0 then
  begin
    GetMem(NewItems, ALimit * SizeOf(Pointer));
    if (Count > 0) and (Items <> nil) then
      System.Move(Items^, NewItems^, Count * SizeOf(Pointer));
  end;
  if (Limit > 0) and (Items <> nil) then
    FreeMem(Items, Limit * SizeOf(Pointer));
  Items := NewItems;
  Limit := ALimit;
end;

procedure TCollection.Store(var S: TStream);
var
  I: Sw_Integer;
begin
  S.Write(Count, SizeOf(Sw_Integer) * 3);
  for I := 0 to Count - 1 do
    PutItem(S, Items^[I]);
end;

{ ---- TSortedCollection -------------------------------------------------------------- }

constructor TSortedCollection.Init(ALimit, ADelta: Sw_Integer);
begin
  inherited Init(ALimit, ADelta);
  Duplicates := False;
end;

constructor TSortedCollection.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Duplicates, SizeOf(Duplicates));
end;

function TSortedCollection.Compare(Key1, Key2: Pointer): Sw_Integer;
begin
  Abstract;
  Compare := 0;
end;

function TSortedCollection.IndexOf(Item: Pointer): Sw_Integer;
var
  I: Sw_Integer;
begin
  IndexOf := -1;
  if Search(KeyOf(Item), I) then
  begin
    if Duplicates then
      while (I < Count) and (Item <> Items^[I]) do
        Inc(I);
    if I < Count then
      IndexOf := I;
  end;
end;

procedure TSortedCollection.Insert(Item: Pointer);
var
  I: Sw_Integer;
begin
  if not Search(KeyOf(Item), I) or Duplicates then
    AtInsert(I, Item);
end;

function TSortedCollection.KeyOf(Item: Pointer): Pointer;
begin
  KeyOf := Item;
end;

{ Binary search; Index is where Key is (the first of equal keys) or where
  it would be inserted. }
function TSortedCollection.Search(Key: Pointer; var Index: Sw_Integer): Boolean;
var
  L, H, I, C: Sw_Integer;
begin
  Search := False;
  L := 0;
  H := Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := Compare(KeyOf(Items^[I]), Key);
    if C < 0 then
      L := I + 1
    else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Search := True;
        if not Duplicates then
          L := I;
      end;
    end;
  end;
  Index := L;
end;

procedure TSortedCollection.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Duplicates, SizeOf(Duplicates));
end;

{ ---- TStringCollection and TStrCollection -------------------------------------------- }

function TStringCollection.Compare(Key1, Key2: Pointer): Sw_Integer;
begin
  if PString(Key1)^ < PString(Key2)^ then
    Compare := -1
  else if PString(Key1)^ > PString(Key2)^ then
    Compare := 1
  else
    Compare := 0;
end;

procedure TStringCollection.FreeItem(Item: Pointer);
begin
  DisposeStr(Item);
end;

function TStringCollection.GetItem(var S: TStream): Pointer;
begin
  GetItem := S.ReadStr;
end;

procedure TStringCollection.PutItem(var S: TStream; Item: Pointer);
begin
  S.WriteStr(Item);
end;

function TStrCollection.Compare(Key1, Key2: Pointer): Sw_Integer;
begin
  Compare := StrComp(Key1, Key2);
end;

procedure TStrCollection.FreeItem(Item: Pointer);
begin
  StrDispose(Item);
end;

function TStrCollection.GetItem(var S: TStream): Pointer;
begin
  GetItem := S.StrRead;
end;

procedure TStrCollection.PutItem(var S: TStream; Item: Pointer);
begin
  S.StrWrite(Item);
end;

end.
