// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Instruction methods of [`Assembler`].
//!
//! Encodings follow the Arm Architecture Reference Manual (A64) and match
//! what LLVM (`clang -c`) emits for the same instruction, including its
//! choice among equivalent forms: `add x0, x1, #-8` as `sub`, `cmp x0, #-1`
//! as `cmn`, `add x0, sp, x1` in the extended-register form, `mov x0, sp`
//! as `add #0`, `ldr x0, [x1, #-8]` as `ldur`, `fmov d0, #0.0` as `fmov d0,
//! xzr`, and the `movz`/`movn`/`orr` choice for `mov rd, #imm`.

use super::assembler::{Assembler, EncResult, FixKind, NOP};
use super::imm::{MovStep, add_imm, fp_imm8, logical_imm, mov_plan};
use super::operand::{
    AnyReg, Cond, Extend, Fp, IndexExt, Label, LogicOp, Mem, Op2, Reg, Round, Shift, SysReg, Target, VReg, regs,
};
use crate::object::RelocKind;

/// The field value of `r` where register 31 means the zero register.
fn zr(r: Reg) -> Result<u32, String> {
    if r.is_sp() {
        Err(format!("`{r}` cannot be used here (register 31 means the zero register in this operand)"))
    } else {
        Ok(r.index() as u32)
    }
}

/// The field value of `r` where register 31 means the stack pointer.
fn sp(r: Reg) -> Result<u32, String> {
    if r.is_zr() {
        Err(format!("`{r}` cannot be used here (register 31 means the stack pointer in this operand)"))
    } else {
        Ok(r.index() as u32)
    }
}

/// Bit 31 (`sf`): set for 64-bit operations.
fn sf(r: Reg) -> u32 {
    (r.is_64() as u32) << 31
}

fn same_width(regs: &[Reg]) -> EncResult {
    if regs.windows(2).all(|w| w[0].is_64() == w[1].is_64()) {
        Ok(())
    } else {
        let names: Vec<String> = regs.iter().map(|r| r.to_string()).collect();
        Err(format!("operands must all be W or all be X registers ({})", names.join(", ")))
    }
}

fn need_x(r: Reg) -> EncResult {
    if r.is_64() { Ok(()) } else { Err(format!("`{r}` must be a 64-bit (X) register")) }
}

fn need_w(r: Reg) -> EncResult {
    if r.is_64() { Err(format!("`{r}` must be a 32-bit (W) register")) } else { Ok(()) }
}

/// The base register of an address: 64-bit, `sp` allowed.
fn addr_base(r: Reg) -> Result<u32, String> {
    if !r.is_64() {
        return Err(format!("address base `{r}` must be a 64-bit register"));
    }
    sp(r)
}

fn fp_same(regs: &[VReg]) -> Result<Fp, String> {
    let fp = regs[0].fp();
    if regs.iter().all(|r| r.fp() == fp) {
        Ok(fp)
    } else {
        let names: Vec<String> = regs.iter().map(|r| r.to_string()).collect();
        Err(format!("operands must all be S or all be D registers ({})", names.join(", ")))
    }
}

/// `value` as the bit pattern of a `bits`-bit immediate: any `i64` for 64
/// bits; for 32 bits, a signed or unsigned 32-bit value.
fn imm_bits(value: i64, bits: u32) -> Result<u64, String> {
    if bits == 32 {
        if !(i32::MIN as i64..=u32::MAX as i64).contains(&value) {
            return Err(format!("immediate {value} does not fit in 32 bits"));
        }
        Ok(value as u64 & 0xffff_ffff)
    } else {
        Ok(value as u64)
    }
}

fn check_cond_not_always(cond: Cond) -> EncResult {
    if matches!(cond, Cond::Al | Cond::Nv) {
        Err(format!("condition `{}` is not allowed here", cond.suffix()))
    } else {
        Ok(())
    }
}

/// Which of the scratch registers x16 and x17 is free, given registers that
/// must not be overwritten (an address base, a register being stored).
fn scratch(avoid: &[Option<Reg>]) -> Result<Reg, String> {
    [regs::X16, regs::X17]
        .into_iter()
        .find(|s| !avoid.iter().flatten().any(|r| r.same(*s)))
        .ok_or_else(|| "needs a scratch register, but x16 and x17 are both in use by this instruction".to_string())
}

/// A load or store: access size (log2 of bytes), SIMD&FP flag and `opc`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Access {
    size: u32,
    v: bool,
    opc: u32,
}

impl Access {
    fn bits(self) -> u32 {
        self.size << 30 | (self.v as u32) << 26 | self.opc << 22
    }
}

/// Load/store kinds by mnemonic family.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Ld {
    /// `ldr`/`str` (W, X, S or D, sized by the register).
    Word,
    /// `ldrb`/`strb`.
    Byte,
    /// `ldrh`/`strh`.
    Half,
    /// `ldrsb`.
    SByte,
    /// `ldrsh`.
    SHalf,
    /// `ldrsw`.
    SWord,
}

/// The access of a load (`load`) or store of kind `kind` into `rt`.
fn access(kind: Ld, load: bool, rt: AnyReg) -> Result<Access, String> {
    let opc = load as u32;
    match (kind, rt) {
        (Ld::Word, AnyReg::Gp(r)) => Ok(Access { size: 2 + r.is_64() as u32, v: false, opc }),
        (Ld::Word, AnyReg::Fp(v)) => Ok(Access { size: 2 + (v.fp() == Fp::D) as u32, v: true, opc }),
        (Ld::Byte | Ld::Half, AnyReg::Gp(r)) => {
            need_w(r)?;
            Ok(Access { size: (kind == Ld::Half) as u32, v: false, opc })
        }
        (Ld::SByte | Ld::SHalf, AnyReg::Gp(r)) if load => {
            // opc 10 extends to 64 bits, 11 to 32 bits.
            Ok(Access { size: (kind == Ld::SHalf) as u32, v: false, opc: if r.is_64() { 2 } else { 3 } })
        }
        (Ld::SWord, AnyReg::Gp(r)) if load => {
            need_x(r)?;
            Ok(Access { size: 2, v: false, opc: 2 })
        }
        (_, AnyReg::Fp(v)) => Err(format!("`{v}` cannot be used with a byte, halfword or sign-extending access")),
        _ => Err("invalid load/store".into()),
    }
}

/// The `Rt` field of a load/store: a general register (31 = zero
/// register) or a SIMD&FP register.
fn rt_field(rt: AnyReg) -> Result<u32, String> {
    match rt {
        AnyReg::Gp(r) => zr(r),
        AnyReg::Fp(v) => Ok(v.index() as u32),
    }
}

fn gp(rt: AnyReg) -> Option<Reg> {
    match rt {
        AnyReg::Gp(r) => Some(r),
        AnyReg::Fp(_) => None,
    }
}

fn simm9(offset: i64) -> Result<u32, String> {
    if (-256..256).contains(&offset) {
        Ok((offset as u32 & 0x1ff) << 12)
    } else {
        Err(format!("offset {offset} is out of range (-256 to 255)"))
    }
}

/// Whether an `[base, #offset]` access of `1 << size` bytes is one
/// instruction: scaled unsigned 12-bit or unscaled signed 9-bit.
pub fn offset_is_direct(size_log2: u32, offset: i64) -> bool {
    (offset >= 0 && offset & ((1 << size_log2) - 1) == 0 && offset >> size_log2 < 4096) || (-256..256).contains(&offset)
}

impl Assembler {
    // ----- add / subtract -----------------------------------------------

    /// `add rd, rn, op`. With an immediate: 0–4095, optionally a multiple of
    /// 4096 below 2^24 (`lsl #12`); a negative value encodes `sub`. With a
    /// register and `sp` as `rd` or `rn`, the extended-register form is used.
    /// Use [`add_const`](Assembler::add_const) for any constant.
    pub fn add(&mut self, rd: Reg, rn: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("add", |a| a.enc_addsub(false, false, rd, rn, op));
    }

    /// `adds rd, rn, op` (sets flags).
    pub fn adds(&mut self, rd: Reg, rn: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("adds", |a| a.enc_addsub(false, true, rd, rn, op));
    }

    /// `sub rd, rn, op`.
    pub fn sub(&mut self, rd: Reg, rn: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("sub", |a| a.enc_addsub(true, false, rd, rn, op));
    }

    /// `subs rd, rn, op` (sets flags).
    pub fn subs(&mut self, rd: Reg, rn: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("subs", |a| a.enc_addsub(true, true, rd, rn, op));
    }

    /// `cmp rn, op` (`subs zr, rn, op`). `cmp x0, #-1` encodes `cmn x0, #1`.
    pub fn cmp(&mut self, rn: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("cmp", |a| a.enc_addsub(true, true, regs::XZR.with_width_of(rn), rn, op));
    }

    /// `cmn rn, op` (`adds zr, rn, op`).
    pub fn cmn(&mut self, rn: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("cmn", |a| a.enc_addsub(false, true, regs::XZR.with_width_of(rn), rn, op));
    }

    /// `neg rd, op` (`sub rd, zr, op`): a register, optionally shifted.
    pub fn neg(&mut self, rd: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("neg", |a| a.enc_neg(false, rd, op));
    }

    /// `negs rd, op` (`subs rd, zr, op`).
    pub fn negs(&mut self, rd: Reg, op: impl Into<Op2>) {
        let op = op.into();
        self.run("negs", |a| a.enc_neg(true, rd, op));
    }

    fn enc_neg(&mut self, flags: bool, rd: Reg, op: Op2) -> EncResult {
        match op {
            Op2::Reg(_) | Op2::Shifted(..) => {
                let zr = regs::XZR.with_width_of(rd);
                let (rm, shift, amount) = match op {
                    Op2::Shifted(rm, s, n) => (rm, s, n),
                    Op2::Reg(rm) => (rm, Shift::Lsl, 0),
                    _ => unreachable!(),
                };
                self.enc_addsub_shifted(true, flags, rd, zr, rm, shift, amount)
            }
            _ => Err("expected a register, optionally shifted".into()),
        }
    }

