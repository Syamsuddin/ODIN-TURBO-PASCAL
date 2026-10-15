{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ IOResult codes, typed and untyped files, directories (values measured with FPC 3.2.2). }
program FilIoCodes;
var F: Text; G: file of Integer; H: file; S: string; I, R: Integer; X: Real; C: Char;
begin
  {$I-}
  Assign(F, 'missing.txt'); Reset(F); WriteLn('reset missing ', IOResult);
  Assign(F, 'nodir/x.txt'); Reset(F); WriteLn('reset nodir ', IOResult);
  Assign(F, 'nodir/x.txt'); Rewrite(F); WriteLn('rewrite nodir ', IOResult);
  Assign(F, 'a.txt'); Close(F); WriteLn('close unopened ', IOResult);
  Rewrite(F); WriteLn(F, '12'); ReadLn(F, S); WriteLn('read on output ', IOResult); Close(F);
  Reset(F); WriteLn(F, 'x'); WriteLn('write on input ', IOResult);
  ReadLn(F, I); WriteLn('int ', I, ' ', IOResult);
  Read(F, I); WriteLn('int at eof ', IOResult);
  Read(F, X); WriteLn('real at eof ', IOResult);
  Read(F, C); WriteLn('char at eof ', Ord(C), ' ', IOResult);
  Read(F, S); WriteLn('str at eof [', S, '] ', IOResult);
  Close(F);
  MkDir('d1'); WriteLn('mkdir ', IOResult); MkDir('d1'); WriteLn('mkdir again ', IOResult);
  RmDir('nope'); WriteLn('rmdir missing ', IOResult); ChDir('nope'); WriteLn('chdir missing ', IOResult);
  Assign(F, 'gone.txt'); Erase(F); WriteLn('erase missing ', IOResult);
  Rename(F, 'other.txt'); WriteLn('rename missing ', IOResult);
  Assign(G, 'ints.dat'); Rewrite(G); I := 7; Write(G, I); I := 9; Write(G, I);
  WriteLn('size ', FileSize(G), ' pos ', FilePos(G)); Seek(G, 0); Read(G, R); WriteLn('first ', R, ' pos ', FilePos(G), ' eof ', Eof(G));
  Seek(G, 5); WriteLn('seek past ', IOResult); Read(G, R); WriteLn('read past ', IOResult); Close(G);
  Assign(G, 'missing.dat'); Reset(G); WriteLn('reset typed missing ', IOResult);
  Assign(H, 'ints.dat'); Reset(H, 1); BlockRead(H, I, 2, R); WriteLn('blockread ', I, ' got ', R, ' ', IOResult);
  BlockRead(H, I, 10, R); WriteLn('partial got ', R, ' ', IOResult); BlockRead(H, I, 10); WriteLn('no result ', IOResult); Close(H);
  Reset(H); WriteLn('reset default recsize filesize ', FileSize(H)); Close(H);
  Assign(F, ''); Rewrite(F); WriteLn('empty name rewrite ', IOResult); Close(F);
  WriteLn('eof input ', Eof);
end.
