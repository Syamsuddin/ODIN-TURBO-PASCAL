// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Assembler for `.s` files (the RTL shims in `rtl/system/arch/*.s`),
//! producing an [`Object`]. [`assemble`] reads x86-64 Intel syntax;
//! [`assemble_for`] also reads AArch64 (see [AArch64 syntax](#aarch64-syntax)).
//!
//! The x86-64 syntax is the one `clang -masm=intel` emits and `.intel_syntax
//! noprefix` accepts, for the instructions [`x86_64::Assembler`] encodes:
//!
//! ```text
//! .text
//! .keep _odin_start
//! _odin_start:                      # a new atom
//!     push rbp
//!     mov rbp, rsp
//!     mov qword ptr [rip + _odin_argc], rdi
//!     call qword ptr [rip + _exit@GOTPCREL]
//! .Lloop:                           # local to _odin_start
//!     jmp .Lloop
//!
//! .import _exit, "/usr/lib/libSystem.B.dylib"
//!
//! .bss
//! .align 8
//! _odin_argc:
//!     .zero 8
//! ```
//!
//! # Atoms and labels
//!
//! A label at the start of a line whose name does not start with `.L`
//! begins a new [`Atom`] in the current section, named after the label.
//! `.L` labels are local to the atom they appear in: jumps and `[rip + .L…]`
//! operands are resolved inside the atom, never through relocations, and in
//! data sections `.quad .L…` becomes an [`RelocKind::Abs64`] against the atom
//! itself. Atoms are placed independently by the linker, so code must not
//! fall through from one atom into the next.
//!
//! Each section remembers its current atom, so switching from `.data` back
//! to `.text` continues the last code atom.
//!
//! # Directives
//!
//! | Directive | Effect |
//! | --- | --- |
//! | `.text` `.rodata` `.data` `.bss` | switch section |
//! | `.globl name` / `.global name` | accepted; atom names are always link-global |
//! | `.keep name` | sets [`Atom::keep`] (may come before or after the atom) |
//! | `.import name, "lib"` | adds an [`Import`] |
//! | `.align n` / `.balign n` | `n` bytes (a power of two); `.p2align k` means 2^k |
//! | `.byte` `.short`/`.word`/`.2byte` `.long`/`.int`/`.4byte` `.quad`/`.8byte` | integers; `.quad` also takes `sym + const` |
//! | `.ascii` / `.asciz`/`.string` | strings, without / with a terminating zero |
//! | `.zero n` / `.space n[, fill]` | `n` bytes; in `.bss` this grows the atom's size |
//! | `.set name, expr` / `.equ name, expr` / `name = expr` | assembly-time constant |
//! | `.intel_syntax [noprefix]` | accepted, so files also assemble with clang |
//!
//! An `.align` right before an atom label sets that atom's alignment;
//! anywhere else it pads inside the current atom (NOPs in code, zeros in
//! data) and raises the atom's alignment to match. Without `.align`, code
//! atoms are aligned to 16 bytes and data atoms to 1.
//!
//! `;` and `#` start a comment, except inside string and character literals.
//! Mnemonics, registers and size keywords are case-insensitive; symbol names
//! are not.
//!
//! # AArch64 syntax
//!
//! With [`Arch::Aarch64`], instructions are those of
//! [`aarch64::Assembler`], written as clang
//! accepts them for `arm64-apple-macos` and `aarch64-linux-gnu`:
//!
//! ```text
//! .text
//! _odin_start:
//!     stp x29, x30, [sp, #-16]!
//!     mov x29, sp
//!     adrp x8, _odin_argc@PAGE          // Darwin; ELF: adrp x8, odin_argc
//!     str x0, [x8, _odin_argc@PAGEOFF]  // ELF: [x8, :lo12:odin_argc]
//!     adrp x16, _exit@GOTPAGE           // ELF: adrp x16, :got:exit
//!     ldr x16, [x16, _exit@GOTPAGEOFF]  // ELF: [x16, :got_lo12:exit]
//!     blr x16
//! .Lloop:
//!     b .Lloop
//! ```
//!
//! * Immediates take an optional `#`; `fmov` also takes decimal fractions
//!   (`#1.5`). Shifts and extends follow as their own operand (`add x0, x1,
//!   x2, lsl #3`, `ldr x0, [x1, w2, sxtw #3]`), as do post-index offsets
//!   (`ldr x0, [x1], #8`); pre-index is `[x1, #8]!`.
//! * Symbol operators: Darwin `sym@PAGE`, `sym@PAGEOFF`, `sym@GOTPAGE`,
//!   `sym@GOTPAGEOFF`, and ELF `sym` (for `adrp`), `:lo12:sym`, `:got:sym`,
//!   `:got_lo12:sym`, each with an optional `+ constant` (not for GOT).
//! * `b.cond`, `cbz`/`cbnz`, `tbz`/`tbnz` and `adr` reach `.L` labels only,
//!   `b`/`bl` reach labels or symbols, and `ldr reg, .Llabel` loads a
//!   literal. Conditional branches are relaxed like the encoder's; an
//!   out-of-range `[base, #offset]` is an error, as in clang (the encoder's
//!   expansions through x16 are not used).
//! * `//` starts a comment anywhere, `#` only at the start of a line. `;`
//!   is rejected: clang reads it as a comment on Darwin but as a statement
//!   separator on Linux.
//!
//! Directives, sections, atoms and `.L` labels follow the same rules as for
//! x86-64. Code atoms are aligned to at least 4 bytes, and `.align` inside
//! code pads with `nop`.

