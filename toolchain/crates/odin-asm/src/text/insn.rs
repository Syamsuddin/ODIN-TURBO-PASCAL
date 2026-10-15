// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Maps Intel-syntax instructions onto [`Assembler`] methods: works out the
//! operand width from registers and `ptr` keywords, checks operand sizes, and
//! resolves `.L` labels.

use std::collections::HashMap;

use super::parse::{PMem, POp};
use crate::x86_64::{
    AluOp, Assembler, BitOp, Cond, Fp, FpLogic, FpOp, Label, Mem, Operand, Reg, ShiftOp, Target, UnaryOp, Width,
};

/// A `.L` label of a code atom (of either architecture's `Label` type).
pub(crate) struct LocalLabel<L = Label> {
    pub label: L,
    /// Line of the definition, once seen.
    pub defined: Option<u32>,
    /// Line of the first reference (or of the definition).
    pub first_use: u32,
}

/// Whether `name` is local to its atom.
pub(crate) fn is_local(name: &str) -> bool {
    name.starts_with(".L")
}

/// Everything an instruction needs from the code atom it goes into.
pub(crate) struct Ctx<'a> {
    pub asm: &'a mut Assembler,
    pub labels: &'a mut HashMap<String, LocalLabel>,
    pub line: u32,
}

impl Ctx<'_> {
    /// The label called `name`, created on first reference.
    pub(crate) fn label(&mut self, name: &str) -> Label {
        if let Some(l) = self.labels.get(name) {
            return l.label;
        }
        let label = self.asm.new_label();
        self.labels.insert(name.to_string(), LocalLabel { label, defined: None, first_use: self.line });
        label
    }

    fn mem(&mut self, m: &PMem) -> Result<Mem, String> {
        if m.rip {
            let Some(sym) = &m.sym else {
                return Err("a RIP-relative address needs a symbol or label".into());
            };
            if m.got {
                return Ok(Mem::got(sym));
            }
            if is_local(sym) {
                let l = self.label(sym);
                return Ok(Mem::label_plus(l, disp32(m.disp)?));
            }
            return Ok(Mem::rip(sym, m.disp));
        }
        if let Some(sym) = &m.sym {
            return Err(format!("an absolute address is not position-independent; write `[rip + {sym}]`"));
        }
        Ok(Mem::Sib { base: m.base, index: m.index, disp: disp32(m.disp)? })
    }

    fn operand(&mut self, p: &POp) -> Result<Operand, String> {
        Ok(match p {
            POp::Reg(r, _) => Operand::Reg(*r),
            POp::Xmm(x) => Operand::Xmm(*x),
            POp::Mem(m) => Operand::Mem(self.mem(m)?),
            POp::Imm(v) => Operand::Imm(*v),
            POp::Sym(name, _) => {
                return Err(format!("symbol `{name}` cannot be used here (as an address: `[rip + {name}]`)"));
            }
        })
    }

    fn target(&mut self, p: &POp, conditional: bool) -> Result<Target, String> {
        match p {
            POp::Sym(_, addend) if *addend != 0 => Err("a branch target cannot have an offset".into()),
            POp::Sym(name, _) if is_local(name) => Ok(Target::Label(self.label(name))),
            POp::Sym(name, _) => Ok(Target::Sym(name.clone())),
            _ if conditional => Err("a conditional jump needs a label or symbol".into()),
            POp::Reg(r, Width::W64) => Ok(Target::Indirect(Operand::Reg(*r))),
            POp::Mem(m) if matches!(m.size, None | Some(8)) => Ok(Target::Indirect(Operand::Mem(self.mem(m)?))),
            _ => Err("expected a label, a symbol, a 64-bit register or a qword memory operand".into()),
        }
    }
}

fn disp32(v: i64) -> Result<i32, String> {
    i32::try_from(v).map_err(|_| format!("displacement {v} does not fit in 32 bits"))
}

fn size_width(bytes: u32) -> Result<Width, String> {
    Width::from_bytes(bytes).ok_or_else(|| "xmmword operands are only allowed in SSE instructions".to_string())
}

/// The common integer width of `ops`, from registers and `ptr` sizes.
fn width(ops: &[&POp]) -> Result<Width, String> {
    let mut found: Option<Width> = None;
    for op in ops {
        let w = match op {
            POp::Reg(_, w) => Some(*w),
            POp::Mem(m) => m.size.map(size_width).transpose()?,
            POp::Xmm(_) => return Err("xmm registers are not allowed here".into()),
            _ => None,
        };
        match (found, w) {
            (Some(a), Some(b)) if a != b => return Err("operand size mismatch".into()),
            (None, Some(b)) => found = Some(b),
            _ => {}
        }
    }
    found.ok_or_else(|| "operand size is ambiguous; add byte/word/dword/qword ptr".to_string())
}

