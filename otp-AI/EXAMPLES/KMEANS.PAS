program KMeansDemo;
{$IFNDEF FPC}
{$M 16384,0,655360}
{$ENDIF}
{$R+}{$S+}{$B-}

uses AITypes,AIData,AIKMeans,AIPlot;
var D: PDataSet; S: TScaler; M: TKMeansModel;
    Labels: TLabels; X,Y,History: TSeries; H,C: Integer;
{$I COMMON.INC}
begin
  Need(NewData(D)); Need(LoadCSV(DataPath('CLUSTER.CSV'),True,TargetNone,D^));
  Need(FitScaler(D^,ScaleStandard,S)); Need(TransformData(S,D^));
  Need(FitKMeans(D^,3,100,0.0001,42,M,Labels,History,H));
  WriteLn('Iterasi=',M.Iterations,' Konvergen=',M.Converged);
  WriteLn('Inertia=',M.Inertia:0:6);
  for C := 1 to M.K do
    WriteLn('Pusat ',C,': ',M.Centers[C,1]:0:4,', ',M.Centers[C,2]:0:4);
  Need(GetColumn(D^,1,X)); Need(GetColumn(D^,2,Y));
  Need(SaveScatterSVG('CLUSTER.SVG',X,Y,D^.Count,Labels,'K-means - fitur standar'));
  Need(SaveCurveSVG('INERTIA.SVG',History,H,'Inertia per iterasi'));
  WriteLn('Grafik: CLUSTER.SVG dan INERTIA.SVG'); FreeData(D)
end.
