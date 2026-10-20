{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 1.2 - Memeriksa kompiler
  Program ini memastikan kompiler terpasang dan bisa membuat program.
  Baris berawalan $IFDEF dibaca sebelum kompilasi: hanya bagian yang
  cocok dengan kompiler dan sistem Anda yang ikut dikompilasi. }

program bab01_02_cek_kompiler;

begin
  WriteLn('PEMERIKSAAN KOMPILER');
  WriteLn('====================');

  { Nama kompiler: kompiler Odin mendefinisikan simbol ODIN }
  {$IFDEF ODIN} WriteLn('Kompiler : Odin (odinpc)'); {$ENDIF}

  { Sistem operasi tempat program berjalan }
  {$IFDEF DARWIN} WriteLn('Sistem   : macOS'); {$ENDIF}
  {$IFDEF LINUX} WriteLn('Sistem   : Linux'); {$ENDIF}
  {$IFDEF WINDOWS} WriteLn('Sistem   : Windows'); {$ENDIF}

  { Jenis prosesor }
  {$IFDEF CPUX86_64} WriteLn('Prosesor : x86-64 (Intel/AMD)'); {$ENDIF}
  {$IFDEF CPUAARCH64} WriteLn('Prosesor : ARM64'); {$ENDIF}

  { Mode Turbo Pascal: Integer berukuran 2 byte, seperti TP7 }
  WriteLn('Integer  : ', SizeOf(Integer), ' byte');
  WriteLn('Uji hitung 2 + 3 = ', 2 + 3);
  WriteLn;
  WriteLn('Kompiler siap dipakai.');
end.