mod a64;
mod insn;
mod lexer;
mod parse;

use std::collections::HashMap;
use std::fmt;

use self::insn::{Ctx, LocalLabel, is_local};
use self::lexer::{Tok, lex, lex_a64};
use self::parse::{Consts, const_expr, operand, split_commas, sym_value};
use crate::aarch64;
use crate::object::{Atom, Import, Object, Reloc, RelocKind, SectionKind};
use crate::x86_64::{self, Assembler};

/// The instruction set of a `.s` file.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Arch {
    /// x86-64, Intel syntax.
    X86_64,
    /// AArch64, clang syntax (Darwin and ELF relocation operators).
    Aarch64,
}

/// An error in a `.s` file, with its location.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AsmError {
    pub file: String,
    /// 1-based line number.
    pub line: u32,
    pub message: String,
}

impl fmt::Display for AsmError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}: {}", self.file, self.line, self.message)
    }
}

impl std::error::Error for AsmError {}

/// Assembles one Intel-syntax (x86-64) source file. `file_name` is used in
/// error messages and as [`Object::name`]. Stops at the first error.
pub fn assemble(source: &str, file_name: &str) -> Result<Object, AsmError> {
    assemble_for(Arch::X86_64, source, file_name)
}

/// Assembles one source file for `arch`. `file_name` is used in error
/// messages and as [`Object::name`]. Stops at the first error.
pub fn assemble_for(arch: Arch, source: &str, file_name: &str) -> Result<Object, AsmError> {
    let mut st = State::new(arch);
    for (i, text) in source.lines().enumerate() {
        st.line = i as u32 + 1;
        st.statement(text).map_err(|message| AsmError { file: file_name.to_string(), line: st.line, message })?;
    }
    st.finish(file_name).map_err(|(line, message)| AsmError { file: file_name.to_string(), line, message })
}

const SECTIONS: [SectionKind; 4] = [SectionKind::Text, SectionKind::ReadOnly, SectionKind::Data, SectionKind::Bss];

fn section_index(s: SectionKind) -> usize {
    SECTIONS.iter().position(|k| *k == s).unwrap()
}

struct AtomState {
    name: String,
    section: SectionKind,
    align: u32,
    line: u32,
    body: Body,
}

enum Body {
    Code { asm: Box<Assembler>, labels: HashMap<String, LocalLabel> },
    A64 { asm: Box<aarch64::Assembler>, labels: HashMap<String, LocalLabel<aarch64::Label>> },
    Data { bytes: Vec<u8>, relocs: Vec<Reloc>, labels: HashMap<String, (u64, u32)>, refs: Vec<LocalRef> },
    Bss { size: u64, labels: HashMap<String, (u64, u32)> },
}

/// `.quad .Lname + addend` in a data atom, resolved when the atom is done.
struct LocalRef {
    offset: u32,
    name: String,
    addend: i64,
    line: u32,
}

struct State {
    arch: Arch,
    line: u32,
    section: SectionKind,
    atoms: Vec<AtomState>,
    by_name: HashMap<String, usize>,
    /// Current atom of each section.
    current: [Option<usize>; 4],
    /// `.align` waiting for the next atom or the next content, per section.
    pending_align: [Option<u32>; 4],
    imports: Vec<(Import, u32)>,
    keeps: Vec<(String, u32)>,
    consts: Consts,
}

