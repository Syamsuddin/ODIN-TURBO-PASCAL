// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Operand types of the x86-64 encoder: registers, widths, condition codes,
//! labels and memory operands.

use std::fmt;

/// A general-purpose register. The access width is not part of the register:
/// every instruction takes a [`Width`], so `Reg::Rax` at [`Width::W32`] is
/// `eax` and at [`Width::W8`] is `al`.
///
/// At [`Width::W8`], `Rsp`, `Rbp`, `Rsi` and `Rdi` are `spl`, `bpl`, `sil`
/// and `dil`; the encoder adds the REX prefix they need. The legacy high-byte
/// registers `ah`, `ch`, `dh` and `bh` are never produced.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum Reg {
    Rax = 0,
    Rcx,
    Rdx,
    Rbx,
    Rsp,
    Rbp,
    Rsi,
    Rdi,
    R8,
    R9,
    R10,
    R11,
    R12,
    R13,
    R14,
    R15,
}

const REG_NAMES: [[&str; 16]; 4] = [
    ["al", "cl", "dl", "bl", "spl", "bpl", "sil", "dil", "r8b", "r9b", "r10b", "r11b", "r12b", "r13b", "r14b", "r15b"],
    ["ax", "cx", "dx", "bx", "sp", "bp", "si", "di", "r8w", "r9w", "r10w", "r11w", "r12w", "r13w", "r14w", "r15w"],
    [
        "eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi", "r8d", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d",
        "r15d",
    ],
    ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"],
];

impl Reg {
    /// All sixteen registers in encoding order.
    pub const ALL: [Reg; 16] = [
        Reg::Rax,
        Reg::Rcx,
        Reg::Rdx,
        Reg::Rbx,
        Reg::Rsp,
        Reg::Rbp,
        Reg::Rsi,
        Reg::Rdi,
        Reg::R8,
        Reg::R9,
        Reg::R10,
        Reg::R11,
        Reg::R12,
        Reg::R13,
        Reg::R14,
        Reg::R15,
    ];

    /// Hardware register number, 0 to 15.
    pub fn index(self) -> u8 {
        self as u8
    }

    /// The register with hardware number `index`, if it is below 16.
    pub fn from_index(index: u8) -> Option<Reg> {
        Reg::ALL.get(index as usize).copied()
    }

    /// The Intel-syntax name at `width`, e.g. `r8d` or `sil`.
    pub fn name(self, width: Width) -> &'static str {
        REG_NAMES[width as usize][self as usize]
    }

    /// Parses a register name in any width (case-insensitive). The high-byte
    /// registers `ah`, `ch`, `dh` and `bh` are not recognized.
    pub fn parse(name: &str) -> Option<(Reg, Width)> {
        let lower = name.to_ascii_lowercase();
        for width in Width::ALL {
            if let Some(i) = REG_NAMES[width as usize].iter().position(|n| *n == lower) {
                return Some((Reg::ALL[i], width));
            }
        }
        None
    }

    /// Low three bits of the register number, as they go into ModRM or SIB.
    pub(crate) fn low3(self) -> u8 {
        self as u8 & 7
    }

    /// Whether the register needs a REX extension bit (r8 to r15).
    pub(crate) fn high(self) -> bool {
        self as u8 >= 8
    }
}

/// An SSE register, `xmm0` to `xmm15`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum Xmm {
    Xmm0 = 0,
    Xmm1,
    Xmm2,
    Xmm3,
    Xmm4,
    Xmm5,
    Xmm6,
    Xmm7,
    Xmm8,
    Xmm9,
    Xmm10,
    Xmm11,
    Xmm12,
    Xmm13,
    Xmm14,
    Xmm15,
}

impl Xmm {
    /// All sixteen registers in encoding order.
    pub const ALL: [Xmm; 16] = [
        Xmm::Xmm0,
        Xmm::Xmm1,
        Xmm::Xmm2,
        Xmm::Xmm3,
        Xmm::Xmm4,
        Xmm::Xmm5,
        Xmm::Xmm6,
        Xmm::Xmm7,
        Xmm::Xmm8,
        Xmm::Xmm9,
        Xmm::Xmm10,
        Xmm::Xmm11,
        Xmm::Xmm12,
        Xmm::Xmm13,
        Xmm::Xmm14,
        Xmm::Xmm15,
    ];

