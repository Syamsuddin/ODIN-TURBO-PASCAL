# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Blocks assembled whole by clang (gen_golden.py) and by odin_asm::text, then
# compared byte for byte: branch relaxation, alignment padding and
# RIP-relative label fixups. Every non-.L label starts a block (an atom).
.intel_syntax noprefix
.text

_short_jumps:
    xor eax, eax
.Lloop:
    inc eax
    cmp eax, 10
    jl .Lloop
    je .Ldone
    jmp .Lloop
.Ldone:
    ret

_near_jumps:
    test edi, edi
    je .Lfar
    jmp .Lfar
    .zero 200
.Lfar:
    ret

# Backward: -128 still fits in rel8, -129 does not.
_backward_boundary:
.Lb128:
    .zero 126
    jmp .Lb128
.Lb129:
    .zero 127
    jmp .Lb129
    ret

# Forward: +127 fits in rel8, +128 does not.
_forward_boundary:
    jmp .Lf127
    .zero 127
.Lf127:
    jmp .Lf128
    .zero 128
.Lf128:
    ret

# The jmp fits in rel8 only while the je stays short; the je must grow.
_cascade:
    jmp .La
    je .Lb
    .zero 122
.La:
    .zero 10
.Lb:
    ret

# Growth propagates backwards over three passes: J3 is too far, which pushes
# J2 out of range, and both push J1 out of range.
_cascade_chain:
    jmp .Lt1
    jmp .Lt2
    jmp .Lt3
    .zero 122
.Lt1:
    .zero 2
.Lt2:
    .zero 6
.Lt3:
    ret

_aligned_loop:
    mov ecx, 100
    .p2align 4
.Lhead:
    dec ecx
    jne .Lhead
    .p2align 3
    ret

# Alignment padding between a jump and its target.
_align_relax:
    jmp .Lafter
    .zero 100
    .p2align 5
    .zero 20
.Lafter:
    jmp .Lafter2
    .p2align 6
.Lafter2:
    ret

_rip_labels:
    lea rax, [rip + .Ltable]
    mov ecx, dword ptr [rip + .Ltable + 4]
    cmp byte ptr [rip + .Ltable], 1
    mov dword ptr [rip + .Ltable + 8], 0x12345
    movsd xmm0, qword ptr [rip + .Lconst]
    jmp .Lend
    .p2align 3
.Lconst:
    .quad 0x3ff0000000000000
.Ltable:
    .long 1, 2, 3
.Lend:
    ret

_calls:
    push rbp
    mov rbp, rsp
    call .Lhelper
    call _external
    call qword ptr [rip + _write@GOTPCREL]
    lea rdi, [rip + _message]
    mov rax, qword ptr [rip + _counter@GOTPCREL]
    cmp qword ptr [rip + _counter + 8], 1
    pop rbp
    jmp _external
.Lhelper:
    ret

# Typical naive code generator output.
_sample:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword ptr [rbp - 8], rdi
    mov dword ptr [rbp - 12], 0
.Lcond:
    mov eax, dword ptr [rbp - 12]
    cmp eax, 10
    jge .Lexit
    movsxd rax, dword ptr [rbp - 12]
    mov rcx, qword ptr [rbp - 8]
    mov byte ptr [rcx + rax], 32
    inc dword ptr [rbp - 12]
    jmp .Lcond
.Lexit:
    cvtsi2sd xmm0, dword ptr [rbp - 12]
    mulsd xmm0, qword ptr [rip + _scale]
    cvttsd2si eax, xmm0
    add rsp, 32
    pop rbp
    ret