/// Items of a data directive such as `.byte 1, 2, 3`.
fn items(args: &[Tok]) -> Result<Vec<&[Tok]>, String> {
    let parts = split_commas(args);
    if parts.iter().any(|p| p.is_empty()) {
        return Err("missing value".into());
    }
    Ok(parts)
}

fn one_ident(args: &[Tok], what: &str) -> Result<String, String> {
    match args {
        [Tok::Ident(name)] => Ok(name.clone()),
        _ => Err(format!("{what} takes one name")),
    }
}

impl State {
    fn new(arch: Arch) -> Self {
        State {
            arch,
            line: 0,
            section: SectionKind::Text,
            atoms: Vec::new(),
            by_name: HashMap::new(),
            current: [None; 4],
            pending_align: [None; 4],
            imports: Vec::new(),
            keeps: Vec::new(),
            consts: Consts::new(),
        }
    }

    fn statement(&mut self, text: &str) -> Result<(), String> {
        let a64 = self.arch == Arch::Aarch64;
        let toks = if a64 { lex_a64(text)? } else { lex(text)? };
        let mut rest = toks.as_slice();
        while let [Tok::Ident(name), Tok::Punct(':'), tail @ ..] = rest {
            self.define_label(name)?;
            rest = tail;
        }
        match rest {
            [] => Ok(()),
            [Tok::Ident(name), Tok::Punct('='), value @ ..] => self.set_const(name, value),
            [Tok::Ident(name), args @ ..] if name.starts_with('.') => self.directive(name, args),
            [Tok::Ident(prefix), Tok::Ident(mnemonic), args @ ..] if !a64 && prefix.eq_ignore_ascii_case("rep") => {
                self.instruction(Some(prefix), mnemonic, args)
            }
            [Tok::Ident(mnemonic), args @ ..] => self.instruction(None, mnemonic, args),
            [t, ..] => Err(format!("expected a label, directive or instruction, found {}", t.describe())),
        }
    }

    fn sec(&self) -> usize {
        section_index(self.section)
    }

    fn define_label(&mut self, name: &str) -> Result<(), String> {
        let line = self.line;
        if is_local(name) {
            let idx = self.content_atom()?;
            let atom = &mut self.atoms[idx];
            let already = match &mut atom.body {
                Body::Code { asm, labels } => {
                    let entry = labels.entry(name.to_string()).or_insert_with(|| LocalLabel {
                        label: asm.new_label(),
                        defined: None,
                        first_use: line,
                    });
                    match entry.defined {
                        Some(l) => Some(l),
                        None => {
                            entry.defined = Some(line);
                            asm.bind(entry.label);
                            None
                        }
                    }
                }
                Body::A64 { asm, labels } => {
                    let entry = labels.entry(name.to_string()).or_insert_with(|| LocalLabel {
                        label: asm.new_label(),
                        defined: None,
                        first_use: line,
                    });
                    match entry.defined {
                        Some(l) => Some(l),
                        None => {
                            entry.defined = Some(line);
                            asm.bind(entry.label);
                            None
                        }
                    }
                }
                Body::Data { bytes, labels, .. } => {
                    labels.insert(name.to_string(), (bytes.len() as u64, line)).map(|(_, l)| l)
                }
                Body::Bss { size, labels } => labels.insert(name.to_string(), (*size, line)).map(|(_, l)| l),
            };
            return match already {
                Some(l) => Err(format!("label `{name}` is already defined at line {l}")),
                None => Ok(()),
            };
        }
        if let Some(&i) = self.by_name.get(name) {
            return Err(format!("symbol `{name}` is already defined at line {}", self.atoms[i].line));
        }
        let sec = self.sec();
        let mut align =
            self.pending_align[sec].take().unwrap_or(if self.section == SectionKind::Text { 16 } else { 1 });
        let body = match self.section {
            SectionKind::Text if self.arch == Arch::Aarch64 => {
                // Instructions are 4-byte words, whatever `.align` says.
                align = align.max(4);
                let mut asm = Box::<aarch64::Assembler>::default();
                asm.strict = true;
                Body::A64 { asm, labels: HashMap::new() }
            }
            SectionKind::Text => Body::Code { asm: Box::default(), labels: HashMap::new() },
            SectionKind::Bss => Body::Bss { size: 0, labels: HashMap::new() },
            _ => Body::Data { bytes: Vec::new(), relocs: Vec::new(), labels: HashMap::new(), refs: Vec::new() },
        };
        self.atoms.push(AtomState { name: name.to_string(), section: self.section, align, line, body });
        self.by_name.insert(name.to_string(), self.atoms.len() - 1);
        self.current[sec] = Some(self.atoms.len() - 1);
        Ok(())
    }

