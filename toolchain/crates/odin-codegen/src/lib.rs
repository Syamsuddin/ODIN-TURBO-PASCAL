// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Code generation: HIR to machine-code atoms.

pub mod x86_64;

use std::collections::HashSet;

use odin_asm::Object;
use odin_base::{FileId, Span};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Os {
    Darwin,
    Linux,
}

#[derive(Clone, Debug)]
pub struct Options {
    pub os: Os,
    /// Source files whose routines get debugger hooks (`--debug`). Empty
    /// for a normal build.
    pub debug_files: HashSet<FileId>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CodegenError {
    pub message: String,
    pub span: Span,
}

pub type CResult<T> = Result<T, CodegenError>;

/// The code offset where a statement starts, for line tables and runtime
/// error positions.
#[derive(Clone, Debug, PartialEq)]
pub struct LineEntry {
    /// Atom (routine symbol) containing the statement.
    pub symbol: String,
    pub offset: u32,
    pub span: Span,
}

/// Where a routine keeps one of its locals, relative to its frame pointer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LocalSlot {
    pub offset: i32,
    /// The slot holds the variable's address (`var` parameters, results
    /// returned by reference, open arrays).
    pub indirect: bool,
}

pub struct Output {
    pub object: Object,
    pub lines: Vec<LineEntry>,
    /// Symbol of the entry point (`_main` on Darwin).
    pub entry: String,
    /// Debug builds: the statement of every line id passed to the hook.
    pub debug_points: Vec<Span>,
    /// Frame slot of every local, per routine (in `Program::routines` order).
    pub frames: Vec<Vec<LocalSlot>>,
    /// Per routine: whether it carries debugger hooks.
    pub instrumented: Vec<bool>,
}

/// Install name of the C library on each OS.
pub fn c_library(os: Os) -> &'static str {
    match os {
        Os::Darwin => "/usr/lib/libSystem.B.dylib",
        Os::Linux => "libc",
    }
}

/// Library name used in `external 'odinrtl'` for routines written in the
/// RTL's assembly shims.
pub const RTL_ASM_LIBRARY: &str = "odinrtl";
