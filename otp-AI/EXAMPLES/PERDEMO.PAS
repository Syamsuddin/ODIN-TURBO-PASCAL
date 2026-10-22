program PerceptronDemo;
{ PERDEMO - perceptron tunggal dengan AILINEAR, batas linear separability.
  Melatih perceptron pada AND.CSV (dua kelas yang terpisah linear) dan
  mencetak epoch serta status konvergensi, lalu memprediksi keempat
  kombinasi input AND. Kemudian melatih perceptron BARU (memakai
  variabel model yang sama) pada XOR.CSV: XOR tidak dapat dipisahkan
  oleh satu garis, jadi perceptron tunggal TIDAK akan konvergen - ini
  hasil pembelajaran yang diharapkan, bukan kegagalan fungsi.
  Latihan (DOCS/GUIDE2.TXT bagian 15, urutan #2): bandingkan Info untuk
  AND (konvergen) dengan XOR (tidak konvergen, lihat NNDEMO untuk
  jaringan yang bisa menyelesaikan XOR). }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AILINEAR,AIOptim;
var D: PDataSet; M: TPerceptronModel; Info: TTrainInfo;
    I,LabelValue: Integer; Score: TFloat;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('AND.CSV'),True,TargetClass,D^));
  Need(FitPerceptron(D^,100,0.1,42,M,Info));          { maks 100 epoch, rate 0.1, seed 42 }
  WriteLn('AND: epoch=',Info.Epochs,' konvergen=',Info.Converged);
  for I:=1 to D^.Count do begin
    Need(PredictPerceptron(M,D^.X[I],LabelValue,Score));
    WriteLn(D^.X[I,1]:0:0,' ',D^.X[I,2]:0:0,' => ',LabelValue)
  end;
  Need(LoadCSV(DataPath('XOR.CSV'),True,TargetClass,D^));  { D dipakai ulang untuk dataset kedua }
  Need(FitPerceptron(D^,100,0.1,42,M,Info));
  WriteLn('XOR: konvergen=',Info.Converged,' error=',Info.FinalLoss:0:4);  { FinalLoss = fraksi salah klasifikasi }
  WriteLn('Perceptron tunggal tidak memisahkan XOR secara linear.'); FreeData(D)
end.