    /// The atom that content (or a `.L` label) goes into, after applying a
    /// pending `.align` as padding.
    fn content_atom(&mut self) -> Result<usize, String> {
        let sec = self.sec();
        let Some(idx) = self.current[sec] else {
            return Err("content before the first label of the section; start an atom with a label".into());
        };
        if let Some(align) = self.pending_align[sec].take() {
            let atom = &mut self.atoms[idx];
            atom.align = atom.align.max(align);
            match &mut atom.body {
                Body::Code { asm, .. } => asm.align(align),
                Body::A64 { asm, .. } => asm.align(align),
                Body::Data { bytes, .. } => bytes.resize(bytes.len().next_multiple_of(align as usize), 0),
                Body::Bss { size, .. } => *size = size.next_multiple_of(align as u64),
            }
        }
        Ok(idx)
    }

    fn set_const(&mut self, name: &str, value: &[Tok]) -> Result<(), String> {
        let v = const_expr(value, &self.consts)?;
        self.consts.insert(name.to_string(), v);
        Ok(())
    }

    fn directive(&mut self, name: &str, args: &[Tok]) -> Result<(), String> {
        let lower = name.to_ascii_lowercase();
        let no_args = |what: &str| if args.is_empty() { Ok(()) } else { Err(format!("`{what}` takes no arguments")) };
        match lower.as_str() {
            ".text" | ".rodata" | ".data" | ".bss" => {
                no_args(name)?;
                self.section = match lower.as_str() {
                    ".text" => SectionKind::Text,
                    ".rodata" => SectionKind::ReadOnly,
                    ".data" => SectionKind::Data,
                    _ => SectionKind::Bss,
                };
                Ok(())
            }
            ".globl" | ".global" => one_ident(args, name).map(|_| ()),
            ".keep" => {
                let sym = one_ident(args, name)?;
                self.keeps.push((sym, self.line));
                Ok(())
            }
            ".import" => {
                let [Tok::Ident(sym), Tok::Punct(','), Tok::Str(lib)] = args else {
                    return Err("expected `.import name, \"library path\"`".into());
                };
                let library = String::from_utf8(lib.clone()).map_err(|_| "library path is not UTF-8".to_string())?;
                if let Some((prev, line)) = self.imports.iter().find(|(i, _)| i.name == *sym) {
                    if prev.library != library {
                        return Err(format!("`{sym}` is already imported from \"{}\" at line {line}", prev.library));
                    }
                    return Ok(());
                }
                self.imports.push((Import { name: sym.clone(), library }, self.line));
                Ok(())
            }
            ".align" | ".balign" | ".p2align" => {
                let [arg] = items(args)?[..] else {
                    return Err(format!("`{name}` takes one argument"));
                };
                let n = const_expr(arg, &self.consts)?;
                let align = if lower == ".p2align" {
                    if !(0..=12).contains(&n) {
                        return Err(format!("alignment 2^{n} is out of range"));
                    }
                    1u32 << n
                } else {
                    if !(1..=4096).contains(&n) || (n & (n - 1)) != 0 {
                        return Err(format!("alignment {n} is not a power of two up to 4096"));
                    }
                    n as u32
                };
                let slot = &mut self.pending_align[self.sec()];
                *slot = Some(slot.unwrap_or(1).max(align));
                Ok(())
            }
            ".byte" | ".short" | ".word" | ".2byte" | ".long" | ".int" | ".4byte" | ".quad" | ".8byte" => {
                let size = match lower.as_str() {
                    ".byte" => 1,
                    ".short" | ".word" | ".2byte" => 2,
                    ".long" | ".int" | ".4byte" => 4,
                    _ => 8,
                };
                for item in items(args)? {
                    self.data_value(size, item)?;
                }
                Ok(())
            }
            ".ascii" | ".asciz" | ".string" => {
                let zero = lower != ".ascii";
                for item in items(args)? {
                    let [Tok::Str(s)] = item else {
                        return Err(format!("`{name}` takes string literals"));
                    };
                    let mut bytes = s.clone();
                    if zero {
                        bytes.push(0);
                    }
                    self.emit_bytes(&bytes)?;
                }
                Ok(())
            }
            ".zero" | ".space" | ".skip" => {
                let parts = items(args)?;
                let (count, fill) = match parts[..] {
                    [n] => (const_expr(n, &self.consts)?, 0),
                    [n, f] if lower != ".zero" => (const_expr(n, &self.consts)?, const_expr(f, &self.consts)?),
                    _ => return Err(format!("wrong number of arguments to `{name}`")),
                };
                if !(0..=1 << 30).contains(&count) {
                    return Err(format!("size {count} is out of range"));
                }
                if !(-128..=255).contains(&fill) {
                    return Err(format!("fill value {fill} does not fit in a byte"));
                }
                let idx = self.content_atom()?;
                if let Body::Bss { size, .. } = &mut self.atoms[idx].body {
                    if fill != 0 {
                        return Err("`.bss` can only hold zeros".into());
                    }
                    *size += count as u64;
                    return Ok(());
                }
                self.emit_bytes(&vec![fill as u8; count as usize])
            }
            ".set" | ".equ" => {
                let [Tok::Ident(cname), Tok::Punct(','), value @ ..] = args else {
                    return Err(format!("expected `{name} name, value`"));
                };
                self.set_const(cname, value)
            }
            ".intel_syntax" | ".att_syntax" if self.arch == Arch::Aarch64 => {
                Err(format!("`{name}` is only for x86-64 files"))
            }
            ".intel_syntax" => match args {
                [] => Ok(()),
                [Tok::Ident(p)] if p.eq_ignore_ascii_case("noprefix") => Ok(()),
                _ => Err("only `.intel_syntax noprefix` is supported".into()),
            },
            ".att_syntax" => Err("AT&T syntax is not supported; use Intel syntax".into()),
            _ => Err(format!("unknown directive `{name}`")),
        }
    }

