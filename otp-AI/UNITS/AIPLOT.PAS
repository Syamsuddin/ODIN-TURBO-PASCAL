unit AIPlot;
{ BGI pada Turbo Pascal. SVG lintas platform tanpa dependensi tambahan. }
{$IFNDEF FPC}
  {$IFNDEF ODIN}
    {$DEFINE TPAIBGI}
  {$ENDIF}
{$ENDIF}
interface
uses AITypes;
function PlotOpen(BGIPath: TFileName): Boolean;
procedure PlotClose;
function PlotScatter(var X,Y: TSeries; N: Integer;
  var Groups: TLabels; Title: string): Boolean;
function PlotCurve(var Y: TSeries; N: Integer; Title: string): Boolean;
function PlotRegression(var X,Y: TSeries; N: Integer;
  Intercept,Slope: TFloat; Title: string): Boolean;
function SaveScatterSVG(FileName: TFileName; var X,Y: TSeries;
  N: Integer; var Groups: TLabels; Title: string): Boolean;
function SaveCurveSVG(FileName: TFileName; var Y: TSeries;
  N: Integer; Title: string): Boolean;
function SaveRegressionSVG(FileName: TFileName; var X,Y: TSeries;
  N: Integer; Intercept,Slope: TFloat; Title: string): Boolean;
implementation
{$IFDEF TPAIBGI}
uses Graph;
{$ENDIF}
var Opened: Boolean;
type
  TBounds = record XLo,XHi,YLo,YHi: TFloat end;
function Bounds(var X,Y: TSeries; N: Integer; var B: TBounds): Boolean;
var I: Integer;
begin
  ClearAIError; Bounds := False;
  if (N < 1) or (N > MaxSamples) then begin
    SetAIError(ErrSize,'Plot memerlukan 1..200 titik'); Exit
  end;
  for I := 1 to N do
    if not ValidNumber(X[I]) or not ValidNumber(Y[I]) then begin
      SetAIError(ErrValue,'Koordinat plot tidak valid'); Exit
    end;
  B.XLo := X[1]; B.XHi := X[1]; B.YLo := Y[1]; B.YHi := Y[1];
  for I := 2 to N do begin
    if X[I] < B.XLo then B.XLo := X[I];
    if X[I] > B.XHi then B.XHi := X[I];
    if Y[I] < B.YLo then B.YLo := Y[I];
    if Y[I] > B.YHi then B.YHi := Y[I]
  end;
  Bounds := True
end;
procedure PadBounds(var B: TBounds);
var DX,DY: TFloat;
begin
  DX := (B.XHi-B.XLo)*0.08; DY := (B.YHi-B.YLo)*0.08;
  if DX < AIEpsilon then DX := 1;
  if DY < AIEpsilon then DY := 1;
  B.XLo := B.XLo-DX; B.XHi := B.XHi+DX;
  B.YLo := B.YLo-DY; B.YHi := B.YHi+DY
end;
function PixelX(X: TFloat; var B: TBounds; Width: Integer): Integer;
begin PixelX := 80+Round((X-B.XLo)/(B.XHi-B.XLo)*(Width-110)) end;
function PixelY(Y: TFloat; var B: TBounds; Height: Integer): Integer;
begin PixelY := Height-65-Round((Y-B.YLo)/(B.YHi-B.YLo)*(Height-120)) end;
function Num(X: TFloat): string;
var S: string[40];
begin
  if (Abs(X) >= 100000) or ((X <> 0) and (Abs(X) < 0.001)) then Str(X:12,S)
  else Str(X:0:3,S);
  Num := S
end;
function GroupColor(Group: Integer): Integer;
var C: Integer;
begin
  C := Group mod 10; if C < 0 then C := C+10;
  case C of
    0: GroupColor := 9;
    1: GroupColor := 12;
    2: GroupColor := 10;
    3: GroupColor := 14;
    4: GroupColor := 13;
    5: GroupColor := 11;
    6: GroupColor := 1;
    7: GroupColor := 4;
    8: GroupColor := 2;
    9: GroupColor := 5
  end
