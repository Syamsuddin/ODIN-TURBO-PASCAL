program BasicDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIMath,AIStats;
var A,B,C: TMatrix; V,W: TVector; S,T: TSeries;
    I: Integer; Value: TFloat;
{$I COMMON.INC}
begin
  WriteLn('OTP-AI - matematika, matriks dan statistik');
  FillChar(V,SizeOf(V),0); FillChar(W,SizeOf(W),0);
  V[1] := 1; V[2] := 2; W[1] := 4; W[2] := 6;
  Need(Euclidean(V,W,2,Value)); WriteLn('Jarak (1,2)-(4,6): ',Value:0:4);
  Need(DotProduct(V,W,2,Value)); WriteLn('Dot product: ',Value:0:4);
  WriteLn('Sigmoid(0): ',Sigmoid(0):0:4);
  Need(MatrixInit(A,2,2)); Need(MatrixIdentity(B,2));
  A.V[1,1] := 1; A.V[1,2] := 2; A.V[2,1] := 3; A.V[2,2] := 4;
  Need(MatrixMultiply(A,B,C));
  WriteLn('A * I:');
  for I := 1 to 2 do WriteLn(C.V[I,1]:8:2,C.V[I,2]:8:2);
  for I := 1 to 5 do begin S[I] := I; T[I] := 2*I+1 end;
  Need(Mean(S,5,Value)); WriteLn('Mean 1..5: ',Value:0:4);
  Need(Median(S,5,Value)); WriteLn('Median: ',Value:0:4);
  Need(Variance(S,5,True,Value)); WriteLn('Varians sampel: ',Value:0:4);
  Need(Correlation(S,T,5,Value)); WriteLn('Korelasi: ',Value:0:4)
end.
