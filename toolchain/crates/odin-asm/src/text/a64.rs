// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Maps AArch64 instructions, in the syntax clang accepts, onto
//! [`aarch64::Assembler`](crate::aarch64::Assembler) methods: parses
//! operands (including the Darwin `@PAGE` and ELF `:lo12:` relocation
//! operators) and resolves `.L` labels.

use std::collections::HashMap;

use super::insn::{LocalLabel, is_local};
use super::lexer::Tok;
use super::parse::{Consts, const_expr, split_commas, split_terms};
use crate::aarch64::{
    AnyReg, Assembler, Cond, Extend, IndexExt, Label, LogicOp, Mem, Op2, Reg, Round, Shift, SysReg, Target, VReg,
};

/// Everything an instruction needs from the code atom it goes into.
pub(crate) struct Ctx<'a> {
    pub asm: &'a mut Assembler,
    pub labels: &'a mut HashMap<String, LocalLabel<Label>>,
    pub line: u32,
    pub consts: &'a Consts,
}

/// A relocation operator written on a symbol.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Modifier {
    /// None written: a branch target, or the page of `adrp` on ELF.
    None,
    /// `sym@PAGE`.
    Page,
    /// `sym@PAGEOFF` / `:lo12:sym`.
    PageOff,
    /// `sym@GOTPAGE` / `:got:sym`.
    GotPage,
    /// `sym@GOTPAGEOFF` / `:got_lo12:sym`.
    GotPageOff,
}

#[derive(Clone, Debug, PartialEq)]
struct SymRef {
    name: String,
    addend: i64,
    modifier: Modifier,
}

/// An operand as written.
#[derive(Clone, Debug, PartialEq)]
enum Op {
    Reg(Reg),
    V(VReg),
    Imm(i64),
    Float(f64),
    /// A symbol or label, possibly with an operator and an addend. Also how
    /// condition names (`eq`), system registers (`fpcr`) and barrier
    /// options (`ish`) arrive.
    Sym(SymRef),
    Mem(PMem),
    /// `lsl #n` etc. after a register or immediate.
    Shift(Shift, i64),
    /// `sxtw`, `uxtb #2` etc. after a register.
    Extend(Extend, Option<i64>),
}

/// `[base]`, `[base, #imm]`, `[base, index{, ext}]`, `[base, sym@PAGEOFF]`,
/// optionally followed by `!`.
#[derive(Clone, Debug, PartialEq)]
struct PMem {
    base: Reg,
    offset: MemOff,
    writeback: bool,
}

#[derive(Clone, Debug, PartialEq)]
enum MemOff {
    None,
    Imm(i64),
    Index { index: Reg, ext: Option<(IndexExt, Option<i64>)> },
    Sym(SymRef),
}

impl Op {
    fn describe(&self) -> &'static str {
        match self {
            Op::Reg(_) => "a general register",
            Op::V(_) => "an FP register",
            Op::Imm(_) => "an immediate",
            Op::Float(_) => "a floating-point immediate",
            Op::Sym(_) => "a symbol",
            Op::Mem(_) => "an address",
            Op::Shift(..) => "a shift",
            Op::Extend(..) => "an extend",
        }
    }
}

fn shift_name(name: &str) -> Option<Shift> {
    match name.to_ascii_lowercase().as_str() {
        "lsl" => Some(Shift::Lsl),
        "lsr" => Some(Shift::Lsr),
        "asr" => Some(Shift::Asr),
        "ror" => Some(Shift::Ror),
        _ => None,
    }
}

fn is_reg_name(name: &str) -> bool {
    Reg::parse(name).is_some() || VReg::parse(name).is_some()
}

/// A constant, or `sym + constant` with an optional relocation operator.
enum Value {
    Const(i64),
    Sym(SymRef),
}

fn darwin_modifier(m: &str) -> Result<Modifier, String> {
    match m.to_ascii_uppercase().as_str() {
        "PAGE" => Ok(Modifier::Page),
        "PAGEOFF" => Ok(Modifier::PageOff),
        "GOTPAGE" => Ok(Modifier::GotPage),
        "GOTPAGEOFF" => Ok(Modifier::GotPageOff),
        _ => Err(format!("unsupported relocation operator `@{m}`")),
    }
}

fn elf_modifier(m: &str) -> Result<Modifier, String> {
    match m.to_ascii_lowercase().as_str() {
        "lo12" => Ok(Modifier::PageOff),
        "got" => Ok(Modifier::GotPage),
        "got_lo12" => Ok(Modifier::GotPageOff),
        _ => Err(format!("unsupported relocation operator `:{m}:`")),
    }
}

/// Evaluates `[:op:] sym[@OP] + constant` or a constant expression.
fn value(toks: &[Tok], consts: &Consts) -> Result<Value, String> {
    let (mut modifier, rest) = match toks {
        [Tok::Punct(':'), Tok::Ident(m), Tok::Punct(':'), rest @ ..] => (elf_modifier(m)?, rest),
        _ => (Modifier::None, toks),
    };
    let mut name: Option<String> = None;
    let mut acc: i128 = 0;
    for (neg, term) in split_terms(rest)? {
        let sym = match term {
            [Tok::Ident(n)] if !consts.contains_key(n) && !is_reg_name(n) => Some((n, Modifier::None)),
            [Tok::Ident(n), Tok::Punct('@'), Tok::Ident(m)] => Some((n, darwin_modifier(m)?)),
            _ => None,
        };
        match sym {
            Some((n, m)) => {
                if neg {
                    return Err(format!("cannot subtract symbol `{n}`"));
                }
                if name.is_some() {
                    return Err("only one symbol is allowed in an expression".into());
                }
                if m != Modifier::None {
                    if modifier != Modifier::None {
                        return Err("two relocation operators on one symbol".into());
                    }
                    modifier = m;
                }
                name = Some(n.clone());
            }
            None => {
                let v = const_expr(term, consts)? as i128;
                acc += if neg { -v } else { v };
            }
        }
    }
    let addend = i64::try_from(acc).map_err(|_| format!("value {acc} does not fit in 64 bits"))?;
    match name {
        Some(name) => Ok(Value::Sym(SymRef { name, addend, modifier })),
        None if modifier != Modifier::None => Err("relocation operator without a symbol".into()),
        None => Ok(Value::Const(addend)),
    }
}

