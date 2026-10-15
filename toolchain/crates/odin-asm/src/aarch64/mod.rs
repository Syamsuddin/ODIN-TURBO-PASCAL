// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! AArch64 machine-code encoder, for `aarch64-darwin` (Apple silicon) and
//! `aarch64-linux`.
//!
//! [`Assembler`] collects the code of one atom (usually one function):
//! instructions are methods named after their mnemonic, taking the
//! destination first; branches go to [`Label`]s, which are bound later; and
//! [`Assembler::finish`] relaxes branches and returns a [`Code`] with the
//! final bytes, the relocations against named symbols, and the offset of
//! every label. [`Code::into_atom`] turns that into an [`Atom`](crate::Atom).
//!
//! # Operands
//!
//! * [`Reg`] is a general-purpose register *with* its width, as in assembly
//!   syntax: [`regs::X0`] and [`regs::W0`] are the 64- and 32-bit views of
//!   register 0 ([`Reg::to_w`], [`Reg::to_x`] convert). The width of an
//!   instruction comes from its registers, which must agree except where
//!   the instruction mixes them (`sxtw x0, w1`, `add x0, x1, w2, sxtw`,
//!   `scvtf d0, w1`, ...).
//! * The stack pointer ([`regs::SP`]) and the zero register
//!   ([`regs::XZR`]) are distinct values even though both encode as 31.
//!   Each instruction knows which of the two each of its fields means:
//!   `add(X0, SP, X1)` switches to the extended-register form, `mov(X0,
//!   SP)` becomes `add x0, sp, #0`, and `XZR` in an `sp` field (or `SP` in
//!   a zero-register field) is an error, so neither can be encoded by
//!   mistake as the other.
//! * [`VReg`] is a scalar view of a SIMD&FP register: [`regs::S0`]..`S31`
//!   (single) and [`regs::D0`]..`D31` (double). [`AnyReg`] accepts either
//!   kind where an instruction does (`ldr`, `str`, `ldp`, `stp`, `fmov`).
//! * [`Op2`] is the flexible second operand of `add`, `sub`, `and`, `cmp`,
//!   `mov`, ...: an integer, a register, or a shifted or extended register
//!   built with [`Reg::lsl`], [`Reg::sxtw`] and friends: `a.add(X0, X1,
//!   X2.lsl(3))`.
//! * [`Mem`] is an addressing mode: `[base, #offset]`, pre/post-index,
//!   register offset, `sym@PAGEOFF`, a GOT slot, a whole symbol, or a
//!   literal at a label.
//! * [`Cond`] is a condition code; [`Cond::invert`] gives the opposite.
//!
//! An operand combination the instruction does not have, or an immediate
//! that does not fit, does not panic: the [`Assembler`] keeps the first
//! [`EncodeError`] and [`finish`](Assembler::finish) returns it, after
//! rolling back the failed instruction.
//!
//! # Instructions
//!
//! Integer: `add` `adds` `sub` `subs` `cmp` `cmn` `neg` `negs`; logical
//! `and` `orr` `eor` `ands` `bic` `orn` `eon` `bics` `tst` `mvn` (all
//! through [`logical`](Assembler::logical) with a [`LogicOp`]); `mov`,
//! `movz` `movn` `movk`; `mul` `madd` `msub` `mneg` `smulh` `umulh` `smull`
//! `umull` `smaddl` `umaddl` `sdiv` `udiv`; `lsl` `lsr` `asr` `ror` (immediate
//! or register); `sxtb` `sxth` `sxtw` `uxtb` `uxth` `ubfx` `sbfx` `ubfiz`
//! `sbfiz` `bfi` `bfxil` `ubfm` `sbfm` `bfm` `extr`; `csel` `csinc` `csinv`
//! `csneg` `cset` `csetm` `cinc` `cinv` `cneg` `ccmp` `ccmn`; `clz` `cls`
//! `rbit` `rev`.
//!
//! Memory: `ldr` `str` (W, X, S, D), `ldrb` `strb` `ldrh` `strh` `ldrsb`
//! `ldrsh` `ldrsw`, the unscaled `ldur*`/`stur*`, and `ldp`/`stp` (W, X, S,
//! D pairs).
//!
//! Branches: [`b`](Assembler::b) and [`bl`](Assembler::bl) to a label or a
//! symbol ([`Target`]), [`b_cond`](Assembler::b_cond), `cbz` `cbnz` `tbz`
//! `tbnz` to labels, `br` `blr` `ret`.
//!
//! Floating point: `fmov` (register, general register ↔ FP, and
//! [`fmov_imm`](Assembler::fmov_imm)), `fadd` `fsub` `fmul` `fdiv` `fnmul`
//! `fmin` `fmax` `fminnm` `fmaxnm`, `fneg` `fabs` `fsqrt`, `fcmp` `fcmpe`
//! (and `_zero` forms), `fcsel`, `fcvt`, `scvtf` `ucvtf`,
//! [`fcvt_int`](Assembler::fcvt_int) with mnemonic shortcuts `fcvtzs`
//! `fcvtzu` `fcvtms` `fcvtps` `fcvtns` `fcvtas`, and
//! [`frint`](Assembler::frint) (`frintn` `frintm` `frintp` `frintz`
//! `frinta`, plus `frintx` `frinti`).
//!
//! System: `nop` `brk` `udf` `svc` `dmb ish` `dsb ish` `isb`, `mrs`/`msr`
//! for NZCV, FPCR and FPSR ([`SysReg`]).
//!
//! Data: [`bytes`](Assembler::bytes), [`word`](Assembler::word),
//! [`abs64`](Assembler::abs64) (`.quad sym + addend`,
//! [`RelocKind::Abs64`](crate::RelocKind::Abs64)),
//! [`diff32`](Assembler::diff32) (jump tables) and
//! [`align`](Assembler::align) (padded with `nop`).
//!
//! # Helpers that expand to several instructions
//!
//! Every instruction method emits exactly one instruction, except these:
//!
//! | Method | Expansion |
//! | --- | --- |
//! | [`mov_imm`](Assembler::mov_imm) | 1–4 of `movz`/`movn`/`movk`/`orr` |
//! | [`add_const`](Assembler::add_const) | `add`/`sub`; two for 24-bit values; else `mov_imm` scratch + `add` |
//! | [`cmp_const`](Assembler::cmp_const) | `cmp`/`cmn`; else `mov_imm` scratch + `cmp` |
//! | [`logical_const`](Assembler::logical_const) | the instruction; else `mov_imm` scratch + the instruction |
//! | loads/stores with [`Mem::Offset`] out of range | `mov_imm` scratch + register-offset access |
//! | `ldp`/`stp` with [`Mem::Offset`] out of range | `add_const` scratch + pair access |
//! | loads/stores with [`Mem::Sym`] | `adrp` scratch + access through `sym@PAGEOFF` |
//! | [`load_address`](Assembler::load_address) | `adrp` + `add` |
//! | [`load_got`](Assembler::load_got) | `adrp` + `ldr` of the GOT slot |
//! | [`call_got`](Assembler::call_got) | `load_got(x16)` + `blr x16` |
//! | `b_cond` `cbz` `cbnz` `tbz` `tbnz` out of range | inverted branch over a `b` (by `finish`) |
//!
//! # Scratch registers and reserved registers
//!
//! * **X16 and X17** (IP0, IP1) are the encoder's scratch registers. The
//!   helpers above use X16, or X17 when X16 is one of the instruction's own
//!   operands (an address base, a register being stored); `call_got`
//!   always clobbers X16. The code generator must never allocate them or
//!   expect them to survive any instruction that may expand. (The AAPCS64
//!   also lets linker veneers clobber them across calls.)
//! * **X18** is the platform register on Apple systems: the OS may change it
//!   at any time, so code must never use it. The encoder accepts it only so
//!   hand-written assembly can name it.
//! * X29 is the frame pointer and X30 the link register; Apple requires a
//!   valid frame chain in X29.
//!
//! # Branches and relaxation
//!
//! `b_cond`, `cbz`/`cbnz` (±1 MiB) and `tbz`/`tbnz` (±32 KiB) to labels
//! start as one instruction; [`finish`](Assembler::finish) turns any whose
//! label ends up out of range into the inverted branch over a `b` (8 bytes),
//! repeating until the layout is stable. Labels bound after such a branch
//! move accordingly, so offsets are only known from [`Code`]. `b`/`bl` to
//! labels reach ±128 MiB and are never relaxed; `adr` and literal loads
//! reach ±1 MiB and are an error beyond. Conditional branches to symbols do
//! not exist (no relocation kind); branch to a local label and `b` from
//! there.
//!
//! # Relocations
//!
//! Relocated fields are left zero; the linker fills them in.
//! `adrp`/`add`/`ldr` pairs for `sym + addend` carry the same addend in both
//! relocations ([`Arm64Page21`](crate::RelocKind::Arm64Page21) and
//! [`Arm64PageOff12`](crate::RelocKind::Arm64PageOff12)). A `PageOff12` on
//! a load or store is scaled by the access size, so the target address must
//! be aligned to it.

mod assembler;
mod imm;
mod insts;
mod operand;

pub use assembler::{Assembler, Code, EncodeError};
pub use imm::{fp_imm8, logical_imm};
pub use insts::offset_is_direct;
pub use operand::{
    AnyReg, Cond, Extend, Fp, IndexExt, Label, LogicOp, Mem, Op2, Reg, Round, Shift, SysReg, Target, VReg, regs,
};
