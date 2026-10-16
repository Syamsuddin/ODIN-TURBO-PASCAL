{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Bab 12.4 - Menghitung vokal
  Setiap karakter diperiksa satu per satu, lalu dihitung menurut
  jenisnya: vokal, konsonan, angka, spasi, atau lainnya. }

program bab12_04_hitung_vokal;

var
  Kalimat: string;
  I: Integer;
  C: Char;
  Vokal, Konsonan, Angka, Spasi, Lainnya: Integer;

begin
  Write('Ketik sebuah kalimat: ');
  ReadLn(Kalimat);

  Vokal := 0; Konsonan := 0; Angka := 0; Spasi := 0; Lainnya := 0;
  for I := 1 to Length(Kalimat) do
  begin
    C := UpCase(Kalimat[I]);             { cukup periksa huruf besar }
    case C of
      'A', 'I', 'U', 'E', 'O':
        Vokal := Vokal + 1;
      'B'..'D', 'F'..'H', 'J'..'N', 'P'..'T', 'V'..'Z':
        Konsonan := Konsonan + 1;
      '0'..'9':
        Angka := Angka + 1;
      ' ':
        Spasi := Spasi + 1;
    else
      Lainnya := Lainnya + 1;            { tanda baca dan simbol }
    end;
  end;

  WriteLn('Panjang  : ', Length(Kalimat));
  WriteLn('Vokal    : ', Vokal);
  WriteLn('Konsonan : ', Konsonan);
  WriteLn('Angka    : ', Angka);
  WriteLn('Spasi    : ', Spasi);
  WriteLn('Lainnya  : ', Lainnya);
end.
