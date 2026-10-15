// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! The code buffer behind [`Assembler`]: labels, fixups, relocations, branch
//! relaxation and the ModRM/SIB encoder that the instruction methods in
//! `insts.rs` build on.
//!
//! Bytes whose size never changes go to one flat buffer. Jumps to labels and
//! alignment padding are kept aside as variable-size items, each anchored at
//! a position in that buffer. Every other position (labels, fixups,
//! relocations) is recorded as "buffer offset + number of variable items
//! before it", so [`Assembler::finish`] can compute final offsets once the
//! sizes of the variable items are known.

use std::fmt;

use super::operand::{Cond, Label, Mem, Reg};
use crate::object::{Atom, Reloc, RelocKind, SectionKind};

/// An instruction that cannot be encoded, an invalid label use, or a value
/// that does not fit its field.
///
/// Instruction methods do not return errors: the first one is kept by the
/// [`Assembler`] (later instructions are still encoded) and returned by
/// [`Assembler::finish`]. [`Assembler::take_error`] lets a caller that wants
/// per-instruction diagnostics (the text assembler) check after each call.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EncodeError {
    /// What went wrong, starting with the mnemonic, e.g.
    /// `"mov: invalid operands (memory, memory)"`.
    pub message: String,
    /// Offset of the failing instruction in the code buffer, counting every
    /// jump as short. Only a hint for locating the instruction.
    pub offset: u32,
}

impl fmt::Display for EncodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} (near code offset {:#x})", self.message, self.offset)
    }
}

impl std::error::Error for EncodeError {}

pub(crate) type EncResult = Result<(), String>;

/// A position: offset in the fixed buffer plus the number of variable-size
/// items emitted before it.
#[derive(Clone, Copy, Debug)]
struct Pos {
    at: u32,
    vars: u32,
}

#[derive(Clone, Copy, Debug)]
enum VarKind {
    /// `jmp` (no condition) or `jcc` to a label: 2 bytes short, 5 or 6 near.
    Jump { cond: Option<Cond>, target: Label },
    /// NOP padding up to a multiple of the alignment.
    Align(u32),
}

#[derive(Clone, Copy, Debug)]
struct Var {
    at: u32,
    kind: VarKind,
    /// For jumps: the near (rel32) form has been chosen.
    long: bool,
}

#[derive(Clone, Copy, Debug)]
enum FixKind {
    /// 32-bit `target + addend - end_of_instruction`, where the instruction
    /// ends `end` bytes after the start of the field.
    Rel32 { end: u8, addend: i64 },
    /// 32-bit `target - base`.
    Diff32 { base: Label },
}

#[derive(Clone, Copy, Debug)]
struct Fixup {
    pos: Pos,
    target: Label,
    kind: FixKind,
}

#[derive(Clone, Debug)]
struct SymReloc {
    pos: Pos,
    kind: RelocKind,
    target: String,
    addend: i64,
}

/// The register-or-memory operand of a ModRM byte. Registers are given by
/// hardware number so general-purpose and xmm registers share the path.
#[derive(Clone, Copy, Debug)]
pub(crate) enum RmArg<'a> {
    Reg(u8),
    Mem(&'a Mem),
}

/// Whether register number `index` used as an 8-bit operand needs a REX
/// prefix to mean `spl`/`bpl`/`sil`/`dil` instead of `ah`/`ch`/`dh`/`bh`.
pub(crate) fn rex8(index: u8) -> bool {
    (4..8).contains(&index)
}

