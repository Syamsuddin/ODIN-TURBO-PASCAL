# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Assembly shims of the Odin RTL for x86-64 Linux (glibc). Declared in Pascal as
#   function ODIN_RETADDR: Pointer; external 'odinrtl' name 'ODIN_RETADDR';
# The routines shared with macOS are identical to x86_64-darwin.s; this file
# adds the process entry point and what glibc reaches differently.
.intel_syntax noprefix
.text

# Process entry, as in glibc's start.S: the kernel leaves argc, argv and envp
# on the stack and the dynamic linker passes its finalizer in rdx.
# __libc_start_main initialises libc, calls main(argc, argv, envp) (the
# code generator's entry stub) and exits with its result.
.keep _start
_start:
    xor ebp, ebp
    mov r9, rdx
    pop rsi
    mov rdx, rsp
    and rsp, -16
    push rax
    push rsp
    xor r8d, r8d
    xor ecx, ecx
    lea rdi, [rip + main]
    call qword ptr [rip + __libc_start_main@GOTPCREL]
    ud2

# Address the executable was loaded at (its ELF header), for the runtime
# error report the IDE maps back to a source line. The linker defines
# __ehdr_start, as GNU ld does.
ODIN_IMAGEBASE:
    lea rax, [rip + __ehdr_start]
    ret

# Address of glibc's `environ`, the same char*** that macOS's _NSGetEnviron
# returns, so the Dos unit reads the environment one way on both systems.
ODIN_NSGETENVIRON:
    mov rax, qword ptr [rip + environ@GOTPCREL]
    ret

# Return address of the Pascal routine that calls this shim. Every routine
# compiled by Odin keeps a frame pointer, and the shim sets up no frame, so
# [rbp + 8] is that routine's return address: the user code that raised a
# runtime error.
ODIN_RETADDR:
    mov rax, qword ptr [rbp + 8]
    ret

# Loads the SSE control/status register from the first argument (edi).
ODIN_SETMXCSR:
    mov dword ptr [rsp - 4], edi
    ldmxcsr dword ptr [rsp - 4]
    ret

# Frame pointer of the routine that called the Pascal routine calling this
# shim (the shim sets up no frame, so [rbp] is that caller's rbp). With it,
# TCollection.ForEach calls a procedure nested in its caller.
ODIN_CALLERFRAME:
    mov rax, qword ptr [rbp]
    ret

# Calls code at rdi with argument rdx and static link rsi (in r10), as a
# nested routine expects; also fine for routines that are not nested.
ODIN_CALLLOCAL:
    mov r10, rsi
    mov rax, rdi
    mov rdi, rdx
    jmp rax

# Like ODIN_CALLLOCAL with five arguments (rdx, rcx, r8, r9 and the first
# stack slot): the callbacks of TOutlineViewer.FirstThat and ForEach.
ODIN_CALLLOCAL5:
    mov r10, rsi
    mov rax, rdi
    mov rdi, rdx
    mov rsi, rcx
    mov rdx, r8
    mov rcx, r9
    mov r8, qword ptr [rsp + 8]
    jmp rax

.import __libc_start_main, "libc"
.import environ, "libc"
