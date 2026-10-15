{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosPaths;
{ TP7 Dos unit on macOS: FExpand makes a path absolute ('\' becomes '/',
  '~' is $HOME, '.' and '..' are resolved, repeated separators collapse
  except a leading '//', a trailing '/' stays). FSearch tries the name as
  given, then each directory of a ';' or ':' separated list, and never
  returns a directory. The current directory is printed as '<cwd>'. }
uses Dos;
var
  Cwd, Home: String;
  T: Text;

function Shown(const S: String): String;
begin
  if Copy(S, 1, Length(Cwd)) = Cwd then
    Shown := '<cwd>' + Copy(S, Length(Cwd) + 1, 255)
  else if (Home <> '') and (Copy(S, 1, Length(Home)) = Home) then
    Shown := '<home>' + Copy(S, Length(Home) + 1, 255)
  else
    Shown := S;
end;

procedure X(const S: String);
begin
  WriteLn('[', S, '] -> [', Shown(FExpand(S)), ']');
end;

procedure Fs(const N, L: String);
begin
  WriteLn('FSearch [', N, '] in [', L, '] -> [', FSearch(N, L), ']');
end;

begin
  GetDir(0, Cwd);
  Home := GetEnv('HOME');
  X('a/../b/./c.txt');
  X('/x/y/../z');
  X('');
  X('.');
  X('x/');
  X('dir\sub\f.x');
  X('/a/./b/.');
  X('/a/b/..');
  X('/..');
  X('/.');
  X('/../a');
  X('a/../');
  X('/a/b/../c/./d/../../e');
  X('/a/.b/..c/...');
  X('/a//');
  X('///');
  X('//a///b/');
  X('/a/b/c/../../..');
  X('./');
  X('a/./');
  X('/x/..y');
  X('~');
  X('~/q');
  X('~root');
  X('a~/b');
  X('x/~/y');
  X('C:\FOO');

  MkDir('bin');
  MkDir('bin/inner');
  Assign(T, 'bin/tool');
  Rewrite(T);
  Close(T);
  Assign(T, 'here.txt');
  Rewrite(T);
  Close(T);
  Fs('tool', 'nothing;bin');
  Fs('tool', 'nothing:bin/');
  Fs('tool', 'nothing');
  Fs('here.txt', 'bin');
  Fs('inner', 'bin');
  Fs('bin', '.');
  Fs('', 'bin');
  Fs('bin/tool', '');
  Fs('tool', ';;bin');
  Fs('inner/../tool', 'bin');

  WriteLn('GetEnv is case-sensitive: ', GetEnv('HOME') <> '', ' [', GetEnv('home'), ']');
  WriteLn('GetEnv missing [', GetEnv('ODIN_NO_SUCH_VARIABLE'), ']');
  WriteLn('EnvStr out of range [', EnvStr(0), '] [', EnvStr(-1), '] [', EnvStr(EnvCount + 1), ']');
  WriteLn('EnvStr entries have "=": ', Pos('=', EnvStr(1)) > 0, ' ', Pos('=', EnvStr(EnvCount)) > 0);
end.