    fn enc_addsub(&mut self, sub: bool, flags: bool, rd: Reg, rn: Reg, op: Op2) -> EncResult {
        match op {
            Op2::Imm(v) => {
                same_width(&[rd, rn])?;
                let (sub, magnitude) = if v < 0 { (!sub, v.unsigned_abs()) } else { (sub, v as u64) };
                let field = add_imm(magnitude).ok_or_else(|| {
                    format!("immediate {v} is not 0 to 4095, optionally shifted left by 12 (use add_const)")
                })?;
                let rd_f = if flags { zr(rd)? } else { sp(rd)? };
                self.emit(
                    sf(rd) | (sub as u32) << 30 | (flags as u32) << 29 | 0x1100_0000 | field | sp(rn)? << 5 | rd_f,
                );
                Ok(())
            }
            // Only the extended-register form takes sp (as rn, or as rd when
            // flags are not set); `lsl #0..4` is its `uxtx` spelling.
            Op2::Reg(rm) | Op2::Shifted(rm, Shift::Lsl, _) if (rd.is_sp() && !flags) || rn.is_sp() => {
                let amount = if let Op2::Shifted(_, _, n) = op { n } else { 0 };
                let ext = if rd.is_64() { Extend::Uxtx } else { Extend::Uxtw };
                self.enc_addsub_ext(sub, flags, rd, rn, rm, ext, amount)
            }
            Op2::Reg(rm) => self.enc_addsub_shifted(sub, flags, rd, rn, rm, Shift::Lsl, 0),
            Op2::Shifted(rm, shift, amount) => self.enc_addsub_shifted(sub, flags, rd, rn, rm, shift, amount),
            Op2::Extended(rm, ext, amount) => self.enc_addsub_ext(sub, flags, rd, rn, rm, ext, amount),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn enc_addsub_shifted(
        &mut self,
        sub: bool,
        flags: bool,
        rd: Reg,
        rn: Reg,
        rm: Reg,
        shift: Shift,
        amount: u8,
    ) -> EncResult {
        same_width(&[rd, rn, rm])?;
        if shift == Shift::Ror {
            return Err("`ror` is not allowed in add/subtract".into());
        }
        if amount as u32 >= rd.bits() {
            return Err(format!("shift amount {amount} is out of range (0 to {})", rd.bits() - 1));
        }
        self.emit(
            sf(rd)
                | (sub as u32) << 30
                | (flags as u32) << 29
                | 0x0B00_0000
                | (shift as u32) << 22
                | zr(rm)? << 16
                | (amount as u32) << 10
                | zr(rn)? << 5
                | zr(rd)?,
        );
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn enc_addsub_ext(
        &mut self,
        sub: bool,
        flags: bool,
        rd: Reg,
        rn: Reg,
        rm: Reg,
        ext: Extend,
        amount: u8,
    ) -> EncResult {
        same_width(&[rd, rn])?;
        if amount > 4 {
            return Err(format!("extend amount {amount} is out of range (0 to 4)"));
        }
        let want_x = rd.is_64() && ext.takes_x();
        if rm.is_64() != want_x {
            let kind = if want_x { "an X" } else { "a W" };
            return Err(format!("`{rm}` must be {kind} register with `{}`", ext.name()));
        }
        let rd_f = if flags { zr(rd)? } else { sp(rd)? };
        self.emit(
            sf(rd)
                | (sub as u32) << 30
                | (flags as u32) << 29
                | 0x0B20_0000
                | zr(rm)? << 16
                | ext.code() << 13
                | (amount as u32) << 10
                | sp(rn)? << 5
                | rd_f,
        );
        Ok(())
    }

    /// `rd = rn + value` for any constant: one `add`/`sub`, two when the
    /// value needs 24 bits (`#hi, lsl #12` then `#lo`), otherwise the value
    /// is built in a scratch register (x16, or x17 when `rn` is x16) and
    /// added. `sp` may be `rd` or `rn`.
    pub fn add_const(&mut self, rd: Reg, rn: Reg, value: i64) {
        self.run("add_const", |a| a.enc_add_const(rd, rn, value));
    }

    fn enc_add_const(&mut self, rd: Reg, rn: Reg, value: i64) -> EncResult {
        same_width(&[rd, rn])?;
        let bits = imm_bits(value, rd.bits())?;
        // At 32 bits, the value wraps: treat it as signed.
        let value = if rd.is_64() { value } else { bits as u32 as i32 as i64 };
        let (sub, m) = if value < 0 { (true, value.unsigned_abs()) } else { (false, value as u64) };
        if add_imm(m).is_some() {
            return self.enc_addsub(sub, false, rd, rn, Op2::Imm(m as i64));
        }
        if m < 1 << 24 {
            self.enc_addsub(sub, false, rd, rn, Op2::Imm((m & !0xfff) as i64))?;
            return self.enc_addsub(sub, false, rd, rd, Op2::Imm((m & 0xfff) as i64));
        }
        let s = scratch(&[Some(rn)])?.with_width_of(rd);
        self.enc_mov_imm(s, value)?;
        self.enc_addsub(false, false, rd, rn, Op2::Reg(s))
    }

    /// Compares `rn` with any constant: `cmp`/`cmn` when the value (or its
    /// negation) is an add/sub immediate, otherwise through a scratch
    /// register (x16, or x17 when `rn` is x16).
    pub fn cmp_const(&mut self, rn: Reg, value: i64) {
        self.run("cmp_const", |a| {
            let bits = imm_bits(value, rn.bits())?;
            let value = if rn.is_64() { value } else { bits as u32 as i32 as i64 };
            let zr = regs::XZR.with_width_of(rn);
            if add_imm(value.unsigned_abs()).is_some() {
                return a.enc_addsub(true, true, zr, rn, Op2::Imm(value));
            }
            let s = scratch(&[Some(rn)])?.with_width_of(rn);
            a.enc_mov_imm(s, value)?;
            a.enc_addsub(true, true, zr, rn, Op2::Reg(s))
        });
    }

    // ----- logical ------------------------------------------------------

    /// A logical instruction: `op rd, rn, op2`. An immediate must be a
    /// bitmask pattern (see [`logical_imm`](super::logical_imm)); for
    /// `bic`/`orn`/`eon`/`bics` its complement must be. `rd` may be `sp`
    /// for `and`/`orr`/`eor` with an immediate.
    pub fn logical(&mut self, op: LogicOp, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        let op2 = op2.into();
        self.run(op.name(), |a| a.enc_logical(op, rd, rn, op2));
    }

    fn enc_logical(&mut self, op: LogicOp, rd: Reg, rn: Reg, op2: Op2) -> EncResult {
        let (opc, n) = op.fields();
        let base = sf(rd) | opc << 29;
        match op2 {
            Op2::Imm(v) => {
                same_width(&[rd, rn])?;
                let mut value = imm_bits(v, rd.bits())?;
                if n == 1 {
                    value = !value & if rd.is_64() { u64::MAX } else { 0xffff_ffff };
                }
                let field = logical_imm(value, rd.bits())
                    .ok_or_else(|| format!("immediate {v:#x} is not a valid bitmask immediate"))?;
                let rd_f = if opc == 3 { zr(rd)? } else { sp(rd)? };
                self.emit(base | 0x1200_0000 | field << 10 | zr(rn)? << 5 | rd_f);
                Ok(())
            }
            Op2::Reg(rm) => self.enc_logical(op, rd, rn, Op2::Shifted(rm, Shift::Lsl, 0)),
            Op2::Shifted(rm, shift, amount) => {
                same_width(&[rd, rn, rm])?;
                if amount as u32 >= rd.bits() {
                    return Err(format!("shift amount {amount} is out of range (0 to {})", rd.bits() - 1));
                }
                self.emit(
                    base | 0x0A00_0000
                        | (shift as u32) << 22
                        | n << 21
                        | zr(rm)? << 16
                        | (amount as u32) << 10
                        | zr(rn)? << 5
                        | zr(rd)?,
                );
                Ok(())
            }
            Op2::Extended(..) => Err("logical instructions take no extended register".into()),
        }
    }

    /// `and rd, rn, op2`.
    pub fn and(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::And, rd, rn, op2);
    }

    /// `orr rd, rn, op2`.
    pub fn orr(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Orr, rd, rn, op2);
    }

    /// `eor rd, rn, op2`.
    pub fn eor(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Eor, rd, rn, op2);
    }

