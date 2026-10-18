program Cari;
uses Dos;
var
  S: SearchRec;
  F: Text;
  N: LongInt;
begin
  Assign(F, 'satu.dat');
  Rewrite(F);
  Close(F);
  Assign(F, 'dua.dat');
  Rewrite(F);
  Close(F);
  N := 0;
  FindFirst('*.dat', AnyFile, S);
  while DosError = 0 do
  begin
    Inc(N);
    FindNext(S);
  end;
  WriteLn(N);
end.
