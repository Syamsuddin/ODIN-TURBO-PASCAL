program OptimizerDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIOptim;
var W,V,G: TFloat; I: Integer;
{$I COMMON.INC}
begin
  WriteLn('Minimum fungsi f(w)=(w-3)^2. Gradien=2*(w-3).');
  W:=-5; V:=0;
  for I:=1 to 100 do begin
    G:=2*(W-3); Need(SGDStep(W,V,G,0.1,0.3,10));
    if I mod 10=0 then WriteLn('Langkah ',I:3,' w=',W:0:6,' loss=',Sqr(W-3):0:8)
  end
end.