/// Builds the machine code of one function (or any other run of code) for
/// x86-64.
///
/// Instruction methods are named after the Intel mnemonic and take the
/// destination first, as in Intel syntax. Integer instructions take a
/// [`Width`](super::Width); operands are anything convertible into
/// [`Operand`](super::Operand) (registers, [`Mem`], integers). An invalid
/// combination does not panic: the first error is kept and returned by
/// [`finish`](Assembler::finish).
///
/// ```
/// use odin_asm::x86_64::{Assembler, Cond, Mem, Reg::*, Width::*};
///
/// let mut a = Assembler::new();
/// let done = a.new_label();
/// a.push(Rbp);
/// a.mov(W64, Rbp, Rsp);
/// a.mov(W32, Rax, Mem::base(Rdi, 8));
/// a.cmp(W32, Rax, 10);
/// a.jcc(Cond::L, done);
/// a.call("_odin_overflow");
/// a.bind(done);
/// a.leave();
/// a.ret();
/// let code = a.finish().unwrap();
/// assert_eq!(code.relocs.len(), 1);
/// ```
#[derive(Clone, Debug)]
pub struct Assembler {
    buf: Vec<u8>,
    vars: Vec<Var>,
    labels: Vec<Option<Pos>>,
    used: Vec<bool>,
    /// Labels whose `used` flag went from false to true, in order, so a
    /// failed instruction can undo its marks.
    newly_used: Vec<u32>,
    fixups: Vec<Fixup>,
    relocs: Vec<SymReloc>,
    exports: Vec<(String, Label)>,
    max_align: u32,
    error: Option<EncodeError>,
}

impl Default for Assembler {
    fn default() -> Self {
        Self::new()
    }
}

/// The result of [`Assembler::finish`]: final bytes, relocations and label
/// offsets, all relative to the start of the code.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Code {
    pub bytes: Vec<u8>,
    /// Relocations against symbols, with offsets relative to the start of
    /// `bytes`. References to labels are already resolved and never appear
    /// here.
    pub relocs: Vec<Reloc>,
    /// Largest alignment requested with [`Assembler::align`] (1 if none). The
    /// code must be placed at a multiple of it for that padding to be right.
    pub align: u32,
    /// Names given with [`Assembler::export`], with their final offsets.
    pub exports: Vec<(String, u32)>,
    labels: Vec<Option<u32>>,
}

impl Code {
    /// Final offset of `label`, or `None` if it was never bound.
    pub fn label_offset(&self, label: Label) -> Option<u32> {
        self.labels.get(label.0 as usize).copied().flatten()
    }

    /// Final offsets of all labels, indexed by [`Label::index`].
    pub fn label_offsets(&self) -> &[Option<u32>] {
        &self.labels
    }

    /// Wraps the code in a [`SectionKind::Text`] atom with its relocations
    /// and exported labels. The atom's alignment is the larger of `align`
    /// and [`Code::align`].
    pub fn into_atom(self, name: impl Into<String>, align: u32) -> Atom {
        let mut atom = Atom::new(name, SectionKind::Text, align.max(self.align), self.bytes);
        atom.relocs = self.relocs;
        atom.labels = self.exports.into_iter().map(|(n, off)| (n, off as u64)).collect();
        atom
    }
}

impl Assembler {
    pub fn new() -> Self {
        Assembler {
            buf: Vec::new(),
            vars: Vec::new(),
            labels: Vec::new(),
            used: Vec::new(),
            newly_used: Vec::new(),
            fixups: Vec::new(),
            relocs: Vec::new(),
            exports: Vec::new(),
            max_align: 1,
            error: None,
        }
    }

    // ----- labels -------------------------------------------------------

    /// Creates an unbound label.
    pub fn new_label(&mut self) -> Label {
        self.labels.push(None);
        self.used.push(false);
        Label(self.labels.len() as u32 - 1)
    }

    /// Binds `label` to the current position. Binding a label twice is an
    /// error.
    pub fn bind(&mut self, label: Label) {
        let pos = self.pos();
        self.run("bind", |a| match a.labels.get_mut(label.0 as usize) {
            None => Err(format!("label L{} does not belong to this assembler", label.0)),
            Some(Some(_)) => Err(format!("label L{} is bound twice", label.0)),
            Some(slot) => {
                *slot = Some(pos);
                Ok(())
            }
        });
    }

    /// Creates a label bound to the current position.
    pub fn here(&mut self) -> Label {
        let l = self.new_label();
        self.bind(l);
        l
    }

    /// Whether `label` has been bound.
    pub fn is_bound(&self, label: Label) -> bool {
        matches!(self.labels.get(label.0 as usize), Some(Some(_)))
    }

