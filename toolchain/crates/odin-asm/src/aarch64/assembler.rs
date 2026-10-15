// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! The code buffer behind [`Assembler`]: labels, fixups, relocations and
//! branch relaxation. The instruction methods in `insts.rs` build on it.
//!
//! Every instruction is one 32-bit word, so the layout only changes through
//! two kinds of variable-size items: conditional branches to labels (4
//! bytes, or 8 once relaxed into an inverted branch over a `b`) and
//! alignment padding. As in the x86-64 encoder, they are kept aside, each
//! anchored at a position in the flat buffer, and every other position is
//! recorded as "buffer offset + number of variable items before it".

use std::fmt;

use super::operand::Label;
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
    /// `"and: immediate 0x5 is not a valid bitmask immediate"`.
    pub message: String,
    /// Offset of the failing instruction in the code buffer, counting every
    /// relaxable branch as short. Only a hint for locating the instruction.
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
    /// `b.cond`, `cbz`/`cbnz` (19-bit offset) or `tbz`/`tbnz` (14-bit
    /// offset) to a label. `insn` has a zero offset field.
    Branch { insn: u32, target: Label, bits: u8 },
    /// NOP padding up to a multiple of the alignment.
    Align(u32),
}

#[derive(Clone, Copy, Debug)]
struct Var {
    at: u32,
    kind: VarKind,
    /// For branches: relaxed into an inverted branch over a `b`.
    long: bool,
}

/// A reference to a label inside the code, resolved by `finish`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum FixKind {
    /// `b`/`bl`: 26-bit word offset at bit 0.
    Imm26,
    /// `ldr` literal: 19-bit word offset at bit 5.
    Imm19,
    /// `adr`: 21-bit byte offset split into immlo (bits 29–30) and immhi
    /// (bits 5–23).
    Adr21,
    /// A 4-byte data field holding `target - base`.
    Diff32 { base: Label },
}

#[derive(Clone, Copy, Debug)]
struct Fixup {
    pos: Pos,
    target: Label,
    kind: FixKind,
    addend: i64,
}

#[derive(Clone, Debug)]
struct SymReloc {
    pos: Pos,
    kind: RelocKind,
    target: String,
    addend: i64,
}

/// `nop`.
pub(crate) const NOP: u32 = 0xD503_201F;

/// Builds the machine code of one function (or any other run of code) for
/// AArch64.
///
/// Instruction methods are named after the mnemonic and take the
/// destination first, as in assembly syntax; registers carry their width
/// ([`X0`](super::regs::X0) vs [`W0`](super::regs::W0)). An invalid
/// combination does not panic: the first error is kept and returned by
/// [`finish`](Assembler::finish).
///
/// ```
/// use odin_asm::aarch64::{Assembler, Cond, Mem, regs::*};
///
/// let mut a = Assembler::new();
/// let done = a.new_label();
/// a.stp(X29, X30, Mem::pre(SP, -16));
/// a.mov(X29, SP);
/// a.ldr(W0, Mem::base(X0, 8));
/// a.cmp(W0, 10);
/// a.b_cond(Cond::Lt, done);
/// a.bl("_odin_overflow");
/// a.bind(done);
/// a.ldp(X29, X30, Mem::post(SP, 16));
/// a.ret();
/// let code = a.finish().unwrap();
/// assert_eq!(code.bytes.len(), 8 * 4);
/// assert_eq!(code.label_offset(done), Some(6 * 4));
/// assert_eq!(code.relocs.len(), 1);
/// ```
#[derive(Clone, Debug)]
pub struct Assembler {
    pub(crate) buf: Vec<u8>,
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
    /// Set by the text assembler: helpers that would expand an operand that
    /// does not fit (an out-of-range `[base, #offset]`) report an error
    /// instead, as clang does.
    pub(crate) strict: bool,
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
    /// Alignment the code needs: the largest requested with
    /// [`Assembler::align`], and at least 4.
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
    /// and [`Code::align`] (so always at least 4).
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
            max_align: 4,
            error: None,
            strict: false,
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