/// Checks that a memory operand of an SSE instruction, if sized, has `size`
/// bytes.
fn check_size(op: &POp, size: u32) -> Result<(), String> {
    match op {
        POp::Mem(PMem { size: Some(s), .. }) if *s != size => Err(format!("memory operand must be {size} bytes")),
        _ => Ok(()),
    }
}

fn xmm(op: &POp) -> Result<crate::x86_64::Xmm, String> {
    match op {
        POp::Xmm(x) => Ok(*x),
        _ => Err("expected an xmm register".into()),
    }
}

fn reg(op: &POp) -> Result<(Reg, Width), String> {
    match op {
        POp::Reg(r, w) => Ok((*r, *w)),
        _ => Err("expected a general-purpose register".into()),
    }
}

fn mnemonic_cond(m: &str, prefix: &str) -> Option<Cond> {
    m.strip_prefix(prefix).and_then(Cond::parse)
}

/// Encodes one instruction. `prefix` is `rep` or similar, written before the
/// mnemonic.
pub(crate) fn encode(ctx: &mut Ctx<'_>, prefix: Option<&str>, mnemonic: &str, ops: &[POp]) -> Result<(), String> {
    let m = mnemonic.to_ascii_lowercase();
    let arity = |k: &[usize]| {
        if k.contains(&ops.len()) {
            Ok(())
        } else {
            let k: Vec<String> = k.iter().map(|n| n.to_string()).collect();
            Err(format!("`{m}` takes {} operand(s), not {}", k.join(" or "), ops.len()))
        }
    };
    if let Some(p) = prefix {
        let string_op =
            matches!(m.as_str(), "movsb" | "movsw" | "movsd" | "movsq" | "stosb" | "stosw" | "stosd" | "stosq");
        if !p.eq_ignore_ascii_case("rep") || !string_op || !ops.is_empty() {
            return Err(format!("prefix `{p}` is not supported with `{m}`"));
        }
    }
    let rep = prefix.is_some();

    let alu = match m.as_str() {
        "add" => Some(AluOp::Add),
        "or" => Some(AluOp::Or),
        "adc" => Some(AluOp::Adc),
        "sbb" => Some(AluOp::Sbb),
        "and" => Some(AluOp::And),
        "sub" => Some(AluOp::Sub),
        "xor" => Some(AluOp::Xor),
        "cmp" => Some(AluOp::Cmp),
        _ => None,
    };
    let unary = match m.as_str() {
        "not" => Some(UnaryOp::Not),
        "neg" => Some(UnaryOp::Neg),
        "mul" => Some(UnaryOp::Mul),
        "div" => Some(UnaryOp::Div),
        "idiv" => Some(UnaryOp::Idiv),
        "inc" => Some(UnaryOp::Inc),
        "dec" => Some(UnaryOp::Dec),
        _ => None,
    };
    let shift = match m.as_str() {
        "rol" => Some(ShiftOp::Rol),
        "ror" => Some(ShiftOp::Ror),
        "rcl" => Some(ShiftOp::Rcl),
        "rcr" => Some(ShiftOp::Rcr),
        "shl" | "sal" => Some(ShiftOp::Shl),
        "shr" => Some(ShiftOp::Shr),
        "sar" => Some(ShiftOp::Sar),
        _ => None,
    };
    let bit = match m.as_str() {
        "bt" => Some(BitOp::Bt),
        "bts" => Some(BitOp::Bts),
        "btr" => Some(BitOp::Btr),
        "btc" => Some(BitOp::Btc),
        _ => None,
    };
    let fp_arith = match m.as_str() {
        "addsd" | "addss" => Some(FpOp::Add),
        "subsd" | "subss" => Some(FpOp::Sub),
        "mulsd" | "mulss" => Some(FpOp::Mul),
        "divsd" | "divss" => Some(FpOp::Div),
        "sqrtsd" | "sqrtss" => Some(FpOp::Sqrt),
        "minsd" | "minss" => Some(FpOp::Min),
        "maxsd" | "maxss" => Some(FpOp::Max),
        _ => None,
    };
    let fp_logic = match m.as_str() {
        "andpd" | "andps" => Some(FpLogic::And),
        "andnpd" | "andnps" => Some(FpLogic::AndNot),
        "orpd" | "orps" => Some(FpLogic::Or),
        "xorpd" | "xorps" => Some(FpLogic::Xor),
        _ => None,
    };
    // Precision of a scalar SSE mnemonic, from its `sd`/`ss` (`pd`/`ps`)
    // suffix.
    let fp = if m.ends_with('d') { Fp::F64 } else { Fp::F32 };
    let fp_size = if fp == Fp::F64 { 8 } else { 4 };

    if let Some(op) = alu {
        arity(&[2])?;
        let w = width(&[&ops[0], &ops[1]])?;
        let (d, s) = (ctx.operand(&ops[0])?, ctx.operand(&ops[1])?);
        ctx.asm.alu(op, w, d, s);
    } else if let Some(op) = unary {
        arity(&[1])?;
        let w = width(&[&ops[0]])?;
        let x = ctx.operand(&ops[0])?;
        ctx.asm.unary(op, w, x);
    } else if let Some(op) = shift {
        arity(&[1, 2])?;
        let w = width(&[&ops[0]])?;
        let count = match ops.get(1) {
            None => Operand::Imm(1),
            Some(POp::Imm(v)) => Operand::Imm(*v),
            Some(POp::Reg(Reg::Rcx, Width::W8)) => Operand::Reg(Reg::Rcx),
            Some(_) => return Err("the shift count must be an immediate or `cl`".into()),
        };
        let d = ctx.operand(&ops[0])?;
        ctx.asm.shift(op, w, d, count);
    } else if let Some(op) = bit {
        arity(&[2])?;
        let w = width(&[&ops[0], &ops[1]])?;
        let (b, i) = (ctx.operand(&ops[0])?, ctx.operand(&ops[1])?);
        ctx.asm.bit(op, w, b, i);
    } else if let Some(op) = fp_arith {
        arity(&[2])?;
        check_size(&ops[1], fp_size)?;
        let (d, s) = (xmm(&ops[0])?, ctx.operand(&ops[1])?);
        ctx.asm.fp_arith(op, fp, d, s);
    } else if let Some(op) = fp_logic {
        arity(&[2])?;
        check_size(&ops[1], 16)?;
        let (d, s) = (xmm(&ops[0])?, ctx.operand(&ops[1])?);
        ctx.asm.fp_logic(op, fp, d, s);
    } else if let Some(c) = mnemonic_cond(&m, "set") {
        arity(&[1])?;
        if !matches!(&ops[0], POp::Reg(_, Width::W8) | POp::Mem(PMem { size: None | Some(1), .. })) {
            return Err("`set` needs an 8-bit register or byte memory operand".into());
        }
        let d = ctx.operand(&ops[0])?;
        ctx.asm.setcc(c, d);
    } else if let Some(c) = mnemonic_cond(&m, "cmov") {
        arity(&[2])?;
        let w = width(&[&ops[0], &ops[1]])?;
        let (d, s) = (reg(&ops[0])?.0, ctx.operand(&ops[1])?);
        ctx.asm.cmov(c, w, d, s);
    } else if let Some(c) = mnemonic_cond(&m, "j").filter(|_| m != "jmp") {
        arity(&[1])?;
        let t = ctx.target(&ops[0], true)?;
        ctx.asm.jcc(c, t);
    } else {
        match m.as_str() {
            "mov" | "test" | "xchg" => {
                arity(&[2])?;
                let w = width(&[&ops[0], &ops[1]])?;
                let (a, b) = (ctx.operand(&ops[0])?, ctx.operand(&ops[1])?);
                match m.as_str() {
                    "mov" => ctx.asm.mov(w, a, b),
                    "test" => ctx.asm.test(w, a, b),
                    _ => ctx.asm.xchg(w, a, b),
                }
            }
            "movabs" => {
                arity(&[2])?;
                match (&ops[0], &ops[1]) {
                    (POp::Reg(r, Width::W64), POp::Imm(v)) => ctx.asm.movabs(*r, *v),
                    _ => return Err("`movabs` needs a 64-bit register and an immediate".into()),
                }
            }
            "lea" => {
                arity(&[2])?;
                let (d, w) = reg(&ops[0])?;
                if !matches!(ops[1], POp::Mem(_)) {
                    return Err("`lea` needs a memory operand".into());
                }
                let s = ctx.operand(&ops[1])?;
                ctx.asm.lea(w, d, s);
            }
            "movzx" | "movsx" => {
                arity(&[2])?;
                let (d, dw) = reg(&ops[0])?;
                let sw = match &ops[1] {
                    POp::Reg(_, w) => *w,
                    POp::Mem(PMem { size: Some(s), .. }) => size_width(*s)?,
                    POp::Mem(_) => return Err("source size is ambiguous; add byte ptr or word ptr".into()),
                    _ => return Err(format!("`{m}` needs a register or memory source")),
                };
                let s = ctx.operand(&ops[1])?;
                if m == "movzx" {
                    ctx.asm.movzx(dw, d, sw, s);
                } else {
                    ctx.asm.movsx(dw, d, sw, s);
                }
            }
            "movsxd" => {
                arity(&[2])?;
                let ok = matches!(
                    (&ops[0], &ops[1]),
                    (POp::Reg(_, Width::W64), POp::Reg(_, Width::W32) | POp::Mem(PMem { size: None | Some(4), .. }))
                );
                if !ok {
                    return Err("`movsxd` needs a 64-bit register and a 32-bit source".into());
                }
                let (d, s) = (reg(&ops[0])?.0, ctx.operand(&ops[1])?);
                ctx.asm.movsxd(d, s);
            }
            "imul" => {
                arity(&[1, 2, 3])?;
                match ops.len() {
                    1 => {
                        let w = width(&[&ops[0]])?;
                        let x = ctx.operand(&ops[0])?;
                        ctx.asm.imul1(w, x);
                    }
                    2 => {
                        let w = width(&[&ops[0], &ops[1]])?;
                        let (d, s) = (reg(&ops[0])?.0, ctx.operand(&ops[1])?);
                        ctx.asm.imul(w, d, s);
                    }
                    _ => {
                        let w = width(&[&ops[0], &ops[1]])?;
                        let POp::Imm(v) = ops[2] else {
                            return Err("the third operand of `imul` must be an immediate".into());
                        };
                        let (d, s) = (reg(&ops[0])?.0, ctx.operand(&ops[1])?);
                        ctx.asm.imul3(w, d, s, v);
                    }
                }
            }
            "cbw" | "cwde" | "cdqe" | "cwd" | "cdq" | "cqo" | "ret" | "leave" | "nop" | "ud2" | "int3" | "cld"
            | "syscall"
                if ops.is_empty() =>
            {
                let a = &mut *ctx.asm;
                match m.as_str() {
                    "cbw" => a.cbw(),
                    "cwde" => a.cwde(),
                    "cdqe" => a.cdqe(),
                    "cwd" => a.cwd(),
                    "cdq" => a.cdq(),
                    "cqo" => a.cqo(),
                    "ret" => a.ret(),
                    "leave" => a.leave(),
                    "nop" => a.nop(),
                    "ud2" => a.ud2(),
                    "int3" => a.int3(),
                    "cld" => a.cld(),
                    _ => a.syscall(),
                }
            }
            "ret" => match ops {
                [POp::Imm(v)] => {
                    let v = u16::try_from(*v).map_err(|_| "`ret` immediate must fit in 16 bits".to_string())?;
                    ctx.asm.ret_imm(v);
                }
                _ => return Err("`ret` takes no operand or a 16-bit immediate".into()),
            },
            "push" | "pop" => {
                arity(&[1])?;
                match &ops[0] {
                    POp::Reg(_, Width::W64) | POp::Mem(PMem { size: None | Some(8), .. }) => {}
                    POp::Imm(_) if m == "push" => {}
                    _ => return Err(format!("`{m}` needs a 64-bit register or qword memory operand")),
                }
                let x = ctx.operand(&ops[0])?;
                if m == "push" {
                    ctx.asm.push(x);
                } else {
                    ctx.asm.pop(x);
                }
            }
            "call" | "jmp" => {
                arity(&[1])?;
                let t = ctx.target(&ops[0], false)?;
                if m == "call" {
                    ctx.asm.call(t);
                } else {
                    ctx.asm.jmp(t);
                }
            }
            "movsb" | "movsw" | "movsd" | "movsq" | "stosb" | "stosw" | "stosd" | "stosq" if ops.is_empty() => {
                let w = match m.as_bytes()[4] {
                    b'b' => Width::W8,
                    b'w' => Width::W16,
                    b'd' => Width::W32,
                    _ => Width::W64,
                };
                match (m.starts_with("movs"), rep) {
                    (true, false) => ctx.asm.movs(w),
                    (true, true) => ctx.asm.rep_movs(w),
                    (false, false) => ctx.asm.stos(w),
                    (false, true) => ctx.asm.rep_stos(w),
                }
            }
            "movsd" | "movss" | "movapd" | "movaps" => {
                arity(&[2])?;
                let size = match m.as_str() {
                    "movsd" => 8,
                    "movss" => 4,
                    _ => 16,
                };
                check_size(&ops[0], size)?;
                check_size(&ops[1], size)?;
                let (d, s) = (ctx.operand(&ops[0])?, ctx.operand(&ops[1])?);
                match m.as_str() {
                    "movsd" => ctx.asm.movsd(d, s),
                    "movss" => ctx.asm.movss(d, s),
                    "movapd" => ctx.asm.movapd(d, s),
                    _ => ctx.asm.movaps(d, s),
                }
            }
            "ucomisd" | "comisd" | "ucomiss" | "comiss" => {
                arity(&[2])?;
                check_size(&ops[1], fp_size)?;
                let (a, b) = (xmm(&ops[0])?, ctx.operand(&ops[1])?);
                ctx.asm.fp_compare(fp, !m.starts_with('u'), a, b);
            }
            "cvtsi2sd" | "cvtsi2ss" => {
                arity(&[2])?;
                let fp = if m == "cvtsi2sd" { Fp::F64 } else { Fp::F32 };
                let sw = match &ops[1] {
                    POp::Reg(_, w) => *w,
                    POp::Mem(PMem { size: Some(s), .. }) => size_width(*s)?,
                    POp::Mem(_) => return Err("source size is ambiguous; add dword ptr or qword ptr".into()),
                    _ => return Err(format!("`{m}` needs an integer register or memory source")),
                };
                let (d, s) = (xmm(&ops[0])?, ctx.operand(&ops[1])?);
                ctx.asm.cvtsi2fp(fp, d, sw, s);
            }
            "cvttsd2si" | "cvtsd2si" | "cvttss2si" | "cvtss2si" => {
                arity(&[2])?;
                let fp = if m.contains("sd") { Fp::F64 } else { Fp::F32 };
                check_size(&ops[1], if fp == Fp::F64 { 8 } else { 4 })?;
                let (d, dw) = reg(&ops[0])?;
                let s = ctx.operand(&ops[1])?;
                ctx.asm.cvtfp2si(fp, m.starts_with("cvtt"), dw, d, s);
            }
            "cvtss2sd" | "cvtsd2ss" => {
                arity(&[2])?;
                check_size(&ops[1], if m == "cvtss2sd" { 4 } else { 8 })?;
                let (d, s) = (xmm(&ops[0])?, ctx.operand(&ops[1])?);
                if m == "cvtss2sd" {
                    ctx.asm.cvtss2sd(d, s);
                } else {
                    ctx.asm.cvtsd2ss(d, s);
                }
            }
            "movq" | "movd" => {
                arity(&[2])?;
                let (rw, size) = if m == "movq" { (Width::W64, 8) } else { (Width::W32, 4) };
                for op in ops {
                    match op {
                        POp::Reg(_, w) if *w != rw => {
                            return Err(format!("`{m}` needs a {}-bit general-purpose register", rw.bits()));
                        }
                        _ => check_size(op, size)?,
                    }
                }
                let (d, s) = (ctx.operand(&ops[0])?, ctx.operand(&ops[1])?);
                if m == "movq" {
                    ctx.asm.movq(d, s);
                } else {
                    ctx.asm.movd(d, s);
                }
            }
            "ldmxcsr" | "stmxcsr" => {
                arity(&[1])?;
                if !matches!(ops[0], POp::Mem(_)) {
                    return Err(format!("`{m}` needs a memory operand"));
                }
                check_size(&ops[0], 4)?;
                let x = ctx.operand(&ops[0])?;
                if m == "ldmxcsr" {
                    ctx.asm.ldmxcsr(x);
                } else {
                    ctx.asm.stmxcsr(x);
                }
            }
            "roundsd" | "roundss" => {
                arity(&[3])?;
                check_size(&ops[1], fp_size)?;
                let mode = match ops[2] {
                    POp::Imm(v @ 0..=255) => v as u8,
                    _ => return Err("the rounding mode must be an immediate from 0 to 255".into()),
                };
                let (d, s) = (xmm(&ops[0])?, ctx.operand(&ops[1])?);
                ctx.asm.fp_round(fp, d, s, mode);
            }
            "cbw" | "cwde" | "cdqe" | "cwd" | "cdq" | "cqo" | "leave" | "nop" | "ud2" | "int3" | "cld" | "syscall"
            | "movsb" | "movsw" | "movsq" | "stosb" | "stosw" | "stosd" | "stosq" => {
                return Err(format!("`{m}` takes no operands"));
            }
            _ => return Err(format!("unknown instruction `{mnemonic}`")),
        }
    }
    match ctx.asm.take_error() {
        Some(e) => Err(e.message),
        None => Ok(()),
    }
}
