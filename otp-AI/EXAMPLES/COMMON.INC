procedure Need(OK: Boolean);
begin
  if not OK then begin
    WriteLn('GAGAL [',AIErrorCode,']: ',AIError); Halt(1)
  end
end;

function DataPath(Name: TFileName): TFileName;
begin
  {$IFDEF FPC} DataPath := 'DATA/'+Name;
  {$ELSE}
    {$IFDEF UNIX} DataPath := 'DATA/'+Name;
    {$ELSE} DataPath := 'DATA\'+Name; {$ENDIF}
  {$ENDIF}
end;