/// An amount after a shift or extend: `#n` or `n`.
fn amount(toks: &[Tok], consts: &Consts) -> Result<i64, String> {
    let toks = match toks {
        [Tok::Punct('#'), rest @ ..] => rest,
        _ => toks,
    };
    if toks.is_empty() {
        return Err("missing shift amount".into());
    }
    const_expr(toks, consts)
}

fn operand(toks: &[Tok], consts: &Consts) -> Result<Op, String> {
    match toks {
        [] => return Err("missing operand".into()),
        [Tok::Punct('['), ..] => {
            let (inner, writeback) = match toks {
                [Tok::Punct('['), inner @ .., Tok::Punct(']')] => (inner, false),
                [Tok::Punct('['), inner @ .., Tok::Punct(']'), Tok::Punct('!')] => (inner, true),
                _ => return Err("expected `]` (optionally followed by `!`) at the end of the address".into()),
            };
            return Ok(Op::Mem(memory(inner, writeback, consts)?));
        }
        [Tok::Ident(name)] => {
            if let Some(r) = Reg::parse(name) {
                return Ok(Op::Reg(r));
            }
            if let Some(v) = VReg::parse(name) {
                return Ok(Op::V(v));
            }
            if let Some(e) = Extend::parse(name) {
                return Ok(Op::Extend(e, None));
            }
        }
        [Tok::Ident(name), rest @ ..] => {
            if let Some(s) = shift_name(name) {
                return Ok(Op::Shift(s, amount(rest, consts)?));
            }
            if let Some(e) = Extend::parse(name) {
                return Ok(Op::Extend(e, Some(amount(rest, consts)?)));
            }
        }
        _ => {}
    }
    let toks = match toks {
        [Tok::Punct('#'), rest @ ..] => rest,
        _ => toks,
    };
    match toks {
        [Tok::Float(b)] => return Ok(Op::Float(f64::from_bits(*b))),
        [Tok::Punct('-'), Tok::Float(b)] => return Ok(Op::Float(-f64::from_bits(*b))),
        [Tok::Punct('+'), Tok::Float(b)] => return Ok(Op::Float(f64::from_bits(*b))),
        [] => return Err("missing immediate".into()),
        _ => {}
    }
    Ok(match value(toks, consts)? {
        Value::Const(v) => Op::Imm(v),
        Value::Sym(s) => Op::Sym(s),
    })
}

/// Parses the inside of `[...]`.
fn memory(inner: &[Tok], writeback: bool, consts: &Consts) -> Result<PMem, String> {
    let parts = split_commas(inner);
    let base = match parts.first() {
        Some([Tok::Ident(name)]) => Reg::parse(name),
        _ => None,
    }
    .ok_or("an address starts with a base register")?;
    let offset = match &parts[1..] {
        [] => MemOff::None,
        [p] => match operand(p, consts)? {
            Op::Imm(v) => MemOff::Imm(v),
            Op::Reg(index) => MemOff::Index { index, ext: None },
            Op::Sym(s) if matches!(s.modifier, Modifier::PageOff | Modifier::GotPageOff) => MemOff::Sym(s),
            Op::Sym(s) => {
                return Err(format!(
                    "symbol `{}` needs `@PAGEOFF`/`@GOTPAGEOFF` or `:lo12:`/`:got_lo12:` in an address",
                    s.name
                ));
            }
            other => return Err(format!("{} cannot be an address offset", other.describe())),
        },
        [p, e] => {
            let Op::Reg(index) = operand(p, consts)? else {
                return Err("a shifted or extended address offset must be a register".into());
            };
            let ext = match operand(e, consts)? {
                Op::Shift(Shift::Lsl, n) => (IndexExt::Lsl, Some(n)),
                Op::Extend(Extend::Uxtw, n) => (IndexExt::Uxtw, n),
                Op::Extend(Extend::Sxtw, n) => (IndexExt::Sxtw, n),
                Op::Extend(Extend::Sxtx, n) => (IndexExt::Sxtx, n),
                _ => return Err("an index register takes `lsl`, `uxtw`, `sxtw` or `sxtx`".into()),
            };
            MemOff::Index { index, ext: Some(ext) }
        }
        _ => return Err("too many parts in the address".into()),
    };
    if writeback && !matches!(offset, MemOff::Imm(_)) {
        return Err("write-back (`!`) needs an immediate offset".into());
    }
    Ok(PMem { base, offset, writeback })
}

fn reg(op: &Op) -> Result<Reg, String> {
    match op {
        Op::Reg(r) => Ok(*r),
        other => Err(format!("expected a general register, found {}", other.describe())),
    }
}

fn vreg(op: &Op) -> Result<VReg, String> {
    match op {
        Op::V(v) => Ok(*v),
        other => Err(format!("expected an S or D register, found {}", other.describe())),
    }
}

fn any(op: &Op) -> Result<AnyReg, String> {
    match op {
        Op::Reg(r) => Ok(AnyReg::Gp(*r)),
        Op::V(v) => Ok(AnyReg::Fp(*v)),
        other => Err(format!("expected a register, found {}", other.describe())),
    }
}