    /// Appends literal bytes to the current atom.
    fn emit_bytes(&mut self, bytes: &[u8]) -> Result<(), String> {
        let idx = self.content_atom()?;
        match &mut self.atoms[idx].body {
            Body::Code { asm, .. } => asm.bytes(bytes),
            Body::A64 { asm, .. } => asm.bytes(bytes),
            Body::Data { bytes: b, .. } => b.extend_from_slice(bytes),
            Body::Bss { .. } => return Err("`.bss` can only hold zeros (use `.zero`)".into()),
        }
        Ok(())
    }

    /// One item of `.byte` .. `.quad`.
    fn data_value(&mut self, size: u32, toks: &[Tok]) -> Result<(), String> {
        let v = sym_value(toks, &self.consts)?;
        if v.got {
            return Err("`@GOTPCREL` is not allowed in data".into());
        }
        let Some(sym) = v.sym else {
            let (lo, hi) = match size {
                1 => (-0x80, 0xFF),
                2 => (-0x8000, 0xFFFF),
                4 => (i32::MIN as i64, u32::MAX as i64),
                _ => (i64::MIN, i64::MAX),
            };
            if size < 8 && (v.value < lo || v.value > hi) {
                return Err(format!("value {} does not fit in {size} bytes", v.value));
            }
            return self.emit_bytes(&v.value.to_le_bytes()[..size as usize]);
        };
        if size != 8 {
            return Err(format!("only `.quad` can hold the address of `{sym}`"));
        }
        let line = self.line;
        let idx = self.content_atom()?;
        match &mut self.atoms[idx].body {
            Body::Code { asm, .. } => {
                if is_local(&sym) {
                    return Err(format!("`.quad {sym}` in code is not supported; put the table in `.rodata`"));
                }
                asm.abs64(sym, v.value);
            }
            Body::A64 { asm, .. } => {
                if is_local(&sym) {
                    return Err(format!("`.quad {sym}` in code is not supported; put the table in `.rodata`"));
                }
                asm.abs64(sym, v.value);
            }
            Body::Data { bytes, relocs, refs, .. } => {
                let offset = bytes.len() as u32;
                if is_local(&sym) {
                    refs.push(LocalRef { offset, name: sym, addend: v.value, line });
                } else {
                    relocs.push(Reloc { offset, kind: RelocKind::Abs64, target: sym, addend: v.value });
                }
                bytes.extend_from_slice(&[0; 8]);
            }
            Body::Bss { .. } => return Err("`.bss` can only hold zeros (use `.zero`)".into()),
        }
        Ok(())
    }

