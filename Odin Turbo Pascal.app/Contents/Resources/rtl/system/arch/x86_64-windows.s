# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Assembly shims of the Odin RTL for x86-64 Windows (Win64 convention:
# arguments in rcx, rdx, r8, r9, 32 bytes of shadow space above the return
# address, rsi/rdi/rbx/rbp/r12-r15 preserved). Declared in Pascal as
#   function ODIN_RETADDR: Pointer; external 'odinrtl' name 'ODIN_RETADDR';
.intel_syntax noprefix
.text

# Process entry. The UCRT is already initialised by its DLL entry point; it
# still has to split the command line and build the environment before
# main(argc, argv) (the code generator's entry stub) can run.
.keep mainCRTStartup
mainCRTStartup:
    push rbx
    sub rsp, 32
    mov ecx, 1                          # _crt_argv_unexpanded_arguments
    call qword ptr [rip + _configure_narrow_argv@GOTPCREL]
    call qword ptr [rip + _initialize_narrow_environment@GOTPCREL]
    call qword ptr [rip + __p___argc@GOTPCREL]
    mov ebx, dword ptr [rax]
    call qword ptr [rip + __p___argv@GOTPCREL]
    mov rdx, qword ptr [rax]
    mov ecx, ebx
    call main
    ud2

# Return address of the Pascal routine that calls this shim. Every routine
# compiled by Odin keeps a frame pointer, and the shim sets up no frame, so
# [rbp + 8] is that routine's return address: the user code that raised a
# runtime error.
ODIN_RETADDR:
    mov rax, qword ptr [rbp + 8]
    ret

# Loads the SSE control/status register from the first argument (ecx),
# through the caller's shadow space.
ODIN_SETMXCSR:
    mov dword ptr [rsp + 8], ecx
    ldmxcsr dword ptr [rsp + 8]
    ret

# Frame pointer of the routine that called the Pascal routine calling this
# shim (the shim sets up no frame, so [rbp] is that caller's rbp). With it,
# TCollection.ForEach calls a procedure nested in its caller.
ODIN_CALLERFRAME:
    mov rax, qword ptr [rbp]
    ret

# Calls code at rcx with argument r8 and static link rdx (in r10), as a
# nested routine expects; also fine for routines that are not nested. The
# jump reuses the caller's shadow space.
ODIN_CALLLOCAL:
    mov r10, rdx
    mov rax, rcx
    mov rcx, r8
    jmp rax

# Like ODIN_CALLLOCAL with five arguments (r8, r9 and the stack slots of
# arguments 5..7): the callbacks of TOutlineViewer.FirstThat and ForEach.
ODIN_CALLLOCAL5:
    mov r10, rdx
    mov rax, rcx
    mov rcx, r8
    mov rdx, r9
    mov r8, qword ptr [rsp + 40]
    mov r9, qword ptr [rsp + 48]
    mov r11, qword ptr [rsp + 56]
    mov qword ptr [rsp + 40], r11
    jmp rax

# Stack probe called by every prologue with the frame size in rax: Windows
# commits stack only through the guard page below it, so the pages of a new
# frame are touched in order, as MSVC's __chkstk does. Keeps every register
# but rax, r11 and the flags (the arguments and the static link in r10 are
# still live).
ODIN_CHKSTK:
    push rcx
    push rax
    lea rcx, [rsp + 24]
    cmp rax, 4096
    jb .Llast
.Lpage:
    sub rcx, 4096
    test qword ptr [rcx], rcx
    sub rax, 4096
    cmp rax, 4096
    jae .Lpage
.Llast:
    sub rcx, rax
    test qword ptr [rcx], rcx
    pop rax
    pop rcx
    ret

# Address the executable was loaded at (its DOS header), for the runtime
# error report the IDE maps back to a source line. The linker defines
# __ImageBase, as MSVC's does.
ODIN_IMAGEBASE:
    lea rax, [rip + __ImageBase]
    ret

# Address of the UCRT's `environ`, the same char*** that macOS's
# _NSGetEnviron returns, so the Dos unit reads the environment one way
# everywhere.
ODIN_NSGETENVIRON:
    sub rsp, 40
    call qword ptr [rip + __p__environ@GOTPCREL]
    add rsp, 40
    ret

.import _configure_narrow_argv, "ucrtbase.dll"
.import _initialize_narrow_environment, "ucrtbase.dll"
.import __p___argc, "ucrtbase.dll"
.import __p___argv, "ucrtbase.dll"
.import __p__environ, "ucrtbase.dll"
