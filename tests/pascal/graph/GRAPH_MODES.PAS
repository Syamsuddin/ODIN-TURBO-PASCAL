{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Graph: driver, mode, galat, palet. }
program GRAPH_MODES;

uses Graph;

var
  O: Text;

procedure Show(const What: String; V: LongInt);
begin
  WriteLn(O, What, ' = ', V);
end;

procedure TryMode(Drv, Mode: Integer);
var
  D, M: Integer;
begin
  D := Drv;
  M := Mode;
  InitGraph(D, M, '');
  Write(O, 'driver ', Drv, ' mode ', Mode, ': ');
  if GraphResult <> grOk then
    WriteLn(O, 'ditolak, GraphDriver=', D)
  else
  begin
    WriteLn(O, GetDriverName, ' ', GetModeName(Mode), ' ', GetMaxX + 1, 'x', GetMaxY + 1, ' warna=',
      GetMaxColor + 1, ' paleta=', GetPaletteSize);
    CloseGraph;
  end;
end;

var
  D, M, I, Lo, Hi: Integer;
  Pal, Def: PaletteType;
  Xa, Ya: Word;
begin
  Assign(O, '');
  Rewrite(O);

  { Sebelum InitGraph }
  Show('GetMaxX sebelum init', GetMaxX);
  Show('GraphResult', GraphResult);
  Show('GraphResult lagi', GraphResult);
  PutPixel(1, 1, 1);
  Show('PutPixel tanpa init', GraphResult);

  { Deteksi }
  DetectGraph(D, M);
  WriteLn(O, 'Detect: ', D, ' ', M);
  D := Detect;
  InitGraph(D, M, 'C:\TP\BGI');
  WriteLn(O, 'InitGraph(Detect): ', D, ' ', M, ' err=', GraphResult);
  WriteLn(O, GetDriverName, ' / ', GetModeName(GetGraphMode), ' / maxmode=', GetMaxMode);
  GetAspectRatio(Xa, Ya);
  WriteLn(O, 'aspek ', Xa, ':', Ya);
  SetAspectRatio(5000, 10000);
  GetAspectRatio(Xa, Ya);
  WriteLn(O, 'aspek baru ', Xa, ':', Ya);
  SetAspectRatio(0, 1);
  Show('SetAspectRatio(0,1)', GraphResult);
  GetModeRange(VGA, Lo, Hi);
  WriteLn(O, 'mode VGA: ', Lo, '..', Hi);
  GetModeRange(CurrentDriver, Lo, Hi);
  WriteLn(O, 'mode driver aktif: ', Lo, '..', Hi);
  GetModeRange(99, Lo, Hi);
  WriteLn(O, 'mode driver 99: ', Lo, '..', Hi);
  CloseGraph;
  Show('GetMaxX sesudah close', GetMaxX);
  Show('GraphResult', GraphResult);
  CloseGraph;
  Show('CloseGraph kedua', GraphResult);

  { Semua driver dan mode }
  for D := 1 to 10 do
  begin
    GetModeRange(D, Lo, Hi);
    for I := Lo to Hi do
      TryMode(D, I);
  end;
  TryMode(VGA, 3);
  TryMode(11, 0);
  TryMode(-5, 0);
  TryMode(CGA, 5);

  { Kode galat }
  for I := 0 downto -18 do
    WriteLn(O, I, ': ', GraphErrorMsg(I));
  WriteLn(O, 'tak dikenal: ', GraphErrorMsg(-99));

  { Palet VGA: bawaan, SetPalette, SetBkColor }
  D := VGA;
  M := VGAHi;
  InitGraph(D, M, '');
  GetPalette(Pal);
  Write(O, 'palet ', Pal.Size, ':');
  for I := 0 to Pal.Size - 1 do
    Write(O, ' ', Pal.Colors[I]);
  WriteLn(O);
  SetPalette(3, 42);
  GetPalette(Pal);
  GetDefaultPalette(Def);
  WriteLn(O, 'warna 3 sekarang ', Pal.Colors[3], ', bawaan ', Def.Colors[3]);
  SetPalette(16, 1);
  Show('SetPalette(16)', GraphResult);
  SetPalette(2, -1);
  Show('SetPalette(2,-1)', GraphResult);
  SetBkColor(4);
  Show('GetBkColor', GetBkColor);
  SetBkColor(16);
  Show('SetBkColor(16)', GraphResult);
  SetColor(7);
  Show('GetColor', GetColor);
  SetColor(16);
  Show('SetColor(16)', GraphResult);
  Show('GetColor tetap', GetColor);
  SetRGBPalette(5, 63, 0, 0);
  Show('SetRGBPalette', GraphResult);
  SetRGBPalette(99, 1, 2, 3);
  Show('SetRGBPalette(99)', GraphResult);
  GraphDefaults;
  Show('GetBkColor sesudah GraphDefaults', GetBkColor);
  Show('GetColor sesudah GraphDefaults', GetColor);
  CloseGraph;
  Close(O);
end.