    /// Hardware register number, 0 to 15.
    pub fn index(self) -> u8 {
        self as u8
    }

    /// The register with hardware number `index`, if it is below 16.
    pub fn from_index(index: u8) -> Option<Xmm> {
        Xmm::ALL.get(index as usize).copied()
    }

    /// Parses `xmm0` to `xmm15` (case-insensitive).
    pub fn parse(name: &str) -> Option<Xmm> {
        let lower = name.to_ascii_lowercase();
        let digits = lower.strip_prefix("xmm")?;
        if digits.is_empty() || (digits.len() > 1 && digits.starts_with('0')) {
            return None;
        }
        Xmm::from_index(digits.parse().ok()?)
    }
}

impl fmt::Display for Xmm {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "xmm{}", self.index())
    }
}

/// Operand width of an integer instruction.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Width {
    W8,
    W16,
    W32,
    W64,
}

impl Width {
    /// The four widths, narrowest first.
    pub const ALL: [Width; 4] = [Width::W8, Width::W16, Width::W32, Width::W64];

    /// Size in bytes: 1, 2, 4 or 8.
    pub fn bytes(self) -> u32 {
        1 << self as u32
    }

    /// Size in bits: 8, 16, 32 or 64.
    pub fn bits(self) -> u32 {
        self.bytes() * 8
    }

    /// The width of `bytes` bytes, if it is 1, 2, 4 or 8.
    pub fn from_bytes(bytes: u32) -> Option<Width> {
        match bytes {
            1 => Some(Width::W8),
            2 => Some(Width::W16),
            4 => Some(Width::W32),
            8 => Some(Width::W64),
            _ => None,
        }
    }

    /// The Intel-syntax size keyword: `byte`, `word`, `dword` or `qword`.
    pub fn ptr_name(self) -> &'static str {
        ["byte", "word", "dword", "qword"][self as usize]
    }
}

/// A condition code, as used by `jcc`, `setcc` and `cmovcc`. Variant names
/// follow the canonical Intel mnemonic suffix; the common aliases are
/// associated constants (`Cond::Z == Cond::E`, `Cond::C == Cond::B`, ...).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum Cond {
    /// Overflow (OF = 1).
    O = 0,
    /// No overflow.
    No,
    /// Below, unsigned `<` (CF = 1).
    B,
    /// Above or equal, unsigned `>=`.
    Ae,
    /// Equal (ZF = 1).
    E,
    /// Not equal.
    Ne,
    /// Below or equal, unsigned `<=`.
    Be,
    /// Above, unsigned `>`.
    A,
    /// Sign (SF = 1).
    S,
    /// No sign.
    Ns,
    /// Parity even (PF = 1); after `ucomisd`, "unordered".
    P,
    /// Parity odd.
    Np,
    /// Less, signed `<`.
    L,
    /// Greater or equal, signed `>=`.
    Ge,
    /// Less or equal, signed `<=`.
    Le,
    /// Greater, signed `>`.
    G,
}

impl Cond {
    pub const C: Cond = Cond::B;
    pub const NAE: Cond = Cond::B;
    pub const NB: Cond = Cond::Ae;
    pub const NC: Cond = Cond::Ae;
    pub const Z: Cond = Cond::E;
    pub const NZ: Cond = Cond::Ne;
    pub const NA: Cond = Cond::Be;
    pub const NBE: Cond = Cond::A;
    pub const PE: Cond = Cond::P;
    pub const PO: Cond = Cond::Np;
    pub const NGE: Cond = Cond::L;
    pub const NL: Cond = Cond::Ge;
    pub const NG: Cond = Cond::Le;
    pub const NLE: Cond = Cond::G;

    /// All sixteen conditions in encoding order.
    pub const ALL: [Cond; 16] = [
        Cond::O,
        Cond::No,
        Cond::B,
        Cond::Ae,
        Cond::E,
        Cond::Ne,
        Cond::Be,
        Cond::A,
        Cond::S,
        Cond::Ns,
        Cond::P,
        Cond::Np,
        Cond::L,
        Cond::Ge,
        Cond::Le,
        Cond::G,
    ];

