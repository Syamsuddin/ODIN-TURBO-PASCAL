{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 19 - Unit buatan sendiri: matematika
  Unit adalah kumpulan konstanta, prosedur, dan fungsi yang bisa
  dipakai banyak program dengan "uses matematika;". Nama file harus
  sama dengan nama unit. Unit tidak bisa dijalankan sendiri: buka dan
  jalankan bab19_01_pakai_unit_sendiri.pas. }

unit matematika;

interface   { bagian umum: daftar yang boleh dipakai program lain }

const
  VersiUnit = '1.0';

function Kuadrat(X: LongInt): LongInt;
function Pangkat(A: LongInt; N: Integer): LongInt;
function Faktorial(N: Integer): LongInt;
function Prima(N: LongInt): Boolean;
function FPB(A, B: LongInt): LongInt;
function KPK(A, B: LongInt): LongInt;

implementation  { bagian dalam: isi lengkap setiap fungsi }

function Kuadrat(X: LongInt): LongInt;
begin
  Kuadrat := X * X;
end;

function Pangkat(A: LongInt; N: Integer): LongInt;
var
  I: Integer;
  Hasil: LongInt;
begin
  Hasil := 1;
  for I := 1 to N do
    Hasil := Hasil * A;
  Pangkat := Hasil;
end;

function Faktorial(N: Integer): LongInt;
begin
  if N <= 1 then
    Faktorial := 1
  else
    Faktorial := N * Faktorial(N - 1);
end;

function Prima(N: LongInt): Boolean;
var
  Pembagi: LongInt;
begin
  Prima := N >= 2;
  Pembagi := 2;
  while Pembagi * Pembagi <= N do
  begin
    if N mod Pembagi = 0 then
    begin
      Prima := False;
      Exit;
    end;
    Pembagi := Pembagi + 1;
  end;
end;

function FPB(A, B: LongInt): LongInt;
var
  Sisa: LongInt;
begin
  while B <> 0 do                        { algoritma Euclid, Bab 8.2 }
  begin
    Sisa := A mod B;
    A := B;
    B := Sisa;
  end;
  FPB := A;
end;

function KPK(A, B: LongInt): LongInt;
begin
  KPK := A div FPB(A, B) * B;            { memakai fungsi lain di unit ini }
end;

end.
