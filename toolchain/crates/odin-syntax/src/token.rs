// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Tokens and compiler switch state.

use odin_base::Span;

/// Turbo Pascal reserved words. Directives such as `forward`, `external`,
/// `virtual` or `absolute` are ordinary identifiers with meaning in context.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Kw {
    And,
    Array,
    Asm,
    Begin,
    Case,
    Const,
    Constructor,
    Destructor,
    Div,
    Do,
    Downto,
    Else,
    End,
    Exports,
    File,
    For,
    Function,
    Goto,
    If,
    Implementation,
    In,
    Inherited,
    Inline,
    Interface,
    Label,
    Library,
    Mod,
    Nil,
    Not,
    Object,
    Of,
    Or,
    Packed,
    Procedure,
    Program,
    Record,
    Repeat,
    Set,
    Shl,
    Shr,
    String,
    Then,
    To,
    Type,
    Unit,
    Until,
    Uses,
    Var,
    While,
    With,
    Xor,
}

const KEYWORDS: &[(&str, Kw)] = &[
    ("AND", Kw::And),
    ("ARRAY", Kw::Array),
    ("ASM", Kw::Asm),
    ("BEGIN", Kw::Begin),
    ("CASE", Kw::Case),
    ("CONST", Kw::Const),
    ("CONSTRUCTOR", Kw::Constructor),
    ("DESTRUCTOR", Kw::Destructor),
    ("DIV", Kw::Div),
    ("DO", Kw::Do),
    ("DOWNTO", Kw::Downto),
    ("ELSE", Kw::Else),
    ("END", Kw::End),
    ("EXPORTS", Kw::Exports),
    ("FILE", Kw::File),
    ("FOR", Kw::For),
    ("FUNCTION", Kw::Function),
    ("GOTO", Kw::Goto),
    ("IF", Kw::If),
    ("IMPLEMENTATION", Kw::Implementation),
    ("IN", Kw::In),
    ("INHERITED", Kw::Inherited),
    ("INLINE", Kw::Inline),
    ("INTERFACE", Kw::Interface),
    ("LABEL", Kw::Label),
    ("LIBRARY", Kw::Library),
    ("MOD", Kw::Mod),
    ("NIL", Kw::Nil),
    ("NOT", Kw::Not),
    ("OBJECT", Kw::Object),
    ("OF", Kw::Of),
    ("OR", Kw::Or),
    ("PACKED", Kw::Packed),
    ("PROCEDURE", Kw::Procedure),
    ("PROGRAM", Kw::Program),
    ("RECORD", Kw::Record),
    ("REPEAT", Kw::Repeat),
    ("SET", Kw::Set),
    ("SHL", Kw::Shl),
    ("SHR", Kw::Shr),
    ("STRING", Kw::String),
    ("THEN", Kw::Then),
    ("TO", Kw::To),
    ("TYPE", Kw::Type),
    ("UNIT", Kw::Unit),
    ("UNTIL", Kw::Until),
    ("USES", Kw::Uses),
    ("VAR", Kw::Var),
    ("WHILE", Kw::While),
    ("WITH", Kw::With),
    ("XOR", Kw::Xor),
];

impl Kw {
    /// Looks up an identifier (any case).
    pub fn from_ident(text: &str) -> Option<Kw> {
        let upper = text.to_ascii_uppercase();
        KEYWORDS.iter().find(|(name, _)| *name == upper).map(|&(_, kw)| kw)
    }