    /// The 4-bit condition number added to the `jcc`/`setcc`/`cmovcc` opcode.
    pub fn code(self) -> u8 {
        self as u8
    }

    /// The opposite condition (`E` ↔ `Ne`, `L` ↔ `Ge`, ...).
    pub fn negate(self) -> Cond {
        Cond::ALL[(self as usize) ^ 1]
    }

    /// The canonical mnemonic suffix, e.g. `"ae"` for `jae`.
    pub fn suffix(self) -> &'static str {
        ["o", "no", "b", "ae", "e", "ne", "be", "a", "s", "ns", "p", "np", "l", "ge", "le", "g"][self as usize]
    }

    /// Parses a mnemonic suffix, accepting every alias (`z`, `nae`, `c`,
    /// `pe`, ...). Case-insensitive.
    pub fn parse(suffix: &str) -> Option<Cond> {
        Some(match suffix.to_ascii_lowercase().as_str() {
            "o" => Cond::O,
            "no" => Cond::No,
            "b" | "c" | "nae" => Cond::B,
            "ae" | "nb" | "nc" => Cond::Ae,
            "e" | "z" => Cond::E,
            "ne" | "nz" => Cond::Ne,
            "be" | "na" => Cond::Be,
            "a" | "nbe" => Cond::A,
            "s" => Cond::S,
            "ns" => Cond::Ns,
            "p" | "pe" => Cond::P,
            "np" | "po" => Cond::Np,
            "l" | "nge" => Cond::L,
            "ge" | "nl" => Cond::Ge,
            "le" | "ng" => Cond::Le,
            "g" | "nle" => Cond::G,
            _ => return None,
        })
    }
}

/// A position in the code of one [`Assembler`](super::Assembler), created
/// unbound by [`Assembler::new_label`](super::Assembler::new_label) and bound
/// once with [`Assembler::bind`](super::Assembler::bind). Labels of different
/// assemblers must not be mixed.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Label(pub(crate) u32);

impl Label {
    /// Sequence number of the label in its assembler, starting at 0. Useful
    /// as a key in side tables.
    pub fn index(self) -> u32 {
        self.0
    }
}

/// A memory operand. The access size comes from the instruction's [`Width`]
/// (or is implied by the instruction, e.g. `movsd`).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Mem {
    /// `[base + index*scale + disp]`. Either register may be absent; with
    /// neither, the operand is the absolute address `disp` (not
    /// position-independent). `scale` must be 1, 2, 4 or 8, and `rsp` cannot
    /// be an index.
    Sib { base: Option<Reg>, index: Option<(Reg, u8)>, disp: i32 },
    /// `[rip + sym + addend]`: RIP-relative to a symbol (an atom, atom label
    /// or import). Emits a [`RelocKind::X86Pc32`](crate::RelocKind::X86Pc32)
    /// whose addend also accounts for the 4-byte field and any trailing
    /// immediate.
    RipSym { sym: String, addend: i64 },
    /// `[rip + sym@GOTPCREL]`: the GOT slot holding the address of `sym`.
    /// Emits a [`RelocKind::X86GotPc32`](crate::RelocKind::X86GotPc32).
    RipGot { sym: String },
    /// `[rip + label + addend]`: RIP-relative to a label of the same
    /// assembler, resolved by [`Assembler::finish`](super::Assembler::finish)
    /// without a relocation.
    RipLabel { label: Label, addend: i32 },
}

impl Mem {
    /// `[base + disp]`.
    pub fn base(base: Reg, disp: i32) -> Mem {
        Mem::Sib { base: Some(base), index: None, disp }
    }

    /// `[base + index*scale + disp]`.
    pub fn index(base: Reg, index: Reg, scale: u8, disp: i32) -> Mem {
        Mem::Sib { base: Some(base), index: Some((index, scale)), disp }
    }

    /// `[index*scale + disp]` without a base register (always a 32-bit
    /// displacement).
    pub fn index_only(index: Reg, scale: u8, disp: i32) -> Mem {
        Mem::Sib { base: None, index: Some((index, scale)), disp }
    }

    /// The absolute address `[disp]`. Not position-independent.
    pub fn abs(disp: i32) -> Mem {
        Mem::Sib { base: None, index: None, disp }
    }

