// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Symbols and scopes.

use std::collections::HashMap;

use odin_base::Span;
use odin_ir::{GlobalId, LabelId, RoutineId, TypeId, Var};

/// A compile-time constant.
#[derive(Clone, Debug, PartialEq)]
pub enum ConstKind {
    Int(i64),
    Real(f64),
    Str(Vec<u8>),
    Set(Vec<u8>),
    Nil,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConstVal {
    pub kind: ConstKind,
    pub ty: TypeId,
}

/// Routines whose argument rules no ordinary declaration can express.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Builtin {
    Write,
    WriteLn,
    Read,
    ReadLn,
    Inc,
    Dec,
    Ord,
    Chr,
    Succ,
    Pred,
    Odd,
    Abs,
    Sqr,
    Sqrt,
    Trunc,
    Round,
    Int,
    Frac,
    Length,
    SizeOf,
    High,
    Low,
    Halt,
    Exit,
    Break,
    Continue,
    New,
    Dispose,
    Assigned,
    Lo,
    Hi,
    Concat,
    Include,
    Exclude,
    Addr,
    Str,
    Val,
    Assign,
    Reset,
    Rewrite,
    Append,
    Close,
    Flush,
    Erase,
    Rename,
    Eof,
    Eoln,
    SeekEof,
    SeekEoln,
    BlockRead,
    BlockWrite,
    Seek,
    FilePos,
    FileSize,
    Truncate,
    FillChar,
    GetMem,
    FreeMem,
    Random,
    RunError,
    Swap,
    TypeOf,
    Ofs,
    Seg,
}

pub const BUILTINS: &[(&str, Builtin)] = &[
    ("WRITE", Builtin::Write),
    ("WRITELN", Builtin::WriteLn),
    ("READ", Builtin::Read),
    ("READLN", Builtin::ReadLn),
    ("INC", Builtin::Inc),
    ("DEC", Builtin::Dec),
    ("ORD", Builtin::Ord),
    ("CHR", Builtin::Chr),
    ("SUCC", Builtin::Succ),
    ("PRED", Builtin::Pred),
    ("ODD", Builtin::Odd),
    ("ABS", Builtin::Abs),
    ("SQR", Builtin::Sqr),
    ("SQRT", Builtin::Sqrt),
    ("TRUNC", Builtin::Trunc),
    ("ROUND", Builtin::Round),
    ("INT", Builtin::Int),
    ("FRAC", Builtin::Frac),
    ("LENGTH", Builtin::Length),
    ("SIZEOF", Builtin::SizeOf),
    ("HIGH", Builtin::High),
    ("LOW", Builtin::Low),
    ("HALT", Builtin::Halt),
    ("EXIT", Builtin::Exit),
    ("BREAK", Builtin::Break),
    ("CONTINUE", Builtin::Continue),
    ("NEW", Builtin::New),
    ("DISPOSE", Builtin::Dispose),
    ("ASSIGNED", Builtin::Assigned),
    ("LO", Builtin::Lo),
    ("HI", Builtin::Hi),
    ("CONCAT", Builtin::Concat),
    ("INCLUDE", Builtin::Include),
    ("EXCLUDE", Builtin::Exclude),
    ("ADDR", Builtin::Addr),
    ("STR", Builtin::Str),
    ("VAL", Builtin::Val),
    ("ASSIGN", Builtin::Assign),
    ("RESET", Builtin::Reset),
    ("REWRITE", Builtin::Rewrite),
    ("APPEND", Builtin::Append),
    ("CLOSE", Builtin::Close),
    ("FLUSH", Builtin::Flush),
    ("ERASE", Builtin::Erase),
    ("RENAME", Builtin::Rename),
    ("EOF", Builtin::Eof),
    ("EOLN", Builtin::Eoln),
    ("SEEKEOF", Builtin::SeekEof),
    ("SEEKEOLN", Builtin::SeekEoln),
    ("BLOCKREAD", Builtin::BlockRead),
    ("BLOCKWRITE", Builtin::BlockWrite),
    ("SEEK", Builtin::Seek),
    ("FILEPOS", Builtin::FilePos),
    ("FILESIZE", Builtin::FileSize),
    ("TRUNCATE", Builtin::Truncate),
    ("FILLCHAR", Builtin::FillChar),
    ("GETMEM", Builtin::GetMem),
    ("FREEMEM", Builtin::FreeMem),
    ("RANDOM", Builtin::Random),
    ("RUNERROR", Builtin::RunError),
    ("SWAP", Builtin::Swap),
    ("TYPEOF", Builtin::TypeOf),
    ("OFS", Builtin::Ofs),
    ("SEG", Builtin::Seg),
];

#[derive(Clone, Debug, PartialEq)]
pub enum Sym {
    Const(ConstVal),
    Type(TypeId),
    Var(Var, TypeId),
    Routine(RoutineId),
    Builtin(Builtin),
    Unit(usize),
    Label(LabelId),
}

impl Sym {
    pub fn global(id: GlobalId, ty: TypeId) -> Sym {
        Sym::Var(Var::Global(id), ty)
    }
}

/// One level of names. Keys are uppercase.
#[derive(Clone, Debug, Default)]
pub struct Scope {
    names: HashMap<String, (Sym, Span)>,
}

impl Scope {
    pub fn get(&self, key: &str) -> Option<&Sym> {
        self.names.get(key).map(|(s, _)| s)
    }

    pub fn contains(&self, key: &str) -> bool {
        self.names.contains_key(key)
    }

    /// Inserts a name; returns the earlier declaration's span on a clash.
    pub fn insert(&mut self, key: String, sym: Sym, span: Span) -> Result<(), Span> {
        if let Some((_, earlier)) = self.names.get(&key) {
            return Err(*earlier);
        }
        self.names.insert(key, (sym, span));
        Ok(())
    }

    /// Inserts or replaces (used when a forward declaration gets its body).
    pub fn replace(&mut self, key: String, sym: Sym, span: Span) {
        self.names.insert(key, (sym, span));
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &Sym)> {
        self.names.iter().map(|(k, (s, _))| (k, s))
    }
}
