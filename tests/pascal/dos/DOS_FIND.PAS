{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosFind;
{ TP7 Dos unit on macOS: FindFirst/FindNext with '*' and '?' wildcards
  (case-sensitive; '*.*' needs a dot). Directories and dot files show up
  only when Attr includes Directory or Hidden. A dot file is Hidden, a file
  the user cannot write is ReadOnly. Entries are sorted here because the
  directory order is not defined. Also GetFAttr, GetFTime/SetFTime. }
uses Dos;
var
  S: SearchRec;
  T: Text;
  F: File;
  A: Word;
  L, M: LongInt;
  DT: DateTime;

procedure Touch(const Name: String);
begin
  Assign(T, Name);
  Rewrite(T);
  Close(T);
end;

procedure List(const P: String; Attr: Word);
var
  Names: array[1..50] of String;
  I, J, K: Integer;
  X: String;
begin
  K := 0;
  FindFirst(P, Attr, S);
  Write('[', P, '] attr ', Attr, ' first ', DosError, ':');
  while DosError = 0 do
  begin
    Inc(K);
    Str(S.Attr, X);
    Names[K] := S.Name + '/' + X;
    FindNext(S);
  end;
  for I := 1 to K do
    for J := I + 1 to K do
      if Names[J] < Names[I] then
      begin
        X := Names[I]; Names[I] := Names[J]; Names[J] := X;
      end;
  for I := 1 to K do
    Write(' ', Names[I]);
  WriteLn(' | end ', DosError);
  FindClose(S);
end;

begin
  MkDir('w');
  MkDir('w/sub');
  MkDir('w/.hdir');
  Touch('w/a.txt');
  Touch('w/b.TXT');
  Touch('w/noext');
  Touch('w/.dot');
  Touch('w/x.y.z');
  Touch('w/sp ace.t');
  Assign(T, 'w/data.bin');
  Rewrite(T);
  Write(T, 'twelve bytes');
  Close(T);

  List('w/*', AnyFile);
  List('w/*.*', AnyFile);
  List('w/*', 0);
  List('w/*', Directory);
  List('w/*', Hidden);
  List('w/*', ReadOnly);
  List('w/*.txt', AnyFile);
  List('w/*.TXT', AnyFile);
  List('w/?.txt', AnyFile);
  List('w/a.*', AnyFile);
  List('w/*.', AnyFile);
  List('w/noext', AnyFile);
  List('w/a.txt', 0);
  List('w/sub', Directory);
  List('w/sub', 0);
  List('w/nothing*', AnyFile);
  List('nodir/*', AnyFile);
  List('w/*.y', AnyFile);
  List('w/*z', AnyFile);
  List('w/x*', AnyFile);
  List('w/[ab]*', AnyFile);
  List('w/', AnyFile);
  List('w', AnyFile);
  List('', AnyFile);

  FindFirst('w/data.bin', AnyFile, S);
  WriteLn('size ', S.Size, ' time set ', S.Time <> 0, ' name ', S.Name);
  FindNext(S);
  WriteLn('next after single ', DosError);
  FindNext(S);
  WriteLn('next again ', DosError);

  Assign(F, 'w/a.txt');
  GetFAttr(F, A);
  WriteLn('attr file ', A, ' err ', DosError);
  Assign(F, 'w/sub');
  GetFAttr(F, A);
  WriteLn('attr dir ', A, ' err ', DosError);
  Assign(F, 'w/.dot');
  GetFAttr(F, A);
  WriteLn('attr dot ', A, ' err ', DosError);
  Assign(F, 'w/missing');
  GetFAttr(F, A);
  WriteLn('attr missing ', A, ' err ', DosError);
  Assign(F, 'w/a.txt');
  SetFAttr(F, ReadOnly);
  GetFAttr(F, A);
  WriteLn('SetFAttr changes nothing: err ', DosError, ' attr ', A);

  Assign(F, 'w/a.txt');
  GetFTime(F, L);
  WriteLn('GetFTime closed: err ', DosError, ' time ', L);
  with DT do
  begin
    Year := 2001; Month := 2; Day := 3; Hour := 4; Min := 5; Sec := 6;
  end;
  PackTime(DT, M);
  SetFTime(F, M);
  WriteLn('SetFTime by name: err ', DosError);
  Reset(F, 1);
  GetFTime(F, L);
  WriteLn('GetFTime open: err ', DosError, ' same ', L = M);
  Close(F);
  FindFirst('w/a.txt', AnyFile, S);
  WriteLn('SearchRec time same ', S.Time = M);
end.