    /// `[rip + sym + addend]`.
    pub fn rip(sym: impl Into<String>, addend: i64) -> Mem {
        Mem::RipSym { sym: sym.into(), addend }
    }

    /// `[rip + sym@GOTPCREL]`, the GOT slot of `sym` (imported functions and
    /// data).
    pub fn got(sym: impl Into<String>) -> Mem {
        Mem::RipGot { sym: sym.into() }
    }

    /// `[rip + label]`.
    pub fn label(label: Label) -> Mem {
        Mem::RipLabel { label, addend: 0 }
    }

    /// `[rip + label + addend]`.
    pub fn label_plus(label: Label, addend: i32) -> Mem {
        Mem::RipLabel { label, addend }
    }

    /// The same operand moved `delta` bytes further, e.g. to reach a record
    /// field.
    ///
    /// # Panics
    ///
    /// If the displacement overflows 32 bits, or on [`Mem::RipGot`] (a GOT
    /// slot has no fields).
    pub fn offset(self, delta: i32) -> Mem {
        match self {
            Mem::Sib { base, index, disp } => {
                Mem::Sib { base, index, disp: disp.checked_add(delta).expect("displacement overflow") }
            }
            Mem::RipSym { sym, addend } => Mem::RipSym { sym, addend: addend + delta as i64 },
            Mem::RipLabel { label, addend } => {
                Mem::RipLabel { label, addend: addend.checked_add(delta).expect("displacement overflow") }
            }
            Mem::RipGot { .. } => panic!("cannot offset a GOT slot operand"),
        }
    }
}

impl fmt::Display for Mem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fn signed(f: &mut fmt::Formatter<'_>, first: bool, v: i64) -> fmt::Result {
            match (first, v < 0) {
                (true, _) => write!(f, "{v}"),
                (false, true) => write!(f, " - {}", v.unsigned_abs()),
                (false, false) => write!(f, " + {v}"),
            }
        }
        f.write_str("[")?;
        match self {
            Mem::Sib { base, index, disp } => {
                let mut first = true;
                if let Some(b) = base {
                    f.write_str(b.name(Width::W64))?;
                    first = false;
                }
                if let Some((i, s)) = index {
                    if !first {
                        f.write_str(" + ")?;
                    }
                    write!(f, "{}*{s}", i.name(Width::W64))?;
                    first = false;
                }
                if *disp != 0 || first {
                    signed(f, first, *disp as i64)?;
                }
            }
            Mem::RipSym { sym, addend } => {
                write!(f, "rip + {sym}")?;
                if *addend != 0 {
                    signed(f, false, *addend)?;
                }
            }
            Mem::RipGot { sym } => write!(f, "rip + {sym}@GOTPCREL")?,
            Mem::RipLabel { label, addend } => {
                write!(f, "rip + L{}", label.0)?;
                if *addend != 0 {
                    signed(f, false, *addend as i64)?;
                }
            }
        }
        f.write_str("]")
    }
}

/// An instruction operand. Instructions take `impl Into<Operand>` where more
/// than one kind is allowed, so registers, memory operands and integers can
/// be passed directly. Integer literals default to `i32`; immediates wider
/// than 32 bits are passed as `i64`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Operand {
    Reg(Reg),
    Xmm(Xmm),
    Mem(Mem),
    Imm(i64),
}

impl From<Reg> for Operand {
    fn from(r: Reg) -> Operand {
        Operand::Reg(r)
    }
}

impl From<Xmm> for Operand {
    fn from(x: Xmm) -> Operand {
        Operand::Xmm(x)
    }
}

impl From<Mem> for Operand {
    fn from(m: Mem) -> Operand {
        Operand::Mem(m)
    }
}

impl From<&Mem> for Operand {
    fn from(m: &Mem) -> Operand {
        Operand::Mem(m.clone())
    }
}

impl From<i32> for Operand {
    fn from(v: i32) -> Operand {
        Operand::Imm(v as i64)
    }
}

impl From<i64> for Operand {
    fn from(v: i64) -> Operand {
        Operand::Imm(v)
    }
}

impl From<u32> for Operand {
    fn from(v: u32) -> Operand {
        Operand::Imm(v as i64)
    }
}

impl From<u8> for Operand {
    fn from(v: u8) -> Operand {
        Operand::Imm(v as i64)
    }
}

