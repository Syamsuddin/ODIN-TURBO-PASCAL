// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Expressions and instruction operands.

use std::collections::HashMap;

use super::lexer::Tok;
use crate::x86_64::{Reg, Width, Xmm};

/// Constants defined with `.set`, `.equ` or `name = value`.
pub(crate) type Consts = HashMap<String, i64>;

/// An operand as written, before labels are resolved.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum POp {
    Reg(Reg, Width),
    Xmm(Xmm),
    Mem(PMem),
    Imm(i64),
    /// A bare symbol or `.L` label, optionally plus a constant: a branch
    /// target.
    Sym(String, i64),
}

/// A memory operand as written.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct PMem {
    /// Size in bytes from `byte ptr` .. `xmmword ptr`, if given.
    pub size: Option<u32>,
    pub base: Option<Reg>,
    pub index: Option<(Reg, u8)>,
    pub disp: i64,
    pub rip: bool,
    pub sym: Option<String>,
    pub got: bool,
}

/// A value that may be a symbol address: `sym + addend` or a constant.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SymValue {
    pub sym: Option<String>,
    pub got: bool,
    pub value: i64,
}

/// Converts an expression result to the 64-bit value it denotes: anything
/// from `i64::MIN` to `u64::MAX` (stored as its two's complement bits).
fn to_i64(v: i128) -> Result<i64, String> {
    if v < i64::MIN as i128 || v > u64::MAX as i128 {
        Err(format!("value {v} does not fit in 64 bits"))
    } else {
        Ok(v as i64)
    }
}

/// Recursive-descent evaluator for constant expressions with C precedence:
/// `| ^ & << >> + - * / %`, unary `- ~ +`, and parentheses.
struct Eval<'a> {
    toks: &'a [Tok],
    pos: usize,
    consts: &'a Consts,
}

impl Eval<'_> {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos)
    }

    fn binary(&mut self, level: u8) -> Result<i128, String> {
        if level == 6 {
            return self.unary();
        }
        let mut lhs = self.binary(level + 1)?;
        loop {
            let op = match (level, self.peek()) {
                (0, Some(Tok::Punct('|'))) => '|',
                (1, Some(Tok::Punct('^'))) => '^',
                (2, Some(Tok::Punct('&'))) => '&',
                (3, Some(Tok::Shl)) => '<',
                (3, Some(Tok::Shr)) => '>',
                (4, Some(Tok::Punct(c @ ('+' | '-')))) => *c,
                (5, Some(Tok::Punct(c @ ('*' | '/' | '%')))) => *c,
                _ => return Ok(lhs),
            };
            self.pos += 1;
            let rhs = self.binary(level + 1)?;
            lhs = match op {
                '|' => lhs | rhs,
                '^' => lhs ^ rhs,
                '&' => lhs & rhs,
                '<' => {
                    if !(0..64).contains(&rhs) {
                        return Err(format!("shift count {rhs} out of range"));
                    }
                    lhs.checked_mul(1 << rhs).ok_or("overflow in constant expression")?
                }
                '>' => {
                    if !(0..64).contains(&rhs) {
                        return Err(format!("shift count {rhs} out of range"));
                    }
                    lhs >> rhs
                }
                '+' => lhs + rhs,
                '-' => lhs - rhs,
                '*' => lhs.checked_mul(rhs).ok_or("overflow in constant expression")?,
                '/' | '%' if rhs == 0 => return Err("division by zero in constant expression".into()),
                '/' => lhs / rhs,
                _ => lhs % rhs,
            };
            if lhs.unsigned_abs() > u128::from(u64::MAX) << 2 {
                return Err("overflow in constant expression".into());
            }
        }
    }

    fn unary(&mut self) -> Result<i128, String> {
        match self.peek() {
            Some(Tok::Punct('-')) => {
                self.pos += 1;
                Ok(-self.unary()?)
            }
            Some(Tok::Punct('+')) => {
                self.pos += 1;
                self.unary()
            }
            Some(Tok::Punct('~')) => {
                self.pos += 1;
                Ok(!(to_i64(self.unary()?)? as i128))
            }
            Some(Tok::Punct('(')) => {
                self.pos += 1;
                let v = self.binary(0)?;
                if !self.peek().is_some_and(|t| t.is_punct(')')) {
                    return Err("missing `)`".into());
                }
                self.pos += 1;
                Ok(v)
            }
            Some(Tok::Num(n)) => {
                let n = *n;
                self.pos += 1;
                Ok(n)
            }
            Some(Tok::Ident(name)) => match self.consts.get(name) {
                Some(v) => {
                    self.pos += 1;
                    Ok(*v as i128)
                }
                None => Err(format!("`{name}` is not a constant")),
            },
            Some(t) => Err(format!("unexpected {} in expression", t.describe())),
            None => Err("missing value".into()),
        }
    }
}

