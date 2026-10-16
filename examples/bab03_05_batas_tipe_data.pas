{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 3.5 - Batas tipe data
  Setiap tipe punya ukuran memori dan rentang nilai. Low dan High
  memberi nilai terkecil dan terbesar, SizeOf memberi ukurannya. }

program bab03_05_batas_tipe_data;

begin
  WriteLn('Tipe     Byte      Terkecil      Terbesar');
  WriteLn('-----------------------------------------');
  WriteLn('Byte    ', SizeOf(Byte):5, Low(Byte):14, High(Byte):14);
  WriteLn('ShortInt', SizeOf(ShortInt):5, Low(ShortInt):14, High(ShortInt):14);
  WriteLn('Word    ', SizeOf(Word):5, Low(Word):14, High(Word):14);
  WriteLn('Integer ', SizeOf(Integer):5, Low(Integer):14, High(Integer):14);
  WriteLn('LongInt ', SizeOf(LongInt):5, Low(LongInt):14, High(LongInt):14);
  WriteLn('Char    ', SizeOf(Char):5, Ord(Low(Char)):14, Ord(High(Char)):14);
  WriteLn('Boolean ', SizeOf(Boolean):5, Ord(False):14, Ord(True):14);
  WriteLn('Real    ', SizeOf(Real):5, '  sekitar 15 angka penting');
  WriteLn;

  { MaxInt dan MaxLongInt adalah konstanta bawaan Pascal }
  WriteLn('MaxInt     = ', MaxInt);
  WriteLn('MaxLongInt = ', MaxLongInt);

  { Range checking aktif (Options > Compiler), jadi nilai yang keluar
    dari rentang menghentikan program dengan runtime error 201:
      var B: Byte;  ...  B := 255;  B := B + 1;
    Pilih tipe yang rentangnya cukup untuk data Anda. }
end.
