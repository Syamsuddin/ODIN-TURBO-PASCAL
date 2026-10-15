// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Object model shared by the code generator and assembler (producers) and
//! the linker (consumer).
//!
//! An [`Object`] is a list of [`Atom`]s, one function or one data item each.
//! The linker places atoms individually, so smart linking (dropping atoms
//! nothing references) needs no extra bookkeeping. Atom and label names are
//! unique across a whole link: the code generator mangles unit-qualified
//! names, and labels local to one function never become relocations.

/// Where an atom ends up in the executable.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum SectionKind {
    /// Machine code, mapped read + execute.
    Text,
    /// Read-only data: string literals, jump tables, constant tables.
    ReadOnly,
    /// Initialized writable data: variables with initial values, typed
    /// constants, VMTs.
    Data,
    /// Zero-initialized writable data. Atoms of this kind have no bytes,
    /// only a size.
    Bss,
}

/// How a relocation field is computed. `S` is the target address, `A` the
/// addend and `P` the address of the field itself.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RelocKind {
    /// x86-64: 32-bit signed PC-relative field, value `S + A - P`. For a
    /// RIP-relative operand that ends the instruction, `A = -4`.
    X86Pc32,
    /// x86-64: like [`RelocKind::X86Pc32`], but `S` is the address of the
    /// target's GOT slot. Used for `call [rip+slot]` and `mov reg, [rip+slot]`
    /// on imported symbols.
    X86GotPc32,
    /// 64-bit absolute address `S + A`. In a position-independent executable
    /// the linker also records a rebase so the loader can slide the value.
    Abs64,
    /// AArch64 `B`/`BL`: 26-bit word offset `(S + A - P) >> 2`.
    Arm64Branch26,
    /// AArch64 `ADRP`: 21-bit page delta `((S + A) & !0xfff) - (P & !0xfff)`.
    Arm64Page21,
    /// AArch64 `ADD`/`LDR`/`STR` immediate: low 12 bits of `S + A`, shifted
    /// right by `scale` (log2 of the access size; 0 for `ADD`).
    Arm64PageOff12 { scale: u8 },
    /// AArch64 `ADRP` to the page of the target's GOT slot.
    Arm64GotPage21,
    /// AArch64 64-bit `LDR` of the target's GOT slot (low 12 bits, scale 3).
    Arm64GotPageOff12,
}

/// A field inside an atom that the linker fills in.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Reloc {
    /// Offset of the field from the start of the atom.
    pub offset: u32,
    pub kind: RelocKind,
    /// Name of an atom, an atom label, or an import.
    pub target: String,
    pub addend: i64,
}

/// One function or one data item, placed by the linker as a unit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Atom {
    /// Unique across the whole link.
    pub name: String,
    pub section: SectionKind,
    /// Alignment in bytes, a power of two.
    pub align: u32,
    /// Contents. Empty for [`SectionKind::Bss`].
    pub bytes: Vec<u8>,
    /// Size in bytes. Equals `bytes.len()` except for [`SectionKind::Bss`].
    pub size: u64,
    pub relocs: Vec<Reloc>,
    /// Extra names pointing inside this atom, as `(name, offset)`. Unique
    /// across the whole link, like atom names.
    pub labels: Vec<(String, u64)>,
    /// Kept by smart linking even when nothing references it (entry points,
    /// tables the debugger finds by name).
    pub keep: bool,
}

impl Atom {
    /// A code or data atom with contents.
    pub fn new(name: impl Into<String>, section: SectionKind, align: u32, bytes: Vec<u8>) -> Self {
        assert!(section != SectionKind::Bss, "use Atom::bss for zero-initialized data");
        assert!(align.is_power_of_two(), "alignment must be a power of two");
        let size = bytes.len() as u64;
        Atom { name: name.into(), section, align, bytes, size, relocs: Vec::new(), labels: Vec::new(), keep: false }
    }

    /// A zero-initialized atom of `size` bytes.
    pub fn bss(name: impl Into<String>, size: u64, align: u32) -> Self {
        assert!(align.is_power_of_two(), "alignment must be a power of two");
        Atom {
            name: name.into(),
            section: SectionKind::Bss,
            align,
            bytes: Vec::new(),
            size,
            relocs: Vec::new(),
            labels: Vec::new(),
            keep: false,
        }
    }

    pub fn reloc(mut self, offset: u32, kind: RelocKind, target: impl Into<String>, addend: i64) -> Self {
        self.relocs.push(Reloc { offset, kind, target: target.into(), addend });
        self
    }

    pub fn keep(mut self) -> Self {
        self.keep = true;
        self
    }
}

/// A symbol provided by a shared library and bound by the loader: functions,
/// or data such as `environ`, from libSystem on macOS and from glibc on
/// Linux.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Import {
    /// Symbol name as the library exports it, e.g. `_write` on Darwin and
    /// `write` on Linux.
    pub name: String,
    /// On Darwin, the library's install name, e.g.
    /// `/usr/lib/libSystem.B.dylib`. On Linux, `libc` for glibc (libc.so.6
    /// together with libm.so.6), `libm`, or a soname such as `libfoo.so.1`.
    pub library: String,
}

/// The output of compiling one unit, or of assembling one `.s` file.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Object {
    /// Unit or file name, used in diagnostics.
    pub name: String,
    pub atoms: Vec<Atom>,
    pub imports: Vec<Import>,
}
