{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Overlay: semua kode sudah di memori, jadi hanya antarmukanya yang ada. }
program OVERLAY_STUB;

{$F+,O+}

uses Overlay;

{$O Overlay}

begin
  WriteLn('konstanta: ', ovrOk, ' ', ovrError, ' ', ovrNotFound, ' ', ovrNoMemory, ' ', ovrIOError, ' ', ovrNoEMSDriver,
    ' ', ovrNoEMSMemory);
  OvrInit('OVERLAY_STUB.OVR');
  WriteLn('OvrInit: ', OvrResult);
  OvrInitEMS;
  WriteLn('OvrInitEMS: ', OvrResult);
  WriteLn('OvrGetBuf: ', OvrGetBuf);
  OvrSetBuf(100000);
  WriteLn('OvrSetBuf: ', OvrResult, ' ', OvrGetBuf);
  OvrSetBuf(-1);
  WriteLn('OvrSetBuf(-1): ', OvrResult, ' ', OvrGetBuf);
  OvrSetRetry(4096);
  WriteLn('OvrGetRetry: ', OvrGetRetry);
  OvrClearBuf;
  WriteLn('OvrClearBuf: ', OvrResult);
  WriteLn('Pencacah: ', OvrTrapCount, ' ', OvrLoadCount);
end.
