// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Whole-program linker: resolves names across [`Object`]s, keeps only the
//! atoms reachable from the entry symbol (smart linking), lays them out and
//! writes a ready-to-run executable in memory.
//!
//! Darwin targets produce a position-independent Mach-O `MH_EXECUTE` that
//! reaches libSystem through a GOT bound by dyld, with an ad-hoc,
//! linker-signed code signature computed here (no `codesign`, no SDK).
//!
//! Linux targets produce a dynamically linked, position-independent ELF
//! executable (`ET_DYN`, `DF_1_PIE`) for glibc: ld-linux loads libc.so.6 and
//! libm.so.6 and fills a GOT through which every import is reached, all
//! before the program starts (`BIND_NOW`, no PLT). Nothing from the system
//! is needed to write it either: no crt files, no `ld`. The entry point is
//! usually the RTL's `_start`, which hands `main` to `__libc_start_main`.
//!
//! The Windows target produces a PE32+ console executable that imports DLL
//! functions by name through its IAT, with base relocations for ASLR (see
//! `pe.rs`).
//!
//! Each writer defines the address of its own header for atoms to refer to:
//! `__mh_execute_header` on Darwin, `__ehdr_start` on Linux, `__ImageBase`
//! on Windows.

mod codesign;
mod elf;
mod layout;
mod leb;
mod macho;
mod pe;
mod reloc;
mod resolve;
mod trie;

use std::collections::BTreeMap;
use std::fmt;

use odin_asm::object::Object;

/// Executable format, architecture and operating system.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Target {
    X86_64Darwin,
    Aarch64Darwin,
    X86_64Linux,
    Aarch64Linux,
    /// PE32+ console executable for 64-bit Windows 10 1809 or later,
    /// importing from DLLs such as `kernel32.dll` and `ucrtbase.dll`.
    X86_64Windows,
}

impl Target {
    /// Name used on the command line and in cache paths.
    pub fn triple(self) -> &'static str {
        match self {
            Target::X86_64Darwin => "x86_64-darwin",
            Target::Aarch64Darwin => "aarch64-darwin",
            Target::X86_64Linux => "x86_64-linux",
            Target::Aarch64Linux => "aarch64-linux",
            Target::X86_64Windows => "x86_64-windows",
        }
    }

    pub fn is_darwin(self) -> bool {
        matches!(self, Target::X86_64Darwin | Target::Aarch64Darwin)
    }

    pub fn is_windows(self) -> bool {
        matches!(self, Target::X86_64Windows)
    }

    pub fn is_arm64(self) -> bool {
        matches!(self, Target::Aarch64Darwin | Target::Aarch64Linux)
    }
}

/// Oldest macOS the output runs on unless told otherwise; matches the IDE's
/// `LSMinimumSystemVersion`.
pub const DEFAULT_MIN_OS: (u16, u8, u8) = (11, 0, 0);

/// What to link and how.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LinkOptions {
    pub target: Target,
    /// Symbol where execution starts, e.g. `_main` on Darwin (called by
    /// dyld like a C `main`) or `_start` on Linux (entered from ld-linux
    /// with the initial process stack). Must name a code atom or a label
    /// inside one.
    pub entry: String,
    /// Code-signing identifier, usually the executable's file name. Darwin
    /// only.
    pub identifier: String,
    /// Minimum OS version as (major, minor, patch). Darwin only: Windows
    /// images always declare 6.0 (see `pe.rs`).
    pub min_os: (u16, u8, u8),
}

impl LinkOptions {
    /// Options with [`DEFAULT_MIN_OS`].
    pub fn new(target: Target, entry: impl Into<String>, identifier: impl Into<String>) -> Self {
        LinkOptions { target, entry: entry.into(), identifier: identifier.into(), min_os: DEFAULT_MIN_OS }
    }
}

/// A linked executable, ready to be written to disk and marked executable.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LinkedImage {
    /// The whole file.
    pub bytes: Vec<u8>,
    /// Unslid address of the Mach-O or ELF header (0 for a Linux PIE), or of
    /// the DOS header, i.e. ImageBase and `__ImageBase` (Windows). At run
    /// time, an address minus the header's runtime address plus this is the
    /// link-time address.
    pub image_base: u64,
    /// Unslid address of every placed atom and label. Atoms dropped by smart
    /// linking are absent.
    pub symbols: BTreeMap<String, u64>,
}

/// Why a link failed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LinkError {
    /// A live atom (or the entry point) names a symbol nothing defines or
    /// imports.
    Undefined { name: String, referenced_from: String },
    /// Two atoms, labels or imports share a name, or one name is imported
    /// from two libraries.
    Duplicate { name: String },
    /// A relocation's value does not fit its field, or is not a multiple of
    /// what the instruction scales it by.
    RelocOutOfRange { atom: String, target: String },
    /// An atom breaks an invariant of the object model.
    Malformed(String),
    /// Valid input this linker cannot express (yet).
    Unsupported(String),
}

impl fmt::Display for LinkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LinkError::Undefined { name, referenced_from } => {
                write!(f, "undefined symbol `{name}`, referenced from `{referenced_from}`")
            }
            LinkError::Duplicate { name } => write!(f, "duplicate symbol `{name}`"),
            LinkError::RelocOutOfRange { atom, target } => {
                write!(f, "relocation in `{atom}` cannot reach `{target}` (out of range or misaligned)")
            }
            LinkError::Malformed(message) => write!(f, "malformed object: {message}"),
            LinkError::Unsupported(message) => write!(f, "unsupported: {message}"),
        }
    }
}

impl std::error::Error for LinkError {}

/// Links `objects` into an executable for `options.target`.
pub fn link(objects: &[Object], options: &LinkOptions) -> Result<LinkedImage, LinkError> {
    if options.target.is_windows() {
        return pe::link(objects, options);
    }
    if options.target.is_darwin() {
        let resolved = resolve::resolve(objects, &options.entry, macho::SYNTHETIC)?;
        macho::write(&resolved, options)
    } else {
        let resolved = resolve::resolve(objects, &options.entry, elf::SYNTHETIC)?;
        elf::write(&resolved, options)
    }
}
