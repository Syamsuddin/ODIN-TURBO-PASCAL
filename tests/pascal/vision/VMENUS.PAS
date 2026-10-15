{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VMenus;
{ Odin Vision snapshot demo: menu bar, status line, windows, Cascade and
  mouse focus. Driven by tests/test_vision.py. }
uses Objects, Drivers, Views, Menus, App;

const
  cmBaru = 100;

type
  TDemo = object(TApplication)
    Count: Integer;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitMenuBar; virtual;
    procedure InitStatusLine; virtual;
    procedure NewWin;
  end;

procedure TDemo.NewWin;
var
  R: TRect;
  W: PWindow;
begin
  Inc(Count);
  R.Assign(Count * 4, Count * 2, Count * 4 + 30, Count * 2 + 9);
  W := New(PWindow, Init(R, 'Jendela', Count));
  W^.Options := W^.Options or ofTileable;
  InsertWindow(W);
end;

procedure TDemo.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evCommand) and (Event.Command = cmBaru) then
  begin
    NewWin;
    ClearEvent(Event);
  end;
end;

procedure TDemo.InitMenuBar;
var
  R: TRect;
begin
  GetExtent(R);
  R.B.Y := R.A.Y + 1;
  MenuBar := New(PMenuBar, Init(R, NewMenu(
    NewSubMenu('~F~ile', hcNoContext, NewMenu(
      NewItem('~B~aru', 'F4', kbF4, cmBaru, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt-X', kbAltX, cmQuit, hcNoContext, nil)))),
    NewSubMenu('~W~indow', hcNoContext, NewMenu(
      StdWindowMenuItems(nil)), nil)))));
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
      NewStatusKey('~F4~ Baru', kbF4, cmBaru,
      NewStatusKey('~F10~ Menu', kbF10, cmMenu,
      StdStatusKeys(nil)))), nil)));
end;

var
  A: TDemo;
begin
  A.Init;
  A.NewWin;
  A.NewWin;
  A.Run;
  A.Done;
  WriteLn('VMENUS selesai, jendela ', A.Count);
end.
