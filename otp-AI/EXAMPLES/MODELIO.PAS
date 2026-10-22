program ModelIODemo;
{ MODELIO - simpan dan muat model (.TPM) dengan AIMODEL.
  Untuk regresi linear dan KNN: melatih model, menyimpannya ke .TPM,
  memuatnya kembali ke variabel model yang berbeda, lalu membandingkan
  prediksi SEBELUM dan SESUDAH disimpan/dimuat untuk observasi yang
  sama - keduanya harus identik jika round-trip berhasil. KNN berbeda
  dari Linear: model KNN hanya menyimpan dataset dan K, bukan menyalin
  datanya, jadi LoadKNN memerlukan dataset Storage milik pemanggil
  sendiri untuk diikatkan ke model yang dimuat.
  Catatan: berkas .TPM hanya valid untuk ABI/compiler yang sama persis,
  bukan format pertukaran lintas compiler atau arsitektur
  (DOCS/GUIDE2.TXT bagian 20, urutan #7). }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AILINEAR,AIKNN,AIModel;
var D,Storage: PDataSet; Linear,Loaded: TLinearModel;
    KNN,KNNLoaded: TKNNModel; V: TVector; P1,P2: TFloat; L: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(NewData(Storage));          { Storage: dataset kosong untuk menampung KNN yang dimuat }
  Need(LoadCSV(DataPath('JAMNILAI.CSV'),True,TargetReal,D^));
  Need(FitLinear(D^,0,Linear)); Need(SaveLinear('LINEAR.TPM',Linear));
  Need(LoadLinear('LINEAR.TPM',Loaded)); FillChar(V,SizeOf(V),0); V[1]:=5;
  Need(PredictLinear(Linear,V,P1)); Need(PredictLinear(Loaded,V,P2));
  WriteLn('Linear sebelum=',P1:0:6,' sesudah=',P2:0:6);  { harus sama }
  Need(FitKNN(D^,3,KNN)); Need(SaveKNN('KNN.TPM',KNN));
  Need(LoadKNN('KNN.TPM',Storage^,KNNLoaded));         { KNNLoaded diikat ke Storage, bukan ke D }
  Need(PredictKNN(KNN,V,L,P1)); Need(PredictKNN(KNNLoaded,V,L,P2));
  WriteLn('KNN sebelum=',P1:0:6,' sesudah=',P2:0:6);    { harus sama }
  WriteLn('TPM hanya untuk ABI/compiler yang sama. Dataset KNN ikut tersimpan.');
  KNN.Fitted:=False; KNN.Data:=nil; KNNLoaded.Fitted:=False; KNNLoaded.Data:=nil;  { lepas sebelum FreeData }
  FreeData(Storage); FreeData(D)
end.
