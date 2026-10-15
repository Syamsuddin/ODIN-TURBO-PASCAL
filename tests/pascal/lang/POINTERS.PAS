{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program Pointers;
type
  PNode = ^TNode;
  TNode = record
    Nilai: Integer;
    Berikut: PNode;
  end;
  TFungsi = function(A, B: Integer): Integer;
var
  Kepala, P, Q: PNode;
  i, Jumlah: Integer;
  X: Integer;
  PI2: ^Integer;
  F: TFungsi;
  Arr: array[1..5] of Integer;

function Tambah(A, B: Integer): Integer; far;
begin
  Tambah := A + B;
end;

function Kali(A, B: Integer): Integer; far;
begin
  Kali := A * B;
end;

function Jumlahkan(const Data: array of Integer): LongInt;
var K: Integer; T: LongInt;
begin
  T := 0;
  for K := Low(Data) to High(Data) do T := T + Data[K];
  Jumlahkan := T;
end;

procedure Gandakan(var Data: array of Integer);
var K: Integer;
begin
  for K := 0 to High(Data) do Data[K] := Data[K] * 2;
end;

begin
  Kepala := nil;
  for i := 1 to 5 do
  begin
    New(P);
    P^.Nilai := i * i;
    P^.Berikut := Kepala;
    Kepala := P;
  end;
  P := Kepala;
  Jumlah := 0;
  while P <> nil do
  begin
    Write(P^.Nilai, ' ');
    Jumlah := Jumlah + P^.Nilai;
    P := P^.Berikut;
  end;
  WriteLn('= ', Jumlah);
  while Kepala <> nil do
  begin
    Q := Kepala^.Berikut;
    Dispose(Kepala);
    Kepala := Q;
  end;
  WriteLn(Kepala = nil, ' ', Assigned(Kepala));
  X := 41;
  PI2 := @X;
  PI2^ := PI2^ + 1;
  WriteLn(X);
  F := Tambah;
  WriteLn(F(3, 4));
  F := Kali;
  WriteLn(F(3, 4));
  for i := 1 to 5 do Arr[i] := i;
  WriteLn(Jumlahkan(Arr));
  Gandakan(Arr);
  for i := 1 to 5 do Write(Arr[i], ' ');
  WriteLn;
end.
