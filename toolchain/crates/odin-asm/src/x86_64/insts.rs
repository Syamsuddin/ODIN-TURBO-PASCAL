// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Instruction methods of [`Assembler`].
//!
//! Encodings follow the Intel SDM and match what LLVM (`clang -c`) emits for
//! the same Intel-syntax instruction, including its choice among equivalent
//! forms: the `rm, reg` opcode for register-to-register ALU/`mov`/`test`, the
//! short accumulator forms (`add eax, imm32` as `05 id`, `test al, imm8` as
//! `A8 ib`), sign-extended imm8 whenever the value fits, `shl r, 1` as `D1`,
//! and `xchg rax, r` as `90+r`.

use super::assembler::{Assembler, EncResult, RmArg, rex8};
use super::operand::{AluOp, BitOp, Cond, Fp, FpLogic, FpOp, Operand, Reg, ShiftOp, Target, UnaryOp, Width, Xmm};
use crate::object::RelocKind;

/// `(legacy prefix, REX.W)` for an integer operand width.
fn opsize(w: Width) -> (Option<u8>, bool) {
    match w {
        Width::W16 => (Some(0x66), false),
        Width::W64 => (None, true),
        _ => (None, false),
    }
}

/// Checks that `v` fits an immediate of width `w` (signed or unsigned; at
/// 64 bits, a sign-extended 32-bit value) and returns it sign-extended from
/// that width.
fn imm_in(w: Width, v: i64) -> Result<i64, String> {
    let (lo, hi) = match w {
        Width::W8 => (-0x80, 0xFF),
        Width::W16 => (-0x8000, 0xFFFF),
        Width::W32 => (i32::MIN as i64, u32::MAX as i64),
        Width::W64 => (i32::MIN as i64, i32::MAX as i64),
    };
    if v < lo || v > hi {
        return Err(if w == Width::W64 {
            format!("immediate {v} does not fit in a sign-extended 32-bit field")
        } else {
            format!("immediate {v} does not fit in {} bits", w.bits())
        });
    }
    Ok(match w {
        Width::W8 => v as i8 as i64,
        Width::W16 => v as i16 as i64,
        _ => v as i32 as i64,
    })
}

/// Little-endian bytes of an immediate of width `w` (4 bytes at 64 bits).
fn imm_bytes(w: Width, v: i64) -> Vec<u8> {
    match w {
        Width::W8 => vec![v as u8],
        Width::W16 => (v as u16).to_le_bytes().to_vec(),
        _ => (v as u32).to_le_bytes().to_vec(),
    }
}

fn fits_i8(v: i64) -> bool {
    i8::try_from(v).is_ok()
}

/// A general-purpose register or memory operand as ModRM r/m.
fn gpr_rm(op: &Operand) -> Option<RmArg<'_>> {
    match op {
        Operand::Reg(r) => Some(RmArg::Reg(r.index())),
        Operand::Mem(m) => Some(RmArg::Mem(m)),
        _ => None,
    }
}

/// An xmm register or memory operand as ModRM r/m.
fn xmm_rm(op: &Operand) -> Option<RmArg<'_>> {
    match op {
        Operand::Xmm(x) => Some(RmArg::Reg(x.index())),
        Operand::Mem(m) => Some(RmArg::Mem(m)),
        _ => None,
    }
}

/// Whether `op` is `spl`/`bpl`/`sil`/`dil` when used as an 8-bit operand.
fn rex8_op(op: &Operand) -> bool {
    matches!(op, Operand::Reg(r) if rex8(r.index()))
}

fn bad(ops: &[&Operand]) -> String {
    let kinds: Vec<&str> = ops.iter().map(|o| o.kind_name()).collect();
    format!("invalid operands ({})", kinds.join(", "))
}

fn no_byte(w: Width) -> EncResult {
    if w == Width::W8 { Err("8-bit operands are not allowed".into()) } else { Ok(()) }
}

fn fp_prefix(fp: Fp) -> u8 {
    match fp {
        Fp::F32 => 0xF3,
        Fp::F64 => 0xF2,
    }
}

impl Assembler {
    // ----- data movement ------------------------------------------------

    /// `mov dst, src`: register to register, load, store, or immediate to
    /// register or memory.
    ///
    /// A 64-bit immediate to a register uses the sign-extended `mov r/m64,
    /// imm32` form when it fits and `movabs` otherwise; to memory it must fit
    /// a sign-extended 32-bit field. Note that `mov(W32, ..)` zero-extends
    /// into the full 64-bit register and is shorter for values below 2^32.
    pub fn mov(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        let (dst, src) = (dst.into(), src.into());
        self.run("mov", |a| a.enc_mov(w, &dst, &src));
    }

    fn enc_mov(&mut self, w: Width, dst: &Operand, src: &Operand) -> EncResult {
        let (pfx, rexw) = opsize(w);
        let byte = w == Width::W8;
        let ob = !byte as u8;
        match (dst, src) {
            (Operand::Reg(_) | Operand::Mem(_), Operand::Reg(s)) => {
                let force = byte && (rex8(s.index()) || rex8_op(dst));
                self.modrm(pfx, rexw, force, &[0x88 | ob], s.index(), gpr_rm(dst).unwrap(), &[])
            }
            (Operand::Reg(d), Operand::Mem(m)) => {
                self.modrm(pfx, rexw, byte && rex8(d.index()), &[0x8A | ob], d.index(), RmArg::Mem(m), &[])
            }
            (Operand::Reg(d), Operand::Imm(v)) if w == Width::W64 => {
                match imm_in(Width::W64, *v) {
                    Ok(v) => self.modrm(None, true, false, &[0xC7], 0, RmArg::Reg(d.index()), &imm_bytes(w, v))?,
                    Err(_) => self.op_reg(None, true, false, 0xB8, *d, &v.to_le_bytes()),
                }
                Ok(())
            }
            (Operand::Reg(d), Operand::Imm(v)) => {
                let v = imm_in(w, *v)?;
                let op = if byte { 0xB0 } else { 0xB8 };
                self.op_reg(pfx, false, byte && rex8(d.index()), op, *d, &imm_bytes(w, v));
                Ok(())
            }
            (Operand::Mem(m), Operand::Imm(v)) => {
                let v = imm_in(w, *v)?;
                self.modrm(pfx, rexw, false, &[0xC6 | ob], 0, RmArg::Mem(m), &imm_bytes(w, v))
            }
            _ => Err(bad(&[dst, src])),
        }
    }