fn gp(rt: AnyReg) -> Result<Reg, String> {
    match rt {
        AnyReg::Gp(r) => Ok(r),
        AnyReg::Fp(v) => Err(format!("`{v}` cannot be used here; expected a general register")),
    }
}

fn imm(op: &Op, lo: i64, hi: i64) -> Result<i64, String> {
    match op {
        Op::Imm(v) if (lo..=hi).contains(v) => Ok(*v),
        Op::Imm(v) => Err(format!("immediate {v} is out of range ({lo} to {hi})")),
        other => Err(format!("expected an immediate, found {}", other.describe())),
    }
}

fn cond(op: &Op) -> Result<Cond, String> {
    match op {
        Op::Sym(SymRef { name, addend: 0, modifier: Modifier::None }) => {
            Cond::parse(name).ok_or_else(|| format!("unknown condition `{name}`"))
        }
        other => Err(format!("expected a condition, found {}", other.describe())),
    }
}

/// The name of a bare identifier operand (a system register, a barrier
/// option).
fn keyword(op: &Op) -> Option<&str> {
    match op {
        Op::Sym(SymRef { name, addend: 0, modifier: Modifier::None }) => Some(name),
        _ => None,
    }
}

/// The flexible second operand: `#imm[, lsl #12]`, `reg[, shift #n]` or
/// `reg, extend [#n]`.
fn op2(ops: &[Op], arith: bool) -> Result<Op2, String> {
    match ops {
        [Op::Imm(v)] => Ok(Op2::Imm(*v)),
        [Op::Imm(v), Op::Shift(Shift::Lsl, s)] if arith && (*s == 0 || *s == 12) => {
            if !(0..4096).contains(v) {
                return Err(format!("immediate {v} is out of range (0 to 4095) with `lsl`"));
            }
            Ok(Op2::Imm(v << s))
        }
        [Op::Imm(_), _] => Err("an immediate here takes no shift other than `lsl #12`".into()),
        [Op::Reg(r)] => Ok(Op2::Reg(*r)),
        [Op::Reg(r), Op::Shift(s, n)] => {
            let n = u8::try_from(*n).map_err(|_| format!("shift amount {n} is out of range"))?;
            Ok(Op2::Shifted(*r, *s, n))
        }
        [Op::Reg(r), Op::Extend(e, n)] if arith => {
            let n = u8::try_from(n.unwrap_or(0)).map_err(|_| "extend amount is out of range".to_string())?;
            Ok(Op2::Extended(*r, *e, n))
        }
        [first, ..] => Err(format!("unexpected {} as the second operand", first.describe())),
        [] => Err("missing operand".into()),
    }
}

/// log2 of the access size of a load/store mnemonic.
fn access_log2(m: &str, rt: AnyReg) -> u32 {
    match m {
        "ldrb" | "strb" | "ldrsb" | "ldurb" | "sturb" | "ldursb" => 0,
        "ldrh" | "strh" | "ldrsh" | "ldurh" | "sturh" | "ldursh" => 1,
        "ldrsw" | "ldursw" => 2,
        _ => match rt {
            AnyReg::Gp(r) => 2 + r.is_64() as u32,
            AnyReg::Fp(v) => v.fp().bytes().trailing_zeros(),
        },
    }
}

impl Ctx<'_> {
    /// The label called `name`, created on first reference.
    fn label(&mut self, name: &str) -> Label {
        if let Some(l) = self.labels.get(name) {
            return l.label;
        }
        let label = self.asm.new_label();
        self.labels.insert(name.to_string(), LocalLabel { label, defined: None, first_use: self.line });
        label
    }

    /// A `.L` label operand (`what` names the instruction for errors).
    fn local(&mut self, op: &Op, what: &str) -> Result<(Label, i64), String> {
        match op {
            Op::Sym(SymRef { name, addend, modifier: Modifier::None }) if is_local(name) => {
                Ok((self.label(name), *addend))
            }
            Op::Sym(SymRef { name, .. }) => Err(format!(
                "`{what}` can only reach `.L` labels of the same atom, not `{name}` (no relocation exists for it)"
            )),
            other => Err(format!("expected a label, found {}", other.describe())),
        }
    }

    /// Converts a parsed address of an access of `1 << size` bytes.
    fn mem(&self, p: &PMem, size: u32) -> Result<Mem, String> {
        let base = p.base;
        Ok(match &p.offset {
            MemOff::None => Mem::Offset { base, offset: 0 },
            MemOff::Imm(v) if p.writeback => Mem::PreIndex { base, offset: *v },
            MemOff::Imm(v) => Mem::Offset { base, offset: *v },
            MemOff::Index { index, ext } => {
                let (ext, amount) = ext.unwrap_or((IndexExt::Lsl, None));
                // `S` is set when the amount is written and equals log2 of
                // the size; for byte accesses, when `#0` is written at all.
                let shift = match amount {
                    None => false,
                    Some(0) if size == 0 => true,
                    Some(0) => false,
                    Some(a) if a == size as i64 => true,
                    Some(a) => return Err(format!("index shift #{a} must be #0 or #{size} for this access size")),
                };
                Mem::Index { base, index: *index, ext, shift }
            }
            MemOff::Sym(s) => match s.modifier {
                Modifier::GotPageOff if s.addend != 0 => return Err("a GOT slot takes no addend".into()),
                Modifier::GotPageOff => Mem::GotPageOff { base, sym: s.name.clone() },
                _ => Mem::PageOff { base, sym: s.name.clone(), addend: s.addend },
            },
        })
    }

    /// The address operand(s) of a load or store: `[...]`, `[...]!`,
    /// `[base], #imm`, or (loads only) a literal label.
    fn ldst_mem(&mut self, ops: &[Op], size: u32, literal: bool) -> Result<Mem, String> {
        match ops {
            [Op::Mem(p)] => self.mem(p, size),
            [Op::Mem(PMem { base, offset: MemOff::None, writeback: false }), Op::Imm(v)] => {
                Ok(Mem::PostIndex { base: *base, offset: *v })
            }
            [op @ Op::Sym(_)] if literal => {
                let (label, addend) = self.local(op, "ldr")?;
                let addend = i32::try_from(addend).map_err(|_| "literal offset out of range".to_string())?;
                Ok(Mem::Label { label, addend })
            }
            _ => Err("expected an address `[base, ...]`".into()),
        }
    }
}

