{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VDialog;
{ Odin Vision snapshot demo: a dialog with an input line (picture
  validator and history), check boxes, radio buttons and buttons; the
  result goes to a MessageBox and to standard output. }
uses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, Validate;

const
  cmDialog = 100;

type
  { Dialog data follows the controls byte for byte: packed. }
  TData = packed record
    Name: String[20];
    Opts: Word;
    Kind: Word;
  end;

  TDemo = object(TApplication)
    Data: TData;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitStatusLine; virtual;
    procedure ShowDialog;
  end;

procedure TDemo.ShowDialog;
var
  D: PDialog;
  R: TRect;
  L: PInputLine;
  C: PView;
  P: array[0..2] of PtrInt;
begin
  R.Assign(0, 0, 50, 15);
  D := New(PDialog, Init(R, 'Data Diri'));
  D^.Options := D^.Options or ofCentered;
  R.Assign(13, 2, 37, 3);
  L := New(PInputLine, Init(R, 20));
  L^.SetValidator(New(PPXPictureValidator, Init('&*?', True)));
  D^.Insert(L);
  R.Assign(2, 2, 12, 3);
  D^.Insert(New(PLabel, Init(R, '~N~ama', L)));
  R.Assign(37, 2, 40, 3);
  D^.Insert(New(PHistory, Init(R, L, 1)));
  R.Assign(3, 5, 22, 8);
  C := New(PCheckBoxes, Init(R, NewSItem('~T~ebal', NewSItem('~M~iring', NewSItem('~G~aris', nil)))));
  D^.Insert(C);
  R.Assign(2, 4, 12, 5);
  D^.Insert(New(PLabel, Init(R, '~G~aya', C)));
  R.Assign(26, 5, 46, 8);
  C := New(PRadioButtons, Init(R, NewSItem('~K~ecil', NewSItem('~S~edang', NewSItem('~B~esar', nil)))));
  D^.Insert(C);
  R.Assign(25, 4, 35, 5);
  D^.Insert(New(PLabel, Init(R, '~U~kuran', C)));
  R.Assign(15, 11, 25, 13);
  D^.Insert(New(PButton, Init(R, 'O~K~', cmOK, bfDefault)));
  R.Assign(27, 11, 37, 13);
  D^.Insert(New(PButton, Init(R, 'Cancel', cmCancel, bfNormal)));
  D^.SelectNext(False);
  if ExecuteDialog(D, @Data) <> cmCancel then
  begin
    P[0] := PtrInt(@Data.Name);
    P[1] := Data.Opts;
    P[2] := Data.Kind;
    MessageBox(#3'Nama %s'#13#3'gaya %d ukuran %d', @P, mfInformation + mfOKButton);
  end;
end;

procedure TDemo.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if (Event.What = evCommand) and (Event.Command = cmDialog) then
  begin
    ShowDialog;
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
      NewStatusKey('~F4~ Dialog', kbF4, cmDialog,
      StdStatusKeys(nil))), nil)));
end;

var
  A: TDemo;
begin
  A.Init;
  A.Data.Name := 'budi';
  A.Data.Opts := 2;
  A.Data.Kind := 1;
  A.Run;
  A.Done;
  WriteLn('VDIALOG ', A.Data.Name, ' ', A.Data.Opts, ' ', A.Data.Kind);
end.