    /// `movabs dst, imm64`: always the 10-byte `REX.W B8+r io` form.
    pub fn movabs(&mut self, dst: Reg, imm: i64) {
        self.op_reg(None, true, false, 0xB8, dst, &imm.to_le_bytes());
    }

    /// `movzx dst, src`: zero-extends an 8- or 16-bit register or memory
    /// operand into a 16-, 32- or 64-bit register. (For 32 → 64 bits use
    /// `mov(W32, ..)`, which zero-extends.)
    pub fn movzx(&mut self, dst_w: Width, dst: Reg, src_w: Width, src: impl Into<Operand>) {
        let src = src.into();
        self.run("movzx", |a| a.enc_extend(0xB6, dst_w, dst, src_w, &src));
    }

    /// `movsx dst, src`: sign-extends an 8- or 16-bit register or memory
    /// operand into a 16-, 32- or 64-bit register. For 32 → 64 bits use
    /// [`movsxd`](Assembler::movsxd).
    pub fn movsx(&mut self, dst_w: Width, dst: Reg, src_w: Width, src: impl Into<Operand>) {
        let src = src.into();
        self.run("movsx", |a| a.enc_extend(0xBE, dst_w, dst, src_w, &src));
    }

    fn enc_extend(&mut self, base: u8, dst_w: Width, dst: Reg, src_w: Width, src: &Operand) -> EncResult {
        if !matches!(src_w, Width::W8 | Width::W16) || dst_w <= src_w {
            return Err(format!("cannot extend {} bits to {} bits", src_w.bits(), dst_w.bits()));
        }
        let rm = gpr_rm(src).ok_or_else(|| bad(&[&Operand::Reg(dst), src]))?;
        let (pfx, rexw) = opsize(dst_w);
        let op = base | (src_w == Width::W16) as u8;
        self.modrm(pfx, rexw, src_w == Width::W8 && rex8_op(src), &[0x0F, op], dst.index(), rm, &[])
    }

    /// `movsxd dst, src`: sign-extends a 32-bit register or memory operand
    /// into a 64-bit register.
    pub fn movsxd(&mut self, dst: Reg, src: impl Into<Operand>) {
        let src = src.into();
        self.run("movsxd", |a| {
            let rm = gpr_rm(&src).ok_or_else(|| bad(&[&Operand::Reg(dst), &src]))?;
            a.modrm(None, true, false, &[0x63], dst.index(), rm, &[])
        });
    }

    /// `lea dst, [mem]` at 16, 32 or 64 bits.
    pub fn lea(&mut self, w: Width, dst: Reg, src: impl Into<Operand>) {
        let src = src.into();
        self.run("lea", |a| {
            no_byte(w)?;
            let Operand::Mem(m) = &src else { return Err(bad(&[&Operand::Reg(dst), &src])) };
            let (pfx, rexw) = opsize(w);
            a.modrm(pfx, rexw, false, &[0x8D], dst.index(), RmArg::Mem(m), &[])
        });
    }

    /// `xchg a, b` (register/register or register/memory, either order).
    pub fn xchg(&mut self, w: Width, a: impl Into<Operand>, b: impl Into<Operand>) {
        let (x, y) = (a.into(), b.into());
        self.run("xchg", |a| {
            let (pfx, rexw) = opsize(w);
            let byte = w == Width::W8;
            match (&x, &y) {
                (Operand::Reg(r), Operand::Reg(s))
                    if !byte && (*r == Reg::Rax || *s == Reg::Rax) && !(w == Width::W32 && r == s) =>
                {
                    // `xchg eax, eax` must not become `90` (nop), which would
                    // not clear the upper half of rax.
                    let other = if *r == Reg::Rax { *s } else { *r };
                    a.op_reg(pfx, rexw, false, 0x90, other, &[]);
                    Ok(())
                }
                (Operand::Reg(r), Operand::Reg(_) | Operand::Mem(_)) => {
                    let force = byte && (rex8(r.index()) || rex8_op(&y));
                    a.modrm(pfx, rexw, force, &[0x86 | !byte as u8], r.index(), gpr_rm(&y).unwrap(), &[])
                }
                (Operand::Mem(m), Operand::Reg(r)) => {
                    a.modrm(pfx, rexw, byte && rex8(r.index()), &[0x86 | !byte as u8], r.index(), RmArg::Mem(m), &[])
                }
                _ => Err(bad(&[&x, &y])),
            }
        });
    }

    /// `push src`: a 64-bit register, a 64-bit memory operand, or an
    /// immediate sign-extended from 8 or 32 bits.
    pub fn push(&mut self, src: impl Into<Operand>) {
        let src = src.into();
        self.run("push", |a| match &src {
            Operand::Reg(r) => {
                a.op_reg(None, false, false, 0x50, *r, &[]);
                Ok(())
            }
            Operand::Imm(v) => {
                let v = imm_in(Width::W64, *v)?;
                if fits_i8(v) {
                    a.plain(None, false, &[0x6A], &[v as u8]);
                } else {
                    a.plain(None, false, &[0x68], &(v as i32).to_le_bytes());
                }
                Ok(())
            }
            Operand::Mem(m) => a.modrm(None, false, false, &[0xFF], 6, RmArg::Mem(m), &[]),
            Operand::Xmm(_) => Err(bad(&[&src])),
        });
    }

