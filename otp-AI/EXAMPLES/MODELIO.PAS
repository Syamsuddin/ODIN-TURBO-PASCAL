program ModelIODemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AILINEAR,AIKNN,AIModel;
var D,Storage: PDataSet; Linear,Loaded: TLinearModel;
    KNN,KNNLoaded: TKNNModel; V: TVector; P1,P2: TFloat; L: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(Storage));
  Need(LoadCSV(DataPath('JAMNILAI.CSV'),True,TargetReal,D^));
  Need(FitLinear(D^,0,Linear)); Need(SaveLinear('LINEAR.TPM',Linear));
  Need(LoadLinear('LINEAR.TPM',Loaded)); FillChar(V,SizeOf(V),0); V[1]:=5;
  Need(PredictLinear(Linear,V,P1)); Need(PredictLinear(Loaded,V,P2));
  WriteLn('Linear sebelum=',P1:0:6,' sesudah=',P2:0:6);
  Need(FitKNN(D^,3,KNN)); Need(SaveKNN('KNN.TPM',KNN));
  Need(LoadKNN('KNN.TPM',Storage^,KNNLoaded));
  Need(PredictKNN(KNN,V,L,P1)); Need(PredictKNN(KNNLoaded,V,L,P2));
  WriteLn('KNN sebelum=',P1:0:6,' sesudah=',P2:0:6);
  WriteLn('TPM hanya untuk ABI/compiler yang sama. Dataset KNN ikut tersimpan.');
  KNN.Fitted:=False; KNN.Data:=nil; KNNLoaded.Fitted:=False; KNNLoaded.Data:=nil;
  FreeData(Storage); FreeData(D)
end.
