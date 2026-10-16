{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 13.3 - Record bersarang
  Field sebuah record boleh berupa record lain. Pegawai punya tanggal
  lahir (record TTanggal) dan alamat (record TAlamat). Aksesnya
  memakai titik berantai: Pegawai.Lahir.Tahun. }

program bab13_03_record_bersarang;

type
  TTanggal = record
    Hari, Bulan, Tahun: Integer;
  end;

  TAlamat = record
    Jalan: string[40];
    Kota: string[20];
    KodePos: string[5];
  end;

  TPegawai = record
    Nama: string[30];
    Lahir: TTanggal;                     { record di dalam record }
    Alamat: TAlamat;
    Gaji: LongInt;
  end;

const
  TahunIni = 2026;

var
  Pegawai: TPegawai;

begin
  Pegawai.Nama := 'Rina Maharani';
  Pegawai.Lahir.Hari := 17;              { titik berantai }
  Pegawai.Lahir.Bulan := 8;
  Pegawai.Lahir.Tahun := 1995;

  with Pegawai.Alamat do                 { with untuk record bagian dalam }
  begin
    Jalan := 'Jl. Pangeran Antasari No. 12';
    Kota := 'Kandangan';
    KodePos := '71211';
  end;
  Pegawai.Gaji := 4750000;

  with Pegawai do
  begin
    WriteLn('Nama      : ', Nama);
    WriteLn('Lahir     : ', Lahir.Hari, '-', Lahir.Bulan, '-', Lahir.Tahun);
    WriteLn('Umur      : sekitar ', TahunIni - Lahir.Tahun, ' tahun');
    WriteLn('Alamat    : ', Alamat.Jalan);
    WriteLn('            ', Alamat.Kota, ' ', Alamat.KodePos);
    WriteLn('Gaji      : Rp ', Gaji);
  end;
end.