impl Operand {
    /// Operand class for error messages.
    pub(crate) fn kind_name(&self) -> &'static str {
        match self {
            Operand::Reg(_) => "register",
            Operand::Xmm(_) => "xmm",
            Operand::Mem(_) => "memory",
            Operand::Imm(_) => "immediate",
        }
    }
}

/// The destination of `call`, `jmp` and `jcc`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Target {
    /// A label of the same assembler (`call`: rel32; `jmp`/`jcc`: rel8 or
    /// rel32, chosen by branch relaxation).
    Label(Label),
    /// A named symbol, reached through a rel32 field with a
    /// [`RelocKind::X86Pc32`](crate::RelocKind::X86Pc32) relocation.
    Sym(String),
    /// Indirect through a 64-bit register or memory operand (`call`, `jmp`
    /// only), e.g. `Mem::got("_write")`.
    Indirect(Operand),
}

impl From<Label> for Target {
    fn from(l: Label) -> Target {
        Target::Label(l)
    }
}

impl From<&str> for Target {
    fn from(s: &str) -> Target {
        Target::Sym(s.to_string())
    }
}

impl From<String> for Target {
    fn from(s: String) -> Target {
        Target::Sym(s)
    }
}

impl From<&String> for Target {
    fn from(s: &String) -> Target {
        Target::Sym(s.clone())
    }
}

impl From<Reg> for Target {
    fn from(r: Reg) -> Target {
        Target::Indirect(Operand::Reg(r))
    }
}

impl From<Mem> for Target {
    fn from(m: Mem) -> Target {
        Target::Indirect(Operand::Mem(m))
    }
}

impl From<&Mem> for Target {
    fn from(m: &Mem) -> Target {
        Target::Indirect(Operand::Mem(m.clone()))
    }
}

/// The eight classic two-operand ALU operations, in opcode order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum AluOp {
    Add = 0,
    Or,
    Adc,
    Sbb,
    And,
    Sub,
    Xor,
    Cmp,
}

/// Rotates and shifts (group 2), with their ModRM opcode extension.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ShiftOp {
    Rol = 0,
    Ror = 1,
    Rcl = 2,
    Rcr = 3,
    /// Also known as `sal`.
    Shl = 4,
    Shr = 5,
    Sar = 7,
}

/// One-operand integer instructions.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum UnaryOp {
    Not,
    Neg,
    /// Unsigned `rdx:rax = rax * src`.
    Mul,
    /// Signed `rdx:rax = rax * src` (one-operand form).
    Imul,
    /// Unsigned divide of `rdx:rax` by the operand.
    Div,
    /// Signed divide of `rdx:rax` by the operand.
    Idiv,
    Inc,
    Dec,
}

/// Bit test instructions.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BitOp {
    /// `bt`: CF = bit.
    Bt,
    /// `bts`: CF = bit, then set it.
    Bts,
    /// `btr`: CF = bit, then clear it.
    Btr,
    /// `btc`: CF = bit, then complement it.
    Btc,
}

/// Scalar floating-point precision.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Fp {
    /// `float` / Pascal `Single` (`ss` instructions).
    F32,
    /// `double` / Pascal `Real` and `Double` (`sd` instructions).
    F64,
}

/// Scalar SSE arithmetic.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum FpOp {
    Add,
    Sub,
    Mul,
    Div,
    Sqrt,
    Min,
    Max,
}

/// Packed bitwise SSE operations, used on scalars for `abs` and negation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum FpLogic {
    And,
    AndNot,
    Or,
    Xor,
}

/// Rounding-mode immediates for `roundsd` / `roundss`. Add
/// [`round::NO_INEXACT`] to suppress the precision exception.
pub mod round {
    /// Round to nearest, ties to even.
    pub const NEAREST: u8 = 0;
    /// Round toward negative infinity (`Floor`).
    pub const DOWN: u8 = 1;
    /// Round toward positive infinity (`Ceil`).
    pub const UP: u8 = 2;
    /// Round toward zero (Pascal `Trunc` / `Int`).
    pub const TRUNCATE: u8 = 3;
    /// Use the rounding mode in MXCSR.
    pub const CURRENT: u8 = 4;
    /// Do not raise the precision (inexact) exception.
    pub const NO_INEXACT: u8 = 8;
}
