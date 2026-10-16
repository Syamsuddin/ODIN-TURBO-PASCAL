{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 19.3 - Menu berwarna
  Menu dipilih dengan tombol panah atas/bawah lalu Enter. Tombol
  panah mengirim dua karakter: #0 lalu kode tombolnya (atas = 72,
  bawah = 80). Pilihan aktif ditandai dengan warna latar berbeda. }

program bab19_03_menu_berwarna;

uses
  Crt;

const
  JumlahMenu = 4;
  Menu: array[1..JumlahMenu] of string[20] =
    ('Profil sekolah', 'Jadwal pelajaran', 'Pengumuman', 'Keluar');

procedure Kotak(X1, Y1, X2, Y2: Integer);
var
  I: Integer;
begin
  GotoXY(X1, Y1); Write('+');
  for I := X1 + 1 to X2 - 1 do Write('-');
  Write('+');
  for I := Y1 + 1 to Y2 - 1 do
  begin
    GotoXY(X1, I); Write('|');
    GotoXY(X2, I); Write('|');
  end;
  GotoXY(X1, Y2); Write('+');
  for I := X1 + 1 to X2 - 1 do Write('-');
  Write('+');
end;

procedure GambarMenu(Aktif: Integer);
var
  I: Integer;
begin
  for I := 1 to JumlahMenu do
  begin
    GotoXY(30, 7 + I * 2);
    if I = Aktif then
    begin
      TextBackground(Cyan);              { pilihan aktif: latar cyan }
      TextColor(Black);
    end
    else
    begin
      TextBackground(Blue);
      TextColor(White);
    end;
    Write(' ', Menu[I], '':20 - Length(Menu[I]), ' ');
  end;
  TextBackground(Blue);
end;

procedure TampilkanIsi(Nomor: Integer);
begin
  TextColor(Yellow);
  GotoXY(10, 20);
  case Nomor of
    1: Write('SMA Negeri Pelita, berdiri tahun 1985.            ');
    2: Write('Senin-Jumat 07.30-14.00, Sabtu kegiatan ekstra.   ');
    3: Write('Ujian semester dimulai tanggal 1 Desember.        ');
  end;
end;

var
  Aktif: Integer;
  Tombol: Char;
  Selesai: Boolean;

begin
  TextBackground(Blue);
  ClrScr;
  TextColor(White);
  Kotak(25, 4, 56, 18);
  TextColor(Yellow);
  GotoXY(32, 6);
  Write('MENU UTAMA SEKOLAH');
  TextColor(LightGray);
  GotoXY(14, 23);
  Write('Panah atas/bawah: pilih    Enter: buka    Esc: keluar');

  Aktif := 1;
  Selesai := False;
  repeat
    GambarMenu(Aktif);
    Tombol := ReadKey;
    if Tombol = #0 then                  { tombol khusus: baca kodenya }
    begin
      Tombol := ReadKey;
      case Tombol of
        #72: if Aktif > 1 then Aktif := Aktif - 1    { panah atas }
             else Aktif := JumlahMenu;               { dari atas ke bawah }
        #80: if Aktif < JumlahMenu then Aktif := Aktif + 1  { panah bawah }
             else Aktif := 1;
      end;
    end
    else if Tombol = #13 then            { Enter }
    begin
      if Aktif = JumlahMenu then
        Selesai := True
      else
        TampilkanIsi(Aktif);
    end
    else if Tombol = #27 then            { Esc }
      Selesai := True;
  until Selesai;

  TextColor(LightGray);
  TextBackground(Black);
  ClrScr;
  WriteLn('Terima kasih telah memakai menu.');
end.
