program FuzzyDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIFuzzy,AIPlot;
var S: TFuzzySystem; Strength: TFuzzyStrength;
    X,Y: TSeries; Groups: TLabels; I: Integer; Output: TFloat;
{$I COMMON.INC}
begin
  DefaultFuzzy(S);
  Need(EvaluateFuzzy(S,28,70,200,Output,Strength));
  WriteLn('Suhu=28, kelembapan=70 => kecepatan kipas=',Output:0:3);
  for I:=1 to 9 do WriteLn('Aturan ',I,' firing=',Strength[I]:0:4);
  FillChar(Groups,SizeOf(Groups),0);
  for I:=1 to 41 do begin
    X[I]:=I-1; Need(EvaluateFuzzy(S,X[I],70,200,Y[I],Strength))
  end;
  Need(SaveScatterSVG('FUZZY.SVG',X,Y,41,Groups,'Suhu vs kipas; kelembapan 70'))
end.