    /// Current offset assuming every relaxable branch is short (a lower
    /// bound).
    pub(crate) fn provisional_offset(&self) -> u32 {
        self.buf.len() as u32 + self.vars.iter().filter(|v| matches!(v.kind, VarKind::Branch { .. })).count() as u32 * 4
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

    /// Appends raw bytes (data inside code). Instructions that follow must
    /// still start at a multiple of 4; [`finish`](Assembler::finish)
    /// rejects branches to misaligned labels.
    pub fn bytes(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }

    /// Appends one instruction word (for encodings this API lacks).
    pub fn word(&mut self, word: u32) {
        self.buf.extend_from_slice(&word.to_le_bytes());
    }

    /// Pads to a multiple of `align` bytes (a power of two) from the start
    /// of the code, with `nop`s (preceded by zero bytes if the position is
    /// not a multiple of 4, as LLVM does). The padding size is settled by
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
        self.relocs.push(SymReloc { pos: self.pos(), kind: RelocKind::Abs64, target: sym.into(), addend });
        self.buf.extend_from_slice(&[0; 8]);
    }

    /// Appends a 4-byte field holding `target - base`, for jump tables of
    /// relative offsets (`adr` the table, `ldrsw` the entry, add, `br`).
    pub fn diff32(&mut self, target: Label, base: Label) {
        self.run("diff32", |a| {
            a.use_label(target)?;
            a.use_label(base)?;
            a.fixups.push(Fixup { pos: a.pos(), target, kind: FixKind::Diff32 { base }, addend: 0 });
            a.buf.extend_from_slice(&[0; 4]);
            Ok(())
        });
    }

    // ----- instruction emission -------------------------------------------

    /// Appends one instruction.
    pub(crate) fn emit(&mut self, word: u32) {
        self.buf.extend_from_slice(&word.to_le_bytes());
    }

    /// Appends an instruction whose field `kind` refers to a symbol.
    pub(crate) fn emit_reloc(&mut self, word: u32, kind: RelocKind, target: &str, addend: i64) {
        self.relocs.push(SymReloc { pos: self.pos(), kind, target: target.to_string(), addend });
        self.emit(word);
    }

    /// Appends an instruction whose field `kind` refers to `target +
    /// addend`, filled in by `finish`.
    pub(crate) fn emit_label(&mut self, word: u32, kind: FixKind, target: Label, addend: i64) -> EncResult {
        self.use_label(target)?;
        self.fixups.push(Fixup { pos: self.pos(), target, kind, addend });
        self.emit(word);
        Ok(())
    }

    /// Appends a relaxable conditional branch (`insn` with a zero offset
    /// field of `bits` bits at bit 5).
    pub(crate) fn branch_var(&mut self, insn: u32, bits: u8, target: Label) -> EncResult {
        self.use_label(target)?;
        self.vars.push(Var { at: self.buf.len() as u32, kind: VarKind::Branch { insn, target, bits }, long: false });
        Ok(())
    }

    // ----- finishing ----------------------------------------------------