    /// Publishes `label` under `name`: [`Code::into_atom`] adds it to
    /// [`Atom::labels`] so other atoms can refer to that point by name.
    pub fn export(&mut self, name: impl Into<String>, label: Label) {
        self.exports.push((name.into(), label));
    }

    // ----- errors -------------------------------------------------------

    /// The first error so far, if any.
    pub fn error(&self) -> Option<&EncodeError> {
        self.error.as_ref()
    }

    /// Removes and returns the first error so far, so encoding can go on as
    /// if it had not happened.
    pub fn take_error(&mut self) -> Option<EncodeError> {
        self.error.take()
    }

    /// Runs one encoding step. On failure, everything the step emitted is
    /// rolled back and the error is kept (unless an earlier one is).
    pub(crate) fn run(&mut self, name: &str, f: impl FnOnce(&mut Self) -> EncResult) {
        let marks = (self.buf.len(), self.vars.len(), self.fixups.len(), self.relocs.len(), self.newly_used.len());
        if let Err(message) = f(self) {
            self.buf.truncate(marks.0);
            self.vars.truncate(marks.1);
            self.fixups.truncate(marks.2);
            self.relocs.truncate(marks.3);
            for l in self.newly_used.drain(marks.4..) {
                self.used[l as usize] = false;
            }
            if self.error.is_none() {
                let offset = self.provisional_offset();
                self.error = Some(EncodeError { message: format!("{name}: {message}"), offset });
            }
        }
    }

    fn pos(&self) -> Pos {
        Pos { at: self.buf.len() as u32, vars: self.vars.len() as u32 }
    }

    /// Current offset assuming every jump is short (a lower bound).
    fn provisional_offset(&self) -> u32 {
        self.buf.len() as u32 + self.vars.iter().filter(|v| matches!(v.kind, VarKind::Jump { .. })).count() as u32 * 2
    }

    pub(crate) fn use_label(&mut self, label: Label) -> EncResult {
        match self.used.get_mut(label.0 as usize) {
            Some(u) => {
                if !*u {
                    *u = true;
                    self.newly_used.push(label.0);
                }
                Ok(())
            }
            None => Err(format!("label L{} does not belong to this assembler", label.0)),
        }
    }

    // ----- raw data -----------------------------------------------------

    /// Appends raw bytes (data inside code, or hand-encoded instructions).
    pub fn bytes(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }

    /// Appends exactly `n` bytes of NOP instructions (the same sequences
    /// LLVM uses: at most 10 bytes each).
    pub fn nops(&mut self, n: u32) {
        nop_fill(&mut self.buf, n);
    }

    /// Pads with NOPs to a multiple of `align` bytes (a power of two) from
    /// the start of the code. The padding size is settled by
    /// [`finish`](Assembler::finish), after branch relaxation, and
    /// [`Code::align`] reports the alignment the code needs.
    pub fn align(&mut self, align: u32) {
        self.run("align", |a| {
            if !align.is_power_of_two() {
                return Err(format!("alignment {align} is not a power of two"));
            }
            if align > 1 {
                a.max_align = a.max_align.max(align);
                a.vars.push(Var { at: a.buf.len() as u32, kind: VarKind::Align(align), long: false });
            }
            Ok(())
        });
    }

    /// Appends an 8-byte field holding the absolute address `sym + addend`
    /// ([`RelocKind::Abs64`]).
    pub fn abs64(&mut self, sym: impl Into<String>, addend: i64) {
        self.reloc_field(RelocKind::Abs64, sym.into(), addend, 8);
    }

    /// Appends a 4-byte field holding `target - base`, for jump tables of
    /// relative offsets (`movsxd` the entry, add the table address, jump).
    pub fn diff32(&mut self, target: Label, base: Label) {
        self.run("diff32", |a| {
            a.use_label(target)?;
            a.use_label(base)?;
            a.fixups.push(Fixup { pos: a.pos(), target, kind: FixKind::Diff32 { base } });
            a.buf.extend_from_slice(&[0; 4]);
            Ok(())
        });
    }