end;
function SVGColor(Group: Integer): string;
var C: Integer;
begin
  C := Group mod 10; if C < 0 then C := C+10;
  case C of
    0: SVGColor := '#2563eb';
    1: SVGColor := '#dc2626';
    2: SVGColor := '#15803d';
    3: SVGColor := '#a16207';
    4: SVGColor := '#9333ea';
    5: SVGColor := '#0891b2';
    6: SVGColor := '#1e3a8a';
    7: SVGColor := '#7f1d1d';
    8: SVGColor := '#14532d';
    9: SVGColor := '#701a75'
  end
end;
function PlotOpen(BGIPath: TFileName): Boolean;
{$IFDEF TPAIBGI}
var Driver,Mode,E: Integer;
{$ENDIF}
begin
  ClearAIError; PlotOpen := False;
  if Opened then begin PlotOpen := True; Exit end;
  {$IFDEF TPAIBGI}
  Driver := Detect; InitGraph(Driver,Mode,BGIPath); E := GraphResult;
  if E <> grOk then begin
    SetAIError(ErrGraphics,'BGI gagal: '+GraphErrorMsg(E)); Exit
  end;
  Opened := True; PlotOpen := True
  {$ELSE}
  SetAIError(ErrGraphics,'Build ini memakai ekspor SVG; BGI untuk Turbo Pascal')
  {$ENDIF}
end;
procedure PlotClose;
begin
  {$IFDEF TPAIBGI}
  if Opened then CloseGraph;
  {$ENDIF}
  Opened := False
end;
{$IFDEF TPAIBGI}
procedure DrawAxes(var B: TBounds; Title: string);
var W,H,I,P: Integer; X,Y: TFloat;
begin
  W := GetMaxX; H := GetMaxY; ClearDevice; SetColor(White);
  OutTextXY(80,15,Copy(Title,1,65));
  Rectangle(80,55,W-30,H-65);
  for I := 0 to 4 do begin
    X := B.XLo+(B.XHi-B.XLo)*I/4;
    Y := B.YLo+(B.YHi-B.YLo)*I/4;
    P := PixelX(X,B,W); Line(P,H-65,P,H-60);
    OutTextXY(P-20,H-45,Num(X));
    P := PixelY(Y,B,H); Line(75,P,80,P);
    OutTextXY(2,P,Num(Y))
  end;
  OutTextXY(W-35,H-25,'X'); OutTextXY(5,35,'Y')
end;
{$ENDIF}
function ScreenPlot(var X,Y: TSeries; N: Integer; var Groups: TLabels;
  Title: string; Join,Regression: Boolean; Intercept,Slope: TFloat): Boolean;
var B: TBounds; X1,X2,Y1,Y2: TFloat;
{$IFDEF TPAIBGI}
    I,PX,PY,W,H: Integer;
{$ENDIF}
begin
  ScreenPlot := False;
  if not Bounds(X,Y,N,B) then Exit;
  if not Opened then begin
    SetAIError(ErrGraphics,'Panggil PlotOpen terlebih dahulu'); Exit
  end;
  X1 := B.XLo; X2 := B.XHi; Y1 := 0; Y2 := 0;
  if Regression then begin
    if not ValidNumber(Intercept) or not ValidNumber(Slope) then begin
      SetAIError(ErrValue,'Parameter garis regresi tidak valid'); Exit
    end;
    Y1 := Intercept+Slope*B.XLo; Y2 := Intercept+Slope*B.XHi;
    if not ValidNumber(Y1) or not ValidNumber(Y2) then begin
      SetAIError(ErrValue,'Garis regresi melampaui batas angka'); Exit
    end;
    if Y1 < B.YLo then B.YLo := Y1;
    if Y1 > B.YHi then B.YHi := Y1;
    if Y2 < B.YLo then B.YLo := Y2;
    if Y2 > B.YHi then B.YHi := Y2
  end;
  PadBounds(B);
  {$IFDEF TPAIBGI}
  W := GetMaxX; H := GetMaxY; DrawAxes(B,Title);
  for I := 1 to N do begin
    SetColor(GroupColor(Groups[I]));
    PX := PixelX(X[I],B,W); PY := PixelY(Y[I],B,H);
    if Join and (I > 1) then
      Line(PixelX(X[I-1],B,W),PixelY(Y[I-1],B,H),PX,PY);
    Circle(PX,PY,3)
  end;
  if Regression then begin
    SetColor(LightRed);
    Line(PixelX(X1,B,W),PixelY(Y1,B,H),
         PixelX(X2,B,W),PixelY(Y2,B,H))
  end;
  ScreenPlot := True
  {$ELSE}
  SetAIError(ErrGraphics,'BGI tidak tersedia pada build ini')
  {$ENDIF}
