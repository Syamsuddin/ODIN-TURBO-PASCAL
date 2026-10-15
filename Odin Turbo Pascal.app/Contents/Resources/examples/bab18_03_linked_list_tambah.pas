{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 18.3 - Linked list: menambah simpul
  Linked list adalah rantai simpul. Setiap simpul berisi data dan
  pointer ke simpul berikutnya; simpul terakhir menunjuk nil. Berbeda
  dengan array, panjangnya bisa bertambah selama program berjalan.
    Awal -> [5| ] -> [12| ] -> [8|nil] }

program bab18_03_linked_list_tambah;

type
  PSimpul = ^TSimpul;                    { boleh ditulis sebelum TSimpul }
  TSimpul = record
    Data: Integer;
    Berikut: PSimpul;                    { pointer ke simpul selanjutnya }
  end;

procedure TambahDepan(var Awal: PSimpul; Nilai: Integer);
var
  Baru: PSimpul;
begin
  New(Baru);
  Baru^.Data := Nilai;
  Baru^.Berikut := Awal;                 { simpul baru menunjuk awal lama }
  Awal := Baru;                          { simpul baru menjadi awal }
end;

procedure TambahBelakang(var Awal: PSimpul; Nilai: Integer);
var
  Baru, P: PSimpul;
begin
  New(Baru);
  Baru^.Data := Nilai;
  Baru^.Berikut := nil;                  { akan menjadi simpul terakhir }
  if Awal = nil then
    Awal := Baru                         { list masih kosong }
  else
  begin
    P := Awal;
    while P^.Berikut <> nil do           { jalan sampai simpul terakhir }
      P := P^.Berikut;
    P^.Berikut := Baru;
  end;
end;

procedure Tampilkan(Awal: PSimpul);
var
  P: PSimpul;
begin
  Write('Awal -> ');
  P := Awal;
  while P <> nil do
  begin
    Write(P^.Data, ' -> ');
    P := P^.Berikut;                     { pindah ke simpul berikutnya }
  end;
  WriteLn('nil');
end;

procedure HapusSemua(var Awal: PSimpul);
var
  P: PSimpul;
begin
  while Awal <> nil do
  begin
    P := Awal;
    Awal := Awal^.Berikut;               { simpan sambungan dulu }
    Dispose(P);                          { baru simpulnya dibuang }
  end;
end;

var
  Daftar: PSimpul;

begin
  Daftar := nil;                         { list kosong }
  Tampilkan(Daftar);
  TambahBelakang(Daftar, 12);
  Tampilkan(Daftar);
  TambahBelakang(Daftar, 8);
  Tampilkan(Daftar);
  TambahDepan(Daftar, 5);
  Tampilkan(Daftar);
  TambahDepan(Daftar, 1);
  Tampilkan(Daftar);
  HapusSemua(Daftar);                    { kembalikan semua memori }
  Tampilkan(Daftar);
end.