    /// Appends a zero field of `len` bytes and a relocation on it.
    pub(crate) fn reloc_field(&mut self, kind: RelocKind, target: String, addend: i64, len: usize) {
        self.relocs.push(SymReloc { pos: self.pos(), kind, target, addend });
        self.buf.extend(std::iter::repeat_n(0, len));
    }

    /// Appends a 4-byte field holding `target + addend - end_of_instruction`,
    /// where the instruction ends `end` bytes after the field starts.
    pub(crate) fn label_rel32(&mut self, target: Label, addend: i64, end: u8) -> EncResult {
        self.use_label(target)?;
        self.fixups.push(Fixup { pos: self.pos(), target, kind: FixKind::Rel32 { end, addend } });
        self.buf.extend_from_slice(&[0; 4]);
        Ok(())
    }

    /// Appends a relaxable `jmp` (no condition) or `jcc` to `target`.
    pub(crate) fn jump_var(&mut self, cond: Option<Cond>, target: Label) -> EncResult {
        self.use_label(target)?;
        self.vars.push(Var { at: self.buf.len() as u32, kind: VarKind::Jump { cond, target }, long: false });
        Ok(())
    }

    // ----- instruction encoding -------------------------------------------

    /// Emits `[legacy] [REX] opcode [imm]`, with REX.W if `w`.
    pub(crate) fn plain(&mut self, legacy: Option<u8>, w: bool, opcode: &[u8], imm: &[u8]) {
        self.buf.extend(legacy);
        if w {
            self.buf.push(0x48);
        }
        self.buf.extend_from_slice(opcode);
        self.buf.extend_from_slice(imm);
    }

    /// Emits `[legacy] [REX] opcode+reg [imm]` (the `push r`, `mov r, imm`
    /// family). `force_rex` is set for `spl`..`dil` as 8-bit operands.
    pub(crate) fn op_reg(&mut self, legacy: Option<u8>, w: bool, force_rex: bool, opcode: u8, reg: Reg, imm: &[u8]) {
        self.buf.extend(legacy);
        let rex = 0x40 | (w as u8) << 3 | reg.high() as u8;
        if rex != 0x40 || force_rex {
            self.buf.push(rex);
        }
        self.buf.push(opcode + reg.low3());
        self.buf.extend_from_slice(imm);
    }