end;
function PlotScatter(var X,Y: TSeries; N: Integer;
  var Groups: TLabels; Title: string): Boolean;
begin PlotScatter := ScreenPlot(X,Y,N,Groups,Title,False,False,0,0) end;
function PlotCurve(var Y: TSeries; N: Integer; Title: string): Boolean;
var X: TSeries; G: TLabels; I: Integer;
begin
  ClearAIError; PlotCurve := False;
  if (N < 1) or (N > MaxSamples) then begin
    SetAIError(ErrSize,'Panjang kurva tidak valid'); Exit
  end;
  FillChar(G,SizeOf(G),0); for I := 1 to N do X[I] := I;
  PlotCurve := ScreenPlot(X,Y,N,G,Title,True,False,0,0)
end;
function PlotRegression(var X,Y: TSeries; N: Integer;
  Intercept,Slope: TFloat; Title: string): Boolean;
var G: TLabels;
begin
  FillChar(G,SizeOf(G),0);
  PlotRegression := ScreenPlot(X,Y,N,G,Title,False,True,Intercept,Slope)
end;
{$I-}
procedure WriteEscaped(var F: Text; S: string);
var I: Integer;
begin
  for I := 1 to Length(S) do case S[I] of
    '&': Write(F,'&amp;'); '<': Write(F,'&lt;');
    '>': Write(F,'&gt;'); '"': Write(F,'&quot;');
    else if Ord(S[I]) >= 32 then Write(F,S[I])
  end
end;
{$I+}
function ExportSVG(FileName: TFileName; var X,Y: TSeries; N: Integer;
  var Groups: TLabels; Title: string; Join,Regression: Boolean;
  Intercept,Slope: TFloat): Boolean;
var F: Text; B: TBounds; I,E,CloseErr,PX,PY: Integer;
    VX,VY,X1,X2,Y1,Y2: TFloat;