    pub fn name(self) -> &'static str {
        KEYWORDS.iter().find(|&&(_, kw)| kw == self).map(|&(name, _)| name).unwrap_or("?")
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Tok {
    /// Identifier as written in the source.
    Ident(String),
    Keyword(Kw),
    /// Unsigned integer literal (decimal or `$hex`).
    Int(u64),
    /// Real literal, correctly rounded to the nearest `f64`.
    Real(f64),
    /// One quoted string or one `#n` control character. Adjacent string
    /// pieces are merged by the parser.
    Str(Vec<u8>),
    /// `^X` control character. Kept apart from `Str` because in a type
    /// context `^T` means "pointer to T".
    CaretChar(u8),
    /// Raw text of an `asm ... end` block (without `asm` and `end`).
    AsmText(String),
    Plus,
    Minus,
    Star,
    Slash,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    Assign,
    Colon,
    Semi,
    Comma,
    Dot,
    DotDot,
    LParen,
    RParen,
    LBracket,
    RBracket,
    Caret,
    At,
    Eof,
}

impl Tok {
    /// Description for error messages ("... tetapi ditemukan X").
    pub fn describe(&self) -> String {
        match self {
            Tok::Ident(name) => format!("identifier {}", name.to_ascii_uppercase()),
            Tok::Keyword(kw) => kw.name().to_string(),
            Tok::Int(_) | Tok::Real(_) => "konstanta angka".to_string(),
            Tok::Str(_) | Tok::CaretChar(_) => "konstanta string".to_string(),
            Tok::AsmText(_) => "blok ASM".to_string(),
            Tok::Eof => "akhir berkas".to_string(),
            other => format!("\"{}\"", other.symbol()),
        }
    }

    /// Spelling of a punctuation token.
    pub fn symbol(&self) -> &'static str {
        match self {
            Tok::Plus => "+",
            Tok::Minus => "-",
            Tok::Star => "*",
            Tok::Slash => "/",
            Tok::Eq => "=",
            Tok::Ne => "<>",
            Tok::Lt => "<",
            Tok::Le => "<=",
            Tok::Gt => ">",
            Tok::Ge => ">=",
            Tok::Assign => ":=",
            Tok::Colon => ":",
            Tok::Semi => ";",
            Tok::Comma => ",",
            Tok::Dot => ".",
            Tok::DotDot => "..",
            Tok::LParen => "(",
            Tok::RParen => ")",
            Tok::LBracket => "[",
            Tok::RBracket => "]",
            Tok::Caret => "^",
            Tok::At => "@",
            _ => "",
        }
    }
}

/// Compiler switches (`{$R+}` and friends) in effect at a token.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Switches(pub u16);

impl Switches {
    /// `$R`: range checking.
    pub const RANGE: u16 = 1 << 0;
    /// `$Q`: overflow checking.
    pub const OVERFLOW: u16 = 1 << 1;
    /// `$I`: I/O checking.
    pub const IO: u16 = 1 << 2;
    /// `$B`: complete Boolean evaluation.
    pub const BOOL_EVAL: u16 = 1 << 3;
    /// `$X`: extended syntax (functions as statements, PChar strings).
    pub const EXTENDED: u16 = 1 << 4;
    /// `$V`: strict var-string checking.
    pub const VAR_STRING: u16 = 1 << 5;
    /// `$P`: open string parameters.
    pub const OPEN_STRING: u16 = 1 << 6;
    /// `$T`: typed `@` operator.
    pub const TYPED_AT: u16 = 1 << 7;
    /// `$S`: stack checking.
    pub const STACK: u16 = 1 << 8;
    /// `$D`: debug information.
    pub const DEBUG: u16 = 1 << 9;

    /// Turbo Pascal 7 defaults: `$B- $D+ $I+ $P- $Q- $R- $S+ $T- $V+ $X+`.
    pub fn tp_default() -> Self {
        Switches(Self::IO | Self::EXTENDED | Self::VAR_STRING | Self::STACK | Self::DEBUG)
    }

    pub fn get(self, flag: u16) -> bool {
        self.0 & flag != 0
    }

    pub fn set(&mut self, flag: u16, on: bool) {
        if on {
            self.0 |= flag;
        } else {
            self.0 &= !flag;
        }
    }

    /// The flag for a single-letter switch, if Odin tracks it.
    pub fn letter(c: u8) -> Option<u16> {
        Some(match c.to_ascii_uppercase() {
            b'R' => Self::RANGE,
            b'Q' => Self::OVERFLOW,
            b'I' => Self::IO,
            b'B' => Self::BOOL_EVAL,
            b'X' => Self::EXTENDED,
            b'V' => Self::VAR_STRING,
            b'P' => Self::OPEN_STRING,
            b'T' => Self::TYPED_AT,
            b'S' => Self::STACK,
            b'D' => Self::DEBUG,
            _ => return None,
        })
    }
}

impl Default for Switches {
    fn default() -> Self {
        Self::tp_default()
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Token {
    pub tok: Tok,
    pub span: Span,
    pub switches: Switches,
}