    /// Emits a ModRM-form instruction:
    /// `[legacy] [REX] opcode ModRM [SIB] [disp] [imm]`.
    ///
    /// `reg` is the ModRM reg field: a register number (0–15) or an opcode
    /// extension (0–7). `force_rex` adds an empty REX prefix, needed when an
    /// 8-bit operand is `spl`, `bpl`, `sil` or `dil`. RIP-relative operands
    /// get a relocation or label fixup that accounts for the trailing `imm`.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn modrm(
        &mut self,
        legacy: Option<u8>,
        w: bool,
        force_rex: bool,
        opcode: &[u8],
        reg: u8,
        rm: RmArg<'_>,
        imm: &[u8],
    ) -> EncResult {
        let r = (reg >> 3) & 1;
        let (x, b) = match rm {
            RmArg::Reg(n) => (0, (n >> 3) & 1),
            RmArg::Mem(Mem::Sib { base, index, .. }) => {
                if let Some((i, scale)) = index {
                    if *i == Reg::Rsp {
                        return Err("rsp cannot be an index register".into());
                    }
                    if !matches!(scale, 1 | 2 | 4 | 8) {
                        return Err(format!("scale {scale} is not 1, 2, 4 or 8"));
                    }
                }
                (index.is_some_and(|(i, _)| i.high()) as u8, base.is_some_and(|b| b.high()) as u8)
            }
            RmArg::Mem(_) => (0, 0),
        };
        self.buf.extend(legacy);
        let rex = 0x40 | (w as u8) << 3 | r << 2 | x << 1 | b;
        if rex != 0x40 || force_rex {
            self.buf.push(rex);
        }
        self.buf.extend_from_slice(opcode);
        let reg3 = (reg & 7) << 3;
        match rm {
            RmArg::Reg(n) => self.buf.push(0xC0 | reg3 | (n & 7)),
            RmArg::Mem(Mem::Sib { base, index, disp }) => {
                let ss = |s: u8| (s.trailing_zeros() as u8) << 6;
                match base {
                    None => {
                        // mod=00 rm=100, SIB base=101: [index*scale + disp32].
                        let sib = match index {
                            Some((i, s)) => ss(*s) | i.low3() << 3 | 5,
                            None => 0x25,
                        };
                        self.buf.extend_from_slice(&[0x04 | reg3, sib]);
                        self.buf.extend_from_slice(&disp.to_le_bytes());
                    }
                    Some(base) => {
                        // rbp/r13 as base cannot use mod=00 (that means
                        // RIP-relative or no base), so they take a zero disp8.
                        let mode = if *disp == 0 && base.low3() != 5 {
                            0
                        } else if i8::try_from(*disp).is_ok() {
                            1
                        } else {
                            2
                        };
                        // rsp/r12 as base always need a SIB byte.
                        if index.is_some() || base.low3() == 4 {
                            let sib = match index {
                                Some((i, s)) => ss(*s) | i.low3() << 3 | base.low3(),
                                None => 0x20 | base.low3(),
                            };
                            self.buf.extend_from_slice(&[mode << 6 | reg3 | 4, sib]);
                        } else {
                            self.buf.push(mode << 6 | reg3 | base.low3());
                        }
                        match mode {
                            1 => self.buf.push(*disp as i8 as u8),
                            2 => self.buf.extend_from_slice(&disp.to_le_bytes()),
                            _ => {}
                        }
                    }
                }
            }
            RmArg::Mem(rip) => {
                self.buf.push(reg3 | 5);
                let end = 4 + imm.len() as u8;
                match rip {
                    Mem::RipSym { sym, addend } => {
                        self.reloc_field(RelocKind::X86Pc32, sym.clone(), addend - end as i64, 4)
                    }
                    Mem::RipGot { sym } => self.reloc_field(RelocKind::X86GotPc32, sym.clone(), -(end as i64), 4),
                    Mem::RipLabel { label, addend } => self.label_rel32(*label, *addend as i64, end)?,
                    Mem::Sib { .. } => unreachable!(),
                }
            }
        }
        self.buf.extend_from_slice(imm);
        Ok(())
    }

    // ----- finishing ----------------------------------------------------

    /// Resolves labels, relaxes branches and returns the final code.
    ///
    /// Every `jmp`/`jcc` to a label starts in its 2-byte short form; any
    /// whose displacement does not fit in 8 bits grows to the near form, and
    /// the layout is recomputed until nothing grows. Branches never shrink,
    /// so this terminates, and in the final layout every short branch fits.
    ///
    /// Fails with the first encoding error, or if a label that is referenced
    /// (or exported) was never bound.
    pub fn finish(mut self) -> Result<Code, EncodeError> {
        if let Some(e) = self.error.take() {
            return Err(e);
        }
        let end = self.provisional_offset();
        let unbound = |what: &str, l: Label| EncodeError {
            message: format!("label L{} is {what} but never bound", l.0),
            offset: end,
        };
        let mut labels = Vec::with_capacity(self.labels.len());
        for (i, (pos, used)) in self.labels.iter().zip(&self.used).enumerate() {
            if *used && pos.is_none() {
                return Err(unbound("used", Label(i as u32)));
            }
            labels.push(*pos);
        }
        for (_, l) in &self.exports {
            if !matches!(labels.get(l.0 as usize), Some(Some(_))) {
                return Err(unbound("exported", *l));
            }
        }

        // Relaxation to a fixpoint. `before[i]` is the total size of the
        // variable items before item `i`.
        let n = self.vars.len();
        let mut before = vec![0u32; n + 1];
        loop {
            let mut acc = 0;
            for (i, v) in self.vars.iter().enumerate() {
                before[i] = acc;
                acc += var_size(v, v.at + acc);
            }
            before[n] = acc;
            let at = |p: Pos| p.at + before[p.vars as usize];
            let mut grew = false;
            for (v, &shift) in self.vars.iter_mut().zip(&before) {
                let VarKind::Jump { target, .. } = v.kind else { continue };
                if v.long {
                    continue;
                }
                let start = v.at + shift;
                let disp = at(labels[target.0 as usize].unwrap()) as i64 - (start as i64 + 2);
                if i8::try_from(disp).is_err() {
                    v.long = true;
                    grew = true;
                }
            }
            if !grew {
                break;
            }
        }
        let at = |p: Pos| p.at + before[p.vars as usize];
        let label_at = |l: Label| at(labels[l.0 as usize].unwrap()) as i64;

        let mut out = Vec::with_capacity(self.buf.len() + before[n] as usize);
        let mut last = 0usize;
        for v in &self.vars {
            out.extend_from_slice(&self.buf[last..v.at as usize]);
            last = v.at as usize;
            let start = out.len() as i64;
            match v.kind {
                VarKind::Jump { cond, target } => {
                    let t = label_at(target);
                    match (v.long, cond) {
                        (false, _) => {
                            out.push(cond.map_or(0xEB, |c| 0x70 + c.code()));
                            out.push((t - (start + 2)) as i8 as u8);
                        }
                        (true, None) => {
                            out.push(0xE9);
                            out.extend_from_slice(&rel32(t - (start + 5), end)?);
                        }
                        (true, Some(c)) => {
                            out.extend_from_slice(&[0x0F, 0x80 + c.code()]);
                            out.extend_from_slice(&rel32(t - (start + 6), end)?);
                        }
                    }
                }
                VarKind::Align(_) => nop_fill(&mut out, var_size(v, start as u32)),
            }
        }
        out.extend_from_slice(&self.buf[last..]);

        for f in &self.fixups {
            let field = at(f.pos) as usize;
            let value = match f.kind {
                FixKind::Rel32 { end: e, addend } => label_at(f.target) + addend - (field as i64 + e as i64),
                FixKind::Diff32 { base } => label_at(f.target) - label_at(base),
            };
            out[field..field + 4].copy_from_slice(&rel32(value, end)?);
        }
        let relocs = self
            .relocs
            .into_iter()
            .map(|r| Reloc { offset: at(r.pos), kind: r.kind, target: r.target, addend: r.addend })
            .collect();
        let exports = self.exports.into_iter().map(|(name, l)| (name, label_at(l) as u32)).collect();
        Ok(Code {
            bytes: out,
            relocs,
            align: self.max_align,
            exports,
            labels: labels.iter().map(|p| p.map(at)).collect(),
        })
    }
}