    /// `pop dst`: a 64-bit register or memory operand.
    pub fn pop(&mut self, dst: impl Into<Operand>) {
        let dst = dst.into();
        self.run("pop", |a| match &dst {
            Operand::Reg(r) => {
                a.op_reg(None, false, false, 0x58, *r, &[]);
                Ok(())
            }
            Operand::Mem(m) => a.modrm(None, false, false, &[0x8F], 0, RmArg::Mem(m), &[]),
            _ => Err(bad(&[&dst])),
        });
    }

    /// `cmovcc dst, src` at 16, 32 or 64 bits.
    pub fn cmov(&mut self, cond: Cond, w: Width, dst: Reg, src: impl Into<Operand>) {
        let src = src.into();
        self.run("cmov", |a| {
            no_byte(w)?;
            let rm = gpr_rm(&src).ok_or_else(|| bad(&[&Operand::Reg(dst), &src]))?;
            let (pfx, rexw) = opsize(w);
            a.modrm(pfx, rexw, false, &[0x0F, 0x40 + cond.code()], dst.index(), rm, &[])
        });
    }

    /// `setcc dst`: an 8-bit register or byte in memory.
    pub fn setcc(&mut self, cond: Cond, dst: impl Into<Operand>) {
        let dst = dst.into();
        self.run("setcc", |a| {
            let rm = gpr_rm(&dst).ok_or_else(|| bad(&[&dst]))?;
            a.modrm(None, false, rex8_op(&dst), &[0x0F, 0x90 + cond.code()], 0, rm, &[])
        });
    }

    // ----- arithmetic and logic -------------------------------------------

    /// One of `add or adc sbb and sub xor cmp`: `reg, reg`, `reg, mem`,
    /// `mem, reg`, `reg, imm` or `mem, imm`. Immediates that fit in a signed
    /// byte use the short `83 /n ib` form.
    pub fn alu(&mut self, op: AluOp, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        let (dst, src) = (dst.into(), src.into());
        let name = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"][op as usize];
        self.run(name, |a| a.enc_alu(op, w, &dst, &src));
    }

    fn enc_alu(&mut self, op: AluOp, w: Width, dst: &Operand, src: &Operand) -> EncResult {
        let n = op as u8;
        let (pfx, rexw) = opsize(w);
        let byte = w == Width::W8;
        let ob = !byte as u8;
        match (dst, src) {
            (Operand::Reg(_) | Operand::Mem(_), Operand::Reg(s)) => {
                let force = byte && (rex8(s.index()) || rex8_op(dst));
                self.modrm(pfx, rexw, force, &[n << 3 | ob], s.index(), gpr_rm(dst).unwrap(), &[])
            }
            (Operand::Reg(d), Operand::Mem(m)) => {
                self.modrm(pfx, rexw, byte && rex8(d.index()), &[n << 3 | 2 | ob], d.index(), RmArg::Mem(m), &[])
            }
            (Operand::Reg(_) | Operand::Mem(_), Operand::Imm(v)) => {
                let v = imm_in(w, *v)?;
                let rm = gpr_rm(dst).unwrap();
                let acc = *dst == Operand::Reg(Reg::Rax);
                if byte {
                    if acc {
                        self.plain(None, false, &[n << 3 | 4], &[v as u8]);
                        Ok(())
                    } else {
                        self.modrm(None, false, rex8_op(dst), &[0x80], n, rm, &[v as u8])
                    }
                } else if fits_i8(v) {
                    self.modrm(pfx, rexw, false, &[0x83], n, rm, &[v as u8])
                } else if acc {
                    self.plain(pfx, rexw, &[n << 3 | 5], &imm_bytes(w, v));
                    Ok(())
                } else {
                    self.modrm(pfx, rexw, false, &[0x81], n, rm, &imm_bytes(w, v))
                }
            }
            _ => Err(bad(&[dst, src])),
        }
    }

