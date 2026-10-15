{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program VisionDemo;
{ Demo Turbo Vision: menu, status line, jendela catatan, dialog, dan
  MessageBox. Jalankan dengan Ctrl+F9; programnya tampil di User screen.
  Tombol: F10 menu, F4 jendela baru, F3 dialog, F6 jendela berikutnya,
  Alt+F3 tutup jendela, Alt+X keluar. Mouse juga bisa dipakai. }
uses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, Editors;

const
  cmCatatan = 100;
  cmDialog = 101;
  cmTentang = 102;

type
  TDemo = object(TApplication)
    Nomor: Integer;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitMenuBar; virtual;
    procedure InitStatusLine; virtual;
    procedure Catatan;
    procedure Dialog;
  end;

{ Jendela berisi editor teks kosong. }
procedure TDemo.Catatan;
var
  R: TRect;
  W: PEditWindow;
begin
  Inc(Nomor);
  R.Assign(Nomor * 2, Nomor, Nomor * 2 + 44, Nomor + 12);
  W := New(PEditWindow, Init(R, '', Nomor));
  InsertWindow(W);
end;

{ Dialog dengan input line, check box, dan radio button. Hasilnya dibaca
  langsung dari kontrol. }
procedure TDemo.Dialog;
var
  D: PDialog;
  R: TRect;
  Nama: PInputLine;
  Gaya: PCheckBoxes;
  Ukuran: PRadioButtons;
  Pesan: String;
begin
  R.Assign(0, 0, 46, 14);
  D := New(PDialog, Init(R, 'Data'));
  D^.Options := D^.Options or ofCentered;
  R.Assign(12, 2, 40, 3);
  Nama := New(PInputLine, Init(R, 30));
  D^.Insert(Nama);
  R.Assign(2, 2, 11, 3);
  D^.Insert(New(PLabel, Init(R, '~N~ama', Nama)));
  R.Assign(3, 5, 21, 8);
  Gaya := New(PCheckBoxes, Init(R, NewSItem('~T~ebal', NewSItem('~M~iring', NewSItem('~G~aris', nil)))));
  D^.Insert(Gaya);
  R.Assign(2, 4, 12, 5);
  D^.Insert(New(PLabel, Init(R, '~G~aya', Gaya)));
  R.Assign(24, 5, 42, 8);
  Ukuran := New(PRadioButtons, Init(R, NewSItem('~K~ecil', NewSItem('~S~edang', NewSItem('~B~esar', nil)))));
  D^.Insert(Ukuran);
  R.Assign(23, 4, 33, 5);
  D^.Insert(New(PLabel, Init(R, '~U~kuran', Ukuran)));
  R.Assign(11, 10, 21, 12);
  D^.Insert(New(PButton, Init(R, 'O~K~', cmOK, bfDefault)));
  R.Assign(24, 10, 34, 12);
  D^.Insert(New(PButton, Init(R, 'Batal', cmCancel, bfNormal)));
  D^.SelectNext(False);
  if Desktop^.ExecView(D) = cmOK then
  begin
    Pesan := 'Halo, ' + Nama^.Data^ + '!';
    if Gaya^.Mark(0) then
      Pesan := Pesan + ' Tebal.';
    if Ukuran^.Value = 2 then
      Pesan := Pesan + ' Besar.';
    MessageBox(#3 + Pesan, nil, mfInformation + mfOKButton);
  end;
  Dispose(D, Done);
end;

procedure TDemo.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evCommand then
  begin
    case Event.Command of
      cmCatatan: Catatan;
      cmDialog: Dialog;
      cmTentang:
        MessageBox(#3'Demo Turbo Vision'#13#3'Odin Turbo Pascal', nil, mfInformation + mfOKButton);
    else
      Exit;
    end;
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
      NewItem('~N~ew window', 'F4', kbF4, cmCatatan, hcNoContext,
      NewItem('~D~ialog...', 'F3', kbF3, cmDialog, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt+X', kbAltX, cmQuit, hcNoContext, nil))))),
    NewSubMenu('~W~indow', hcNoContext, NewMenu(
      NewItem('~T~ile', '', kbNoKey, cmTile, hcNoContext,
      NewItem('C~a~scade', '', kbNoKey, cmCascade, hcNoContext,
      NewItem('~N~ext', 'F6', kbF6, cmNext, hcNoContext,
      NewItem('~C~lose', 'Alt+F3', kbAltF3, cmClose, hcNoContext, nil))))),
    NewSubMenu('~H~elp', hcNoContext, NewMenu(
      NewItem('~A~bout...', '', kbNoKey, cmTentang, hcNoContext, nil)), nil))))));
end;

procedure TDemo.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  StatusLine := New(PStatusLine, Init(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~Alt+X~ Exit', kbAltX, cmQuit,
      NewStatusKey('~F4~ New', kbF4, cmCatatan,
      NewStatusKey('~F3~ Dialog', kbF3, cmDialog,
      NewStatusKey('~F10~ Menu', kbF10, cmMenu,
      NewStatusKey('', kbF6, cmNext,
      NewStatusKey('', kbAltF3, cmClose, nil)))))), nil)));
end;

var
  Demo: TDemo;
begin
  Demo.Init;
  { Tanpa ini editor tidak bisa menanyakan "simpan?" saat keluar. }
  EditorDialog := StdEditorDialog;
  Demo.Catatan;
  Demo.Run;
  Demo.Done;
  WriteLn('Demo Turbo Vision selesai.');
end.