begin
  ExportSVG := False;
  if not Bounds(X,Y,N,B) then Exit;
  X1 := B.XLo; X2 := B.XHi; Y1 := 0; Y2 := 0;
  if Regression then begin
    if not ValidNumber(Intercept) or not ValidNumber(Slope) then begin
      SetAIError(ErrValue,'Parameter garis regresi tidak valid'); Exit
    end;
    Y1 := Intercept+Slope*X1; Y2 := Intercept+Slope*X2;
    if not ValidNumber(Y1) or not ValidNumber(Y2) then begin
      SetAIError(ErrValue,'Garis regresi melampaui batas angka'); Exit
    end;
    if Y1 < B.YLo then B.YLo := Y1;
    if Y1 > B.YHi then B.YHi := Y1;
    if Y2 < B.YLo then B.YLo := Y2;
    if Y2 > B.YHi then B.YHi := Y2
  end;
  PadBounds(B); Assign(F,FileName);
  {$I-} Rewrite(F); E := IOResult; {$I+}
  if E <> 0 then begin SetAIError(ErrIO,'Berkas SVG gagal dibuat'); Exit end;
  {$I-}
  WriteLn(F,'<svg xmlns="http://www.w3.org/2000/svg" width="800" height="500" viewBox="0 0 800 500">');
  WriteLn(F,'<rect width="800" height="500" fill="#f8fafc"/>');
  WriteLn(F,'<g font-family="sans-serif" fill="#0f172a" font-size="12">');
  Write(F,'<text x="80" y="30" font-size="18">'); WriteEscaped(F,Title);
  WriteLn(F,'</text>');
  WriteLn(F,'<rect x="80" y="55" width="690" height="380" fill="white" stroke="#94a3b8"/>');
  for I := 0 to 4 do begin
    VX := B.XLo+(B.XHi-B.XLo)*I/4;
    VY := B.YLo+(B.YHi-B.YLo)*I/4;
    PX := PixelX(VX,B,800); PY := PixelY(VY,B,500);
    WriteLn(F,'<text x="',PX,'" y="458" text-anchor="middle">',Num(VX),'</text>');
    WriteLn(F,'<text x="72" y="',PY+4,'" text-anchor="end">',Num(VY),'</text>')
  end;
  if Join then begin
    Write(F,'<polyline fill="none" stroke="#2563eb" stroke-width="2" points="');
    for I := 1 to N do Write(F,PixelX(X[I],B,800),',',PixelY(Y[I],B,500),' ');
    WriteLn(F,'"/>')
  end;
  for I := 1 to N do
    WriteLn(F,'<circle cx="',PixelX(X[I],B,800),'" cy="',PixelY(Y[I],B,500),
      '" r="4" fill="',SVGColor(Groups[I]),'"/>');
  if Regression then
    WriteLn(F,'<line x1="',PixelX(X1,B,800),'" y1="',PixelY(Y1,B,500),
      '" x2="',PixelX(X2,B,800),'" y2="',PixelY(Y2,B,500),
      '" stroke="#dc2626" stroke-width="2"/>');
  WriteLn(F,'<text x="760" y="485">X</text><text x="20" y="45">Y</text>');
  WriteLn(F,'<text x="80" y="485">OTP-AI 2.0 | Warna mengikuti kode kelompok modulo 10</text>');
  WriteLn(F,'</g></svg>');
  E := IOResult; Close(F); CloseErr := IOResult;
  {$I+}
  if (E <> 0) or (CloseErr <> 0) then begin
    SetAIError(ErrIO,'Gagal menulis SVG'); Exit
  end;
  ExportSVG := True
end;
function SaveScatterSVG(FileName: TFileName; var X,Y: TSeries;
  N: Integer; var Groups: TLabels; Title: string): Boolean;
begin
  SaveScatterSVG := ExportSVG(FileName,X,Y,N,Groups,Title,False,False,0,0)
end;
function SaveCurveSVG(FileName: TFileName; var Y: TSeries;
  N: Integer; Title: string): Boolean;
var X: TSeries; G: TLabels; I: Integer;
begin
  ClearAIError; SaveCurveSVG := False;
  if (N < 1) or (N > MaxSamples) then begin
    SetAIError(ErrSize,'Panjang kurva tidak valid'); Exit
  end;
  FillChar(G,SizeOf(G),0); for I := 1 to N do X[I] := I;
  SaveCurveSVG := ExportSVG(FileName,X,Y,N,G,Title,True,False,0,0)
end;
function SaveRegressionSVG(FileName: TFileName; var X,Y: TSeries;
  N: Integer; Intercept,Slope: TFloat; Title: string): Boolean;
var G: TLabels;
begin
  FillChar(G,SizeOf(G),0);
  SaveRegressionSVG := ExportSVG(FileName,X,Y,N,G,Title,False,True,Intercept,Slope)
end;
begin Opened := False end.
