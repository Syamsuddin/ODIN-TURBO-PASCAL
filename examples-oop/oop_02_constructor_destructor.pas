{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ OOP 2 - Constructor dan destructor
  Constructor menyiapkan objek baru (memberi nilai awal), destructor
  membereskannya sebelum memorinya dibuang. Destructor class selalu
  bernama Destroy dan ditandai override; Free memanggilnya, dan Free
  aman dipanggil untuk rujukan nil. }

program oop_02_constructor_destructor;

type
  TLampu = class
    Ruang: String;
    Menyala: Boolean;
    constructor Create(const ARuang: String);
    destructor Destroy; override;
    procedure Tekan;
  end;

constructor TLampu.Create(const ARuang: String);
begin
  inherited Create;                      { biasakan memanggil induknya dulu }
  Ruang := ARuang;
  Menyala := False;
  WriteLn('Lampu ', Ruang, ' dipasang.');
end;

destructor TLampu.Destroy;
begin
  if Menyala then
    WriteLn('Lampu ', Ruang, ' dimatikan dulu.');
  WriteLn('Lampu ', Ruang, ' dilepas.');
  inherited Destroy;                     { induk membereskan bagiannya }
end;

procedure TLampu.Tekan;
begin
  Menyala := not Menyala;
  if Menyala then
    WriteLn('Lampu ', Ruang, ': NYALA')
  else
    WriteLn('Lampu ', Ruang, ': padam');
end;

var
  Tamu, Dapur: TLampu;

begin
  Tamu := TLampu.Create('ruang tamu');
  Dapur := TLampu.Create('dapur');
  Tamu.Tekan;
  Dapur.Tekan;
  Dapur.Tekan;
  Tamu.Free;                             { memanggil Destroy }
  Dapur.Free;
  Tamu := nil;
  Tamu.Free;                             { nil: tidak terjadi apa-apa }
  WriteLn('Selesai.');
end.
