{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VColors;
{ Odin Vision snapshot demo: a TTerminal window written with WriteLn
  through AssignDevice (its small buffer wraps and drops old lines), and
  the TColorDialog, stored to a stream and loaded back before it runs.
  OK applies the new colors to the application palette. }
uses Objects, Drivers, Views, Menus, Dialogs, App, ColorSel, TextView;

const
  cmColors = 100;

type
  TDemo = object(TApplication)
    Term: PTerminal;
    constructor Init;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitStatusLine; virtual;
    procedure Colors;
  end;

var
  T: Text;

constructor TDemo.Init;
var
  R: TRect;
  W: PWindow;
  I: Integer;
begin
  inherited Init;
  RegisterViews;
  RegisterDialogs;
  RegisterColorSel;
  R.Assign(2, 1, 36, 12);
  W := New(PWindow, Init(R, 'Terminal', 1));
  W^.GetExtent(R);
  R.Grow(-1, -1);
  Term := New(PTerminal, Init(R, W^.StandardScrollBar(sbHorizontal + sbHandleKeyboard),
    W^.StandardScrollBar(sbVertical + sbHandleKeyboard), 256));
  W^.Insert(Term);
  InsertWindow(W);
  AssignDevice(T, Term);
  Rewrite(T);
  for I := 1 to 20 do
    WriteLn(T, 'Baris ', I, ' dari 20');
  WriteLn(T, 'Tab:'#9'satu'#9'dua');
  WriteLn(T, 'Baris panjang yang melewati lebar jendela terminal');
  Write(T, 'Siap');
end;

procedure TDemo.Colors;
var
  D: PColorDialog;
  S: TMemoryStream;
begin
  D := New(PColorDialog, Init('',
    ColorGroup('Desktop', DesktopColorItems(nil),
    ColorGroup('Menus', MenuColorItems(nil),
    ColorGroup('Dialogs', DialogColorItems(dpGrayDialog, nil),
    ColorGroup('Windows', WindowColorItems(wpBlueWindow, nil), nil))))));
  { Through a stream and back: the loaded copy runs. }
  S.Init(0, 1024);
  S.Put(D);
  Dispose(D, Done);
  S.Seek(0);
  D := PColorDialog(S.Get);
  if S.Status <> stOk then
    WriteLn(T, 'stream ', S.Status);
  S.Done;
  if ExecuteDialog(D, Application^.GetPalette) <> cmCancel then
  begin
    Redraw;
    WriteLn(T);
    Write(T, 'Desktop ', Ord(GetPalette^[1]), ', menu ', Ord(GetPalette^[2]));
  end;
end;

procedure TDemo.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evCommand) and (Event.Command = cmColors) then
  begin
    Colors;
    ClearEvent(Event);
  end;
end;

procedure TDemo.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  StatusLine := New(PStatusLine, Init(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~Alt-X~ Exit', kbAltX, cmQuit,
      NewStatusKey('~F4~ Colors', kbF4, cmColors,
      StdStatusKeys(nil))), nil)));
end;

var
  A: TDemo;
  Lines, Width: Integer;
begin
  A.Init;
  A.Run;
  Lines := A.Term^.Limit.Y;
  Width := A.Term^.CalcWidth;
  Close(T);
  A.Done;
  WriteLn('VCOLORS ', Lines, ' ', Width);
end.
