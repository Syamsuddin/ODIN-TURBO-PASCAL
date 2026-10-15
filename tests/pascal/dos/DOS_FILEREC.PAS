{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosFileRec;
{ TP7 Dos unit: the FileRec and TextRec views of file variables. Mode holds
  fmClosed, fmInput, fmOutput or fmInOut; Name holds the assigned name as a
  null-terminated character array; RecSize holds the record size. }
uses Dos;
var
  T: Text;
  F: File;
  G: file of Integer;
  W: file of LongInt;
  I: Integer;

function ModeName(M: Word): String;
begin
  if M = fmClosed then ModeName := 'fmClosed'
  else if M = fmInput then ModeName := 'fmInput'
  else if M = fmOutput then ModeName := 'fmOutput'
  else if M = fmInOut then ModeName := 'fmInOut'
  else ModeName := 'other';
end;

procedure ShowName(const Lbl: String; var R: FileRec);
var
  K: Integer;
  S: String;
begin
  S := '';
  K := 0;
  while (K < 255) and (R.Name[K] <> #0) do
  begin
    S := S + Chr(Ord(R.Name[K]));
    Inc(K);
  end;
  WriteLn(Lbl, ' name [', S, '] length ', K);
end;

begin
  WriteLn('Input:  ', ModeName(TextRec(Input).Mode));
  WriteLn('Output: ', ModeName(TextRec(Output).Mode));

  Assign(T, 'modes.txt');
  WriteLn('text assigned: ', ModeName(TextRec(T).Mode));
  Rewrite(T);
  WriteLn('text rewrite:  ', ModeName(TextRec(T).Mode));
  WriteLn(T, 'one line');
  Close(T);
  WriteLn('text closed:   ', ModeName(TextRec(T).Mode));
  Reset(T);
  WriteLn('text reset:    ', ModeName(TextRec(T).Mode));
  Close(T);
  Append(T);
  WriteLn('text append:   ', ModeName(TextRec(T).Mode));
  Close(T);
  WriteLn('text closed:   ', ModeName(TextRec(T).Mode));

  Assign(F, 'modes.txt');
  ShowName('untyped', FileRec(F));
  WriteLn('untyped assigned: ', ModeName(FileRec(F).Mode));
  Reset(F, 1);
  WriteLn('untyped reset 1:  ', ModeName(FileRec(F).Mode), ' RecSize ', FileRec(F).RecSize);
  Close(F);
  WriteLn('untyped closed:   ', ModeName(FileRec(F).Mode));
  Reset(F);
  WriteLn('untyped reset:    RecSize ', FileRec(F).RecSize);
  Close(F);

  Assign(F, 'blocks.dat');
  Rewrite(F, 16);
  WriteLn('untyped rewrite 16: ', ModeName(FileRec(F).Mode), ' RecSize ', FileRec(F).RecSize);
  Close(F);

  Assign(G, 'ints.dat');
  ShowName('typed', FileRec(G));
  Rewrite(G);
  WriteLn('typed rewrite: ', ModeName(FileRec(G).Mode), ' RecSize ', FileRec(G).RecSize);
  for I := 1 to 3 do Write(G, I);
  Close(G);
  WriteLn('typed closed:  ', ModeName(FileRec(G).Mode));

  { FileMode chooses the mode that Reset gives typed and untyped files. }
  FileMode := 0;
  Reset(G);
  WriteLn('typed reset FileMode=0: ', ModeName(FileRec(G).Mode));
  Close(G);
  FileMode := 1;
  Reset(G);
  WriteLn('typed reset FileMode=1: ', ModeName(FileRec(G).Mode));
  Close(G);
  FileMode := 2;
  Reset(G);
  WriteLn('typed reset FileMode=2: ', ModeName(FileRec(G).Mode));
  Close(G);
  FileMode := 0;
  Rewrite(G);
  WriteLn('typed rewrite FileMode=0: ', ModeName(FileRec(G).Mode));
  Close(G);
  FileMode := 0;
  Reset(T);
  WriteLn('text reset FileMode=0: ', ModeName(TextRec(T).Mode));
  Close(T);
  FileMode := 2;

  Assign(W, 'longs.dat');
  Rewrite(W);
  WriteLn('file of LongInt RecSize ', FileRec(W).RecSize);
  Close(W);
end.
