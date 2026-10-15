# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Assembly shims of the Odin RTL for x86-64 macOS. Declared in Pascal as
#   function ODIN_RETADDR: Pointer; external 'odinrtl' name 'ODIN_RETADDR';
.intel_syntax noprefix
.text

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