    /// Resolves labels, relaxes branches and returns the final code.
    ///
    /// Every `b.cond`, `cbz`/`cbnz` and `tbz`/`tbnz` to a label starts as a
    /// single instruction; any whose target is out of range (±1 MiB, or
    /// ±32 KiB for `tbz`/`tbnz`) becomes the inverted branch over an
    /// unconditional `b` (±128 MiB), and the layout is recomputed until
    /// nothing grows. Branches never shrink, so this terminates. (`b.al` and
    /// `b.nv` cannot be inverted; out of range they become a plain `b`.)
    ///
    /// Fails with the first encoding error, if a label that is referenced
    /// (or exported) was never bound, if a branch or `adr`/literal target is
    /// out of range even so, or if one lands on a misaligned offset.
    pub fn finish(mut self) -> Result<Code, EncodeError> {
        if let Some(e) = self.error.take() {
            return Err(e);
        }
        let end = self.provisional_offset();
        let err = |message: String| EncodeError { message, offset: end };
        let mut labels = Vec::with_capacity(self.labels.len());
        for (i, (pos, used)) in self.labels.iter().zip(&self.used).enumerate() {
            if *used && pos.is_none() {
                return Err(err(format!("label L{i} is used but never bound")));
            }
            labels.push(*pos);
        }
        for (_, l) in &self.exports {
            if !matches!(labels.get(l.0 as usize), Some(Some(_))) {
                return Err(err(format!("label L{} is exported but never bound", l.0)));
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
                let VarKind::Branch { target, bits, .. } = v.kind else { continue };
                if v.long {
                    continue;
                }
                let disp = at(labels[target.0 as usize].unwrap()) as i64 - (v.at + shift) as i64;
                if !fits_words(disp, bits) {
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
                VarKind::Branch { insn, target, bits } => {
                    let disp = label_at(target) - start;
                    let always = is_always(insn);
                    let word = match (v.long, always) {
                        (false, _) => insn | word_field(disp, bits, 5).map_err(err)?,
                        // b.al / b.nv: a plain `b` does the same.
                        (true, true) => 0x1400_0000 | word_field(disp, 26, 0).map_err(err)?,
                        (true, false) => {
                            // Inverted condition, skipping the `b` (+8).
                            out.extend_from_slice(&(invert(insn) | 2 << 5).to_le_bytes());
                            0x1400_0000 | word_field(disp - 4, 26, 0).map_err(err)?
                        }
                    };
                    out.extend_from_slice(&word.to_le_bytes());
                }
                VarKind::Align(_) => pad(&mut out, var_size(v, start as u32)),
            }
        }
        out.extend_from_slice(&self.buf[last..]);

        for f in &self.fixups {
            let field = at(f.pos) as usize;
            let disp = label_at(f.target) + f.addend - field as i64;
            let old = u32::from_le_bytes(out[field..field + 4].try_into().unwrap());
            let word = match f.kind {
                FixKind::Imm26 => old | word_field(disp, 26, 0).map_err(err)?,
                FixKind::Imm19 => old | word_field(disp, 19, 5).map_err(err)?,
                FixKind::Adr21 => {
                    if !(-(1 << 20)..1 << 20).contains(&disp) {
                        return Err(err(format!("adr target {disp} bytes away is out of range (±1 MiB)")));
                    }
                    let d = disp as u32;
                    old | (d & 3) << 29 | ((d >> 2) & 0x7_ffff) << 5
                }
                FixKind::Diff32 { base } => {
                    let value = label_at(f.target) - label_at(base);
                    i32::try_from(value).map_err(|_| err(format!("difference {value} does not fit in 32 bits")))? as u32
                }
            };
            out[field..field + 4].copy_from_slice(&word.to_le_bytes());
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
        VarKind::Branch { insn, .. } if v.long && !is_always(insn) => 8,
        VarKind::Branch { .. } => 4,
        VarKind::Align(a) => start.wrapping_neg() & (a - 1),
    }
}

/// Whether a byte displacement is a multiple of 4 that fits a signed word
/// offset of `bits` bits.
fn fits_words(disp: i64, bits: u8) -> bool {
    disp & 3 == 0 && (-(1i64 << (bits + 1))..1i64 << (bits + 1)).contains(&disp)
}

/// The word offset `disp / 4` as a `bits`-bit field at bit `shift`.
fn word_field(disp: i64, bits: u8, shift: u32) -> Result<u32, String> {
    if disp & 3 != 0 {
        return Err(format!("branch or literal target at a displacement of {disp} bytes is not 4-byte aligned"));
    }
    if !fits_words(disp, bits) {
        let range = match bits {
            26 => "±128 MiB",
            19 => "±1 MiB",
            _ => "±32 KiB",
        };
        return Err(format!("target {disp} bytes away is out of range ({range})"));
    }
    Ok((((disp >> 2) as u32) & ((1 << bits) - 1)) << shift)
}

/// Whether a relaxable branch is `b.al` or `b.nv`.
fn is_always(insn: u32) -> bool {
    insn & 0xFF00_0010 == 0x5400_0000 && insn & 0xE == 0xE
}

/// The opposite branch: `b.cond` with the condition inverted, `cbz` ↔
/// `cbnz`, `tbz` ↔ `tbnz` (bit 24 in both families).
fn invert(insn: u32) -> u32 {
    if insn & 0xFF00_0010 == 0x5400_0000 { insn ^ 1 } else { insn ^ 1 << 24 }
}

/// Appends `n` bytes of padding: zeros up to a multiple of 4, then `nop`s.
/// (Padding ends at a multiple of the alignment, so when that is 4 or more,
/// `n % 4` zeros bring the position to a multiple of 4.)
fn pad(out: &mut Vec<u8>, n: u32) {
    let zeros = n % 4;
    out.extend(std::iter::repeat_n(0, zeros as usize));
    for _ in 0..(n - zeros) / 4 {
        out.extend_from_slice(&NOP.to_le_bytes());
    }
}