fn var_size(v: &Var, start: u32) -> u32 {
    match v.kind {
        VarKind::Jump { .. } if !v.long => 2,
        VarKind::Jump { cond: None, .. } => 5,
        VarKind::Jump { cond: Some(_), .. } => 6,
        VarKind::Align(a) => start.wrapping_neg() & (a - 1),
    }
}

fn rel32(value: i64, offset: u32) -> Result<[u8; 4], EncodeError> {
    i32::try_from(value)
        .map(i32::to_le_bytes)
        .map_err(|_| EncodeError { message: format!("displacement {value} does not fit in 32 bits"), offset })
}

/// NOP sequences of 1 to 10 bytes, as emitted by LLVM for x86-64.
const NOPS: [&[u8]; 10] = [
    &[0x90],
    &[0x66, 0x90],
    &[0x0F, 0x1F, 0x00],
    &[0x0F, 0x1F, 0x40, 0x00],
    &[0x0F, 0x1F, 0x44, 0x00, 0x00],
    &[0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00],
    &[0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00],
    &[0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
    &[0x66, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
    &[0x66, 0x2E, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
];

/// Appends `n` bytes of NOPs, longest instructions first.
fn nop_fill(out: &mut Vec<u8>, mut n: u32) {
    while n > 0 {
        let len = n.min(NOPS.len() as u32);
        out.extend_from_slice(NOPS[len as usize - 1]);
        n -= len;
    }
}
