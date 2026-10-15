// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! x86-64 machine-code encoder.
//!
//! [`Assembler`] collects the code of one atom (usually one function):
//! instructions are methods named after their Intel mnemonic, taking the
//! destination first; jumps go to [`Label`]s, which are bound later; and
//! [`Assembler::finish`] relaxes branches and returns a [`Code`] with the
//! final bytes, the relocations against named symbols, and the offset of
//! every label. [`Code::into_atom`] turns that into an [`Atom`](crate::Atom).
//!
//! # Operands
//!
//! * [`Reg`] names one of the 16 general-purpose registers; the access width
//!   is the [`Width`] argument of the instruction, so `(W32, Reg::R8)` is
//!   `r8d`. 8-bit `spl`/`bpl`/`sil`/`dil` get their REX prefix
//!   automatically; `ah`..`bh` are never produced.
//! * [`Xmm`] names an SSE register.
//! * [`Mem`] is `[base + index*scale + disp]` or RIP-relative to a symbol
//!   ([`RelocKind::X86Pc32`](crate::RelocKind::X86Pc32)), a symbol's GOT
//!   slot ([`RelocKind::X86GotPc32`](crate::RelocKind::X86GotPc32)) or a
//!   local [`Label`].
//! * Immediates are plain integers (`i32` by default, `i64` for wider
//!   values).
//!
//! All of these convert into [`Operand`], which most instructions accept. An
//! operand combination the instruction does not have (say, memory to memory)
//! or an immediate out of range does not panic: the [`Assembler`] keeps the
//! first [`EncodeError`] and [`finish`](Assembler::finish) returns it.
//!
//! # Instructions
//!
//! Families with a shared encoding have one method taking an op enum plus a
//! method per mnemonic: [`alu`](Assembler::alu) ([`AluOp`]: `add` `or` `adc`
//! `sbb` `and` `sub` `xor` `cmp`), [`unary`](Assembler::unary) ([`UnaryOp`]:
//! `not` `neg` `mul` `imul1` `div` `idiv` `inc` `dec`),
//! [`shift`](Assembler::shift) ([`ShiftOp`]), [`bit`](Assembler::bit)
//! ([`BitOp`]), [`fp_arith`](Assembler::fp_arith) ([`FpOp`] × [`Fp`]: `addsd`
//! .. `maxss`), [`fp_logic`](Assembler::fp_logic) ([`FpLogic`]: `andpd` ..
//! `xorps`), [`fp_compare`](Assembler::fp_compare), [`cvtsi2fp`](Assembler::cvtsi2fp),
//! [`cvtfp2si`](Assembler::cvtfp2si) and [`fp_round`](Assembler::fp_round).
//! The one-operand signed multiply is `imul1`, since `imul` is the
//! two-operand form.
//!
//! Branches take a [`Target`]: a [`Label`], a symbol name (`&str`), or a
//! register or [`Mem`] for indirect `call`/`jmp`. `jmp`/`jcc` to labels are
//! relaxed by [`finish`](Assembler::finish); `call` is always rel32.
//!
//! # Relocation addends
//!
//! A RIP-relative field is relative to the end of the instruction, which may
//! carry an immediate after the field. The encoder folds this into the
//! addend: `[rip + sym + a]` gives `addend = a - 4 - imm_len`, so
//! `cmp byte ptr [rip + sym], 1` has addend -5 and `call sym` has -4.

mod assembler;
mod insts;
mod operand;

pub use assembler::{Assembler, Code, EncodeError};
pub use operand::{
    AluOp, BitOp, Cond, Fp, FpLogic, FpOp, Label, Mem, Operand, Reg, ShiftOp, Target, UnaryOp, Width, Xmm, round,
};