    /// `ands rd, rn, op2` (sets N and Z, clears C and V).
    pub fn ands(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Ands, rd, rn, op2);
    }

    /// `bic rd, rn, op2`: `rn & !op2`.
    pub fn bic(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Bic, rd, rn, op2);
    }

    /// `orn rd, rn, op2`: `rn | !op2`.
    pub fn orn(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Orn, rd, rn, op2);
    }

    /// `eon rd, rn, op2`: `rn ^ !op2`.
    pub fn eon(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Eon, rd, rn, op2);
    }

    /// `bics rd, rn, op2` (sets flags).
    pub fn bics(&mut self, rd: Reg, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Bics, rd, rn, op2);
    }

    /// `tst rn, op2` (`ands zr, rn, op2`).
    pub fn tst(&mut self, rn: Reg, op2: impl Into<Op2>) {
        self.logical(LogicOp::Ands, regs::XZR.with_width_of(rn), rn, op2);
    }

    /// `mvn rd, op2` (`orn rd, zr, op2`): a register, optionally shifted.
    pub fn mvn(&mut self, rd: Reg, op2: impl Into<Op2>) {
        let op2 = op2.into();
        self.run("mvn", |a| {
            if let Op2::Imm(_) = op2 {
                return Err("expected a register, optionally shifted (use mov_imm for constants)".into());
            }
            a.enc_logical(LogicOp::Orn, rd, regs::XZR.with_width_of(rd), op2)
        });
    }

    /// A logical operation with any constant: one instruction when the
    /// value (or for `bic`/`orn`/`eon`/`bics`, its complement) is a bitmask
    /// immediate, otherwise through a scratch register (x16, or x17 when
    /// `rn` is x16).
    pub fn logical_const(&mut self, op: LogicOp, rd: Reg, rn: Reg, value: i64) {
        self.run(op.name(), |a| {
            let bits = imm_bits(value, rd.bits())?;
            let mask = if rd.is_64() { u64::MAX } else { 0xffff_ffff };
            let probe = if op.fields().1 == 1 { !bits & mask } else { bits };
            if logical_imm(probe, rd.bits()).is_some() {
                return a.enc_logical(op, rd, rn, Op2::Imm(value));
            }
            let s = scratch(&[Some(rn)])?.with_width_of(rd);
            a.enc_mov_imm(s, value)?;
            a.enc_logical(op, rd, rn, Op2::Reg(s))
        });
    }

    // ----- moves --------------------------------------------------------

    /// `mov rd, src`. From a register: `orr rd, zr, rm`, or `add rd, rm,
    /// #0` when either is `sp`. From an immediate: the single `movz`,
    /// `movn` or `orr` that clang would pick; a value that needs more is an
    /// error (use [`mov_imm`](Assembler::mov_imm)).
    pub fn mov(&mut self, rd: Reg, src: impl Into<Op2>) {
        let src = src.into();
        self.run("mov", |a| match src {
            Op2::Reg(rm) => {
                same_width(&[rd, rm])?;
                if rd.is_sp() || rm.is_sp() {
                    a.enc_addsub(false, false, rd, rm, Op2::Imm(0))
                } else {
                    a.enc_logical(LogicOp::Orr, rd, regs::XZR.with_width_of(rd), Op2::Reg(rm))
                }
            }
            Op2::Imm(v) => {
                let plan = mov_plan(imm_bits(v, rd.bits())?, rd.bits());
                if plan.len() != 1 {
                    return Err(format!("immediate {v:#x} needs {} instructions (use mov_imm)", plan.len()));
                }
                a.enc_mov_steps(rd, &plan)
            }
            _ => Err("expected a register or an immediate".into()),
        });
    }

    /// Loads any constant into `rd` with the shortest sequence of `movz`,
    /// `movn`, `movk` and `orr` (1 to 4 instructions for X, 1 or 2 for W).
    /// For a W register the value may be given signed or unsigned.
    pub fn mov_imm(&mut self, rd: Reg, value: i64) {
        self.run("mov_imm", |a| a.enc_mov_imm(rd, value));
    }

    fn enc_mov_imm(&mut self, rd: Reg, value: i64) -> EncResult {
        let plan = mov_plan(imm_bits(value, rd.bits())?, rd.bits());
        self.enc_mov_steps(rd, &plan)
    }

    fn enc_mov_steps(&mut self, rd: Reg, plan: &[MovStep]) -> EncResult {
        for step in plan {
            match *step {
                MovStep::Movz(imm, sh) => self.enc_movw(0b10, rd, imm, sh)?,
                MovStep::Movn(imm, sh) => self.enc_movw(0b00, rd, imm, sh)?,
                MovStep::Movk(imm, sh) => self.enc_movw(0b11, rd, imm, sh)?,
                MovStep::Orr(field) => self.emit(sf(rd) | 0x3200_0000 | field << 10 | 31 << 5 | sp(rd)?),
            }
        }
        Ok(())
    }

    fn enc_movw(&mut self, opc: u32, rd: Reg, imm: u16, shift: u8) -> EncResult {
        if shift % 16 != 0 || shift as u32 >= rd.bits() {
            return Err(format!("shift {shift} is not 0, 16{}", if rd.is_64() { ", 32 or 48" } else { "" }));
        }
        self.emit(sf(rd) | opc << 29 | 0x1280_0000 | (shift as u32 / 16) << 21 | (imm as u32) << 5 | zr(rd)?);
        Ok(())
    }

    /// `movz rd, #imm, lsl #shift`: `rd = imm << shift`.
    pub fn movz(&mut self, rd: Reg, imm: u16, shift: u8) {
        self.run("movz", |a| a.enc_movw(0b10, rd, imm, shift));
    }

    /// `movn rd, #imm, lsl #shift`: `rd = !(imm << shift)`.
    pub fn movn(&mut self, rd: Reg, imm: u16, shift: u8) {
        self.run("movn", |a| a.enc_movw(0b00, rd, imm, shift));
    }

    /// `movk rd, #imm, lsl #shift`: replaces 16 bits of `rd`.
    pub fn movk(&mut self, rd: Reg, imm: u16, shift: u8) {
        self.run("movk", |a| a.enc_movw(0b11, rd, imm, shift));
    }

    // ----- multiply and divide --------------------------------------------

    fn enc_madd(&mut self, o0: u32, rd: Reg, rn: Reg, rm: Reg, ra: Reg) -> EncResult {
        same_width(&[rd, rn, rm, ra])?;
        self.emit(sf(rd) | 0x1B00_0000 | zr(rm)? << 16 | o0 << 15 | zr(ra)? << 10 | zr(rn)? << 5 | zr(rd)?);
        Ok(())
    }

    /// `madd rd, rn, rm, ra`: `rd = ra + rn * rm`.
    pub fn madd(&mut self, rd: Reg, rn: Reg, rm: Reg, ra: Reg) {
        self.run("madd", |a| a.enc_madd(0, rd, rn, rm, ra));
    }

    /// `msub rd, rn, rm, ra`: `rd = ra - rn * rm` (with `sdiv`, the
    /// remainder).
    pub fn msub(&mut self, rd: Reg, rn: Reg, rm: Reg, ra: Reg) {
        self.run("msub", |a| a.enc_madd(1, rd, rn, rm, ra));
    }

    /// `mul rd, rn, rm` (`madd` with the zero register).
    pub fn mul(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("mul", |a| a.enc_madd(0, rd, rn, rm, regs::XZR.with_width_of(rd)));
    }

    /// `mneg rd, rn, rm`: `rd = -(rn * rm)`.
    pub fn mneg(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("mneg", |a| a.enc_madd(1, rd, rn, rm, regs::XZR.with_width_of(rd)));
    }

    /// The widening multiplies: `op31` selects `smaddl` (001), `umaddl`
    /// (101), `smulh` (010), `umulh` (110).
    fn enc_long_mul(&mut self, op31: u32, o0: u32, rd: Reg, rn: Reg, rm: Reg, ra: Reg) -> EncResult {
        need_x(rd)?;
        need_x(ra)?;
        if op31 & 2 != 0 {
            need_x(rn)?;
            need_x(rm)?;
        } else {
            need_w(rn)?;
            need_w(rm)?;
        }
        self.emit(0x9B00_0000 | op31 << 21 | zr(rm)? << 16 | o0 << 15 | zr(ra)? << 10 | zr(rn)? << 5 | zr(rd)?);
        Ok(())
    }

    /// `smulh xd, xn, xm`: high 64 bits of the signed 128-bit product.
    pub fn smulh(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("smulh", |a| a.enc_long_mul(0b010, 0, rd, rn, rm, regs::XZR));
    }

    /// `umulh xd, xn, xm`: high 64 bits of the unsigned 128-bit product.
    pub fn umulh(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("umulh", |a| a.enc_long_mul(0b110, 0, rd, rn, rm, regs::XZR));
    }

    /// `smull xd, wn, wm`: signed 32 × 32 → 64-bit product.
    pub fn smull(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("smull", |a| a.enc_long_mul(0b001, 0, rd, rn, rm, regs::XZR));
    }

    /// `umull xd, wn, wm`: unsigned 32 × 32 → 64-bit product.
    pub fn umull(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("umull", |a| a.enc_long_mul(0b101, 0, rd, rn, rm, regs::XZR));
    }

    /// `smaddl xd, wn, wm, xa`: `xa + wn * wm`, signed.
    pub fn smaddl(&mut self, rd: Reg, rn: Reg, rm: Reg, ra: Reg) {
        self.run("smaddl", |a| a.enc_long_mul(0b001, 0, rd, rn, rm, ra));
    }

    /// `umaddl xd, wn, wm, xa`: `xa + wn * wm`, unsigned.
    pub fn umaddl(&mut self, rd: Reg, rn: Reg, rm: Reg, ra: Reg) {
        self.run("umaddl", |a| a.enc_long_mul(0b101, 0, rd, rn, rm, ra));
    }

    fn enc_dp2(&mut self, opcode: u32, rd: Reg, rn: Reg, rm: Reg) -> EncResult {
        same_width(&[rd, rn, rm])?;
        self.emit(sf(rd) | 0x1AC0_0000 | zr(rm)? << 16 | opcode << 10 | zr(rn)? << 5 | zr(rd)?);
        Ok(())
    }

    /// `sdiv rd, rn, rm`: signed division rounding toward zero. Division by
    /// zero gives 0 and does not trap; `MIN / -1` gives `MIN`.
    pub fn sdiv(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("sdiv", |a| a.enc_dp2(0b000011, rd, rn, rm));
    }

    /// `udiv rd, rn, rm`: unsigned division; division by zero gives 0.
    pub fn udiv(&mut self, rd: Reg, rn: Reg, rm: Reg) {
        self.run("udiv", |a| a.enc_dp2(0b000010, rd, rn, rm));
    }

    // ----- shifts and bitfields --------------------------------------------

    fn enc_shift(&mut self, kind: Shift, rd: Reg, rn: Reg, op: Op2) -> EncResult {
        match op {
            Op2::Reg(rm) => self.enc_dp2(0b001000 | kind as u32, rd, rn, rm),
            Op2::Imm(n) => {
                same_width(&[rd, rn])?;
                let bits = rd.bits() as i64;
                if !(0..bits).contains(&n) {
                    return Err(format!("shift amount {n} is out of range (0 to {})", bits - 1));
                }
                let (n, w) = (n as u32, bits as u32);
                match kind {
                    Shift::Lsl => self.enc_bfm(0b10, rd, rn, (w - n) % w, w - 1 - n),
                    Shift::Lsr => self.enc_bfm(0b10, rd, rn, n, w - 1),
                    Shift::Asr => self.enc_bfm(0b00, rd, rn, n, w - 1),
                    Shift::Ror => self.enc_extr(rd, rn, rn, n),
                }
            }
            _ => Err("expected a shift amount or a register".into()),
        }
    }

    /// `lsl rd, rn, #n` (`ubfm`) or `lsl rd, rn, rm` (`lslv`).
    pub fn lsl(&mut self, rd: Reg, rn: Reg, amount: impl Into<Op2>) {
        let op = amount.into();
        self.run("lsl", |a| a.enc_shift(Shift::Lsl, rd, rn, op));
    }

    /// `lsr rd, rn, #n` (`ubfm`) or `lsr rd, rn, rm` (`lsrv`).
    pub fn lsr(&mut self, rd: Reg, rn: Reg, amount: impl Into<Op2>) {
        let op = amount.into();
        self.run("lsr", |a| a.enc_shift(Shift::Lsr, rd, rn, op));
    }

    /// `asr rd, rn, #n` (`sbfm`) or `asr rd, rn, rm` (`asrv`).
    pub fn asr(&mut self, rd: Reg, rn: Reg, amount: impl Into<Op2>) {
        let op = amount.into();
        self.run("asr", |a| a.enc_shift(Shift::Asr, rd, rn, op));
    }

    /// `ror rd, rn, #n` (`extr`) or `ror rd, rn, rm` (`rorv`).
    pub fn ror(&mut self, rd: Reg, rn: Reg, amount: impl Into<Op2>) {
        let op = amount.into();
        self.run("ror", |a| a.enc_shift(Shift::Ror, rd, rn, op));
    }

    fn enc_bfm(&mut self, opc: u32, rd: Reg, rn: Reg, immr: u32, imms: u32) -> EncResult {
        same_width(&[rd, rn])?;
        if immr >= rd.bits() || imms >= rd.bits() {
            return Err(format!("bitfield positions #{immr}, #{imms} are out of range (0 to {})", rd.bits() - 1));
        }
        let n = rd.is_64() as u32;
        self.emit(sf(rd) | opc << 29 | 0x1300_0000 | n << 22 | immr << 16 | imms << 10 | zr(rn)? << 5 | zr(rd)?);
        Ok(())
    }

    /// `sbfm rd, rn, #immr, #imms`.
    pub fn sbfm(&mut self, rd: Reg, rn: Reg, immr: u8, imms: u8) {
        self.run("sbfm", |a| a.enc_bfm(0b00, rd, rn, immr as u32, imms as u32));
    }

    /// `bfm rd, rn, #immr, #imms`.
    pub fn bfm(&mut self, rd: Reg, rn: Reg, immr: u8, imms: u8) {
        self.run("bfm", |a| a.enc_bfm(0b01, rd, rn, immr as u32, imms as u32));
    }

    /// `ubfm rd, rn, #immr, #imms`.
    pub fn ubfm(&mut self, rd: Reg, rn: Reg, immr: u8, imms: u8) {
        self.run("ubfm", |a| a.enc_bfm(0b10, rd, rn, immr as u32, imms as u32));
    }

    /// Sign- or zero-extends the low `from_bits` of the W register `rn`.
    fn enc_extend(&mut self, signed: bool, from_bits: u32, rd: Reg, rn: Reg) -> EncResult {
        need_w(rn)?;
        if from_bits == 32 {
            need_x(rd)?;
        }
        if !signed {
            need_w(rd)?;
        }
        let opc = if signed { 0b00 } else { 0b10 };
        self.enc_bfm(opc, rd, rn.with_width_of(rd), 0, from_bits - 1)
    }

    /// `sxtb rd, wn`: sign-extends a byte to 32 or 64 bits.
    pub fn sxtb(&mut self, rd: Reg, rn: Reg) {
        self.run("sxtb", |a| a.enc_extend(true, 8, rd, rn));
    }

    /// `sxth rd, wn`: sign-extends a halfword to 32 or 64 bits.
    pub fn sxth(&mut self, rd: Reg, rn: Reg) {
        self.run("sxth", |a| a.enc_extend(true, 16, rd, rn));
    }

    /// `sxtw xd, wn`: sign-extends a word to 64 bits.
    pub fn sxtw(&mut self, rd: Reg, rn: Reg) {
        self.run("sxtw", |a| a.enc_extend(true, 32, rd, rn));
    }

    /// `uxtb wd, wn`: zero-extends a byte (writing a W register also clears
    /// the upper 32 bits, so this serves 64-bit results too).
    pub fn uxtb(&mut self, rd: Reg, rn: Reg) {
        self.run("uxtb", |a| a.enc_extend(false, 8, rd, rn));
    }

    /// `uxth wd, wn`: zero-extends a halfword.
    pub fn uxth(&mut self, rd: Reg, rn: Reg) {
        self.run("uxth", |a| a.enc_extend(false, 16, rd, rn));
    }

    /// Checks a `#lsb, #width` bitfield and returns `(lsb, width)`.
    fn field(rd: Reg, lsb: u8, width: u8) -> Result<(u32, u32), String> {
        let (lsb, width, bits) = (lsb as u32, width as u32, rd.bits());
        if lsb >= bits || width == 0 || width > bits - lsb {
            return Err(format!("bitfield #{lsb}, #{width} does not fit in {bits} bits"));
        }
        Ok((lsb, width))
    }

    /// `ubfx rd, rn, #lsb, #width`: extracts `width` bits at `lsb`, zero-extended.
    pub fn ubfx(&mut self, rd: Reg, rn: Reg, lsb: u8, width: u8) {
        self.run("ubfx", |a| {
            let (l, w) = Self::field(rd, lsb, width)?;
            a.enc_bfm(0b10, rd, rn, l, l + w - 1)
        });
    }

    /// `sbfx rd, rn, #lsb, #width`: extracts `width` bits at `lsb`, sign-extended.
    pub fn sbfx(&mut self, rd: Reg, rn: Reg, lsb: u8, width: u8) {
        self.run("sbfx", |a| {
            let (l, w) = Self::field(rd, lsb, width)?;
            a.enc_bfm(0b00, rd, rn, l, l + w - 1)
        });
    }

    /// `ubfiz rd, rn, #lsb, #width`: the low `width` bits of `rn`, shifted
    /// left by `lsb`, other bits zero.
    pub fn ubfiz(&mut self, rd: Reg, rn: Reg, lsb: u8, width: u8) {
        self.run("ubfiz", |a| {
            let (l, w) = Self::field(rd, lsb, width)?;
            a.enc_bfm(0b10, rd, rn, (rd.bits() - l) % rd.bits(), w - 1)
        });
    }

    /// `sbfiz rd, rn, #lsb, #width`: like `ubfiz`, sign-extended.
    pub fn sbfiz(&mut self, rd: Reg, rn: Reg, lsb: u8, width: u8) {
        self.run("sbfiz", |a| {
            let (l, w) = Self::field(rd, lsb, width)?;
            a.enc_bfm(0b00, rd, rn, (rd.bits() - l) % rd.bits(), w - 1)
        });
    }

    /// `bfi rd, rn, #lsb, #width`: inserts the low `width` bits of `rn` into
    /// `rd` at `lsb`.
    pub fn bfi(&mut self, rd: Reg, rn: Reg, lsb: u8, width: u8) {
        self.run("bfi", |a| {
            let (l, w) = Self::field(rd, lsb, width)?;
            a.enc_bfm(0b01, rd, rn, (rd.bits() - l) % rd.bits(), w - 1)
        });
    }

    /// `bfxil rd, rn, #lsb, #width`: copies `width` bits of `rn` at `lsb`
    /// into the low bits of `rd`.
    pub fn bfxil(&mut self, rd: Reg, rn: Reg, lsb: u8, width: u8) {
        self.run("bfxil", |a| {
            let (l, w) = Self::field(rd, lsb, width)?;
            a.enc_bfm(0b01, rd, rn, l, l + w - 1)
        });
    }

    fn enc_extr(&mut self, rd: Reg, rn: Reg, rm: Reg, lsb: u32) -> EncResult {
        same_width(&[rd, rn, rm])?;
        if lsb >= rd.bits() {
            return Err(format!("position {lsb} is out of range (0 to {})", rd.bits() - 1));
        }
        let n = rd.is_64() as u32;
        self.emit(sf(rd) | 0x1380_0000 | n << 22 | zr(rm)? << 16 | lsb << 10 | zr(rn)? << 5 | zr(rd)?);
        Ok(())
    }

    /// `extr rd, rn, rm, #lsb`: bits `lsb..` of the concatenation `rn:rm`.
    pub fn extr(&mut self, rd: Reg, rn: Reg, rm: Reg, lsb: u8) {
        self.run("extr", |a| a.enc_extr(rd, rn, rm, lsb as u32));
    }

    fn enc_dp1(&mut self, opcode: u32, rd: Reg, rn: Reg) -> EncResult {
        same_width(&[rd, rn])?;
        self.emit(sf(rd) | 0x5AC0_0000 | opcode << 10 | zr(rn)? << 5 | zr(rd)?);
        Ok(())
    }

    /// `clz rd, rn`: count leading zero bits.
    pub fn clz(&mut self, rd: Reg, rn: Reg) {
        self.run("clz", |a| a.enc_dp1(0b000100, rd, rn));
    }

    /// `cls rd, rn`: count leading sign bits (not counting the sign bit).
    pub fn cls(&mut self, rd: Reg, rn: Reg) {
        self.run("cls", |a| a.enc_dp1(0b000101, rd, rn));
    }

    /// `rbit rd, rn`: reverse the bit order (with `clz`, counts trailing
    /// zeros).
    pub fn rbit(&mut self, rd: Reg, rn: Reg) {
        self.run("rbit", |a| a.enc_dp1(0b000000, rd, rn));
    }

    /// `rev rd, rn`: reverse the byte order.
    pub fn rev(&mut self, rd: Reg, rn: Reg) {
        self.run("rev", |a| a.enc_dp1(0b000010 | rd.is_64() as u32, rd, rn));
    }

    // ----- conditional select and compare -----------------------------------

    fn enc_csel(&mut self, op: u32, o2: u32, rd: Reg, rn: Reg, rm: Reg, cond: Cond) -> EncResult {
        same_width(&[rd, rn, rm])?;
        self.emit(
            sf(rd) | op << 30 | 0x1A80_0000 | zr(rm)? << 16 | cond.code() << 12 | o2 << 10 | zr(rn)? << 5 | zr(rd)?,
        );
        Ok(())
    }

    /// `csel rd, rn, rm, cond`: `rd = cond ? rn : rm`.
    pub fn csel(&mut self, rd: Reg, rn: Reg, rm: Reg, cond: Cond) {
        self.run("csel", |a| a.enc_csel(0, 0, rd, rn, rm, cond));
    }

    /// `csinc rd, rn, rm, cond`: `rd = cond ? rn : rm + 1`.
    pub fn csinc(&mut self, rd: Reg, rn: Reg, rm: Reg, cond: Cond) {
        self.run("csinc", |a| a.enc_csel(0, 1, rd, rn, rm, cond));
    }

    /// `csinv rd, rn, rm, cond`: `rd = cond ? rn : !rm`.
    pub fn csinv(&mut self, rd: Reg, rn: Reg, rm: Reg, cond: Cond) {
        self.run("csinv", |a| a.enc_csel(1, 0, rd, rn, rm, cond));
    }

    /// `csneg rd, rn, rm, cond`: `rd = cond ? rn : -rm`.
    pub fn csneg(&mut self, rd: Reg, rn: Reg, rm: Reg, cond: Cond) {
        self.run("csneg", |a| a.enc_csel(1, 1, rd, rn, rm, cond));
    }

    /// `cset rd, cond`: `rd = cond ? 1 : 0`.
    pub fn cset(&mut self, rd: Reg, cond: Cond) {
        self.run("cset", |a| {
            check_cond_not_always(cond)?;
            let z = regs::XZR.with_width_of(rd);
            a.enc_csel(0, 1, rd, z, z, cond.invert())
        });
    }

    /// `csetm rd, cond`: `rd = cond ? -1 : 0`.
    pub fn csetm(&mut self, rd: Reg, cond: Cond) {
        self.run("csetm", |a| {
            check_cond_not_always(cond)?;
            let z = regs::XZR.with_width_of(rd);
            a.enc_csel(1, 0, rd, z, z, cond.invert())
        });
    }

    /// `cinc rd, rn, cond`: `rd = cond ? rn + 1 : rn`.
    pub fn cinc(&mut self, rd: Reg, rn: Reg, cond: Cond) {
        self.run("cinc", |a| {
            check_cond_not_always(cond)?;
            a.enc_csel(0, 1, rd, rn, rn, cond.invert())
        });
    }

    /// `cinv rd, rn, cond`: `rd = cond ? !rn : rn`.
    pub fn cinv(&mut self, rd: Reg, rn: Reg, cond: Cond) {
        self.run("cinv", |a| {
            check_cond_not_always(cond)?;
            a.enc_csel(1, 0, rd, rn, rn, cond.invert())
        });
    }

    /// `cneg rd, rn, cond`: `rd = cond ? -rn : rn`.
    pub fn cneg(&mut self, rd: Reg, rn: Reg, cond: Cond) {
        self.run("cneg", |a| {
            check_cond_not_always(cond)?;
            a.enc_csel(1, 1, rd, rn, rn, cond.invert())
        });
    }

    fn enc_ccmp(&mut self, op: u32, rn: Reg, rhs: Op2, nzcv: u8, cond: Cond) -> EncResult {
        if nzcv > 15 {
            return Err(format!("flags #{nzcv} are out of range (0 to 15)"));
        }
        let rhs_bits = match rhs {
            Op2::Imm(v) if (0..32).contains(&v) => 0x800 | (v as u32) << 16,
            Op2::Imm(v) => return Err(format!("immediate {v} is out of range (0 to 31)")),
            Op2::Reg(rm) => {
                same_width(&[rn, rm])?;
                zr(rm)? << 16
            }
            _ => return Err("expected a register or an immediate 0 to 31".into()),
        };
        self.emit(sf(rn) | op << 30 | 0x3A40_0000 | rhs_bits | cond.code() << 12 | zr(rn)? << 5 | nzcv as u32);
        Ok(())
    }

    /// `ccmp rn, rhs, #nzcv, cond`: if `cond` holds, the flags of `cmp rn,
    /// rhs`; otherwise the flags `nzcv` (N=8, Z=4, C=2, V=1). `rhs` is a
    /// register or an immediate 0–31.
    pub fn ccmp(&mut self, rn: Reg, rhs: impl Into<Op2>, nzcv: u8, cond: Cond) {
        let rhs = rhs.into();
        self.run("ccmp", |a| a.enc_ccmp(1, rn, rhs, nzcv, cond));
    }

    /// `ccmn rn, rhs, #nzcv, cond`: like `ccmp` with `cmn`.
    pub fn ccmn(&mut self, rn: Reg, rhs: impl Into<Op2>, nzcv: u8, cond: Cond) {
        let rhs = rhs.into();
        self.run("ccmn", |a| a.enc_ccmp(0, rn, rhs, nzcv, cond));
    }

    // ----- loads and stores -------------------------------------------------

    fn enc_ldst(&mut self, kind: Ld, load: bool, rt: AnyReg, mem: &Mem) -> EncResult {
        let acc = access(kind, load, rt)?;
        let rt_f = rt_field(rt)?;
        let scale = acc.size;
        let base = acc.bits() | rt_f;
        match mem {
            Mem::Offset { base: rn, offset } => {
                let rn_f = addr_base(*rn)?;
                let off = *offset;
                if off >= 0 && off & ((1 << scale) - 1) == 0 && off >> scale < 4096 {
                    self.emit(base | 0x3900_0000 | ((off >> scale) as u32) << 10 | rn_f << 5);
                } else if (-256..256).contains(&off) {
                    self.emit(base | 0x3800_0000 | simm9(off)? | rn_f << 5);
                } else if self.strict {
                    return Err(format!(
                        "offset {off} is out of range (0 to {} in steps of {}, or -256 to 255)",
                        4095 << scale,
                        1 << scale
                    ));
                } else {
                    let s = scratch(&[Some(*rn), if load { None } else { gp(rt) }])?;
                    self.enc_mov_imm(s, off)?;
                    self.emit(base | 0x3820_0800 | (s.index() as u32) << 16 | 0b011 << 13 | rn_f << 5);
                }
            }
            Mem::PreIndex { base: rn, offset } | Mem::PostIndex { base: rn, offset } => {
                let rn_f = addr_base(*rn)?;
                if let Some(r) = gp(rt)
                    && r.same(*rn)
                    && !r.is_zr()
                {
                    return Err(format!("`{r}` is both the transfer register and the written-back base"));
                }
                let mode = if matches!(mem, Mem::PreIndex { .. }) { 0b11 } else { 0b01 };
                self.emit(base | 0x3800_0000 | simm9(*offset)? | mode << 10 | rn_f << 5);
            }
            Mem::Index { base: rn, index, ext, shift } => {
                let rn_f = addr_base(*rn)?;
                let want_x = matches!(ext, IndexExt::Lsl | IndexExt::Sxtx);
                if index.is_64() != want_x {
                    let kind = if want_x { "an X" } else { "a W" };
                    return Err(format!("index `{index}` must be {kind} register here"));
                }
                self.emit(
                    base | 0x3820_0800 | zr(*index)? << 16 | ext.code() << 13 | (*shift as u32) << 12 | rn_f << 5,
                );
            }
            Mem::PageOff { base: rn, sym, addend } => {
                let rn_f = addr_base(*rn)?;
                self.emit_reloc(
                    base | 0x3900_0000 | rn_f << 5,
                    RelocKind::Arm64PageOff12 { scale: scale as u8 },
                    sym,
                    *addend,
                );
            }
            Mem::GotPageOff { base: rn, sym } => {
                if acc != (Access { size: 3, v: false, opc: 1 }) {
                    return Err("a GOT slot can only be loaded with a 64-bit `ldr`".into());
                }
                let rn_f = addr_base(*rn)?;
                self.emit_reloc(base | 0x3900_0000 | rn_f << 5, RelocKind::Arm64GotPageOff12, sym, 0);
            }
            Mem::Sym { sym, addend } => {
                if self.strict {
                    return Err("a symbol address needs `adrp`".into());
                }
                let s = scratch(&[if load { None } else { gp(rt) }])?;
                self.emit_reloc(0x9000_0000 | s.index() as u32, RelocKind::Arm64Page21, sym, *addend);
                self.emit_reloc(
                    base | 0x3900_0000 | (s.index() as u32) << 5,
                    RelocKind::Arm64PageOff12 { scale: scale as u8 },
                    sym,
                    *addend,
                );
            }
            Mem::Label { label, addend } => {
                let opc = match acc {
                    Access { size: 2, opc: 1, .. } => 0b00,
                    Access { size: 3, opc: 1, .. } => 0b01,
                    Access { size: 2, v: false, opc: 2 } => 0b10,
                    _ if !load => return Err("cannot store to a literal".into()),
                    _ => return Err("literal loads are only `ldr` (W, X, S, D) and `ldrsw`".into()),
                };
                self.emit_label(
                    opc << 30 | 0x1800_0000 | (acc.v as u32) << 26 | rt_f,
                    FixKind::Imm19,
                    *label,
                    *addend as i64,
                )?;
            }
        }
        Ok(())
    }

    /// `ldr rt, mem`: a 32- or 64-bit general register, or an S or D
    /// register. Out-of-range [`Mem::Offset`]s and [`Mem::Sym`] expand
    /// through a scratch register (see the [module docs](super)).
    pub fn ldr(&mut self, rt: impl Into<AnyReg>, mem: Mem) {
        let rt = rt.into();
        self.run("ldr", |a| a.enc_ldst(Ld::Word, true, rt, &mem));
    }

    /// `str rt, mem`.
    pub fn str(&mut self, rt: impl Into<AnyReg>, mem: Mem) {
        let rt = rt.into();
        self.run("str", |a| a.enc_ldst(Ld::Word, false, rt, &mem));
    }

    /// `ldrb wt, mem`: load a byte, zero-extended.
    pub fn ldrb(&mut self, rt: Reg, mem: Mem) {
        self.run("ldrb", |a| a.enc_ldst(Ld::Byte, true, rt.into(), &mem));
    }

    /// `strb wt, mem`.
    pub fn strb(&mut self, rt: Reg, mem: Mem) {
        self.run("strb", |a| a.enc_ldst(Ld::Byte, false, rt.into(), &mem));
    }

    /// `ldrh wt, mem`: load a halfword, zero-extended.
    pub fn ldrh(&mut self, rt: Reg, mem: Mem) {
        self.run("ldrh", |a| a.enc_ldst(Ld::Half, true, rt.into(), &mem));
    }

    /// `strh wt, mem`.
    pub fn strh(&mut self, rt: Reg, mem: Mem) {
        self.run("strh", |a| a.enc_ldst(Ld::Half, false, rt.into(), &mem));
    }

    /// `ldrsb rt, mem`: load a byte, sign-extended to 32 or 64 bits.
    pub fn ldrsb(&mut self, rt: Reg, mem: Mem) {
        self.run("ldrsb", |a| a.enc_ldst(Ld::SByte, true, rt.into(), &mem));
    }

    /// `ldrsh rt, mem`: load a halfword, sign-extended to 32 or 64 bits.
    pub fn ldrsh(&mut self, rt: Reg, mem: Mem) {
        self.run("ldrsh", |a| a.enc_ldst(Ld::SHalf, true, rt.into(), &mem));
    }

    /// `ldrsw xt, mem`: load a word, sign-extended to 64 bits.
    pub fn ldrsw(&mut self, rt: Reg, mem: Mem) {
        self.run("ldrsw", |a| a.enc_ldst(Ld::SWord, true, rt.into(), &mem));
    }

    /// The unscaled forms: `[base, #offset]` with a signed 9-bit offset,
    /// whatever its alignment.
    fn enc_unscaled(&mut self, kind: Ld, load: bool, rt: AnyReg, base: Reg, offset: i64) -> EncResult {
        let acc = access(kind, load, rt)?;
        self.emit(acc.bits() | 0x3800_0000 | simm9(offset)? | addr_base(base)? << 5 | rt_field(rt)?);
        Ok(())
    }

    /// `ldur rt, [base, #offset]` (offset -256 to 255).
    pub fn ldur(&mut self, rt: impl Into<AnyReg>, base: Reg, offset: i64) {
        let rt = rt.into();
        self.run("ldur", |a| a.enc_unscaled(Ld::Word, true, rt, base, offset));
    }

    /// `stur rt, [base, #offset]`.
    pub fn stur(&mut self, rt: impl Into<AnyReg>, base: Reg, offset: i64) {
        let rt = rt.into();
        self.run("stur", |a| a.enc_unscaled(Ld::Word, false, rt, base, offset));
    }

    /// `ldurb wt, [base, #offset]`.
    pub fn ldurb(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("ldurb", |a| a.enc_unscaled(Ld::Byte, true, rt.into(), base, offset));
    }

    /// `sturb wt, [base, #offset]`.
    pub fn sturb(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("sturb", |a| a.enc_unscaled(Ld::Byte, false, rt.into(), base, offset));
    }

    /// `ldurh wt, [base, #offset]`.
    pub fn ldurh(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("ldurh", |a| a.enc_unscaled(Ld::Half, true, rt.into(), base, offset));
    }

    /// `sturh wt, [base, #offset]`.
    pub fn sturh(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("sturh", |a| a.enc_unscaled(Ld::Half, false, rt.into(), base, offset));
    }

    /// `ldursb rt, [base, #offset]`.
    pub fn ldursb(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("ldursb", |a| a.enc_unscaled(Ld::SByte, true, rt.into(), base, offset));
    }

    /// `ldursh rt, [base, #offset]`.
    pub fn ldursh(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("ldursh", |a| a.enc_unscaled(Ld::SHalf, true, rt.into(), base, offset));
    }

    /// `ldursw xt, [base, #offset]`.
    pub fn ldursw(&mut self, rt: Reg, base: Reg, offset: i64) {
        self.run("ldursw", |a| a.enc_unscaled(Ld::SWord, true, rt.into(), base, offset));
    }

    fn enc_pair(&mut self, load: bool, rt1: AnyReg, rt2: AnyReg, mem: &Mem) -> EncResult {
        let (opc, v, scale) = match (rt1, rt2) {
            (AnyReg::Gp(a), AnyReg::Gp(b)) => {
                same_width(&[a, b])?;
                if a.is_64() { (0b10, 0, 3) } else { (0b00, 0, 2) }
            }
            (AnyReg::Fp(a), AnyReg::Fp(b)) => match fp_same(&[a, b])? {
                Fp::S => (0b00, 1, 2),
                Fp::D => (0b01, 1, 3),
            },
            _ => return Err("both registers must be general registers, or both SIMD&FP registers".into()),
        };
        let (f1, f2) = (rt_field(rt1)?, rt_field(rt2)?);
        if load && rt1 == rt2 {
            return Err(format!("loading `{rt1}` twice is unpredictable"));
        }
        let base = opc << 30 | 0x2800_0000 | v << 26 | (load as u32) << 22 | f2 << 10 | f1;
        let imm7 = |offset: i64| -> Option<u32> {
            let q = offset >> scale;
            (offset & ((1 << scale) - 1) == 0 && (-64..64).contains(&q)).then_some((q as u32 & 0x7f) << 15)
        };
        let range = || format!("-{} to {} in steps of {}", 64 << scale, 63 << scale, 1 << scale);
        match mem {
            Mem::Offset { base: rn, offset } => {
                let rn_f = addr_base(*rn)?;
                if let Some(field) = imm7(*offset) {
                    self.emit(base | 0b10 << 23 | field | rn_f << 5);
                } else if self.strict {
                    return Err(format!("offset {offset} is out of range ({})", range()));
                } else {
                    let stored = if load { [None, None] } else { [gp(rt1), gp(rt2)] };
                    let s = scratch(&[Some(*rn), stored[0], stored[1]])?;
                    self.enc_add_const(s, *rn, *offset)?;
                    self.emit(base | 0b10 << 23 | (s.index() as u32) << 5);
                }
            }
            Mem::PreIndex { base: rn, offset } | Mem::PostIndex { base: rn, offset } => {
                let rn_f = addr_base(*rn)?;
                for r in [gp(rt1), gp(rt2)].into_iter().flatten() {
                    if r.same(*rn) && !r.is_zr() {
                        return Err(format!("`{r}` is both a transfer register and the written-back base"));
                    }
                }
                let field = imm7(*offset).ok_or_else(|| format!("offset {offset} is out of range ({})", range()))?;
                let mode = if matches!(mem, Mem::PreIndex { .. }) { 0b11 } else { 0b01 };
                self.emit(base | mode << 23 | field | rn_f << 5);
            }
            _ => return Err("a register pair takes [base, #offset], [base, #offset]! or [base], #offset".into()),
        }
        Ok(())
    }

    /// `ldp rt1, rt2, mem`: two X, W, D or S registers from consecutive
    /// slots. `mem` is [`Mem::Offset`] (an out-of-range offset expands
    /// through a scratch register), [`Mem::PreIndex`] or
    /// [`Mem::PostIndex`] (7-bit offsets scaled by the register size).
    pub fn ldp(&mut self, rt1: impl Into<AnyReg>, rt2: impl Into<AnyReg>, mem: Mem) {
        let (rt1, rt2) = (rt1.into(), rt2.into());
        self.run("ldp", |a| a.enc_pair(true, rt1, rt2, &mem));
    }

    /// `stp rt1, rt2, mem`, e.g. `stp(X29, X30, Mem::pre(SP, -16))`.
    pub fn stp(&mut self, rt1: impl Into<AnyReg>, rt2: impl Into<AnyReg>, mem: Mem) {
        let (rt1, rt2) = (rt1.into(), rt2.into());
        self.run("stp", |a| a.enc_pair(false, rt1, rt2, &mem));
    }

    // ----- addresses of symbols and labels -----------------------------------

    /// `adrp xd, sym@PAGE` (with `sym + addend`): the 4 KiB page of the
    /// symbol, ±4 GiB ([`RelocKind::Arm64Page21`]).
    pub fn adrp(&mut self, rd: Reg, sym: &str, addend: i64) {
        self.run("adrp", |a| {
            need_x(rd)?;
            a.emit_reloc(0x9000_0000 | zr(rd)?, RelocKind::Arm64Page21, sym, addend);
            Ok(())
        });
    }

    /// `adrp xd, sym@GOTPAGE`: the page of the GOT slot of `sym`
    /// ([`RelocKind::Arm64GotPage21`]).
    pub fn adrp_got(&mut self, rd: Reg, sym: &str) {
        self.run("adrp", |a| {
            need_x(rd)?;
            a.emit_reloc(0x9000_0000 | zr(rd)?, RelocKind::Arm64GotPage21, sym, 0);
            Ok(())
        });
    }

    /// `add xd, xn, sym@PAGEOFF` (with `sym + addend`): the low 12 bits of
    /// the address ([`RelocKind::Arm64PageOff12`] with scale 0).
    pub fn add_pageoff(&mut self, rd: Reg, rn: Reg, sym: &str, addend: i64) {
        self.run("add", |a| {
            need_x(rd)?;
            need_x(rn)?;
            a.emit_reloc(0x9100_0000 | sp(rn)? << 5 | sp(rd)?, RelocKind::Arm64PageOff12 { scale: 0 }, sym, addend);
            Ok(())
        });
    }

    /// The address `sym + addend` in `xd`: `adrp` + `add` (2 instructions,
    /// ±4 GiB).
    pub fn load_address(&mut self, rd: Reg, sym: &str, addend: i64) {
        self.adrp(rd, sym, addend);
        self.add_pageoff(rd, rd, sym, addend);
    }

    /// The address of `sym` from its GOT slot (imported symbols): `adrp
    /// xd, sym@GOTPAGE` + `ldr xd, [xd, sym@GOTPAGEOFF]`.
    pub fn load_got(&mut self, rd: Reg, sym: &str) {
        self.run("load_got", |a| {
            need_x(rd)?;
            a.emit_reloc(0x9000_0000 | zr(rd)?, RelocKind::Arm64GotPage21, sym, 0);
            a.enc_ldst(Ld::Word, true, rd.into(), &Mem::GotPageOff { base: rd, sym: sym.to_string() })
        });
    }

    /// Calls `sym` through its GOT slot: `load_got(x16, sym)` + `blr x16`.
    /// This is how code calls imported functions (libSystem), which a `bl`
    /// cannot reach. Clobbers x16.
    pub fn call_got(&mut self, sym: &str) {
        self.load_got(regs::X16, sym);
        self.blr(regs::X16);
    }

    /// `adr xd, label + addend`: a PC-relative address within ±1 MiB.
    pub fn adr(&mut self, rd: Reg, label: Label, addend: i32) {
        self.run("adr", |a| {
            need_x(rd)?;
            let rd_f = zr(rd)?;
            a.emit_label(0x1000_0000 | rd_f, FixKind::Adr21, label, addend as i64)
        });
    }

    // ----- branches -----------------------------------------------------

    fn enc_branch(&mut self, link: bool, target: Target) -> EncResult {
        let op = if link { 0x9400_0000 } else { 0x1400_0000 };
        match target {
            Target::Label(l) => self.emit_label(op, FixKind::Imm26, l, 0),
            Target::Sym(s) => {
                self.emit_reloc(op, RelocKind::Arm64Branch26, &s, 0);
                Ok(())
            }
        }
    }

    /// `b target`: a label (±128 MiB) or a symbol
    /// ([`RelocKind::Arm64Branch26`]).
    pub fn b(&mut self, target: impl Into<Target>) {
        let t = target.into();
        self.run("b", |a| a.enc_branch(false, t));
    }

    /// `bl target`: call a label or a symbol (not an import; see
    /// [`call_got`](Assembler::call_got)).
    pub fn bl(&mut self, target: impl Into<Target>) {
        let t = target.into();
        self.run("bl", |a| a.enc_branch(true, t));
    }

    /// `b.cond label` (±1 MiB, relaxed beyond that).
    pub fn b_cond(&mut self, cond: Cond, target: Label) {
        self.run("b.cond", |a| a.branch_var(0x5400_0000 | cond.code(), 19, target));
    }

    /// `cbz rt, label`: branch if `rt` is zero (±1 MiB, relaxed beyond).
    pub fn cbz(&mut self, rt: Reg, target: Label) {
        self.run("cbz", |a| a.branch_var(sf(rt) | 0x3400_0000 | zr(rt)?, 19, target));
    }

    /// `cbnz rt, label`: branch if `rt` is not zero.
    pub fn cbnz(&mut self, rt: Reg, target: Label) {
        self.run("cbnz", |a| a.branch_var(sf(rt) | 0x3500_0000 | zr(rt)?, 19, target));
    }

    fn enc_tb(&mut self, op: u32, rt: Reg, bit: u8, target: Label) -> EncResult {
        if bit as u32 >= rt.bits() {
            return Err(format!("bit {bit} is out of range for `{rt}`"));
        }
        let bit = bit as u32;
        self.branch_var((bit >> 5) << 31 | op | (bit & 31) << 19 | zr(rt)?, 14, target)
    }

    /// `tbz rt, #bit, label`: branch if the bit is zero (±32 KiB, relaxed
    /// beyond).
    pub fn tbz(&mut self, rt: Reg, bit: u8, target: Label) {
        self.run("tbz", |a| a.enc_tb(0x3600_0000, rt, bit, target));
    }

    /// `tbnz rt, #bit, label`: branch if the bit is one.
    pub fn tbnz(&mut self, rt: Reg, bit: u8, target: Label) {
        self.run("tbnz", |a| a.enc_tb(0x3700_0000, rt, bit, target));
    }

    fn enc_branch_reg(&mut self, op: u32, rn: Reg) -> EncResult {
        need_x(rn)?;
        self.emit(op | zr(rn)? << 5);
        Ok(())
    }

    /// `br xn`: jump to the address in `xn`.
    pub fn br(&mut self, rn: Reg) {
        self.run("br", |a| a.enc_branch_reg(0xD61F_0000, rn));
    }

    /// `blr xn`: call the address in `xn`.
    pub fn blr(&mut self, rn: Reg) {
        self.run("blr", |a| a.enc_branch_reg(0xD63F_0000, rn));
    }

    /// `ret` (to x30).
    pub fn ret(&mut self) {
        self.emit(0xD65F_03C0);
    }

    /// `ret xn`.
    pub fn ret_to(&mut self, rn: Reg) {
        self.run("ret", |a| a.enc_branch_reg(0xD65F_0000, rn));
    }

    // ----- floating point -------------------------------------------------

    fn enc_fp2(&mut self, opcode: u32, vd: VReg, vn: VReg, vm: VReg) -> EncResult {
        let fp = fp_same(&[vd, vn, vm])?;
        self.emit(
            0x1E20_0800
                | fp.ftype() << 22
                | (vm.index() as u32) << 16
                | opcode << 12
                | (vn.index() as u32) << 5
                | vd.index() as u32,
        );
        Ok(())
    }

    /// `fadd vd, vn, vm`.
    pub fn fadd(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fadd", |a| a.enc_fp2(0b0010, vd, vn, vm));
    }

    /// `fsub vd, vn, vm`.
    pub fn fsub(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fsub", |a| a.enc_fp2(0b0011, vd, vn, vm));
    }

    /// `fmul vd, vn, vm`.
    pub fn fmul(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fmul", |a| a.enc_fp2(0b0000, vd, vn, vm));
    }

    /// `fdiv vd, vn, vm`.
    pub fn fdiv(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fdiv", |a| a.enc_fp2(0b0001, vd, vn, vm));
    }

    /// `fmax vd, vn, vm` (NaN if either operand is NaN).
    pub fn fmax(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fmax", |a| a.enc_fp2(0b0100, vd, vn, vm));
    }

    /// `fmin vd, vn, vm` (NaN if either operand is NaN).
    pub fn fmin(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fmin", |a| a.enc_fp2(0b0101, vd, vn, vm));
    }

    /// `fmaxnm vd, vn, vm` (a quiet NaN operand loses to a number).
    pub fn fmaxnm(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fmaxnm", |a| a.enc_fp2(0b0110, vd, vn, vm));
    }

    /// `fminnm vd, vn, vm`.
    pub fn fminnm(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fminnm", |a| a.enc_fp2(0b0111, vd, vn, vm));
    }

    /// `fnmul vd, vn, vm`: `-(vn * vm)`.
    pub fn fnmul(&mut self, vd: VReg, vn: VReg, vm: VReg) {
        self.run("fnmul", |a| a.enc_fp2(0b1000, vd, vn, vm));
    }

    fn enc_fp1(&mut self, opcode: u32, ftype: u32, vd: VReg, vn: VReg) -> EncResult {
        self.emit(0x1E20_4000 | ftype << 22 | opcode << 15 | (vn.index() as u32) << 5 | vd.index() as u32);
        Ok(())
    }

    fn enc_fp1_same(&mut self, opcode: u32, vd: VReg, vn: VReg) -> EncResult {
        let fp = fp_same(&[vd, vn])?;
        self.enc_fp1(opcode, fp.ftype(), vd, vn)
    }

    /// `fneg vd, vn`.
    pub fn fneg(&mut self, vd: VReg, vn: VReg) {
        self.run("fneg", |a| a.enc_fp1_same(0b000010, vd, vn));
    }

    /// `fabs vd, vn`.
    pub fn fabs(&mut self, vd: VReg, vn: VReg) {
        self.run("fabs", |a| a.enc_fp1_same(0b000001, vd, vn));
    }

    /// `fsqrt vd, vn`.
    pub fn fsqrt(&mut self, vd: VReg, vn: VReg) {
        self.run("fsqrt", |a| a.enc_fp1_same(0b000011, vd, vn));
    }

    /// `frint<mode> vd, vn`: round to an integral value in floating point.
    pub fn frint(&mut self, mode: Round, vd: VReg, vn: VReg) {
        let opcode = match mode {
            Round::Nearest => 0b001000,
            Round::Up => 0b001001,
            Round::Down => 0b001010,
            Round::Zero => 0b001011,
            Round::Away => 0b001100,
        };
        self.run("frint", |a| a.enc_fp1_same(opcode, vd, vn));
    }

    /// `frintn vd, vn`: to nearest, ties to even.
    pub fn frintn(&mut self, vd: VReg, vn: VReg) {
        self.frint(Round::Nearest, vd, vn);
    }

    /// `frintm vd, vn`: toward minus infinity (`Floor`).
    pub fn frintm(&mut self, vd: VReg, vn: VReg) {
        self.frint(Round::Down, vd, vn);
    }

    /// `frintp vd, vn`: toward plus infinity (`Ceil`).
    pub fn frintp(&mut self, vd: VReg, vn: VReg) {
        self.frint(Round::Up, vd, vn);
    }

    /// `frintz vd, vn`: toward zero (Pascal `Int`).
    pub fn frintz(&mut self, vd: VReg, vn: VReg) {
        self.frint(Round::Zero, vd, vn);
    }

    /// `frinta vd, vn`: to nearest, ties away from zero.
    pub fn frinta(&mut self, vd: VReg, vn: VReg) {
        self.frint(Round::Away, vd, vn);
    }

    /// `frintx vd, vn`: in the FPCR rounding mode, raising Inexact.
    pub fn frintx(&mut self, vd: VReg, vn: VReg) {
        self.run("frintx", |a| a.enc_fp1_same(0b001110, vd, vn));
    }

    /// `frinti vd, vn`: in the FPCR rounding mode.
    pub fn frinti(&mut self, vd: VReg, vn: VReg) {
        self.run("frinti", |a| a.enc_fp1_same(0b001111, vd, vn));
    }

    /// `fcvt vd, vn`: between single and double precision.
    pub fn fcvt(&mut self, vd: VReg, vn: VReg) {
        self.run("fcvt", |a| {
            if vd.fp() == vn.fp() {
                return Err("source and destination precision are the same".into());
            }
            let opcode = if vd.fp() == Fp::D { 0b000101 } else { 0b000100 };
            a.enc_fp1(opcode, vn.fp().ftype(), vd, vn)
        });
    }

    /// `fmov dst, src`: between FP registers of the same precision, or
    /// between a general register and an FP register of the same size (`w`
    /// ↔ `s`, `x` ↔ `d`, bits unchanged). `xzr`/`wzr` as source give +0.0.
    pub fn fmov(&mut self, dst: impl Into<AnyReg>, src: impl Into<AnyReg>) {
        let (dst, src) = (dst.into(), src.into());
        self.run("fmov", |a| match (dst, src) {
            (AnyReg::Fp(vd), AnyReg::Fp(vn)) => a.enc_fp1_same(0, vd, vn),
            (AnyReg::Fp(vd), AnyReg::Gp(rn)) => a.enc_fmov_gp(0b111, rn, vd, vd.index() as u32, zr(rn)?),
            (AnyReg::Gp(rd), AnyReg::Fp(vn)) => a.enc_fmov_gp(0b110, rd, vn, zr(rd)?, vn.index() as u32),
            (AnyReg::Gp(_), AnyReg::Gp(_)) => Err("both operands are general registers (use mov)".into()),
        });
    }

    fn enc_fmov_gp(&mut self, opcode: u32, r: Reg, v: VReg, d: u32, n: u32) -> EncResult {
        if r.is_64() != (v.fp() == Fp::D) {
            return Err(format!("`{r}` and `{v}` differ in size"));
        }
        self.emit(sf(r) | 0x1E20_0000 | v.fp().ftype() << 22 | opcode << 16 | n << 5 | d);
        Ok(())
    }

    /// `fmov vd, #value`: +0.0 (as `fmov vd, xzr`, like clang) or a value
    /// encodable in 8 bits (see [`fp_imm8`](super::fp_imm8)); anything else
    /// is an error (load it from memory, or `mov_imm` + `fmov`).
    pub fn fmov_imm(&mut self, vd: VReg, value: f64) {
        self.run("fmov", |a| {
            if value == 0.0 && value.is_sign_positive() {
                let zr = if vd.fp() == Fp::D { regs::XZR } else { regs::WZR };
                return a.enc_fmov_gp(0b111, zr, vd, vd.index() as u32, 31);
            }
            let imm8 = fp_imm8(value).ok_or_else(|| format!("{value} cannot be encoded as an 8-bit immediate"))?;
            a.emit(0x1E20_1000 | vd.fp().ftype() << 22 | (imm8 as u32) << 13 | vd.index() as u32);
            Ok(())
        });
    }

    fn enc_fcmp(&mut self, opc2: u32, vn: VReg, vm: Option<VReg>) -> EncResult {
        let fp = fp_same(&[vn, vm.unwrap_or(vn)])?;
        let rm = vm.map_or(0, |v| v.index() as u32);
        self.emit(0x1E20_2000 | fp.ftype() << 22 | rm << 16 | (vn.index() as u32) << 5 | opc2);
        Ok(())
    }

    /// `fcmp vn, vm`: sets NZCV (unordered: C and V set).
    pub fn fcmp(&mut self, vn: VReg, vm: VReg) {
        self.run("fcmp", |a| a.enc_fcmp(0b00000, vn, Some(vm)));
    }

    /// `fcmp vn, #0.0`.
    pub fn fcmp_zero(&mut self, vn: VReg) {
        self.run("fcmp", |a| a.enc_fcmp(0b01000, vn, None));
    }

    /// `fcmpe vn, vm`: like `fcmp`, but quiet NaNs also raise Invalid.
    pub fn fcmpe(&mut self, vn: VReg, vm: VReg) {
        self.run("fcmpe", |a| a.enc_fcmp(0b10000, vn, Some(vm)));
    }

    /// `fcmpe vn, #0.0`.
    pub fn fcmpe_zero(&mut self, vn: VReg) {
        self.run("fcmpe", |a| a.enc_fcmp(0b11000, vn, None));
    }

    /// `fcsel vd, vn, vm, cond`: `vd = cond ? vn : vm`.
    pub fn fcsel(&mut self, vd: VReg, vn: VReg, vm: VReg, cond: Cond) {
        self.run("fcsel", |a| {
            let fp = fp_same(&[vd, vn, vm])?;
            a.emit(
                0x1E20_0C00
                    | fp.ftype() << 22
                    | (vm.index() as u32) << 16
                    | cond.code() << 12
                    | (vn.index() as u32) << 5
                    | vd.index() as u32,
            );
            Ok(())
        });
    }

    /// Conversion between a general register and an FP register:
    /// `rmode:opcode` selects the instruction.
    fn enc_fp_int(&mut self, rmode: u32, opcode: u32, r: Reg, v: VReg, to_fp: bool) -> EncResult {
        let (d, n) = if to_fp { (v.index() as u32, zr(r)?) } else { (zr(r)?, v.index() as u32) };
        self.emit(sf(r) | 0x1E20_0000 | v.fp().ftype() << 22 | rmode << 19 | opcode << 16 | n << 5 | d);
        Ok(())
    }

    /// `scvtf vd, rn`: signed W or X integer to S or D.
    pub fn scvtf(&mut self, vd: VReg, rn: Reg) {
        self.run("scvtf", |a| a.enc_fp_int(0b00, 0b010, rn, vd, true));
    }

    /// `ucvtf vd, rn`: unsigned W or X integer to S or D.
    pub fn ucvtf(&mut self, vd: VReg, rn: Reg) {
        self.run("ucvtf", |a| a.enc_fp_int(0b00, 0b011, rn, vd, true));
    }

    /// `fcvt<mode><s|u> rd, vn`: S or D to a signed (`signed`) or unsigned
    /// W or X integer, rounding by `mode`. Out-of-range values saturate and
    /// NaN gives 0; nothing traps (check FPSR.IOC for errors).
    pub fn fcvt_int(&mut self, mode: Round, signed: bool, rd: Reg, vn: VReg) {
        let (rmode, opcode, letter) = match mode {
            Round::Nearest => (0b00, 0b000, 'n'),
            Round::Away => (0b00, 0b100, 'a'),
            Round::Up => (0b01, 0b000, 'p'),
            Round::Down => (0b10, 0b000, 'm'),
            Round::Zero => (0b11, 0b000, 'z'),
        };
        let name = format!("fcvt{letter}{}", if signed { 's' } else { 'u' });
        self.run(&name, |a| a.enc_fp_int(rmode, opcode | !signed as u32, rd, vn, false));
    }

    /// `fcvtzs rd, vn`: toward zero, signed (Pascal `Trunc`).
    pub fn fcvtzs(&mut self, rd: Reg, vn: VReg) {
        self.fcvt_int(Round::Zero, true, rd, vn);
    }

    /// `fcvtzu rd, vn`: toward zero, unsigned.
    pub fn fcvtzu(&mut self, rd: Reg, vn: VReg) {
        self.fcvt_int(Round::Zero, false, rd, vn);
    }

    /// `fcvtms rd, vn`: toward minus infinity, signed (`Floor`).
    pub fn fcvtms(&mut self, rd: Reg, vn: VReg) {
        self.fcvt_int(Round::Down, true, rd, vn);
    }

    /// `fcvtps rd, vn`: toward plus infinity, signed (`Ceil`).
    pub fn fcvtps(&mut self, rd: Reg, vn: VReg) {
        self.fcvt_int(Round::Up, true, rd, vn);
    }

    /// `fcvtns rd, vn`: to nearest, ties to even, signed.
    pub fn fcvtns(&mut self, rd: Reg, vn: VReg) {
        self.fcvt_int(Round::Nearest, true, rd, vn);
    }

    /// `fcvtas rd, vn`: to nearest, ties away from zero, signed.
    pub fn fcvtas(&mut self, rd: Reg, vn: VReg) {
        self.fcvt_int(Round::Away, true, rd, vn);
    }

    // ----- system -------------------------------------------------------

    /// `nop`.
    pub fn nop(&mut self) {
        self.emit(NOP);
    }

    /// `brk #imm`: breakpoint (SIGTRAP).
    pub fn brk(&mut self, imm: u16) {
        self.emit(0xD420_0000 | (imm as u32) << 5);
    }

    /// `udf #imm`: permanently undefined (SIGILL).
    pub fn udf(&mut self, imm: u16) {
        self.emit(imm as u32);
    }

    /// `svc #imm`: system call (Linux uses `#0`, Darwin `#0x80`).
    pub fn svc(&mut self, imm: u16) {
        self.emit(0xD400_0001 | (imm as u32) << 5);
    }

    /// `dmb ish`: data memory barrier, inner shareable.
    pub fn dmb_ish(&mut self) {
        self.emit(0xD503_3BBF);
    }

    /// `dsb ish`: data synchronization barrier, inner shareable.
    pub fn dsb_ish(&mut self) {
        self.emit(0xD503_3B9F);
    }

    /// `isb`: instruction synchronization barrier.
    pub fn isb(&mut self) {
        self.emit(0xD503_3FDF);
    }

    /// `mrs xt, sysreg`: read a system register.
    pub fn mrs(&mut self, rt: Reg, sr: SysReg) {
        self.run("mrs", |a| {
            need_x(rt)?;
            a.emit(0xD530_0000 | sr.encoding() << 5 | zr(rt)?);
            Ok(())
        });
    }

    /// `msr sysreg, xt`: write a system register.
    pub fn msr(&mut self, sr: SysReg, rt: Reg) {
        self.run("msr", |a| {
            need_x(rt)?;
            a.emit(0xD510_0000 | sr.encoding() << 5 | zr(rt)?);
            Ok(())
        });
    }
}
