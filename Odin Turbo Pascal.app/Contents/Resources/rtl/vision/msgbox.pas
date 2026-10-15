{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit MsgBox dari Odin Vision: MessageBox dan InputBox. Implementasi
  clean-room berdasarkan dokumentasi API Turbo Vision TP7. Judul dan
  tombol berbahasa Inggris, seperti label menu Turbo Vision. }
unit MsgBox;

{$R-,Q-,I-,X+}

interface

uses Objects;

const
  mfWarning = $0000;
  mfError = $0001;
  mfInformation = $0002;
  mfConfirmation = $0003;
  mfInsertInApp = $0080;

  mfYesButton = $0100;
  mfNoButton = $0200;
  mfOKButton = $0400;
  mfCancelButton = $0800;

  mfYesNoCancel = mfYesButton + mfNoButton + mfCancelButton;
  mfOKCancel = mfOKButton + mfCancelButton;

function MessageBox(const Msg: String; Params: Pointer; AOptions: Word): Word;
function MessageBoxRect(var R: TRect; const Msg: String; Params: Pointer; AOptions: Word): Word;
function InputBox(const Title, ALabel: String; var S: String; Limit: Byte): Word;
function InputBoxRect(var Bounds: TRect; const Title, ALabel: String; var S: String; Limit: Byte): Word;

implementation

uses Drivers, Views, Dialogs, App;

{ Centers R in the desktop, or in the application with mfInsertInApp. }
procedure Center(var R: TRect; InApp: Boolean);
var
  W, H: Sw_Integer;
  Owner: PView;
begin
  if InApp or (Desktop = nil) then
    Owner := Application
  else
    Owner := Desktop;
  W := R.B.X - R.A.X;
  H := R.B.Y - R.A.Y;
  if Owner <> nil then
    R.Assign((Owner^.Size.X - W) div 2, (Owner^.Size.Y - H) div 2,
      (Owner^.Size.X - W) div 2 + W, (Owner^.Size.Y - H) div 2 + H);
end;

function MessageBox(const Msg: String; Params: Pointer; AOptions: Word): Word;
var
  R: TRect;
begin
  R.Assign(0, 0, 40, 9);
  Center(R, AOptions and mfInsertInApp <> 0);
  MessageBox := MessageBoxRect(R, Msg, Params, AOptions);
end;

function MessageBoxRect(var R: TRect; const Msg: String; Params: Pointer; AOptions: Word): Word;
const
  Titles: array[0..3] of String[11] = ('Warning', 'Error', 'Information', 'Confirm');
  Names: array[0..3] of String[7] = ('~Y~es', '~N~o', 'O~K~', 'Cancel');
  Commands: array[0..3] of Word = (cmYes, cmNo, cmOK, cmCancel);
var
  Dialog: PDialog;
  T: TRect;
  S: String;
  I, X, Count: Sw_Integer;
  Buttons: array[0..3] of PButton;
  Dummy: PtrInt;
begin
  Dialog := New(PDialog, Init(R, Titles[AOptions and 3]));
  T.Assign(3, 2, Dialog^.Size.X - 2, Dialog^.Size.Y - 3);
  if Params = nil then
  begin
    Dummy := 0;
    FormatStr(S, Msg, Dummy);
  end
  else
    FormatStr(S, Msg, Params^);
  Dialog^.Insert(New(PStaticText, Init(T, S)));
  X := -2;
  Count := 0;
  for I := 0 to 3 do
    if AOptions and ($0100 shl I) <> 0 then
    begin
      T.Assign(0, 0, 10, 2);
      Buttons[Count] := New(PButton, Init(T, Names[I], Commands[I], bfNormal));
      Inc(X, Buttons[Count]^.Size.X + 2);
      Inc(Count);
    end;
  X := (Dialog^.Size.X - X) div 2;
  for I := 0 to Count - 1 do
  begin
    Dialog^.Insert(Buttons[I]);
    Buttons[I]^.MoveTo(X, Dialog^.Size.Y - 3);
    Inc(X, Buttons[I]^.Size.X + 2);
  end;
  Dialog^.SelectNext(False);
  if (AOptions and mfInsertInApp <> 0) or (Desktop = nil) then
    MessageBoxRect := Application^.ExecView(Dialog)
  else
    MessageBoxRect := Desktop^.ExecView(Dialog);
  Dispose(Dialog, Done);
end;

function InputBox(const Title, ALabel: String; var S: String; Limit: Byte): Word;
var
  R: TRect;
begin
  R.Assign(0, 0, 60, 8);
  Center(R, False);
  InputBox := InputBoxRect(R, Title, ALabel, S, Limit);
end;

function InputBoxRect(var Bounds: TRect; const Title, ALabel: String; var S: String; Limit: Byte): Word;
var
  Dialog: PDialog;
  Control: PView;
  R: TRect;
  C: Word;
begin
  Dialog := New(PDialog, Init(Bounds, Title));
  R.Assign(4 + CStrLen(ALabel), 2, Dialog^.Size.X - 3, 3);
  Control := New(PInputLine, Init(R, Limit));
  Dialog^.Insert(Control);
  R.Assign(2, 2, 3 + CStrLen(ALabel), 3);
  Dialog^.Insert(New(PLabel, Init(R, ALabel, Control)));
  R.Assign(Dialog^.Size.X - 24, Dialog^.Size.Y - 3, Dialog^.Size.X - 14, Dialog^.Size.Y - 1);
  Dialog^.Insert(New(PButton, Init(R, 'O~K~', cmOK, bfDefault)));
  Inc(R.A.X, 12);
  Inc(R.B.X, 12);
  Dialog^.Insert(New(PButton, Init(R, 'Cancel', cmCancel, bfNormal)));
  Dialog^.SelectNext(False);
  Dialog^.SetData(S);
  if Desktop <> nil then
    C := Desktop^.ExecView(Dialog)
  else
    C := Application^.ExecView(Dialog);
  if C <> cmCancel then
    Dialog^.GetData(S);
  Dispose(Dialog, Done);
  InputBoxRect := C;
end;

end.