    fn instruction(&mut self, prefix: Option<&str>, mnemonic: &str, args: &[Tok]) -> Result<(), String> {
        if self.section != SectionKind::Text {
            return Err(format!("instruction `{mnemonic}` outside `.text`"));
        }
        if self.arch == Arch::Aarch64 {
            let idx = self.content_atom()?;
            let line = self.line;
            let Body::A64 { asm, labels } = &mut self.atoms[idx].body else { unreachable!() };
            let mut ctx = a64::Ctx { asm, labels, line, consts: &self.consts };
            return a64::encode(&mut ctx, mnemonic, args);
        }
        let mut ops = Vec::new();
        for part in split_commas(args) {
            ops.push(operand(part, &self.consts)?);
        }
        let idx = self.content_atom()?;
        let line = self.line;
        let Body::Code { asm, labels } = &mut self.atoms[idx].body else { unreachable!() };
        let mut ctx = Ctx { asm, labels, line };
        insn::encode(&mut ctx, prefix, mnemonic, &ops)
    }

    fn finish(self, file_name: &str) -> Result<Object, (u32, String)> {
        for (import, line) in &self.imports {
            if let Some(&i) = self.by_name.get(&import.name) {
                let defined = self.atoms[i].line;
                return Err((*line, format!("`{}` is both imported and defined (at line {defined})", import.name)));
            }
        }
        let mut atoms = Vec::with_capacity(self.atoms.len());
        for a in self.atoms {
            let atom = match a.body {
                Body::Code { asm, labels } => {
                    let mut undefined: Vec<(&String, &LocalLabel)> =
                        labels.iter().filter(|(_, l)| l.defined.is_none()).collect();
                    undefined.sort_by_key(|(_, l)| l.first_use);
                    if let Some((name, l)) = undefined.first() {
                        return Err((
                            l.first_use,
                            format!("undefined label `{name}` (`.L` labels are local to their atom, `{}`)", a.name),
                        ));
                    }
                    let code: x86_64::Code = asm.finish().map_err(|e| (a.line, format!("in `{}`: {}", a.name, e)))?;
                    code.into_atom(a.name, a.align)
                }
                Body::A64 { asm, labels } => {
                    let mut undefined: Vec<(&String, &LocalLabel<aarch64::Label>)> =
                        labels.iter().filter(|(_, l)| l.defined.is_none()).collect();
                    undefined.sort_by_key(|(_, l)| l.first_use);
                    if let Some((name, l)) = undefined.first() {
                        return Err((
                            l.first_use,
                            format!("undefined label `{name}` (`.L` labels are local to their atom, `{}`)", a.name),
                        ));
                    }
                    let code = asm.finish().map_err(|e| (a.line, format!("in `{}`: {}", a.name, e)))?;
                    code.into_atom(a.name, a.align)
                }
                Body::Data { bytes, mut relocs, labels, refs } => {
                    for r in refs {
                        let Some((offset, _)) = labels.get(&r.name) else {
                            return Err((
                                r.line,
                                format!(
                                    "undefined label `{}` (`.L` labels are local to their atom, `{}`)",
                                    r.name, a.name
                                ),
                            ));
                        };
                        relocs.push(Reloc {
                            offset: r.offset,
                            kind: RelocKind::Abs64,
                            target: a.name.clone(),
                            addend: *offset as i64 + r.addend,
                        });
                    }
                    relocs.sort_by_key(|r| r.offset);
                    let mut atom = Atom::new(a.name, a.section, a.align, bytes);
                    atom.relocs = relocs;
                    atom
                }
                Body::Bss { size, .. } => Atom::bss(a.name, size, a.align),
            };
            atoms.push(atom);
        }
        for (name, line) in &self.keeps {
            match self.by_name.get(name) {
                Some(&i) => atoms[i].keep = true,
                None => return Err((*line, format!("`.keep {name}`: no atom of that name in this file"))),
            }
        }
        Ok(Object { name: file_name.to_string(), atoms, imports: self.imports.into_iter().map(|(i, _)| i).collect() })
    }
}
