// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//
// Assembly shims of the Odin RTL for aarch64 Linux (glibc). Declared in
// Pascal as
//   function ODIN_RETADDR: Pointer; external 'odinrtl' name 'ODIN_RETADDR';
// The routines shared with macOS are identical to aarch64-darwin.s; this file
// adds the process entry point and what glibc reaches differently.
.text

// Process entry, as in glibc's start.S: the kernel leaves argc, argv and
// envp on the stack and the dynamic linker passes its finalizer in x0.
// __libc_start_main initialises libc, calls main(argc, argv, envp) (the code
// generator's entry stub) and exits with its result.
.keep _start
_start:
    mov x29, #0
    mov x30, #0
    mov x5, x0
    ldr x1, [sp]
    add x2, sp, #8
    mov x6, sp
    adrp x0, main
    add x0, x0, :lo12:main
    mov x3, #0
    mov x4, #0
    adrp x16, :got:__libc_start_main
    ldr x16, [x16, :got_lo12:__libc_start_main]
    blr x16
    udf #0

// Address the executable was loaded at (its ELF header), for the runtime
// error report the IDE maps back to a source line. The linker defines
// __ehdr_start, as GNU ld does.
ODIN_IMAGEBASE:
    adrp x0, __ehdr_start
    add x0, x0, :lo12:__ehdr_start
    ret

// Address of glibc's `environ`, the same char*** that macOS's _NSGetEnviron
// returns, so the Dos unit reads the environment one way on both systems.
ODIN_NSGETENVIRON:
    adrp x0, :got:environ
    ldr x0, [x0, :got_lo12:environ]
    ret

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

.import __libc_start_main, "libc"
.import environ, "libc"
