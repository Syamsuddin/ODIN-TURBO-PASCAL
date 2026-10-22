{ Dipakai di hampir semua baris contoh OTP-AI: operasi unit AI mengembalikan
  Boolean, dan Need menghentikan program dengan pesan jelas jika operasi itu
  gagal, daripada melanjutkan dengan hasil yang tidak boleh dipakai. }
procedure Need(OK: Boolean);
begin
  if not OK then begin
    WriteLn('GAGAL [',AIErrorCode,']: ',AIError); Halt(1)
  end
end;

{ Dipakai DataPath di bawah untuk memeriksa folder mana yang berisi DATA. }
function FileExists(Name: TFileName): Boolean;
var F: Text;
begin
  Assign(F,Name);
  {$I-} Reset(F); {$I+}
  if IOResult=0 then begin Close(F); FileExists:=True end
  else FileExists:=False
end;

{ Mencari DATA di folder kerja (otp-AI), lalu di folder induk bila program
  dijalankan dari EXAMPLES, seperti yang dilakukan IDE. }
function DataPath(Name: TFileName): TFileName;
var Sep: string; P: TFileName;
begin
  {$IFDEF FPC} Sep := '/';
  {$ELSE}
    {$IFDEF UNIX} Sep := '/';
    {$ELSE} Sep := '\'; {$ENDIF}
  {$ENDIF}
  P := 'DATA'+Sep+Name;
  if not FileExists(P) then P := '..'+Sep+'DATA'+Sep+Name;
  DataPath := P
end;
