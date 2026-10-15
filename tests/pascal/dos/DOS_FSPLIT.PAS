{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program DosFSplit;
{ TP7 Dos unit: FSplit splits a path into directory, name and extension.
  The directory keeps its trailing separator; the extension starts at the
  last dot of the last component. A backslash also separates directories
  and comes back as '/'. Nothing is truncated to DOS 8.3 lengths. }
uses Dos;

procedure S(const P: PathStr);
var
  D: DirStr;
  N: NameStr;
  E: ExtStr;
begin
  D := '#';
  N := '#';
  E := '#';
  FSplit(P, D, N, E);
  WriteLn('[', P, '] -> dir [', D, '] name [', N, '] ext [', E, ']');
end;

procedure Plain;
{ Plain String variables work too: the Dos string types hold 255 chars. }
var
  P, D, N, E: String;
begin
  P := '/home/user/report.final.txt';
  FSplit(P, D, N, E);
  WriteLn('String vars: [', D, '] [', N, '] [', E, ']');
  WriteLn('rejoined: ', D + N + E = P);
end;

begin
  WriteLn('-- ordinary paths');
  S('/usr/local/bin/fpc');
  S('file.txt');
  S('archive.tar.gz');
  S('a.b.c');
  S('../x.pas');
  S('./y');
  S('dir.d/file');
  S('a.b/c');
  S('x/y/z.');
  S('a b/c d.e f');
  WriteLn('-- directories only');
  S('dir/');
  S('/');
  S('/a/b.c/');
  S('//double//slash.x');
  WriteLn('-- dots');
  S('.profile');
  S('dir/.hidden.txt');
  S('name.');
  S('.');
  S('..');
  S('...');
  S('a..b');
  WriteLn('-- empty');
  S('');
  WriteLn('-- DOS style');
  S('C:\TP\BIN\TURBO.EXE');
  S('dir\file.ext');
  S('mixed\sep/file.e');
  S('C:FOO.BAR');
  WriteLn('-- long names');
  S('averyveryverylongfilename.extensionlong');
  S('/a/directory/name/that/is/longer/than/sixty/seven/characters/total/f.pas');
  Plain;
end.
