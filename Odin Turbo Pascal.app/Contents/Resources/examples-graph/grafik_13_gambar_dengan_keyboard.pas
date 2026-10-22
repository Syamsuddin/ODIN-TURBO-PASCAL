{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Grafik 13 - Menggambar dengan tombol panah
  Jendela grafik meneruskan tombol ke program seperti layar teks, jadi
  ReadKey bekerja. Tombol panah dan fungsi mengirim #0 lalu kode scan.
  Panah: gerak pena, spasi: angkat atau turunkan pena, 1..9: ganti warna,
  C: bersihkan, Esc atau Q: selesai. }

program grafik_13_gambar_dengan_keyboard;

uses Crt, Graph;

const
  Langkah = 4;

var
  Driver, Mode: Integer;
  X, Y: Integer;
  Warna: Integer;
  Turun: Boolean;
  Tombol: Char;

procedure Kursor(Hapus: Boolean);
begin
  { Tanda silang kecil digambar dengan XOR: dua kali = hilang }
  SetWriteMode(XORPut);
  SetColor(15);
  Line(X - 5, Y, X + 5, Y);
  Line(X, Y - 5, X, Y + 5);
  SetWriteMode(CopyPut);
end;

procedure Petunjuk;
begin
  SetColor(White);
  OutTextXY(8, 4, 'Panah: gerak  Spasi: pena naik/turun  1-9: warna  C: hapus  Esc: selesai');
end;

begin
  Driver := Detect;
  InitGraph(Driver, Mode, '');
  if GraphResult <> grOk then Halt(1);

  X := 320; Y := 240; Warna := LightGreen; Turun := True;
  Petunjuk;
  Kursor(False);
  repeat
    Tombol := ReadKey;
    Kursor(True);                      { hapus tanda silang sebelum bergerak }
    if Tombol = #0 then
    begin
      Tombol := ReadKey;               { kode scan: 72 atas, 80 bawah, 75 kiri, 77 kanan }
      if Turun then
      begin
        SetColor(Warna);
        MoveTo(X, Y);
      end;
      case Tombol of
        #72: Dec(Y, Langkah);
        #80: Inc(Y, Langkah);
        #75: Dec(X, Langkah);
        #77: Inc(X, Langkah);
      end;
      if X < 0 then X := 0;
      if Y < 20 then Y := 20;
      if X > GetMaxX then X := GetMaxX;
      if Y > GetMaxY then Y := GetMaxY;
      if Turun then LineTo(X, Y);
      Tombol := #0;
    end
    else
      case UpCase(Tombol) of
        ' ': Turun := not Turun;
        '1'..'9': Warna := Ord(Tombol) - Ord('0');
        'C':
          begin
            ClearDevice;
            Petunjuk;
          end;
      end;
    Kursor(False);
  until (Tombol = #27) or (UpCase(Tombol) = 'Q') or (Tombol = #26);
  CloseGraph;
end.
