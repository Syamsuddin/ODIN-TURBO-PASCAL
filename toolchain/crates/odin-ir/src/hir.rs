// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Typed, name-resolved program representation produced by semantic
//! analysis and consumed by the code generators.
//!
//! Every expression carries its type. Implicit conversions, range checks,
//! `with` scopes and the magic of `Write`/`Read`/`Inc`/... are already made
//! explicit, so a code generator only has to follow the tree.

use odin_base::Span;

use crate::types::{ParamMode, Signature, Type, TypeId, TypeTable};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct RoutineId(pub u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct GlobalId(pub u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct LabelId(pub u32);

/// The whole program after semantic analysis.
pub struct Program {
    pub types: TypeTable,
    pub globals: Vec<Global>,
    pub routines: Vec<Routine>,
    /// Unit initialization routines in execution order.
    pub init_order: Vec<RoutineId>,
    /// The main program body.
    pub main: RoutineId,
    /// Source files, for line tables.
    pub files: Vec<std::path::PathBuf>,
}

/// Initial contents of a global: raw bytes plus pointer fields.
#[derive(Clone, Debug, PartialEq)]
pub struct GlobalInit {
    pub bytes: Vec<u8>,
    /// `(offset, symbol)` pairs: 64-bit addresses of other globals or routines.
    pub pointers: Vec<(u64, String)>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Global {
    /// Mangled symbol, unique in the program (`UNIT.NAME`).
    pub symbol: String,
    /// Name as declared, for the debugger.
    pub name: String,
    pub ty: TypeId,
    /// `None` means zero-initialized (bss).
    pub init: Option<GlobalInit>,
    /// String literals and other constants that are never written.
    pub readonly: bool,
    pub span: Span,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LocalKind {
    /// Parameter `index` of the signature.
    Param(u32),
    /// The hidden `High` value of an open array parameter.
    OpenHigh(u32),
    /// A function's result variable.
    Result,
    Var,
    /// Compiler temporary.
    Temp,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Local {
    pub name: String,
    pub ty: TypeId,
    pub kind: LocalKind,
}

#[derive(Clone, Debug, PartialEq)]
pub enum RoutineBody {
    Code(Vec<Stmt>),
    /// A C function from a shared library (`cdecl; external 'c' name 'write'`).
    External {
        symbol: String,
        library: String,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Routine {
    /// Mangled symbol (`UNIT.NAME`, `UNIT.OUTER.INNER`).
    pub symbol: String,
    /// Source-level name for stack traces (`UMath.Kuadrat`).
    pub display: String,
    pub sig: Signature,
    /// Lexically enclosing routine; nested routines receive its frame
    /// pointer as a static link.
    pub parent: Option<RoutineId>,
    /// Parameters first (in signature order), then everything else.
    pub locals: Vec<Local>,
    pub body: RoutineBody,
    pub span: Span,
}

impl Routine {
    pub fn result_local(&self) -> Option<u32> {
        self.locals.iter().position(|l| l.kind == LocalKind::Result).map(|i| i as u32)
    }
}

/// How an argument travels to a routine.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Passing {
    /// Scalar value in a register.
    Value,
    /// Address of the caller's variable (`var`, `const` structured,
    /// untyped).
    Ref,
    /// Address of a value the callee copies on entry (value parameters of
    /// strings, records, arrays and large sets).
    RefCopy,
    /// Address of the first element, followed by a hidden `High` value.
    OpenArray,
}

/// Whether a value of this type fits in one register.
pub fn is_scalar(types: &TypeTable, ty: TypeId) -> bool {
    match types.get(ty) {
        Type::Int(_)
        | Type::Bool
        | Type::Char
        | Type::Enum { .. }
        | Type::Subrange { .. }
        | Type::Real(_)
        | Type::Pointer(_)
        | Type::Procedural(_)
        | Type::Nil => true,
        // Sets always live in memory, whatever their size.
        _ => false,
    }
}

pub fn passing(types: &TypeTable, mode: ParamMode, ty: TypeId) -> Passing {
    if matches!(types.get(ty), Type::OpenArray { .. } | Type::OpenString) {
        return Passing::OpenArray;
    }
    match mode {
        ParamMode::Var => Passing::Ref,
        ParamMode::Const if is_scalar(types, ty) => Passing::Value,
        ParamMode::Const => Passing::Ref,
        ParamMode::Value if is_scalar(types, ty) => Passing::Value,
        ParamMode::Value => Passing::RefCopy,
    }
}

/// Whether a function returns its result through a hidden pointer.
pub fn result_by_ref(types: &TypeTable, ty: TypeId) -> bool {
    !is_scalar(types, ty)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Var {
    Global(GlobalId),
    /// Local `index` of `routine`, which is the current routine or one of
    /// its lexical ancestors.
    Local {
        routine: RoutineId,
        index: u32,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cond {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

impl Cond {
    pub fn swap(self) -> Cond {
        match self {
            Cond::Lt => Cond::Gt,
            Cond::Le => Cond::Ge,
            Cond::Gt => Cond::Lt,
            Cond::Ge => Cond::Le,
            c => c,
        }
    }

    pub fn eval<T: PartialOrd>(self, a: T, b: T) -> bool {
        match self {
            Cond::Eq => a == b,
            Cond::Ne => a != b,
            Cond::Lt => a < b,
            Cond::Le => a <= b,
            Cond::Gt => a > b,
            Cond::Ge => a >= b,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnOp {
    /// Integer negation (64-bit).
    Neg,
    /// Bitwise not (64-bit).
    Not,
    BoolNot,
    RealNeg,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinOp {
    // Integer arithmetic, computed in 64 bits like FPC on 64-bit targets.
    Add,
    Sub,
    Mul,
    /// `Add`/`Sub`/`Mul` with a 64-bit overflow check (`{$Q+}`, runtime
    /// error 215).
    AddChecked,
    SubChecked,
    MulChecked,
    Div,
    Mod,
    And,
    Or,
    Xor,
    /// Shifts use the width of the expression type (32 or 64 bits).
    Shl,
    Shr,
    /// Ordinal, Boolean, Char and pointer comparison on 64-bit values.
    Cmp(Cond),
    RealAdd,
    RealSub,
    RealMul,
    RealDiv,
    RealCmp(Cond),
    /// Short-circuit Boolean operators (`{$B-}`).
    AndThen,
    OrElse,
    /// Complete evaluation (`{$B+}`) and `xor`.
    BoolAnd,
    BoolOr,
    BoolXor,
    StrCmp(Cond),
    SetUnion,
    SetDiff,
    SetIntersect,
    /// `=`, `<>`, `<=` (subset), `>=` (superset).
    SetCmp(Cond),
    /// Ordinal (left) `in` set (right).
    In,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Conv {
    /// Integer to Real.
    IntToReal,
    /// Wrap a 64-bit integer to the expression type's size, then sign- or
    /// zero-extend (typecasts, `Chr`, `Ord`).
    Resize,
    /// Fail with runtime error 201 unless `lo <= value <= hi`.
    RangeCheck { lo: i64, hi: i64 },
    /// Single character to a string of length 1.
    CharToStr,
    /// Reinterpret bits (pointer <-> pointer, procedural <-> pointer).
    Bits,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Intrinsic {
    /// `Length(s)`: the length byte of a short string.
    Length,
    /// `High` of an open array parameter (argument: the parameter).
    OpenHigh,
    Odd,
    AbsInt,
    AbsReal,
    SqrInt,
    SqrReal,
    Sqrt,
    /// Truncation toward zero (Int64 result).
    Trunc,
    /// Banker's rounding like FPC (Int64 result).
    Round,
    /// Integer part / fractional part of a Real.
    Int,
    Frac,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Callee {
    Routine(RoutineId),
    /// A procedural value.
    Indirect(Box<Expr>),
    /// A virtual method: the first argument is the instance (`Self`); the
    /// code address is slot `slot` of the VMT found at `vmt_offset` in it.
    /// `routine` gives the signature. `check` (under `{$R+}`) reports
    /// runtime error 210 for an instance without a valid VMT.
    Virtual {
        routine: RoutineId,
        vmt_offset: u64,
        slot: u32,
        check: bool,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub ty: TypeId,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ExprKind {
    Int(i64),
    Real(f64),
    /// String constant.
    Str(Vec<u8>),
    Nil,
    /// Set constant in the layout of `ty`.
    SetConst(Vec<u8>),
    /// Address of a routine (procedural value, `@Proc`).
    RoutineAddr(RoutineId),
    Var(Var),
    /// Field at `offset` of a record lvalue.
    Field {
        base: Box<Expr>,
        offset: u64,
    },
    /// Element of an array lvalue (or a character of a string, with
    /// `lo = 0`). `check` adds a range check against `lo..=hi`.
    Index {
        base: Box<Expr>,
        index: Box<Expr>,
        lo: i64,
        hi: i64,
        check: bool,
    },
    /// Element of an open array parameter (bounds from its hidden High).
    OpenIndex {
        base: Box<Expr>,
        index: Box<Expr>,
        check: bool,
    },
    Deref(Box<Expr>),
    AddrOf(Box<Expr>),
    Unary(UnOp, Box<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
    Convert(Conv, Box<Expr>),
    /// Arguments match the callee's parameters one to one; for `Ref`,
    /// `RefCopy` and `OpenArray` passing the argument is the lvalue or
    /// value whose address is passed.
    Call {
        callee: Callee,
        args: Vec<Expr>,
    },
    /// String concatenation (result type: String).
    Concat(Vec<Expr>),
    /// Set constructor with run-time elements.
    SetBuild(Vec<(Expr, Option<Expr>)>),
    Intrinsic(Intrinsic, Vec<Expr>),
}

impl Expr {
    pub fn new(kind: ExprKind, ty: TypeId, span: Span) -> Self {
        Expr { kind, ty, span }
    }

    pub fn int_value(&self) -> Option<i64> {
        match self.kind {
            ExprKind::Int(v) => Some(v),
            _ => None,
        }
    }

    pub fn is_const(&self) -> bool {
        matches!(
            self.kind,
            ExprKind::Int(_) | ExprKind::Real(_) | ExprKind::Str(_) | ExprKind::Nil | ExprKind::SetConst(_)
        )
    }

    /// Whether this expression denotes storage (can be assigned or passed
    /// by reference).
    pub fn is_lvalue(&self) -> bool {
        matches!(
            self.kind,
            ExprKind::Var(_)
                | ExprKind::Field { .. }
                | ExprKind::Index { .. }
                | ExprKind::OpenIndex { .. }
                | ExprKind::Deref(_)
        )
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct CaseArm {
    pub ranges: Vec<(i64, i64)>,
    pub body: Vec<Stmt>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Stmt {
    pub kind: StmtKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum StmtKind {
    /// `value` already has the target's type (conversions and range checks
    /// are explicit); strings are truncated to the target's capacity.
    Assign {
        target: Expr,
        value: Expr,
    },
    /// A call whose result (if any) is discarded.
    Call(Expr),
    If {
        cond: Expr,
        then: Vec<Stmt>,
        otherwise: Vec<Stmt>,
    },
    While {
        cond: Expr,
        body: Vec<Stmt>,
    },
    Repeat {
        body: Vec<Stmt>,
        cond: Expr,
    },
    /// `limit` is a temporary holding the final value, evaluated once.
    For {
        var: Expr,
        from: Expr,
        to: Expr,
        limit: Var,
        down: bool,
        body: Vec<Stmt>,
    },
    Case {
        selector: Expr,
        arms: Vec<CaseArm>,
        otherwise: Vec<Stmt>,
    },
    Goto(LabelId),
    Label(LabelId),
    Break,
    Continue,
    Exit,
    /// A source statement made of several lowered statements (`WriteLn`
    /// becomes several RTL calls); the span marks one line-table entry.
    Block(Vec<Stmt>),
}

/// Symbols of runtime routines the code generators call directly. They are
/// defined by `rtl/system/system.pas`.
pub mod rtl {
    /// Runtime error 201 (no arguments; reports its caller's address).
    pub const RANGE_ERROR: &str = "SYSTEM.ODIN_RANGEERROR";
    /// Runtime error 215.
    pub const OVERFLOW_ERROR: &str = "SYSTEM.ODIN_OVERFLOWERROR";
    /// Runtime error 200.
    pub const DIVZERO_ERROR: &str = "SYSTEM.ODIN_DIVZEROERROR";
    /// `(Dest: Pointer; MaxLen: Int64; Src: Pointer)`: copy a string,
    /// truncated to `MaxLen` characters.
    pub const STR_ASSIGN: &str = "SYSTEM.ODIN_STRASSIGN";
    /// `(Dest: Pointer; Src: Pointer)`: append to a 255-character string.
    pub const STR_APPEND: &str = "SYSTEM.ODIN_STRAPPEND";
    /// `(A, B: Pointer): LongInt`, returning -1, 0 or 1.
    pub const STR_COMPARE: &str = "SYSTEM.ODIN_STRCOMPARE";
    /// `(ArgC: LongInt; ArgV: Pointer)`, called first by the entry point.
    pub const STARTUP: &str = "SYSTEM.ODIN_STARTUP";
    /// `(Code: LongInt)`, called after the main program; never returns.
    pub const HALT: &str = "SYSTEM.ODIN_HALT";
    /// Runtime error 210: a virtual method called on an object without a
    /// valid VMT (no constructor call), under `{$R+}`.
    pub const OBJECT_ERROR: &str = "SYSTEM.ODIN_OBJECTERROR";
    /// Debug builds (`--debug`): id of the statement being executed.
    pub const DBG_LINE: &str = "SYSTEM.ODIN_DBG_LINE";
    /// Debug builds: number of instrumented routines on the call stack.
    pub const DBG_DEPTH: &str = "SYSTEM.ODIN_DBG_DEPTH";
    /// Debug builds: memory shared with the debugger, or nil without one.
    /// Byte 0: step mode, byte 1: pause request, byte `16 + id`: breakpoint.
    pub const DBG_SHARED: &str = "SYSTEM.ODIN_DBG_SHARED";
    /// Debug builds: one 16-byte entry per depth (caller's line id u32,
    /// routine index u32, frame pointer u64).
    pub const DBG_STACK: &str = "SYSTEM.ODIN_DBG_STACK";
    /// Entries in [`DBG_STACK`]; deeper calls are counted but not recorded.
    pub const DBG_STACK_SIZE: i32 = 4096;
    /// `(Id: LongInt)`: a statement where the debugger may want to stop.
    pub const DBG_HOOK: &str = "SYSTEM.ODIN_DBG_HOOK";
    /// `(LineCount: LongInt)`: connects to the debugger, called after startup.
    pub const DBG_INIT: &str = "SYSTEM.ODIN_DBG_INIT";
}
