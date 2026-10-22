program PlotDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIPlot;
var X,Y: TSeries; Groups: TLabels; I: Integer; Path: TFileName;
{$I COMMON.INC}
begin
  for I := 1 to 20 do begin
    X[I] := I/2; Y[I] := 10+3*X[I]+(I mod 3-1);
    Groups[I] := 0
  end;
  Need(SaveRegressionSVG('PLOT.SVG',X,Y,20,10,3,'Contoh BGI dan SVG'));
  WriteLn('PLOT.SVG sudah dibuat.');
  {$IFNDEF FPC}
  Path := 'C:\TP\BGI';
  if ParamCount > 0 then Path := ParamStr(1);
  if PlotOpen(Path) then begin
    Need(PlotScatter(X,Y,20,Groups,'Scatter plot. Tekan Enter.')); ReadLn;
    Need(PlotRegression(X,Y,20,10,3,'Regresi. Tekan Enter.')); ReadLn;
    Need(PlotCurve(Y,20,'Kurva. Tekan Enter.')); ReadLn;
    PlotClose
  end else WriteLn(AIError)
  {$ELSE}
  WriteLn('BGI khusus build Turbo Pascal. Buka SVG di peramban.')
  {$ENDIF}
end.
