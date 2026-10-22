unit AIMath;
interface
uses AITypes;
function Clamp(X, Lo, Hi: TFloat): TFloat;
function Sigmoid(X: TFloat): TFloat;
function SafeExp(X: TFloat; var Value: TFloat): Boolean;
function SafeLn(X: TFloat; var Value: TFloat): Boolean;
function SafeSqrt(X: TFloat; var Value: TFloat): Boolean;
function IntPower(X: TFloat; N: Integer; var Value: TFloat): Boolean;
function DotProduct(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
function DistanceSquared(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
function Euclidean(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
function Manhattan(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
procedure AISetSeed(Seed: LongInt);
function AIRandom: TFloat;
function AIRandomInt(Limit: Integer): Integer;

function MatrixInit(var M: TMatrix; Rows, Cols: Integer): Boolean;
function MatrixIdentity(var M: TMatrix; N: Integer): Boolean;
function MatrixAdd(var A,B,C: TMatrix): Boolean;
function MatrixSubtract(var A,B,C: TMatrix): Boolean;
function MatrixScale(var A: TMatrix; Factor: TFloat;
  var C: TMatrix): Boolean;
function MatrixTranspose(var A,C: TMatrix): Boolean;
function MatrixMultiply(var A,B,C: TMatrix): Boolean;
implementation
var State: LongInt;
function Clamp(X, Lo, Hi: TFloat): TFloat;
begin
  ClearAIError;
  if Lo > Hi then begin
    SetAIError(ErrValue, 'Batas Clamp terbalik'); Clamp := 0; Exit
  end;
  if X < Lo then X := Lo;
  if X > Hi then X := Hi;
  Clamp := X
end;
function Sigmoid(X: TFloat): TFloat;
var E: TFloat;
begin
  ClearAIError;
  if X >= 0 then begin
    if X > 80 then Sigmoid := 1
    else Sigmoid := 1 / (1 + Exp(-X))
  end else begin
    if X < -80 then Sigmoid := 0
    else begin E := Exp(X); Sigmoid := E / (1 + E) end
  end
end;
function SafeExp(X: TFloat; var Value: TFloat): Boolean;
begin
  ClearAIError; Value := 0; SafeExp := False;
  if (X <> X) or (X < -80) or (X > 80) then begin
    SetAIError(ErrValue, 'SafeExp memerlukan -80 <= X <= 80'); Exit
  end;
  Value := Exp(X); SafeExp := True
end;
function SafeLn(X: TFloat; var Value: TFloat): Boolean;
begin
  ClearAIError; Value := 0; SafeLn := False;
  if not ValidNumber(X) or (X <= 0) then begin
    SetAIError(ErrValue, 'SafeLn memerlukan X positif <= 1E12'); Exit
  end;
  Value := Ln(X); SafeLn := True
end;
function SafeSqrt(X: TFloat; var Value: TFloat): Boolean;
begin
  ClearAIError; Value := 0; SafeSqrt := False;
  if not ValidNumber(X) or (X < 0) then begin
    SetAIError(ErrValue, 'SafeSqrt memerlukan 0 <= X <= 1E12'); Exit
  end;
  Value := Sqrt(X); SafeSqrt := True
end;
function IntPower(X: TFloat; N: Integer; var Value: TFloat): Boolean;
var I, Count: Integer; Base: TFloat;
begin
  ClearAIError; Value := 0; IntPower := False;
  if not ValidNumber(X) or (N < -100) or (N > 100) then begin
    SetAIError(ErrValue, 'Pangkat harus -100..100 dan basis valid'); Exit
  end;
  if (X = 0) and (N < 0) then begin
    SetAIError(ErrValue, 'Nol tidak boleh berpangkat negatif'); Exit
  end;
  Base := X; Count := N;
  if N < 0 then begin
    if Abs(X) < 1.0E-12 then begin
      SetAIError(ErrValue, 'Basis terlalu kecil untuk invers'); Exit
    end;
    Base := 1/X; Count := -N
  end;
  Value := 1;
  for I := 1 to Count do begin
    if Abs(Base) > 1 then
      if Abs(Value) > 1.0E30/Abs(Base) then begin
        Value := 0; SetAIError(ErrValue, 'Hasil pangkat terlalu besar'); Exit
      end;
    Value := Value*Base
  end;
  IntPower := True
end;
function DotProduct(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
var J: Integer;
begin
  Value := 0; DotProduct := False;
  if not CheckVector(A,N) then Exit;
  if not CheckVector(B,N) then Exit;
  for J := 1 to N do Value := Value + A[J]*B[J];
  DotProduct := True
end;
function DistanceSquared(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
var J: Integer; D: TFloat;
begin
  Value := 0; DistanceSquared := False;
  if not CheckVector(A,N) then Exit;
  if not CheckVector(B,N) then Exit;
  for J := 1 to N do begin D := A[J]-B[J]; Value := Value+D*D end;
  DistanceSquared := True
end;
function Euclidean(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
begin
  Euclidean := False;
  if not DistanceSquared(A,B,N,Value) then Exit;
  Value := Sqrt(Value); Euclidean := True
end;
function Manhattan(var A,B: TVector; N: Integer;
  var Value: TFloat): Boolean;
var J: Integer;
begin
  Value := 0; Manhattan := False;
  if not CheckVector(A,N) then Exit;
  if not CheckVector(B,N) then Exit;
  for J := 1 to N do Value := Value+Abs(A[J]-B[J]);
  Manhattan := True
end;
procedure AISetSeed(Seed: LongInt);
begin
  State := Seed mod 2147483647;
  if State <= 0 then State := State + 2147483646
end;
function AIRandom: TFloat;
var Hi,Lo,T: LongInt;
begin
  { Park-Miller, bentuk Schrage: tidak overflow LongInt 32 bit. }
  Hi := State div 127773; Lo := State mod 127773;
  T := 16807*Lo - 2836*Hi;
  if T > 0 then State := T else State := T + 2147483647;
  AIRandom := State / 2147483647.0
end;
function AIRandomInt(Limit: Integer): Integer;
var R: Integer;
begin
  ClearAIError; AIRandomInt := 0;
  if Limit <= 0 then begin
    SetAIError(ErrValue, 'Batas acak harus positif'); Exit
  end;
  R := Trunc(AIRandom*Limit);
  if R >= Limit then R := Limit-1;
  AIRandomInt := R
end;
function GoodMatrix(var M: TMatrix): Boolean;
var I,J: Integer;
begin
  ClearAIError; GoodMatrix := False;
  if (M.Rows < 1) or (M.Rows > MaxMatrix) or
     (M.Cols < 1) or (M.Cols > MaxMatrix) then begin
    SetAIError(ErrSize, 'Ukuran matriks harus 1..16'); Exit
  end;
  for I := 1 to M.Rows do for J := 1 to M.Cols do
    if not ValidNumber(M.V[I,J]) then begin
      SetAIError(ErrValue, 'Elemen matriks melampaui 1E12'); Exit
    end;
  GoodMatrix := True
end;
function MatrixInit(var M: TMatrix; Rows, Cols: Integer): Boolean;
begin
  ClearAIError; FillChar(M,SizeOf(M),0); MatrixInit := False;
  if (Rows < 1) or (Rows > MaxMatrix) or
     (Cols < 1) or (Cols > MaxMatrix) then begin
    SetAIError(ErrSize, 'Ukuran matriks harus 1..16'); Exit
  end;
  M.Rows := Rows; M.Cols := Cols; MatrixInit := True
end;
function MatrixIdentity(var M: TMatrix; N: Integer): Boolean;
var I: Integer;
begin
  MatrixIdentity := False;
  if not MatrixInit(M,N,N) then Exit;
  for I := 1 to N do M.V[I,I] := 1;
  MatrixIdentity := True
end;
function MatrixAdd(var A,B,C: TMatrix): Boolean;
var I,J: Integer; T: TMatrix;
begin
  MatrixAdd := False;
  if not GoodMatrix(A) then Exit;
  if not GoodMatrix(B) then Exit;
  if (A.Rows <> B.Rows) or (A.Cols <> B.Cols) then begin
    SetAIError(ErrSize, 'Dimensi penjumlahan tidak cocok'); Exit
  end;
  T := A;
  for I := 1 to A.Rows do for J := 1 to A.Cols do begin
    T.V[I,J] := A.V[I,J]+B.V[I,J];
    if not ValidNumber(T.V[I,J]) then begin
      SetAIError(ErrValue, 'Hasil penjumlahan matriks melampaui 1E12'); Exit
    end
  end;
  C := T; MatrixAdd := True
end;
function MatrixSubtract(var A,B,C: TMatrix): Boolean;
var I,J: Integer; T: TMatrix;
begin
  MatrixSubtract := False;
  if not GoodMatrix(A) then Exit;
  if not GoodMatrix(B) then Exit;
  if (A.Rows <> B.Rows) or (A.Cols <> B.Cols) then begin
    SetAIError(ErrSize, 'Dimensi pengurangan tidak cocok'); Exit
  end;
  T := A;
  for I := 1 to A.Rows do for J := 1 to A.Cols do begin
    T.V[I,J] := A.V[I,J]-B.V[I,J];
    if not ValidNumber(T.V[I,J]) then begin
      SetAIError(ErrValue, 'Hasil pengurangan matriks melampaui 1E12'); Exit
    end
  end;
  C := T; MatrixSubtract := True
end;
function MatrixScale(var A: TMatrix; Factor: TFloat;
  var C: TMatrix): Boolean;
var I,J: Integer; T: TMatrix;
begin
  MatrixScale := False;
  if not GoodMatrix(A) then Exit;
  if not ValidNumber(Factor) then begin
    SetAIError(ErrValue, 'Faktor skala tidak valid'); Exit
  end;
  T := A;
  for I := 1 to A.Rows do for J := 1 to A.Cols do begin
    T.V[I,J] := A.V[I,J]*Factor;
    if not ValidNumber(T.V[I,J]) then begin
      SetAIError(ErrValue, 'Hasil skala matriks melampaui 1E12'); Exit
    end
  end;
  C := T; MatrixScale := True
end;
function MatrixTranspose(var A,C: TMatrix): Boolean;
var I,J: Integer; T: TMatrix;
begin
  MatrixTranspose := False;
  if not GoodMatrix(A) then Exit;
  FillChar(T,SizeOf(T),0); T.Rows := A.Cols; T.Cols := A.Rows;
  for I := 1 to A.Rows do for J := 1 to A.Cols do
    T.V[J,I] := A.V[I,J];
  C := T; MatrixTranspose := True
end;
function MatrixMultiply(var A,B,C: TMatrix): Boolean;
var I,J,K: Integer; T: TMatrix;
begin
  MatrixMultiply := False;
  if not GoodMatrix(A) then Exit;
  if not GoodMatrix(B) then Exit;
  if A.Cols <> B.Rows then begin
    SetAIError(ErrSize, 'Dimensi perkalian tidak cocok'); Exit
  end;
  FillChar(T,SizeOf(T),0); T.Rows := A.Rows; T.Cols := B.Cols;
  for I := 1 to A.Rows do for J := 1 to B.Cols do
    for K := 1 to A.Cols do
      T.V[I,J] := T.V[I,J]+A.V[I,K]*B.V[K,J];
  for I := 1 to T.Rows do for J := 1 to T.Cols do
    if not ValidNumber(T.V[I,J]) then begin
      SetAIError(ErrValue, 'Hasil perkalian matriks melampaui 1E12'); Exit
    end;
  C := T; MatrixMultiply := True
end;
begin State := 1 end.
