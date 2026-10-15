{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 18.4 - Linked list: menghapus simpul
  Untuk membuang simpul, sambungkan simpul SEBELUMNYA langsung ke
  simpul SESUDAHNYA, lalu Dispose simpul itu. Simpul pertama
  ditangani khusus karena tidak punya simpul sebelumnya. }

program bab18_04_linked_list_hapus;

type
  PSimpul = ^TSimpul;
  TSimpul = record
    Data: Integer;
    Berikut: PSimpul;
  end;

procedure TambahBelakang(var Awal: PSimpul; Nilai: Integer);
var
  Baru, P: PSimpul;
begin
  New(Baru);
  Baru^.Data := Nilai;
  Baru^.Berikut := nil;
  if Awal = nil then
    Awal := Baru
  else
  begin
    P := Awal;
    while P^.Berikut <> nil do
      P := P^.Berikut;
    P^.Berikut := Baru;
  end;
end;

procedure Tampilkan(Awal: PSimpul);
begin
  Write('  ');
  while Awal <> nil do                   { Awal di sini hanya salinan }
  begin
    Write(Awal^.Data, ' -> ');
    Awal := Awal^.Berikut;
  end;
  WriteLn('nil');
end;

{ Menghapus simpul pertama yang berisi Nilai; False bila tidak ada }
function Hapus(var Awal: PSimpul; Nilai: Integer): Boolean;
var
  Sebelum, P: PSimpul;
begin
  Sebelum := nil;
  P := Awal;
  while (P <> nil) and (P^.Data <> Nilai) do
  begin
    Sebelum := P;                        { ingat simpul sebelumnya }
    P := P^.Berikut;
  end;

  if P = nil then
    Hapus := False                       { tidak ditemukan }
  else
  begin
    if Sebelum = nil then
      Awal := P^.Berikut                 { yang dihapus simpul pertama }
    else
      Sebelum^.Berikut := P^.Berikut;    { lompati simpul P }
    Dispose(P);
    Hapus := True;
  end;
end;

procedure Coba(var Awal: PSimpul; Nilai: Integer);
begin
  if Hapus(Awal, Nilai) then
    WriteLn('Hapus ', Nilai, ':')
  else
    WriteLn('Hapus ', Nilai, ': tidak ditemukan');
  Tampilkan(Awal);
end;

var
  Daftar: PSimpul;
  I: Integer;

begin
  Daftar := nil;
  for I := 1 to 5 do
    TambahBelakang(Daftar, I * 10);
  WriteLn('List awal:');
  Tampilkan(Daftar);

  Coba(Daftar, 30);                      { simpul di tengah }
  Coba(Daftar, 10);                      { simpul pertama }
  Coba(Daftar, 50);                      { simpul terakhir }
  Coba(Daftar, 99);                      { tidak ada }
  Coba(Daftar, 20);
  Coba(Daftar, 40);                      { list menjadi kosong }
end.
