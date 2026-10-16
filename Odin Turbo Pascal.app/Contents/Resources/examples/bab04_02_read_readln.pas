{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 4.2 - Read dan ReadLn
  ReadLn membaca masukan dari keyboard sampai Enter ditekan, lalu
  menyimpannya ke variabel. Ketik jawaban di User screen. }

program bab04_02_read_readln;

var
  Nama: string;
  Umur: Integer;
  Tinggi: Real;
  A, B: Integer;

begin
  Write('Nama Anda   : ');      { Write: jawaban diketik di baris yang sama }
  ReadLn(Nama);                 { membaca satu baris teks }
  Write('Umur (tahun): ');
  ReadLn(Umur);                 { membaca bilangan bulat }
  Write('Tinggi (cm) : ');
  ReadLn(Tinggi);               { membaca bilangan pecahan, misal 160.5 }

  { Beberapa bilangan bisa dibaca sekaligus, dipisahkan spasi }
  Write('Ketik dua bilangan, pisahkan dengan spasi: ');
  ReadLn(A, B);

  WriteLn;
  WriteLn('Halo, ', Nama, '!');
  WriteLn('Tahun depan umur Anda ', Umur + 1, ' tahun.');
  WriteLn('Tinggi Anda ', Tinggi:0:1, ' cm.');
  WriteLn(A, ' + ', B, ' = ', A + B);

  { Bila yang diketik bukan angka untuk variabel bilangan, program
    berhenti dengan runtime error 106. Bab 12 membahas cara mencegahnya. }
end.
