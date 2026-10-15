{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VEditor;
{ Odin Vision snapshot demo: an untitled TEditWindow, an outline window
  and the standard editor dialogs (save prompt on exit). }
uses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, Editors, Outline;

const
  cmOutline = 101;

type
  TDemo = object(TApplication)
    constructor Init;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitStatusLine; virtual;
    procedure OpenOutline;
  end;

constructor TDemo.Init;
var
  R: TRect;
begin
  inherited Init;
  EditorDialog := StdEditorDialog;
  R.Assign(0, 0, 44, 16);
  InsertWindow(New(PEditWindow, Init(R, '', 1)));
end;

procedure TDemo.OpenOutline;
var
  R: TRect;
  W: PWindow;
begin
  R.Assign(42, 3, 74, 13);
  W := New(PWindow, Init(R, 'Pohon', 2));
  W^.GetExtent(R);
  R.Grow(-1, -1);
  W^.Insert(New(POutline, Init(R, nil, nil,
    NewNode('Hewan',
      NewNode('Mamalia', NewNode('Kucing', nil, NewNode('Paus', nil, nil)),
      NewNode('Burung', NewNode('Elang', nil, nil), nil)), nil))));
  InsertWindow(W);
end;

procedure TDemo.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evCommand) and (Event.Command = cmOutline) then
  begin
    OpenOutline;
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
      NewStatusKey('~F4~ Pohon', kbF4, cmOutline,
      StdStatusKeys(nil))), nil)));
end;

var
  A: TDemo;
begin
  A.Init;
  A.Run;
  A.Done;
  WriteLn('VEDITOR selesai');
end.