/// Encodes one instruction.
pub(crate) fn encode(ctx: &mut Ctx<'_>, mnemonic: &str, args: &[Tok]) -> Result<(), String> {
    let m = mnemonic.to_ascii_lowercase();
    let mut ops = Vec::new();
    for part in split_commas(args) {
        ops.push(operand(part, ctx.consts)?);
    }
    let n = ops.len();
    let arity = |k: &[usize]| {
        if k.contains(&n) {
            Ok(())
        } else {
            let k: Vec<String> = k.iter().map(|n| n.to_string()).collect();
            Err(format!("`{m}` takes {} operand(s), not {n}", k.join(" or ")))
        }
    };
    let logic = match m.as_str() {
        "and" => Some(LogicOp::And),
        "orr" => Some(LogicOp::Orr),
        "eor" => Some(LogicOp::Eor),
        "ands" => Some(LogicOp::Ands),
        "bic" => Some(LogicOp::Bic),
        "orn" => Some(LogicOp::Orn),
        "eon" => Some(LogicOp::Eon),
        "bics" => Some(LogicOp::Bics),
        _ => None,
    };
    let rint = match m.as_str() {
        "frintn" => Some(Round::Nearest),
        "frinta" => Some(Round::Away),
        "frintm" => Some(Round::Down),
        "frintp" => Some(Round::Up),
        "frintz" => Some(Round::Zero),
        _ => None,
    };
    // fcvt{n,a,p,m,z}{s,u}
    let fcvt_int = match m.strip_prefix("fcvt").map(str::as_bytes) {
        Some([mode, sign @ (b's' | b'u')]) => {
            let mode = match mode {
                b'n' => Some(Round::Nearest),
                b'a' => Some(Round::Away),
                b'p' => Some(Round::Up),
                b'm' => Some(Round::Down),
                b'z' => Some(Round::Zero),
                _ => None,
            };
            mode.map(|mode| (mode, *sign == b's'))
        }
        _ => None,
    };
    let bcond = m.strip_prefix("b.").or_else(|| (m.len() == 3).then(|| &m[1..])).and_then(Cond::parse);

    if let Some(op) = logic {
        arity(&[3, 4])?;
        let (rd, rn) = (reg(&ops[0])?, reg(&ops[1])?);
        ctx.asm.logical(op, rd, rn, op2(&ops[2..], false)?);
    } else if let Some(mode) = rint {
        arity(&[2])?;
        ctx.asm.frint(mode, vreg(&ops[0])?, vreg(&ops[1])?);
    } else if let Some((mode, signed)) = fcvt_int {
        arity(&[2])?;
        ctx.asm.fcvt_int(mode, signed, reg(&ops[0])?, vreg(&ops[1])?);
    } else if let (Some(c), true) = (bcond, m.starts_with('b') && !matches!(m.as_str(), "bic" | "bfi" | "bfm" | "brk"))
    {
        arity(&[1])?;
        let (label, addend) = ctx.local(&ops[0], &m)?;
        if addend != 0 {
            return Err("a branch target cannot have an offset".into());
        }
        ctx.asm.b_cond(c, label);
    } else {
        match m.as_str() {
            "add" | "adds" | "sub" | "subs" => {
                arity(&[3, 4])?;
                let (rd, rn) = (reg(&ops[0])?, reg(&ops[1])?);
                if let Op::Sym(s) = &ops[2] {
                    if m != "add" || n != 3 || s.modifier != Modifier::PageOff {
                        return Err(format!(
                            "symbol `{}` is only allowed as `add xd, xn, sym@PAGEOFF` / `:lo12:sym`",
                            s.name
                        ));
                    }
                    ctx.asm.add_pageoff(rd, rn, &s.name, s.addend);
                } else {
                    let op = op2(&ops[2..], true)?;
                    match m.as_str() {
                        "add" => ctx.asm.add(rd, rn, op),
                        "adds" => ctx.asm.adds(rd, rn, op),
                        "sub" => ctx.asm.sub(rd, rn, op),
                        _ => ctx.asm.subs(rd, rn, op),
                    }
                }
            }
            "cmp" | "cmn" => {
                arity(&[2, 3])?;
                let (rn, op) = (reg(&ops[0])?, op2(&ops[1..], true)?);
                if m == "cmp" { ctx.asm.cmp(rn, op) } else { ctx.asm.cmn(rn, op) }
            }
            "neg" | "negs" => {
                arity(&[2, 3])?;
                let (rd, op) = (reg(&ops[0])?, op2(&ops[1..], false)?);
                if m == "neg" { ctx.asm.neg(rd, op) } else { ctx.asm.negs(rd, op) }
            }
            "tst" => {
                arity(&[2, 3])?;
                ctx.asm.tst(reg(&ops[0])?, op2(&ops[1..], false)?);
            }
            "mvn" => {
                arity(&[2, 3])?;
                ctx.asm.mvn(reg(&ops[0])?, op2(&ops[1..], false)?);
            }
            "mov" => {
                arity(&[2])?;
                let rd = reg(&ops[0])?;
                match &ops[1] {
                    Op::Reg(rm) => ctx.asm.mov(rd, *rm),
                    Op::Imm(v) => ctx.asm.mov(rd, *v),
                    other => return Err(format!("cannot move {} into a register", other.describe())),
                }
            }
            "movz" | "movn" | "movk" => {
                arity(&[2, 3])?;
                let rd = reg(&ops[0])?;
                let value = imm(&ops[1], 0, 0xffff)? as u16;
                let shift = match ops.get(2) {
                    None => 0,
                    Some(Op::Shift(Shift::Lsl, s @ 0..=48)) => *s as u8,
                    Some(_) => return Err("expected `lsl #0`, `#16`, `#32` or `#48`".into()),
                };
                match m.as_str() {
                    "movz" => ctx.asm.movz(rd, value, shift),
                    "movn" => ctx.asm.movn(rd, value, shift),
                    _ => ctx.asm.movk(rd, value, shift),
                }
            }
            "mul" | "mneg" | "smulh" | "umulh" | "smull" | "umull" | "sdiv" | "udiv" | "lslv" | "lsrv" | "asrv"
            | "rorv" => {
                arity(&[3])?;
                let (rd, rn, rm) = (reg(&ops[0])?, reg(&ops[1])?, reg(&ops[2])?);
                match m.as_str() {
                    "mul" => ctx.asm.mul(rd, rn, rm),
                    "mneg" => ctx.asm.mneg(rd, rn, rm),
                    "smulh" => ctx.asm.smulh(rd, rn, rm),
                    "umulh" => ctx.asm.umulh(rd, rn, rm),
                    "smull" => ctx.asm.smull(rd, rn, rm),
                    "umull" => ctx.asm.umull(rd, rn, rm),
                    "sdiv" => ctx.asm.sdiv(rd, rn, rm),
                    "udiv" => ctx.asm.udiv(rd, rn, rm),
                    "lslv" => ctx.asm.lsl(rd, rn, rm),
                    "lsrv" => ctx.asm.lsr(rd, rn, rm),
                    "asrv" => ctx.asm.asr(rd, rn, rm),
                    _ => ctx.asm.ror(rd, rn, rm),
                }
            }
            "madd" | "msub" | "smaddl" | "umaddl" => {
                arity(&[4])?;
                let (rd, rn, rm, ra) = (reg(&ops[0])?, reg(&ops[1])?, reg(&ops[2])?, reg(&ops[3])?);
                match m.as_str() {
                    "madd" => ctx.asm.madd(rd, rn, rm, ra),
                    "msub" => ctx.asm.msub(rd, rn, rm, ra),
                    "smaddl" => ctx.asm.smaddl(rd, rn, rm, ra),
                    _ => ctx.asm.umaddl(rd, rn, rm, ra),
                }
            }
            "lsl" | "lsr" | "asr" | "ror" => {
                arity(&[3])?;
                let (rd, rn) = (reg(&ops[0])?, reg(&ops[1])?);
                let amount = match &ops[2] {
                    Op::Reg(rm) => Op2::Reg(*rm),
                    Op::Imm(v) => Op2::Imm(*v),
                    other => return Err(format!("expected a register or a shift amount, found {}", other.describe())),
                };
                match m.as_str() {
                    "lsl" => ctx.asm.lsl(rd, rn, amount),
                    "lsr" => ctx.asm.lsr(rd, rn, amount),
                    "asr" => ctx.asm.asr(rd, rn, amount),
                    _ => ctx.asm.ror(rd, rn, amount),
                }
            }
            "sxtb" | "sxth" | "sxtw" | "uxtb" | "uxth" | "clz" | "cls" | "rbit" | "rev" => {
                arity(&[2])?;
                let (rd, rn) = (reg(&ops[0])?, reg(&ops[1])?);
                match m.as_str() {
                    "sxtb" => ctx.asm.sxtb(rd, rn),
                    "sxth" => ctx.asm.sxth(rd, rn),
                    "sxtw" => ctx.asm.sxtw(rd, rn),
                    "uxtb" => ctx.asm.uxtb(rd, rn),
                    "uxth" => ctx.asm.uxth(rd, rn),
                    "clz" => ctx.asm.clz(rd, rn),
                    "cls" => ctx.asm.cls(rd, rn),
                    "rbit" => ctx.asm.rbit(rd, rn),
                    _ => ctx.asm.rev(rd, rn),
                }
            }
            "ubfx" | "sbfx" | "ubfiz" | "sbfiz" | "bfi" | "bfxil" | "ubfm" | "sbfm" | "bfm" => {
                arity(&[4])?;
                let (rd, rn) = (reg(&ops[0])?, reg(&ops[1])?);
                let (p, q) = (imm(&ops[2], 0, 64)? as u8, imm(&ops[3], 0, 64)? as u8);
                match m.as_str() {
                    "ubfx" => ctx.asm.ubfx(rd, rn, p, q),
                    "sbfx" => ctx.asm.sbfx(rd, rn, p, q),
                    "ubfiz" => ctx.asm.ubfiz(rd, rn, p, q),
                    "sbfiz" => ctx.asm.sbfiz(rd, rn, p, q),
                    "bfi" => ctx.asm.bfi(rd, rn, p, q),
                    "bfxil" => ctx.asm.bfxil(rd, rn, p, q),
                    "ubfm" => ctx.asm.ubfm(rd, rn, p, q),
                    "sbfm" => ctx.asm.sbfm(rd, rn, p, q),
                    _ => ctx.asm.bfm(rd, rn, p, q),
                }
            }
            "extr" => {
                arity(&[4])?;
                ctx.asm.extr(reg(&ops[0])?, reg(&ops[1])?, reg(&ops[2])?, imm(&ops[3], 0, 63)? as u8);
            }
            "csel" | "csinc" | "csinv" | "csneg" => {
                arity(&[4])?;
                let (rd, rn, rm, c) = (reg(&ops[0])?, reg(&ops[1])?, reg(&ops[2])?, cond(&ops[3])?);
                match m.as_str() {
                    "csel" => ctx.asm.csel(rd, rn, rm, c),
                    "csinc" => ctx.asm.csinc(rd, rn, rm, c),
                    "csinv" => ctx.asm.csinv(rd, rn, rm, c),
                    _ => ctx.asm.csneg(rd, rn, rm, c),
                }
            }
            "cset" | "csetm" => {
                arity(&[2])?;
                let (rd, c) = (reg(&ops[0])?, cond(&ops[1])?);
                if m == "cset" { ctx.asm.cset(rd, c) } else { ctx.asm.csetm(rd, c) }
            }
            "cinc" | "cinv" | "cneg" => {
                arity(&[3])?;
                let (rd, rn, c) = (reg(&ops[0])?, reg(&ops[1])?, cond(&ops[2])?);
                match m.as_str() {
                    "cinc" => ctx.asm.cinc(rd, rn, c),
                    "cinv" => ctx.asm.cinv(rd, rn, c),
                    _ => ctx.asm.cneg(rd, rn, c),
                }
            }
            "ccmp" | "ccmn" => {
                arity(&[4])?;
                let rn = reg(&ops[0])?;
                let rhs = match &ops[1] {
                    Op::Reg(r) => Op2::Reg(*r),
                    Op::Imm(v) => Op2::Imm(*v),
                    other => return Err(format!("expected a register or an immediate, found {}", other.describe())),
                };
                let (nzcv, c) = (imm(&ops[2], 0, 15)? as u8, cond(&ops[3])?);
                if m == "ccmp" { ctx.asm.ccmp(rn, rhs, nzcv, c) } else { ctx.asm.ccmn(rn, rhs, nzcv, c) }
            }
            "ldr" | "str" | "ldrb" | "strb" | "ldrh" | "strh" | "ldrsb" | "ldrsh" | "ldrsw" => {
                arity(&[2, 3])?;
                let rt = any(&ops[0])?;
                let literal = matches!(m.as_str(), "ldr" | "ldrsw");
                let mem = ctx.ldst_mem(&ops[1..], access_log2(&m, rt), literal)?;
                match m.as_str() {
                    "ldr" => ctx.asm.ldr(rt, mem),
                    "str" => ctx.asm.str(rt, mem),
                    "ldrb" => ctx.asm.ldrb(gp(rt)?, mem),
                    "strb" => ctx.asm.strb(gp(rt)?, mem),
                    "ldrh" => ctx.asm.ldrh(gp(rt)?, mem),
                    "strh" => ctx.asm.strh(gp(rt)?, mem),
                    "ldrsb" => ctx.asm.ldrsb(gp(rt)?, mem),
                    "ldrsh" => ctx.asm.ldrsh(gp(rt)?, mem),
                    _ => ctx.asm.ldrsw(gp(rt)?, mem),
                }
            }
            "ldur" | "stur" | "ldurb" | "sturb" | "ldurh" | "sturh" | "ldursb" | "ldursh" | "ldursw" => {
                arity(&[2])?;
                let rt = any(&ops[0])?;
                let (base, offset) = match &ops[1] {
                    Op::Mem(PMem { base, offset: MemOff::None, writeback: false }) => (*base, 0),
                    Op::Mem(PMem { base, offset: MemOff::Imm(v), writeback: false }) => (*base, *v),
                    _ => return Err(format!("`{m}` takes `[base, #offset]`")),
                };
                match m.as_str() {
                    "ldur" => ctx.asm.ldur(rt, base, offset),
                    "stur" => ctx.asm.stur(rt, base, offset),
                    "ldurb" => ctx.asm.ldurb(gp(rt)?, base, offset),
                    "sturb" => ctx.asm.sturb(gp(rt)?, base, offset),
                    "ldurh" => ctx.asm.ldurh(gp(rt)?, base, offset),
                    "sturh" => ctx.asm.sturh(gp(rt)?, base, offset),
                    "ldursb" => ctx.asm.ldursb(gp(rt)?, base, offset),
                    "ldursh" => ctx.asm.ldursh(gp(rt)?, base, offset),
                    _ => ctx.asm.ldursw(gp(rt)?, base, offset),
                }
            }
            "ldp" | "stp" => {
                arity(&[3, 4])?;
                let (rt1, rt2) = (any(&ops[0])?, any(&ops[1])?);
                let mem = match &ops[2..] {
                    [Op::Mem(PMem { offset: MemOff::Index { .. } | MemOff::Sym(_), .. })] => {
                        return Err("a register pair takes [base, #offset], [base, #offset]! or [base], #offset".into());
                    }
                    rest => ctx.ldst_mem(rest, 3, false)?,
                };
                if m == "ldp" { ctx.asm.ldp(rt1, rt2, mem) } else { ctx.asm.stp(rt1, rt2, mem) }
            }
            "adrp" => {
                arity(&[2])?;
                let rd = reg(&ops[0])?;
                match &ops[1] {
                    Op::Sym(s) if is_local(&s.name) => {
                        return Err(format!("`adrp` to the local label `{}`; use `adr`", s.name));
                    }
                    Op::Sym(SymRef { name, addend, modifier: Modifier::None | Modifier::Page }) => {
                        ctx.asm.adrp(rd, name, *addend)
                    }
                    Op::Sym(SymRef { name, addend: 0, modifier: Modifier::GotPage }) => ctx.asm.adrp_got(rd, name),
                    Op::Sym(SymRef { modifier: Modifier::GotPage, .. }) => {
                        return Err("a GOT page takes no addend".into());
                    }
                    _ => return Err("expected `sym@PAGE`, `sym@GOTPAGE`, `sym` or `:got:sym`".into()),
                }
            }
            "adr" => {
                arity(&[2])?;
                let rd = reg(&ops[0])?;
                let (label, addend) = ctx.local(&ops[1], "adr")?;
                let addend = i32::try_from(addend).map_err(|_| "offset out of range".to_string())?;
                ctx.asm.adr(rd, label, addend);
            }
            "b" | "bl" => {
                arity(&[1])?;
                let target = match &ops[0] {
                    Op::Sym(SymRef { addend: 0, modifier: Modifier::None, name }) => {
                        if is_local(name) {
                            Target::Label(ctx.label(name))
                        } else {
                            Target::Sym(name.clone())
                        }
                    }
                    Op::Sym(_) => return Err("a branch target cannot have an offset or operator".into()),
                    other => return Err(format!("expected a label or symbol, found {}", other.describe())),
                };
                if m == "b" { ctx.asm.b(target) } else { ctx.asm.bl(target) }
            }
            "cbz" | "cbnz" => {
                arity(&[2])?;
                let rt = reg(&ops[0])?;
                let (label, addend) = ctx.local(&ops[1], &m)?;
                if addend != 0 {
                    return Err("a branch target cannot have an offset".into());
                }
                if m == "cbz" { ctx.asm.cbz(rt, label) } else { ctx.asm.cbnz(rt, label) }
            }
            "tbz" | "tbnz" => {
                arity(&[3])?;
                let (rt, bit) = (reg(&ops[0])?, imm(&ops[1], 0, 63)? as u8);
                let (label, addend) = ctx.local(&ops[2], &m)?;
                if addend != 0 {
                    return Err("a branch target cannot have an offset".into());
                }
                if m == "tbz" { ctx.asm.tbz(rt, bit, label) } else { ctx.asm.tbnz(rt, bit, label) }
            }
            "br" | "blr" => {
                arity(&[1])?;
                let rn = reg(&ops[0])?;
                if m == "br" { ctx.asm.br(rn) } else { ctx.asm.blr(rn) }
            }
            "ret" => {
                arity(&[0, 1])?;
                match ops.first() {
                    None => ctx.asm.ret(),
                    Some(op) => ctx.asm.ret_to(reg(op)?),
                }
            }
            "fmov" => {
                arity(&[2])?;
                match &ops[1] {
                    Op::Float(v) => ctx.asm.fmov_imm(vreg(&ops[0])?, *v),
                    Op::Imm(v) => ctx.asm.fmov_imm(vreg(&ops[0])?, *v as f64),
                    src => ctx.asm.fmov(any(&ops[0])?, any(src)?),
                }
            }
            "fadd" | "fsub" | "fmul" | "fdiv" | "fmax" | "fmin" | "fmaxnm" | "fminnm" | "fnmul" => {
                arity(&[3])?;
                let (d, a, b) = (vreg(&ops[0])?, vreg(&ops[1])?, vreg(&ops[2])?);
                match m.as_str() {
                    "fadd" => ctx.asm.fadd(d, a, b),
                    "fsub" => ctx.asm.fsub(d, a, b),
                    "fmul" => ctx.asm.fmul(d, a, b),
                    "fdiv" => ctx.asm.fdiv(d, a, b),
                    "fmax" => ctx.asm.fmax(d, a, b),
                    "fmin" => ctx.asm.fmin(d, a, b),
                    "fmaxnm" => ctx.asm.fmaxnm(d, a, b),
                    "fminnm" => ctx.asm.fminnm(d, a, b),
                    _ => ctx.asm.fnmul(d, a, b),
                }
            }
            "fneg" | "fabs" | "fsqrt" | "fcvt" | "frintx" | "frinti" => {
                arity(&[2])?;
                let (d, s) = (vreg(&ops[0])?, vreg(&ops[1])?);
                match m.as_str() {
                    "fneg" => ctx.asm.fneg(d, s),
                    "fabs" => ctx.asm.fabs(d, s),
                    "fsqrt" => ctx.asm.fsqrt(d, s),
                    "fcvt" => ctx.asm.fcvt(d, s),
                    "frintx" => ctx.asm.frintx(d, s),
                    _ => ctx.asm.frinti(d, s),
                }
            }
            "fcmp" | "fcmpe" => {
                arity(&[2])?;
                let vn = vreg(&ops[0])?;
                let e = m == "fcmpe";
                match &ops[1] {
                    // Only `#0.0`: clang rejects `#0` here.
                    Op::Float(z) if *z == 0.0 => {
                        if e {
                            ctx.asm.fcmpe_zero(vn)
                        } else {
                            ctx.asm.fcmp_zero(vn)
                        }
                    }
                    Op::Float(_) | Op::Imm(_) => return Err("the only immediate `fcmp` takes is #0.0".into()),
                    other => {
                        let vm = vreg(other)?;
                        if e { ctx.asm.fcmpe(vn, vm) } else { ctx.asm.fcmp(vn, vm) }
                    }
                }
            }
            "fcsel" => {
                arity(&[4])?;
                ctx.asm.fcsel(vreg(&ops[0])?, vreg(&ops[1])?, vreg(&ops[2])?, cond(&ops[3])?);
            }
            "scvtf" | "ucvtf" => {
                arity(&[2])?;
                let (vd, rn) = (vreg(&ops[0])?, reg(&ops[1])?);
                if m == "scvtf" { ctx.asm.scvtf(vd, rn) } else { ctx.asm.ucvtf(vd, rn) }
            }
            "nop" | "isb" if n == 0 => {
                if m == "nop" {
                    ctx.asm.nop()
                } else {
                    ctx.asm.isb()
                }
            }
            "isb" if n == 1 && keyword(&ops[0]).is_some_and(|k| k.eq_ignore_ascii_case("sy")) => ctx.asm.isb(),
            "brk" | "udf" | "svc" => {
                arity(&[1])?;
                let v = imm(&ops[0], 0, 0xffff)? as u16;
                match m.as_str() {
                    "brk" => ctx.asm.brk(v),
                    "udf" => ctx.asm.udf(v),
                    _ => ctx.asm.svc(v),
                }
            }
            "dmb" | "dsb" => {
                arity(&[1])?;
                if !keyword(&ops[0]).is_some_and(|k| k.eq_ignore_ascii_case("ish")) {
                    return Err(format!("only `{m} ish` is supported"));
                }
                if m == "dmb" { ctx.asm.dmb_ish() } else { ctx.asm.dsb_ish() }
            }
            "mrs" => {
                arity(&[2])?;
                let rt = reg(&ops[0])?;
                let sr = keyword(&ops[1]).and_then(SysReg::parse).ok_or("expected `nzcv`, `fpcr` or `fpsr`")?;
                ctx.asm.mrs(rt, sr);
            }
            "msr" => {
                arity(&[2])?;
                let sr = keyword(&ops[0]).and_then(SysReg::parse).ok_or("expected `nzcv`, `fpcr` or `fpsr`")?;
                ctx.asm.msr(sr, reg(&ops[1])?);
            }
            "nop" | "isb" => return Err(format!("`{m}` takes no operands")),
            _ => return Err(format!("unknown instruction `{mnemonic}`")),
        }
    }
    match ctx.asm.take_error() {
        Some(e) => Err(e.message),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::super::lexer::lex_a64;
    use super::*;

    fn op(s: &str) -> Result<Op, String> {
        let mut c = Consts::new();
        c.insert("EIGHT".into(), 8);
        // Lexed after a mnemonic, since `#` at the start of a line is a comment.
        operand(&lex_a64(&format!("op {s}")).unwrap()[1..], &c)
    }

    fn sym(name: &str, addend: i64, modifier: Modifier) -> Op {
        Op::Sym(SymRef { name: name.into(), addend, modifier })
    }

    #[test]
    fn operands() {
        use crate::aarch64::regs::*;
        assert_eq!(op("x5"), Ok(Op::Reg(X5)));
        assert_eq!(op("WZR"), Ok(Op::Reg(WZR)));
        assert_eq!(op("fp"), Ok(Op::Reg(X29)));
        assert_eq!(op("d31"), Ok(Op::V(D31)));
        assert_eq!(op("#-EIGHT * 2"), Ok(Op::Imm(-16)));
        assert_eq!(op("16"), Ok(Op::Imm(16)));
        assert_eq!(op("#-0.5"), Ok(Op::Float(-0.5)));
        assert_eq!(op("lsl #12"), Ok(Op::Shift(Shift::Lsl, 12)));
        assert_eq!(op("sxtw"), Ok(Op::Extend(Extend::Sxtw, None)));
        assert_eq!(op("uxtw #2"), Ok(Op::Extend(Extend::Uxtw, Some(2))));
        assert_eq!(op("_x@PAGE"), Ok(sym("_x", 0, Modifier::Page)));
        assert_eq!(op("_x@PAGEOFF + 8"), Ok(sym("_x", 8, Modifier::PageOff)));
        assert_eq!(op(":lo12:x+4"), Ok(sym("x", 4, Modifier::PageOff)));
        assert_eq!(op("#:got_lo12:x"), Ok(sym("x", 0, Modifier::GotPageOff)));
        assert_eq!(op(":got:x"), Ok(sym("x", 0, Modifier::GotPage)));
        assert_eq!(op("eq"), Ok(sym("eq", 0, Modifier::None)));
        assert!(op("_x@TLVPPAGE").is_err());
        assert!(op(":pg_hi21:x").is_err());
        assert!(op("_x - _y").is_err());
        let m = |s: &str| match op(s) {
            Ok(Op::Mem(m)) => m,
            other => panic!("{s}: {other:?}"),
        };
        assert_eq!(m("[sp, #-16]!"), PMem { base: SP, offset: MemOff::Imm(-16), writeback: true });
        assert_eq!(m("[x1]"), PMem { base: X1, offset: MemOff::None, writeback: false });
        assert_eq!(
            m("[x1, w2, sxtw #3]"),
            PMem {
                base: X1,
                offset: MemOff::Index { index: W2, ext: Some((IndexExt::Sxtw, Some(3))) },
                writeback: false
            }
        );
        assert_eq!(
            m("[x1, _g@PAGEOFF+4]").offset,
            MemOff::Sym(SymRef { name: "_g".into(), addend: 4, modifier: Modifier::PageOff })
        );
        assert!(op("[x1, _g]").is_err());
        assert!(op("[x1, x2]!").is_err());
        assert!(op("[x1, #8").is_err());
        assert!(op("[w1]").is_ok_and(|o| matches!(o, Op::Mem(PMem { base: W1, .. }))));
    }
}
