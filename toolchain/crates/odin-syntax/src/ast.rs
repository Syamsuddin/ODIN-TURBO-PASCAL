// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Abstract syntax tree for Turbo Pascal 7, extended with classes.
//!
//! The parser resolves no names. Ambiguities that need symbol information
//! (a call versus a typecast, a type name versus a constant in a subrange)
//! are kept in a neutral form and settled by semantic analysis.

use odin_base::Span;

use crate::token::Switches;

/// An identifier as written. Pascal identifiers are case-insensitive;
/// compare with [`Ident::key`] or [`Ident::is`].
#[derive(Clone, Debug, PartialEq)]
pub struct Ident {
    pub name: String,
    pub span: Span,
}

impl Ident {
    /// Uppercase form used for lookups.
    pub fn key(&self) -> String {
        self.name.to_ascii_uppercase()
    }

    /// Case-insensitive comparison with `other`.
    pub fn is(&self, other: &str) -> bool {
        self.name.eq_ignore_ascii_case(other)
    }
}

/// `Unit.Name` or just `Name`.
#[derive(Clone, Debug, PartialEq)]
pub struct QualIdent {
    pub unit: Option<Ident>,
    pub name: Ident,
}

impl QualIdent {
    pub fn span(&self) -> Span {
        match &self.unit {
            Some(u) => u.span.to(self.name.span),
            None => self.name.span,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Module {
    Program(Program),
    Unit(Unit),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Program {
    pub name: Option<Ident>,
    /// `program X(Input, Output);` parameters, accepted and ignored.
    pub params: Vec<Ident>,
    pub uses: Vec<Ident>,
    pub block: Block,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Unit {
    pub name: Ident,
    pub interface_uses: Vec<Ident>,
    pub interface: Vec<Decl>,
    pub implementation_uses: Vec<Ident>,
    pub implementation: Vec<Decl>,
    /// Statements between `begin` and the final `end.`; `None` when the
    /// unit ends with a bare `end.`.
    pub init: Option<Vec<Stmt>>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Block {
    pub decls: Vec<Decl>,
    pub body: Body,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Body {
    /// `begin ... end`; the span covers both keywords.
    Statements(Vec<Stmt>, Span),
    /// The body of an `assembler` routine.
    Asm(AsmBlock),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Decl {
    Labels(Vec<Label>),
    Consts(Vec<ConstDecl>),
    Types(Vec<TypeDecl>),
    Vars(Vec<VarDecl>),
    Routine(Box<Routine>),
}

/// A statement label: digits (0..9999) or an identifier.
#[derive(Clone, Debug, PartialEq)]
pub enum Label {
    Number(u32, Span),
    Name(Ident),
}

impl Label {
    pub fn span(&self) -> Span {
        match self {
            Label::Number(_, s) => *s,
            Label::Name(i) => i.span,
        }
    }

    /// Key for lookups: the number, or the uppercase identifier.
    pub fn key(&self) -> String {
        match self {
            Label::Number(n, _) => n.to_string(),
            Label::Name(i) => i.key(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConstDecl {
    pub name: Ident,
    /// Present for typed constants (`X: Integer = 5`).
    pub ty: Option<TypeExpr>,
    pub value: ConstInit,
    pub span: Span,
}

/// Value of a constant. Structured forms only appear in typed constants.
#[derive(Clone, Debug, PartialEq)]
pub enum ConstInit {
    Expr(Expr),
    /// `(a, b, c)` for arrays.
    List(Vec<ConstInit>, Span),
    /// `(X: 1; Y: 2)` for records and objects.
    Record(Vec<(Ident, ConstInit)>, Span),
}

impl ConstInit {
    pub fn span(&self) -> Span {
        match self {
            ConstInit::Expr(e) => e.span,
            ConstInit::List(_, s) | ConstInit::Record(_, s) => *s,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct TypeDecl {
    pub name: Ident,
    pub ty: TypeExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct VarDecl {
    pub names: Vec<Ident>,
    pub ty: TypeExpr,
    pub absolute: Option<Absolute>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Absolute {
    /// `absolute OtherVar`: shares storage with another variable.
    Var(Expr),
    /// `absolute $B800:$0000`: a real-mode address (rejected later).
    Address(Expr, Expr, Span),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoutineKind {
    Procedure,
    Function,
    Constructor,
    Destructor,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParamMode {
    Value,
    Var,
    Const,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParamGroup {
    pub mode: ParamMode,
    pub names: Vec<Ident>,
    /// `None` for untyped `var`/`const` parameters.
    pub ty: Option<TypeExpr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum DirectiveKind {
    Forward,
    External,
    Assembler,
    Far,
    Near,
    Interrupt,
    Cdecl,
    Export,
    /// `virtual` (or `dynamic`) with an optional dynamic method index.
    Virtual(Option<Expr>),
    /// `override`: replaces an inherited virtual method of a class.
    Override,
    /// `abstract`: a virtual method without a body.
    Abstract,
    /// `reintroduce`: hides an inherited method on purpose.
    Reintroduce,
    /// `overload`: other methods of the same name stay visible.
    Overload,
    /// Directives Odin accepts and ignores (`stdcall`, `register`, ...).
    Other(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Directive {
    pub kind: DirectiveKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RoutineHeading {
    pub kind: RoutineKind,
    /// `class procedure` / `class function`.
    pub class_method: bool,
    /// For `procedure TObj.Method`, the object type name.
    pub owner: Option<Ident>,
    pub name: Ident,
    pub params: Vec<ParamGroup>,
    pub result: Option<TypeExpr>,
    pub directives: Vec<Directive>,
    pub span: Span,
    /// Switches at the start of the heading (`{$P+}` makes `var String`
    /// parameters open strings).
    pub switches: Switches,
}

impl RoutineHeading {
    pub fn has(&self, f: impl Fn(&DirectiveKind) -> bool) -> bool {
        self.directives.iter().any(|d| f(&d.kind))
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Routine {
    pub heading: RoutineHeading,
    pub body: RoutineBody,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum RoutineBody {
    /// A heading in a unit interface or object type, or a `forward`
    /// declaration.
    Declaration,
    /// `external ['lib'] [name 'sym']`.
    External {
        library: Option<Expr>,
        name: Option<Expr>,
    },
    /// `inline(...)` machine code (16-bit; rejected later).
    Inline(Span),
    Block(Block),
}

#[derive(Clone, Debug, PartialEq)]
pub struct TypeExpr {
    pub kind: TypeKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TypeKind {
    Named(QualIdent),
    /// `string` or `string[N]`.
    String(Option<Box<Expr>>),
    /// `file` or `file of T`.
    File(Option<Box<TypeExpr>>),
    Subrange(Box<Expr>, Box<Expr>),
    Enum(Vec<Ident>),
    Array {
        packed: bool,
        index: Vec<TypeExpr>,
        elem: Box<TypeExpr>,
    },
    /// `array of T`, only valid as a parameter type.
    OpenArray(Box<TypeExpr>),
    Record {
        packed: bool,
        fields: FieldList,
    },
    /// An `object`, or a `class` (also a forward `class;`).
    Object(Box<ObjectType>),
    /// `class of TFoo`.
    ClassOf(QualIdent),
    Set {
        packed: bool,
        base: Box<TypeExpr>,
    },
    Pointer(Box<TypeExpr>),
    Procedural {
        function: bool,
        params: Vec<ParamGroup>,
        result: Option<Box<TypeExpr>>,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub struct FieldDecl {
    pub names: Vec<Ident>,
    pub ty: TypeExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FieldList {
    pub fields: Vec<FieldDecl>,
    pub variant: Option<Box<VariantPart>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct VariantPart {
    /// `case Tag: T of` names a tag field; `case T of` does not.
    pub tag: Option<Ident>,
    pub tag_type: QualIdent,
    pub cases: Vec<VariantCase>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct VariantCase {
    pub labels: Vec<CaseLabel>,
    pub fields: FieldList,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ObjectType {
    /// `class` rather than `object`.
    pub class: bool,
    /// `TFoo = class;`: completed later in the same type section.
    pub forward: bool,
    pub parent: Option<QualIdent>,
    pub members: Vec<ObjectMember>,
}

/// Visibility section of a member.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Visibility {
    Public,
    Published,
    Protected,
    StrictProtected,
    Private,
    StrictPrivate,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ObjectMember {
    /// A field; `class_var` for `class var` fields.
    Field {
        decl: FieldDecl,
        vis: Visibility,
        class_var: bool,
    },
    Method {
        heading: RoutineHeading,
        vis: Visibility,
    },
    Property {
        decl: Box<PropertyDecl>,
        vis: Visibility,
    },
}

/// `property Name[Index: T]: T read Getter write Setter; default;`
#[derive(Clone, Debug, PartialEq)]
pub struct PropertyDecl {
    pub name: Ident,
    /// Index parameters of an array property.
    pub params: Vec<ParamGroup>,
    pub ty: TypeExpr,
    pub read: Option<Ident>,
    pub write: Option<Ident>,
    /// `default` after an array property.
    pub default: bool,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnOp {
    Neg,
    Pos,
    Not,
    AddrOf,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    /// `/`, always real division.
    RealDiv,
    Div,
    Mod,
    And,
    Or,
    Xor,
    Shl,
    Shr,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    In,
    /// `x is TFoo`.
    Is,
    /// `x as TFoo`.
    As,
}

impl BinOp {
    pub fn symbol(self) -> &'static str {
        match self {
            BinOp::Add => "+",
            BinOp::Sub => "-",
            BinOp::Mul => "*",
            BinOp::RealDiv => "/",
            BinOp::Div => "div",
            BinOp::Mod => "mod",
            BinOp::And => "and",
            BinOp::Or => "or",
            BinOp::Xor => "xor",
            BinOp::Shl => "shl",
            BinOp::Shr => "shr",
            BinOp::Eq => "=",
            BinOp::Ne => "<>",
            BinOp::Lt => "<",
            BinOp::Le => "<=",
            BinOp::Gt => ">",
            BinOp::Ge => ">=",
            BinOp::In => "in",
            BinOp::Is => "is",
            BinOp::As => "as",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum ExprKind {
    Int(u64),
    Real(f64),
    /// A string or character constant (one byte long = a `Char` constant).
    Str(Vec<u8>),
    Nil,
    Name(Ident),
    /// Set constructor `[a, b..c]`.
    Set(Vec<SetItem>),
    Unary(UnOp, Box<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
    /// `f(args)`: a call or a typecast, decided by semantic analysis.
    Call {
        callee: Box<Expr>,
        args: Vec<Arg>,
    },
    Index {
        base: Box<Expr>,
        indices: Vec<Expr>,
    },
    /// `a.b`: a field, a method, or a unit-qualified name.
    Field {
        base: Box<Expr>,
        field: Ident,
    },
    Deref(Box<Expr>),
    /// `inherited Name`, or a bare `inherited` (the method being defined,
    /// with its own arguments).
    Inherited(Option<Ident>),
    /// `string(x)` style casts to the reserved word `string`.
    StringType,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SetItem {
    pub lo: Expr,
    pub hi: Option<Expr>,
}

/// A call argument. `width` and `decimals` are only valid in
/// `Write`/`WriteLn`/`Str` (`x:10:2`).
#[derive(Clone, Debug, PartialEq)]
pub struct Arg {
    pub value: Expr,
    pub width: Option<Expr>,
    pub decimals: Option<Expr>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Stmt {
    pub kind: StmtKind,
    pub span: Span,
    /// Switches in effect at the first token of the statement.
    pub switches: Switches,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CaseLabel {
    pub lo: Expr,
    pub hi: Option<Expr>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CaseArm {
    pub labels: Vec<CaseLabel>,
    pub body: Stmt,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct AsmBlock {
    pub text: String,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum StmtKind {
    Empty,
    Assign {
        target: Expr,
        value: Expr,
    },
    /// A procedure call, or a function call used as a statement (`{$X+}`).
    Call(Expr),
    Compound(Vec<Stmt>),
    If {
        cond: Expr,
        then: Box<Stmt>,
        otherwise: Option<Box<Stmt>>,
    },
    Case {
        expr: Expr,
        arms: Vec<CaseArm>,
        otherwise: Option<Vec<Stmt>>,
    },
    While {
        cond: Expr,
        body: Box<Stmt>,
    },
    Repeat {
        body: Vec<Stmt>,
        cond: Expr,
    },
    For {
        var: Ident,
        from: Expr,
        to: Expr,
        down: bool,
        body: Box<Stmt>,
    },
    With {
        records: Vec<Expr>,
        body: Box<Stmt>,
    },
    Goto(Label),
    Labeled(Label, Box<Stmt>),
    Asm(AsmBlock),
}
