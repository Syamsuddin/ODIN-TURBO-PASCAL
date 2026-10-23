{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program ClsObjectOverride;
{ override belongs to classes; a TP object overrides with virtual. }
type
  TA = object
    procedure Run; virtual;
  end;
  TB = object(TA)
    procedure Run; override;
  end;
procedure TA.Run;
begin
end;
procedure TB.Run;
begin
end;
begin
end.
