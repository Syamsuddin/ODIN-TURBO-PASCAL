# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Blocks assembled whole by clang (gen_golden_aarch64.py) and by
# odin_asm::text, then compared word for word: prologue and epilogue, branch
# relaxation, alignment padding, literal loads and symbol addresses. Every
# non-.L label starts a block (an atom). clang does not relax branches, so a
# line ending in `//@ a || b` is given to clang as the instructions a, b: the
# relaxed form odin_asm must produce.
.text

_prologue:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str d8, [sp, #32]
    sub sp, sp, #64
    mov x19, x0
    stur w1, [x29, #-4]
    ldur w0, [x29, #-4]
    str x0, [sp, #8]
    ldr x1, [sp, #8]
    add sp, sp, #64
    ldr d8, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

_short_branches:
    mov w0, #0
.Lloop:
    add w0, w0, #1
    cmp w0, #10
    b.lt .Lloop
    cbz x1, .Ldone
    cbnz w2, .Lloop
    tbz w0, #0, .Lloop
    tbnz x3, #63, .Ldone
    b.al .Ldone
    bhs .Ldone
    b .Lloop
.Ldone:
    ret

// tbz reaches +32764 bytes: the first fits, the second is 4 bytes too far.
_tbz_forward:
    tbz w0, #1, .Lfits
    .zero 32760
.Lfits:
    tbz w0, #2, .Lfar           //@ tbnz w0, #2, .+8 || b .Lfar
    .zero 32764
.Lfar:
    ret

// ... and -32768 bytes back.
_tbz_backward:
.Lb1:
    .zero 32768
    tbz w0, #3, .Lb1
.Lb2:
    .zero 32768
    nop
    tbnz x0, #40, .Lb2          //@ tbz x0, #40, .+8 || b .Lb2
    ret

// Relaxing the second branch pushes the first one out of range.
_cascade:
    tbz w0, #0, .La             //@ tbnz w0, #0, .+8 || b .La
    tbz w0, #1, .Lb             //@ tbnz w0, #1, .+8 || b .Lb
    .zero 32756
.La:
    .zero 8
.Lb:
    ret

// b.cond and cbz/cbnz reach ±1 MiB; b.al has no inverse and becomes b.
_far_conditions:
    b.ne .Lfar                  //@ b.eq .+8 || b .Lfar
    cbz x0, .Lfar               //@ cbnz x0, .+8 || b .Lfar
    cbnz w1, .Lnear
    b.al .Lfar                  //@ b .Lfar
    b.hs .Lnear
.Lnear:
    .zero 1048576
.Lfar:
    b.lo .Lnear
    b.hi .Lnear                 //@ b.ls .+8 || b .Lnear
    ret

_aligned_loop:
    mov w1, #100
    .p2align 4
.Lloop:
    subs w1, w1, #1
    b.ne .Lloop
    .p2align 3
    ret

_literals:
    ldr d0, .Lpi
    ldr x1, .Lbig
    ldr w2, .Lbig
    ldrsw x3, .Lbig
    ldr s4, .Lbig
    adr x4, .Lpi
    adr x5, .Lbig+4
    ret
    .p2align 3
.Lpi:
    .quad 0x400921fb54442d18
.Lbig:
    .quad 0x123456789abcdef0

_symbols:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, _msg@PAGE
    add x0, x0, _msg@PAGEOFF
    adrp x8, _counter@PAGE
    ldr w9, [x8, _counter@PAGEOFF]
    add w9, w9, #1
    str w9, [x8, _counter@PAGEOFF]
    adrp x8, _table@PAGE+16
    ldr d0, [x8, _table@PAGEOFF+16]
    adrp x16, _write@GOTPAGE
    ldr x16, [x16, _write@GOTPAGEOFF]
    blr x16
    bl _helper
    ldp x29, x30, [sp], #16
    b _tail
    .p2align 3
    .quad _vtable + 16

_sample:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov x19, x0
    mov w8, #0
    mov x9, #0
.Lnext:
    ldr w10, [x19, x9, lsl #2]
    add w8, w8, w10
    add x9, x9, #1
    cmp x9, #100
    b.lo .Lnext
    scvtf d0, w8
    fmov d1, #10.0
    fdiv d0, d0, d1
    fcvtzs w0, d0
    mrs x1, fpsr
    tbnz w1, #0, .Linvalid
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
.Linvalid:
    brk #1