    pub fn add(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Add, w, dst, src);
    }

    pub fn or(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Or, w, dst, src);
    }

    pub fn adc(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Adc, w, dst, src);
    }

    pub fn sbb(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Sbb, w, dst, src);
    }

    pub fn and(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::And, w, dst, src);
    }

    pub fn sub(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Sub, w, dst, src);
    }

    pub fn xor(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Xor, w, dst, src);
    }

    pub fn cmp(&mut self, w: Width, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.alu(AluOp::Cmp, w, dst, src);
    }

    /// `test a, b`: `reg/mem, reg` (either order) or `reg/mem, imm`.
    pub fn test(&mut self, w: Width, a: impl Into<Operand>, b: impl Into<Operand>) {
        let (x, y) = (a.into(), b.into());
        self.run("test", |a| {
            let (pfx, rexw) = opsize(w);
            let byte = w == Width::W8;
            let ob = !byte as u8;
            // `test` is symmetric: put a register operand in the reg field.
            let (rm_op, reg_op) = match (&x, &y) {
                (Operand::Reg(r), Operand::Mem(_)) => (&y, Some(*r)),
                (_, Operand::Reg(r)) => (&x, Some(*r)),
                _ => (&x, None),
            };
            match (reg_op, rm_op, &y) {
                (Some(r), Operand::Reg(_) | Operand::Mem(_), _) => {
                    let force = byte && (rex8(r.index()) || rex8_op(rm_op));
                    a.modrm(pfx, rexw, force, &[0x84 | ob], r.index(), gpr_rm(rm_op).unwrap(), &[])
                }
                (None, Operand::Reg(_) | Operand::Mem(_), Operand::Imm(v)) => {
                    let v = imm_in(w, *v)?;
                    if x == Operand::Reg(Reg::Rax) {
                        a.plain(pfx, rexw, &[0xA8 | ob], &imm_bytes(w, v));
                        Ok(())
                    } else {
                        a.modrm(pfx, rexw, byte && rex8_op(&x), &[0xF6 | ob], 0, gpr_rm(&x).unwrap(), &imm_bytes(w, v))
                    }
                }
                _ => Err(bad(&[&x, &y])),
            }
        });
    }

    /// Two-operand `imul dst, src` (16, 32 or 64 bits).
    pub fn imul(&mut self, w: Width, dst: Reg, src: impl Into<Operand>) {
        let src = src.into();
        self.run("imul", |a| {
            no_byte(w)?;
            if let Operand::Imm(v) = src {
                return a.enc_imul3(w, dst, &Operand::Reg(dst), v);
            }
            let rm = gpr_rm(&src).ok_or_else(|| bad(&[&Operand::Reg(dst), &src]))?;
            let (pfx, rexw) = opsize(w);
            a.modrm(pfx, rexw, false, &[0x0F, 0xAF], dst.index(), rm, &[])
        });
    }

    /// Three-operand `imul dst, src, imm` (16, 32 or 64 bits).
    pub fn imul3(&mut self, w: Width, dst: Reg, src: impl Into<Operand>, imm: i64) {
        let src = src.into();
        self.run("imul", |a| {
            no_byte(w)?;
            a.enc_imul3(w, dst, &src, imm)
        });
    }

    fn enc_imul3(&mut self, w: Width, dst: Reg, src: &Operand, imm: i64) -> EncResult {
        let rm = gpr_rm(src).ok_or_else(|| bad(&[&Operand::Reg(dst), src]))?;
        let v = imm_in(w, imm)?;
        let (pfx, rexw) = opsize(w);
        if fits_i8(v) {
            self.modrm(pfx, rexw, false, &[0x6B], dst.index(), rm, &[v as u8])
        } else {
            self.modrm(pfx, rexw, false, &[0x69], dst.index(), rm, &imm_bytes(w, v))
        }
    }

    /// One-operand `not neg mul imul div idiv inc dec` on a register or
    /// memory operand.
    pub fn unary(&mut self, op: UnaryOp, w: Width, operand: impl Into<Operand>) {
        let x = operand.into();
        let (name, opc, ext) = match op {
            UnaryOp::Not => ("not", 0xF6, 2),
            UnaryOp::Neg => ("neg", 0xF6, 3),
            UnaryOp::Mul => ("mul", 0xF6, 4),
            UnaryOp::Imul => ("imul", 0xF6, 5),
            UnaryOp::Div => ("div", 0xF6, 6),
            UnaryOp::Idiv => ("idiv", 0xF6, 7),
            UnaryOp::Inc => ("inc", 0xFE, 0),
            UnaryOp::Dec => ("dec", 0xFE, 1),
        };
        self.run(name, |a| {
            let rm = gpr_rm(&x).ok_or_else(|| bad(&[&x]))?;
            let (pfx, rexw) = opsize(w);
            let byte = w == Width::W8;
            a.modrm(pfx, rexw, byte && rex8_op(&x), &[opc | !byte as u8], ext, rm, &[])
        });
    }

    pub fn not(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Not, w, operand);
    }

    pub fn neg(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Neg, w, operand);
    }

    /// Unsigned `rdx:rax = rax * operand` (`ax = al * operand` at 8 bits).
    pub fn mul(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Mul, w, operand);
    }

    /// One-operand signed `rdx:rax = rax * operand`.
    pub fn imul1(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Imul, w, operand);
    }

    /// Unsigned divide of `rdx:rax` by the operand: quotient in rax,
    /// remainder in rdx.
    pub fn div(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Div, w, operand);
    }

    /// Signed divide of `rdx:rax` by the operand (prepare rdx with
    /// [`cqo`](Assembler::cqo) / [`cdq`](Assembler::cdq)).
    pub fn idiv(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Idiv, w, operand);
    }

    pub fn inc(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Inc, w, operand);
    }

    pub fn dec(&mut self, w: Width, operand: impl Into<Operand>) {
        self.unary(UnaryOp::Dec, w, operand);
    }

    /// A shift or rotate of a register or memory operand. `count` is an
    /// immediate (0–255; 1 uses the short `D1` form) or `Reg::Rcx`, meaning
    /// `cl`.
    pub fn shift(&mut self, op: ShiftOp, w: Width, dst: impl Into<Operand>, count: impl Into<Operand>) {
        let (dst, count) = (dst.into(), count.into());
        let name = ["rol", "ror", "rcl", "rcr", "shl", "shr", "sal", "sar"][op as usize];
        self.run(name, |a| {
            let rm = gpr_rm(&dst).ok_or_else(|| bad(&[&dst, &count]))?;
            let (pfx, rexw) = opsize(w);
            let byte = w == Width::W8;
            let force = byte && rex8_op(&dst);
            let ob = !byte as u8;
            match count {
                Operand::Imm(1) => a.modrm(pfx, rexw, force, &[0xD0 | ob], op as u8, rm, &[]),
                Operand::Imm(n @ 0..=255) => a.modrm(pfx, rexw, force, &[0xC0 | ob], op as u8, rm, &[n as u8]),
                Operand::Imm(n) => Err(format!("shift count {n} does not fit in 8 bits")),
                Operand::Reg(Reg::Rcx) => a.modrm(pfx, rexw, force, &[0xD2 | ob], op as u8, rm, &[]),
                _ => Err("the shift count must be an immediate or cl".into()),
            }
        });
    }

    pub fn shl(&mut self, w: Width, dst: impl Into<Operand>, count: impl Into<Operand>) {
        self.shift(ShiftOp::Shl, w, dst, count);
    }

    pub fn shr(&mut self, w: Width, dst: impl Into<Operand>, count: impl Into<Operand>) {
        self.shift(ShiftOp::Shr, w, dst, count);
    }

    pub fn sar(&mut self, w: Width, dst: impl Into<Operand>, count: impl Into<Operand>) {
        self.shift(ShiftOp::Sar, w, dst, count);
    }

    pub fn rol(&mut self, w: Width, dst: impl Into<Operand>, count: impl Into<Operand>) {
        self.shift(ShiftOp::Rol, w, dst, count);
    }

    pub fn ror(&mut self, w: Width, dst: impl Into<Operand>, count: impl Into<Operand>) {
        self.shift(ShiftOp::Ror, w, dst, count);
    }

    /// `cbw`: al → ax, sign-extended.
    pub fn cbw(&mut self) {
        self.plain(Some(0x66), false, &[0x98], &[]);
    }

    /// `cwde`: ax → eax, sign-extended.
    pub fn cwde(&mut self) {
        self.plain(None, false, &[0x98], &[]);
    }

    /// `cdqe`: eax → rax, sign-extended.
    pub fn cdqe(&mut self) {
        self.plain(None, true, &[0x98], &[]);
    }

    /// `cwd`: dx:ax = ax, sign-extended.
    pub fn cwd(&mut self) {
        self.plain(Some(0x66), false, &[0x99], &[]);
    }

    /// `cdq`: edx:eax = eax, sign-extended.
    pub fn cdq(&mut self) {
        self.plain(None, false, &[0x99], &[]);
    }

    /// `cqo`: rdx:rax = rax, sign-extended.
    pub fn cqo(&mut self) {
        self.plain(None, true, &[0x99], &[]);
    }

    /// `bt bts btr btc base, bit` at 16, 32 or 64 bits. `bit` is a register
    /// or an immediate (0–255). With a memory base and a register bit index,
    /// the index may address bits beyond the operand (a bit string), which
    /// suits Pascal sets.
    pub fn bit(&mut self, op: BitOp, w: Width, base: impl Into<Operand>, bit: impl Into<Operand>) {
        let (base, bit) = (base.into(), bit.into());
        let (name, reg_op, ext) = match op {
            BitOp::Bt => ("bt", 0xA3, 4),
            BitOp::Bts => ("bts", 0xAB, 5),
            BitOp::Btr => ("btr", 0xB3, 6),
            BitOp::Btc => ("btc", 0xBB, 7),
        };
        self.run(name, |a| {
            no_byte(w)?;
            let rm = gpr_rm(&base).ok_or_else(|| bad(&[&base, &bit]))?;
            let (pfx, rexw) = opsize(w);
            match bit {
                Operand::Reg(r) => a.modrm(pfx, rexw, false, &[0x0F, reg_op], r.index(), rm, &[]),
                Operand::Imm(n @ 0..=255) => a.modrm(pfx, rexw, false, &[0x0F, 0xBA], ext, rm, &[n as u8]),
                Operand::Imm(n) => Err(format!("bit index {n} does not fit in 8 bits")),
                _ => Err(bad(&[&base, &bit])),
            }
        });
    }

    pub fn bt(&mut self, w: Width, base: impl Into<Operand>, bit: impl Into<Operand>) {
        self.bit(BitOp::Bt, w, base, bit);
    }

    pub fn bts(&mut self, w: Width, base: impl Into<Operand>, bit: impl Into<Operand>) {
        self.bit(BitOp::Bts, w, base, bit);
    }

    pub fn btr(&mut self, w: Width, base: impl Into<Operand>, bit: impl Into<Operand>) {
        self.bit(BitOp::Btr, w, base, bit);
    }

    pub fn btc(&mut self, w: Width, base: impl Into<Operand>, bit: impl Into<Operand>) {
        self.bit(BitOp::Btc, w, base, bit);
    }

    // ----- string instructions --------------------------------------------

    fn string_op(&mut self, rep: bool, opcode: u8, w: Width) {
        if rep {
            self.bytes(&[0xF3]);
        }
        let (pfx, rexw) = opsize(w);
        self.plain(pfx, rexw, &[opcode | (w != Width::W8) as u8], &[]);
    }

    /// `movsb`/`movsw`/`movsd`/`movsq`: copy one element from `[rsi]` to
    /// `[rdi]`.
    pub fn movs(&mut self, w: Width) {
        self.string_op(false, 0xA4, w);
    }

    /// `rep movsb` (and wider): copy `rcx` elements from `[rsi]` to `[rdi]`.
    pub fn rep_movs(&mut self, w: Width) {
        self.string_op(true, 0xA4, w);
    }

    /// `stosb`/`stosw`/`stosd`/`stosq`: store al/ax/eax/rax at `[rdi]`.
    pub fn stos(&mut self, w: Width) {
        self.string_op(false, 0xAA, w);
    }

    /// `rep stosb` (and wider): store `rcx` copies of al/ax/eax/rax at
    /// `[rdi]`.
    pub fn rep_stos(&mut self, w: Width) {
        self.string_op(true, 0xAA, w);
    }

    // ----- control flow -------------------------------------------------

    /// `call target`: rel32 to a label or symbol, or indirect through a
    /// 64-bit register or memory operand (e.g. `Mem::got("_write")`).
    pub fn call(&mut self, target: impl Into<Target>) {
        let target = target.into();
        self.run("call", |a| match &target {
            Target::Label(l) => {
                a.plain(None, false, &[0xE8], &[]);
                a.label_rel32(*l, 0, 4)
            }
            Target::Sym(s) => {
                a.plain(None, false, &[0xE8], &[]);
                a.reloc_field(RelocKind::X86Pc32, s.clone(), -4, 4);
                Ok(())
            }
            Target::Indirect(op) => {
                let rm = gpr_rm(op).ok_or_else(|| bad(&[op]))?;
                a.modrm(None, false, false, &[0xFF], 2, rm, &[])
            }
        });
    }

    /// `jmp target`: to a label (short or near, chosen by
    /// [`finish`](Assembler::finish)), rel32 to a symbol (tail call), or
    /// indirect through a 64-bit register or memory operand.
    pub fn jmp(&mut self, target: impl Into<Target>) {
        let target = target.into();
        self.run("jmp", |a| match &target {
            Target::Label(l) => a.jump_var(None, *l),
            Target::Sym(s) => {
                a.plain(None, false, &[0xE9], &[]);
                a.reloc_field(RelocKind::X86Pc32, s.clone(), -4, 4);
                Ok(())
            }
            Target::Indirect(op) => {
                let rm = gpr_rm(op).ok_or_else(|| bad(&[op]))?;
                a.modrm(None, false, false, &[0xFF], 4, rm, &[])
            }
        });
    }

    /// `jcc target`: to a label (short or near) or, near only, to a symbol.
    pub fn jcc(&mut self, cond: Cond, target: impl Into<Target>) {
        let target = target.into();
        self.run("jcc", |a| match &target {
            Target::Label(l) => a.jump_var(Some(cond), *l),
            Target::Sym(s) => {
                a.plain(None, false, &[0x0F, 0x80 + cond.code()], &[]);
                a.reloc_field(RelocKind::X86Pc32, s.clone(), -4, 4);
                Ok(())
            }
            Target::Indirect(_) => Err("conditional jumps cannot be indirect".into()),
        });
    }

    pub fn ret(&mut self) {
        self.bytes(&[0xC3]);
    }

    /// `ret imm16`: return and pop `bytes` bytes of arguments.
    pub fn ret_imm(&mut self, bytes: u16) {
        self.plain(None, false, &[0xC2], &bytes.to_le_bytes());
    }

    pub fn leave(&mut self) {
        self.bytes(&[0xC9]);
    }

    /// One-byte `nop`. See [`nops`](Assembler::nops) and
    /// [`align`](Assembler::align) for padding.
    pub fn nop(&mut self) {
        self.bytes(&[0x90]);
    }

    pub fn ud2(&mut self) {
        self.bytes(&[0x0F, 0x0B]);
    }

    pub fn int3(&mut self) {
        self.bytes(&[0xCC]);
    }

    pub fn cld(&mut self) {
        self.bytes(&[0xFC]);
    }

    pub fn syscall(&mut self) {
        self.bytes(&[0x0F, 0x05]);
    }

    /// `ldmxcsr m32`: load the SSE control/status register from memory.
    pub fn ldmxcsr(&mut self, src: impl Into<Operand>) {
        self.mxcsr("ldmxcsr", 2, src.into());
    }

    /// `stmxcsr m32`: store the SSE control/status register to memory.
    pub fn stmxcsr(&mut self, dst: impl Into<Operand>) {
        self.mxcsr("stmxcsr", 3, dst.into());
    }

    fn mxcsr(&mut self, name: &str, ext: u8, x: Operand) {
        self.run(name, |a| {
            let Operand::Mem(m) = &x else { return Err(bad(&[&x])) };
            a.modrm(None, false, false, &[0x0F, 0xAE], ext, RmArg::Mem(m), &[])
        });
    }

    // ----- SSE scalar floating point ------------------------------------------

    /// A move with a load/register form and a store form.
    fn xmov(&mut self, name: &str, pfx: Option<u8>, load: u8, store: u8, dst: Operand, src: Operand) {
        self.run(name, |a| match (&dst, &src) {
            (Operand::Xmm(d), Operand::Xmm(_) | Operand::Mem(_)) => {
                a.modrm(pfx, false, false, &[0x0F, load], d.index(), xmm_rm(&src).unwrap(), &[])
            }
            (Operand::Mem(m), Operand::Xmm(s)) => {
                a.modrm(pfx, false, false, &[0x0F, store], s.index(), RmArg::Mem(m), &[])
            }
            _ => Err(bad(&[&dst, &src])),
        });
    }

    /// `movsd dst, src`: xmm ← xmm (low 64 bits; the upper half of `dst` is
    /// kept), xmm ← m64 (upper half zeroed), or m64 ← xmm.
    pub fn movsd(&mut self, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.xmov("movsd", Some(0xF2), 0x10, 0x11, dst.into(), src.into());
    }

    /// `movss dst, src`: like [`movsd`](Assembler::movsd) for 32-bit floats.
    pub fn movss(&mut self, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.xmov("movss", Some(0xF3), 0x10, 0x11, dst.into(), src.into());
    }

    /// `movapd dst, src`: full 128-bit move (memory must be 16-byte aligned).
    /// The usual way to copy one xmm register to another.
    pub fn movapd(&mut self, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.xmov("movapd", Some(0x66), 0x28, 0x29, dst.into(), src.into());
    }

    /// `movaps dst, src`: like [`movapd`](Assembler::movapd), one byte shorter.
    pub fn movaps(&mut self, dst: impl Into<Operand>, src: impl Into<Operand>) {
        self.xmov("movaps", None, 0x28, 0x29, dst.into(), src.into());
    }

    /// Scalar `add sub mul div sqrt min max` (`sd` or `ss`): `dst op= src`,
    /// with `src` an xmm register or memory.
    pub fn fp_arith(&mut self, op: FpOp, fp: Fp, dst: Xmm, src: impl Into<Operand>) {
        let src = src.into();
        let (name, opc) = match op {
            FpOp::Sqrt => ("sqrt", 0x51),
            FpOp::Add => ("add", 0x58),
            FpOp::Mul => ("mul", 0x59),
            FpOp::Sub => ("sub", 0x5C),
            FpOp::Min => ("min", 0x5D),
            FpOp::Div => ("div", 0x5E),
            FpOp::Max => ("max", 0x5F),
        };
        let name = format!("{name}{}", if fp == Fp::F64 { "sd" } else { "ss" });
        self.run(&name, |a| {
            let rm = xmm_rm(&src).ok_or_else(|| bad(&[&Operand::Xmm(dst), &src]))?;
            a.modrm(Some(fp_prefix(fp)), false, false, &[0x0F, opc], dst.index(), rm, &[])
        });
    }

    pub fn addsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Add, Fp::F64, dst, src);
    }

    pub fn subsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Sub, Fp::F64, dst, src);
    }

    pub fn mulsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Mul, Fp::F64, dst, src);
    }

    pub fn divsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Div, Fp::F64, dst, src);
    }

    pub fn sqrtsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Sqrt, Fp::F64, dst, src);
    }

    pub fn minsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Min, Fp::F64, dst, src);
    }

    pub fn maxsd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Max, Fp::F64, dst, src);
    }

    pub fn addss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Add, Fp::F32, dst, src);
    }

    pub fn subss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Sub, Fp::F32, dst, src);
    }

    pub fn mulss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Mul, Fp::F32, dst, src);
    }

    pub fn divss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Div, Fp::F32, dst, src);
    }

    pub fn sqrtss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Sqrt, Fp::F32, dst, src);
    }

    pub fn minss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Min, Fp::F32, dst, src);
    }

    pub fn maxss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_arith(FpOp::Max, Fp::F32, dst, src);
    }

    /// `ucomisd`/`ucomiss` (`ordered == false`) or `comisd`/`comiss`: compare
    /// and set ZF, PF, CF like an unsigned compare; PF = 1 means unordered
    /// (a NaN). `comis*` also raises the invalid exception on quiet NaNs.
    pub fn fp_compare(&mut self, fp: Fp, ordered: bool, a: Xmm, b: impl Into<Operand>) {
        let b = b.into();
        let name = match (ordered, fp) {
            (false, Fp::F64) => "ucomisd",
            (false, Fp::F32) => "ucomiss",
            (true, Fp::F64) => "comisd",
            (true, Fp::F32) => "comiss",
        };
        self.run(name, |asm| {
            let rm = xmm_rm(&b).ok_or_else(|| bad(&[&Operand::Xmm(a), &b]))?;
            let pfx = (fp == Fp::F64).then_some(0x66);
            asm.modrm(pfx, false, false, &[0x0F, 0x2E | ordered as u8], a.index(), rm, &[])
        });
    }

    pub fn ucomisd(&mut self, a: Xmm, b: impl Into<Operand>) {
        self.fp_compare(Fp::F64, false, a, b);
    }

    pub fn comisd(&mut self, a: Xmm, b: impl Into<Operand>) {
        self.fp_compare(Fp::F64, true, a, b);
    }

    pub fn ucomiss(&mut self, a: Xmm, b: impl Into<Operand>) {
        self.fp_compare(Fp::F32, false, a, b);
    }

    pub fn comiss(&mut self, a: Xmm, b: impl Into<Operand>) {
        self.fp_compare(Fp::F32, true, a, b);
    }

    /// `cvtsi2sd`/`cvtsi2ss dst, src`: convert a signed 32- or 64-bit integer
    /// (register or memory, of width `src_w`) to floating point.
    pub fn cvtsi2fp(&mut self, fp: Fp, dst: Xmm, src_w: Width, src: impl Into<Operand>) {
        let src = src.into();
        let name = if fp == Fp::F64 { "cvtsi2sd" } else { "cvtsi2ss" };
        self.run(name, |a| {
            if !matches!(src_w, Width::W32 | Width::W64) {
                return Err("the integer operand must be 32 or 64 bits".into());
            }
            let rm = gpr_rm(&src).ok_or_else(|| bad(&[&Operand::Xmm(dst), &src]))?;
            a.modrm(Some(fp_prefix(fp)), src_w == Width::W64, false, &[0x0F, 0x2A], dst.index(), rm, &[])
        });
    }

    pub fn cvtsi2sd(&mut self, dst: Xmm, src_w: Width, src: impl Into<Operand>) {
        self.cvtsi2fp(Fp::F64, dst, src_w, src);
    }

    pub fn cvtsi2ss(&mut self, dst: Xmm, src_w: Width, src: impl Into<Operand>) {
        self.cvtsi2fp(Fp::F32, dst, src_w, src);
    }

    /// `cvt(t)sd2si`/`cvt(t)ss2si dst, src`: convert to a signed 32- or
    /// 64-bit integer, truncating toward zero (`truncate`, Pascal `Trunc`) or
    /// with the MXCSR rounding mode (round to nearest even by default).
    pub fn cvtfp2si(&mut self, fp: Fp, truncate: bool, dst_w: Width, dst: Reg, src: impl Into<Operand>) {
        let src = src.into();
        let name = match (truncate, fp) {
            (true, Fp::F64) => "cvttsd2si",
            (false, Fp::F64) => "cvtsd2si",
            (true, Fp::F32) => "cvttss2si",
            (false, Fp::F32) => "cvtss2si",
        };
        self.run(name, |a| {
            if !matches!(dst_w, Width::W32 | Width::W64) {
                return Err("the integer operand must be 32 or 64 bits".into());
            }
            let rm = xmm_rm(&src).ok_or_else(|| bad(&[&Operand::Reg(dst), &src]))?;
            let opc = if truncate { 0x2C } else { 0x2D };
            a.modrm(Some(fp_prefix(fp)), dst_w == Width::W64, false, &[0x0F, opc], dst.index(), rm, &[])
        });
    }

    pub fn cvttsd2si(&mut self, dst_w: Width, dst: Reg, src: impl Into<Operand>) {
        self.cvtfp2si(Fp::F64, true, dst_w, dst, src);
    }

    pub fn cvtsd2si(&mut self, dst_w: Width, dst: Reg, src: impl Into<Operand>) {
        self.cvtfp2si(Fp::F64, false, dst_w, dst, src);
    }

    pub fn cvttss2si(&mut self, dst_w: Width, dst: Reg, src: impl Into<Operand>) {
        self.cvtfp2si(Fp::F32, true, dst_w, dst, src);
    }

    pub fn cvtss2si(&mut self, dst_w: Width, dst: Reg, src: impl Into<Operand>) {
        self.cvtfp2si(Fp::F32, false, dst_w, dst, src);
    }

    /// `cvtss2sd dst, src`: single to double.
    pub fn cvtss2sd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        let src = src.into();
        self.run("cvtss2sd", |a| {
            let rm = xmm_rm(&src).ok_or_else(|| bad(&[&Operand::Xmm(dst), &src]))?;
            a.modrm(Some(0xF3), false, false, &[0x0F, 0x5A], dst.index(), rm, &[])
        });
    }

    /// `cvtsd2ss dst, src`: double to single.
    pub fn cvtsd2ss(&mut self, dst: Xmm, src: impl Into<Operand>) {
        let src = src.into();
        self.run("cvtsd2ss", |a| {
            let rm = xmm_rm(&src).ok_or_else(|| bad(&[&Operand::Xmm(dst), &src]))?;
            a.modrm(Some(0xF2), false, false, &[0x0F, 0x5A], dst.index(), rm, &[])
        });
    }

    /// `movq dst, src`: 64 bits between a general-purpose register and an
    /// xmm register (either way), xmm ← m64, m64 ← xmm, or xmm ← xmm (both
    /// zero the upper half of an xmm destination).
    pub fn movq(&mut self, dst: impl Into<Operand>, src: impl Into<Operand>) {
        let (dst, src) = (dst.into(), src.into());
        self.run("movq", |a| match (&dst, &src) {
            (Operand::Xmm(x), Operand::Reg(r)) => {
                a.modrm(Some(0x66), true, false, &[0x0F, 0x6E], x.index(), RmArg::Reg(r.index()), &[])
            }
            (Operand::Reg(r), Operand::Xmm(x)) => {
                a.modrm(Some(0x66), true, false, &[0x0F, 0x7E], x.index(), RmArg::Reg(r.index()), &[])
            }
            (Operand::Xmm(x), Operand::Xmm(_) | Operand::Mem(_)) => {
                a.modrm(Some(0xF3), false, false, &[0x0F, 0x7E], x.index(), xmm_rm(&src).unwrap(), &[])
            }
            (Operand::Mem(m), Operand::Xmm(x)) => {
                a.modrm(Some(0x66), false, false, &[0x0F, 0xD6], x.index(), RmArg::Mem(m), &[])
            }
            _ => Err(bad(&[&dst, &src])),
        });
    }

    /// `movd dst, src`: 32 bits between a general-purpose register or memory
    /// and an xmm register (either way).
    pub fn movd(&mut self, dst: impl Into<Operand>, src: impl Into<Operand>) {
        let (dst, src) = (dst.into(), src.into());
        self.run("movd", |a| match (&dst, &src) {
            (Operand::Xmm(x), Operand::Reg(_) | Operand::Mem(_)) => {
                a.modrm(Some(0x66), false, false, &[0x0F, 0x6E], x.index(), gpr_rm(&src).unwrap(), &[])
            }
            (Operand::Reg(_) | Operand::Mem(_), Operand::Xmm(x)) => {
                a.modrm(Some(0x66), false, false, &[0x0F, 0x7E], x.index(), gpr_rm(&dst).unwrap(), &[])
            }
            _ => Err(bad(&[&dst, &src])),
        });
    }

    /// Packed bitwise `and andn or xor` (`pd` for [`Fp::F64`], `ps` for
    /// [`Fp::F32`]): with a sign-mask constant, `xorpd` negates and `andpd`
    /// takes the absolute value. A memory operand must be 16-byte aligned.
    pub fn fp_logic(&mut self, op: FpLogic, fp: Fp, dst: Xmm, src: impl Into<Operand>) {
        let src = src.into();
        let (name, opc) = match op {
            FpLogic::And => ("and", 0x54),
            FpLogic::AndNot => ("andn", 0x55),
            FpLogic::Or => ("or", 0x56),
            FpLogic::Xor => ("xor", 0x57),
        };
        let name = format!("{name}{}", if fp == Fp::F64 { "pd" } else { "ps" });
        self.run(&name, |a| {
            let rm = xmm_rm(&src).ok_or_else(|| bad(&[&Operand::Xmm(dst), &src]))?;
            let pfx = (fp == Fp::F64).then_some(0x66);
            a.modrm(pfx, false, false, &[0x0F, opc], dst.index(), rm, &[])
        });
    }

    pub fn andpd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::And, Fp::F64, dst, src);
    }

    pub fn andnpd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::AndNot, Fp::F64, dst, src);
    }

    pub fn orpd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::Or, Fp::F64, dst, src);
    }

    pub fn xorpd(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::Xor, Fp::F64, dst, src);
    }

    pub fn andps(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::And, Fp::F32, dst, src);
    }

    pub fn andnps(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::AndNot, Fp::F32, dst, src);
    }

    pub fn orps(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::Or, Fp::F32, dst, src);
    }

    pub fn xorps(&mut self, dst: Xmm, src: impl Into<Operand>) {
        self.fp_logic(FpLogic::Xor, Fp::F32, dst, src);
    }

    /// `roundsd`/`roundss dst, src, mode` (SSE4.1) with a mode from
    /// [`round`](super::round). Every Mac with an x86-64 CPU has SSE4.1 (the
    /// oldest, Core 2 "Penryn" based models, already do), so no fallback is
    /// needed for `Int`, `Trunc`, `Round` and friends.
    pub fn fp_round(&mut self, fp: Fp, dst: Xmm, src: impl Into<Operand>, mode: u8) {
        let src = src.into();
        let name = if fp == Fp::F64 { "roundsd" } else { "roundss" };
        self.run(name, |a| {
            let rm = xmm_rm(&src).ok_or_else(|| bad(&[&Operand::Xmm(dst), &src]))?;
            let opc = if fp == Fp::F64 { 0x0B } else { 0x0A };
            a.modrm(Some(0x66), false, false, &[0x0F, 0x3A, opc], dst.index(), rm, &[mode])
        });
    }

    pub fn roundsd(&mut self, dst: Xmm, src: impl Into<Operand>, mode: u8) {
        self.fp_round(Fp::F64, dst, src, mode);
    }

    pub fn roundss(&mut self, dst: Xmm, src: impl Into<Operand>, mode: u8) {
        self.fp_round(Fp::F32, dst, src, mode);
    }
}
