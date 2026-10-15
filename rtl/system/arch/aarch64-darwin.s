// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//
// Assembly shims of the Odin RTL for arm64 macOS (Apple silicon). Declared
// in Pascal as
//   function ODIN_RETADDR: Pointer; external 'odinrtl' name 'ODIN_RETADDR';
// x16/x17 are scratch registers, x18 is never touched (platform register).
.text

// Return address of the Pascal routine that calls this shim. Every routine
// compiled by Odin keeps a frame record (x29 = saved x29, x30 above it) and
// the shim sets up none, so [x29 + 8] is that routine's return address: the
// user code that raised a runtime error.
ODIN_RETADDR:
    ldr x0, [x29, #8]
    ret

// Frame pointer of the routine that called the Pascal routine calling this
// shim (the shim sets up no frame, so [x29] is that caller's x29). With it,
// TCollection.ForEach calls a procedure nested in its caller.
ODIN_CALLERFRAME:
    ldr x0, [x29]
    ret

// Calls code at x0 with argument x2 and static link x1 (in x15), as a nested
// routine expects; also fine for routines that are not nested.
ODIN_CALLLOCAL:
    mov x15, x1
    mov x9, x0
    mov x0, x2
    br x9

// Like ODIN_CALLLOCAL with five arguments (x2..x6): the callbacks of
// TOutlineViewer.FirstThat and ForEach.
ODIN_CALLLOCAL5:
    mov x15, x1
    mov x9, x0
    mov x0, x2
    mov x1, x3
    mov x2, x4
    mov x3, x5
    mov x4, x6
    br x9