/// Evaluates a constant expression that must use all of `toks`.
pub(crate) fn const_expr(toks: &[Tok], consts: &Consts) -> Result<i64, String> {
    let mut e = Eval { toks, pos: 0, consts };
    let v = e.binary(0)?;
    if let Some(t) = e.peek() {
        return Err(format!("unexpected {} in expression", t.describe()));
    }
    to_i64(v)
}

/// Splits `toks` at top-level commas (outside brackets and parentheses).
pub(crate) fn split_commas(toks: &[Tok]) -> Vec<&[Tok]> {
    let mut parts = Vec::new();
    let mut depth = 0i32;
    let mut start = 0;
    for (i, t) in toks.iter().enumerate() {
        match t {
            Tok::Punct('(' | '[') => depth += 1,
            Tok::Punct(')' | ']') => depth -= 1,
            Tok::Punct(',') if depth == 0 => {
                parts.push(&toks[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    if !toks.is_empty() {
        parts.push(&toks[start..]);
    }
    parts
}

/// Splits `toks` into top-level additive terms, each with its sign
/// (`true` for minus). A `+` or `-` that follows an operator is unary and
/// stays inside its term.
pub(crate) fn split_terms(toks: &[Tok]) -> Result<Vec<(bool, &[Tok])>, String> {
    let mut terms = Vec::new();
    let mut depth = 0i32;
    let mut start = 0;
    let mut neg = false;
    for (i, t) in toks.iter().enumerate() {
        match t {
            Tok::Punct('(') => depth += 1,
            Tok::Punct(')') => depth -= 1,
            Tok::Punct(c @ ('+' | '-')) if depth == 0 && i > start => {
                let after_operand = matches!(toks[i - 1], Tok::Num(_) | Tok::Ident(_) | Tok::Punct(')'));
                if after_operand {
                    terms.push((neg, &toks[start..i]));
                    neg = *c == '-';
                    start = i + 1;
                }
            }
            _ => {}
        }
    }
    if start >= toks.len() {
        return Err("missing value".into());
    }
    terms.push((neg, &toks[start..]));
    Ok(terms)
}

/// Whether `name` is a register (any width, including the unsupported
/// high-byte ones), `rip` or an xmm register, so it cannot be a symbol.
fn is_reg_name(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    Reg::parse(&lower).is_some()
        || Xmm::parse(&lower).is_some()
        || matches!(lower.as_str(), "rip" | "ah" | "bh" | "ch" | "dh" | "eip")
}

/// If `term` is a symbol reference (`name` or `name@GOTPCREL`), returns it.
fn symbol_term(term: &[Tok], consts: &Consts) -> Result<Option<(String, bool)>, String> {
    match term {
        [Tok::Ident(name)] if !consts.contains_key(name) && !is_reg_name(name) => Ok(Some((name.clone(), false))),
        [Tok::Ident(name), Tok::Punct('@'), Tok::Ident(kind)] if !is_reg_name(name) => {
            if kind.eq_ignore_ascii_case("GOTPCREL") {
                Ok(Some((name.clone(), true)))
            } else {
                Err(format!("unsupported symbol modifier `@{kind}`"))
            }
        }
        _ => Ok(None),
    }
}

/// Evaluates `sym + constant`, `constant + sym` or a constant.
pub(crate) fn sym_value(toks: &[Tok], consts: &Consts) -> Result<SymValue, String> {
    let mut out = SymValue { sym: None, got: false, value: 0 };
    let mut acc: i128 = 0;
    for (neg, term) in split_terms(toks)? {
        if let Some((name, got)) = symbol_term(term, consts)? {
            if out.sym.is_some() {
                return Err("only one symbol is allowed in an expression".into());
            }
            if neg {
                return Err(format!("cannot subtract symbol `{name}`"));
            }
            out.sym = Some(name);
            out.got = got;
        } else {
            let v = const_expr(term, consts)? as i128;
            acc += if neg { -v } else { v };
        }
    }
    out.value = to_i64(acc)?;
    Ok(out)
}

/// Parses one instruction operand.
pub(crate) fn operand(toks: &[Tok], consts: &Consts) -> Result<POp, String> {
    let (size, rest) = match toks {
        [Tok::Ident(kw), Tok::Ident(ptr), rest @ ..] if ptr.eq_ignore_ascii_case("ptr") => {
            let size = match kw.to_ascii_lowercase().as_str() {
                "byte" => 1,
                "word" => 2,
                "dword" => 4,
                "qword" => 8,
                "xmmword" => 16,
                _ => return Err(format!("unknown operand size `{kw}`")),
            };
            (Some(size), rest)
        }
        _ => (None, toks),
    };
    if let [Tok::Punct('['), inner @ .., Tok::Punct(']')] = rest {
        let mut m = memory(inner, consts)?;
        m.size = size;
        return Ok(POp::Mem(m));
    }
    if size.is_some() {
        return Err("expected `[` after `ptr`".into());
    }
    if let [Tok::Ident(name)] = rest {
        let lower = name.to_ascii_lowercase();
        if let Some((r, w)) = Reg::parse(&lower) {
            return Ok(POp::Reg(r, w));
        }
        if let Some(x) = Xmm::parse(&lower) {
            return Ok(POp::Xmm(x));
        }
        if matches!(lower.as_str(), "ah" | "bh" | "ch" | "dh") {
            return Err(format!("high-byte register `{name}` is not supported"));
        }
    }
    if rest.is_empty() {
        return Err("missing operand".into());
    }
    let v = sym_value(rest, consts)?;
    match v.sym {
        Some(_) if v.got => Err("`@GOTPCREL` is only allowed in `[rip + sym@GOTPCREL]`".into()),
        Some(name) => Ok(POp::Sym(name, v.value)),
        None => Ok(POp::Imm(v.value)),
    }
}

/// Parses the inside of `[...]`.
fn memory(toks: &[Tok], consts: &Consts) -> Result<PMem, String> {
    let mut m = PMem::default();
    let mut disp: i128 = 0;
    let mut regs: Vec<(Reg, u8, bool)> = Vec::new(); // (reg, scale, scale written)
    let reg64 = |name: &str| -> Result<Option<Reg>, String> {
        match Reg::parse(name) {
            Some((r, Width::W64)) => Ok(Some(r)),
            Some(_) => Err(format!("`{name}` cannot address memory; use a 64-bit register")),
            None => Ok(None),
        }
    };
    for (neg, term) in split_terms(toks)? {
        // Registers, `rip`, `reg*scale` and `scale*reg`.
        let scaled = match term {
            [Tok::Ident(r)] if r.eq_ignore_ascii_case("rip") => {
                if neg || m.rip {
                    return Err("bad use of `rip`".into());
                }
                m.rip = true;
                continue;
            }
            [Tok::Ident(r)] => reg64(r)?.map(|r| (r, 1, false)),
            [Tok::Ident(r), Tok::Punct('*'), s @ ..] => match reg64(r)? {
                Some(r) => Some((r, scale(s, consts)?, true)),
                None => None,
            },
            [s @ .., Tok::Punct('*'), Tok::Ident(r)] => match reg64(r)? {
                Some(r) => Some((r, scale(s, consts)?, true)),
                None => None,
            },
            _ => None,
        };
        if let Some(reg) = scaled {
            if neg {
                return Err("a register cannot be subtracted".into());
            }
            regs.push(reg);
            continue;
        }
        if let Some((name, got)) = symbol_term(term, consts)? {
            if neg {
                return Err(format!("cannot subtract symbol `{name}`"));
            }
            if m.sym.is_some() {
                return Err("only one symbol is allowed in an address".into());
            }
            m.sym = Some(name);
            m.got = got;
            continue;
        }
        let v = const_expr(term, consts)? as i128;
        disp += if neg { -v } else { v };
    }
    m.disp = to_i64(disp)?;
    match regs.as_slice() {
        [] => {}
        [(r, s, written)] => {
            if *written || *s != 1 {
                m.index = Some((*r, *s));
            } else {
                m.base = Some(*r);
            }
        }
        [(b, 1, false), (i, s, _)] => {
            // `[rax + rsp]` is encoded as `[rsp + rax]`, like GNU as does.
            if *i == Reg::Rsp && *s == 1 {
                m.base = Some(*i);
                m.index = Some((*b, 1));
            } else {
                m.base = Some(*b);
                m.index = Some((*i, *s));
            }
        }
        [(i, s, true), (b, 1, false)] => {
            m.base = Some(*b);
            m.index = Some((*i, *s));
        }
        _ => return Err("an address has at most a base and a scaled index register".into()),
    }
    if m.rip && (m.base.is_some() || m.index.is_some()) {
        return Err("`rip` cannot be combined with other registers".into());
    }
    if m.got && (!m.rip || m.disp != 0) {
        return Err("`@GOTPCREL` is only allowed as `[rip + sym@GOTPCREL]`".into());
    }
    Ok(m)
}

fn scale(toks: &[Tok], consts: &Consts) -> Result<u8, String> {
    match const_expr(toks, consts)? {
        s @ (1 | 2 | 4 | 8) => Ok(s as u8),
        s => Err(format!("scale {s} is not 1, 2, 4 or 8")),
    }
}

#[cfg(test)]
mod tests {
    use super::super::lexer::lex;
    use super::*;

    fn op(s: &str) -> Result<POp, String> {
        let mut c = Consts::new();
        c.insert("FOUR".into(), 4);
        operand(&lex(s).unwrap(), &c)
    }

    #[test]
    fn expressions() {
        let c = Consts::new();
        let e = |s: &str| const_expr(&lex(s).unwrap(), &c);
        assert_eq!(e("1 + 2 * 3"), Ok(7));
        assert_eq!(e("(1 + 2) * 3"), Ok(9));
        assert_eq!(e("-8 - -2"), Ok(-6));
        assert_eq!(e("1 << 4 | 1"), Ok(17));
        assert_eq!(e("~0"), Ok(-1));
        assert_eq!(e("0xffffffffffffffff"), Ok(-1));
        assert!(e("1 / 0").is_err());
        assert!(e("foo").is_err());
    }

    #[test]
    fn operands() {
        assert_eq!(op("r9d"), Ok(POp::Reg(Reg::R9, Width::W32)));
        assert_eq!(op("sil"), Ok(POp::Reg(Reg::Rsi, Width::W8)));
        assert_eq!(op("xmm12"), Ok(POp::Xmm(Xmm::Xmm12)));
        assert!(op("ah").is_err());
        assert_eq!(op("-FOUR * 2"), Ok(POp::Imm(-8)));
        assert_eq!(op("foo + 8"), Ok(POp::Sym("foo".into(), 8)));
        let m = |s: &str| match op(s) {
            Ok(POp::Mem(m)) => m,
            other => panic!("{s}: {other:?}"),
        };
        let a = m("qword ptr [rbp - 8]");
        assert_eq!((a.size, a.base, a.disp), (Some(8), Some(Reg::Rbp), -8));
        let b = m("[rax + 8*rcx + FOUR]");
        assert_eq!((b.base, b.index, b.disp), (Some(Reg::Rax), Some((Reg::Rcx, 8)), 4));
        let c = m("[rax + rsp]");
        assert_eq!((c.base, c.index), (Some(Reg::Rsp), Some((Reg::Rax, 1))));
        let d = m("[rip + _write@GOTPCREL]");
        assert!(d.rip && d.got && d.sym.as_deref() == Some("_write"));
        let e = m("[rcx*4]");
        assert_eq!((e.base, e.index), (None, Some((Reg::Rcx, 4))));
        assert!(op("[eax]").is_err());
        assert!(op("[rax - rbx]").is_err());
        assert!(op("[rax*3]").is_err());
        assert!(op("[rip + rax]").is_err());
    }
}
