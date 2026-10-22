program OptimizerDemo;
{ OPTDEMO - optimizer SGD dengan momentum, dari AIOPTIM.
  Meminimalkan fungsi sederhana f(w)=(w-3)^2, gradiennya 2*(w-3), lewat
  100 langkah SGDStep dengan learning rate 0.1, momentum 0.3 dan
  clipping gradien di 10. W dimulai dari -5 dan seharusnya mendekati 3
  (minimum fungsi), sementara loss mendekati 0.
  Latihan (DOCS/GUIDE2.TXT bagian 13, urutan #1): ubah rate, momentum
  dan Clip, lalu amati seberapa cepat (atau tidak stabil) w mendekati 3. }
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIOptim;
var W,V,G: TFloat; I: Integer;
{$I COMMON.INC}
begin
  WriteLn('Minimum fungsi f(w)=(w-3)^2. Gradien=2*(w-3).');
  W:=-5; V:=0;                                     { W = parameter yang dioptimasi, V = velocity momentum }
  for I:=1 to 100 do begin
    G:=2*(W-3); Need(SGDStep(W,V,G,0.1,0.3,10));    { rate=0.1, momentum=0.3, clip gradien ke [-10,10] }
    if I mod 10=0 then WriteLn('Langkah ',I:3,' w=',W:0:6,' loss=',Sqr(W-3):0:8)
  end
end.
