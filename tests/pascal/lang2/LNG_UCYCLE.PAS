{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
program LngUCycle;
{ Units that reach each other through implementation uses (TP allows it;
  only interface uses must not form a cycle). Turbo Vision's Dialogs,
  Validate, MsgBox and App have this shape. }
uses UCycA;
begin
  A(9);
  WriteLn;
end.
