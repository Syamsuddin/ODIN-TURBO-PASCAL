// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Operand types of the AArch64 encoder: registers, condition codes, shifts
//! and extends, labels, branch targets and memory operands.

use std::fmt;

/// Internal number of the zero register (`xzr`/`wzr`).
const ZR: u8 = 31;
/// Internal number of the stack pointer (`sp`/`wsp`). Both encode as 31;
/// keeping them apart lets every instruction check which one its field
/// means, so `sp` can never silently become `xzr` or the other way round.
const SPN: u8 = 32;

/// A general-purpose register at a width: `x0`–`x30` / `w0`–`w30`, the stack
/// pointer `sp`/`wsp`, or the zero register `xzr`/`wzr`.
///
/// The width is part of the register, as in assembly syntax: [`regs::X0`] is
/// the 64-bit view and [`regs::W0`] the 32-bit view of the same register.
/// Writing a W register clears the upper 32 bits.
///
/// In the instruction set, number 31 means `sp` in some fields and `xzr` in
/// others. A `Reg` knows which of the two it is, and every instruction
/// checks it against the field it goes into: `add(X0, SP, X1)` picks the
/// extended-register form (whose source field means `sp`), and passing
/// `XZR` where only `sp` makes sense is an [`EncodeError`](super::EncodeError),
/// never a silent change of meaning.
///
/// X18 is the platform register on Apple systems and must not be used;
/// X16/X17 are the encoder's scratch registers (see the [module
/// docs](super)).
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Reg {
    /// 0–30, [`ZR`] or [`SPN`].
    id: u8,
    x: bool,
}

impl Reg {
    /// `xN` (64-bit) for `n` in 0..=30.
    ///
    /// # Panics
    ///
    /// If `n > 30`; use [`regs::SP`] or [`regs::XZR`] for number 31.
    pub const fn x(n: u8) -> Reg {
        assert!(n <= 30, "general-purpose registers are x0 to x30");
        Reg { id: n, x: true }
    }

    /// `wN` (32-bit) for `n` in 0..=30.
    ///
    /// # Panics
    ///
    /// If `n > 30`; use [`regs::WSP`] or [`regs::WZR`] for number 31.
    pub const fn w(n: u8) -> Reg {
        assert!(n <= 30, "general-purpose registers are w0 to w30");
        Reg { id: n, x: false }
    }

    /// The 64-bit view of the same register (`w3` → `x3`, `wsp` → `sp`).
    pub const fn to_x(self) -> Reg {
        Reg { id: self.id, x: true }
    }

    /// The 32-bit view of the same register (`x3` → `w3`, `sp` → `wsp`).
    pub const fn to_w(self) -> Reg {
        Reg { id: self.id, x: false }
    }

    /// The same register at the width of `other`.
    pub const fn with_width_of(self, other: Reg) -> Reg {
        Reg { id: self.id, x: other.x }
    }

    /// Whether this is a 64-bit (X) view.
    pub const fn is_64(self) -> bool {
        self.x
    }

    /// Size in bits: 32 or 64.
    pub const fn bits(self) -> u32 {
        if self.x { 64 } else { 32 }
    }

    /// Whether this is `sp` or `wsp`.
    pub const fn is_sp(self) -> bool {
        self.id == SPN
    }

    /// Whether this is `xzr` or `wzr`.
    pub const fn is_zr(self) -> bool {
        self.id == ZR
    }

    /// The register number as encoded: 0–30, or 31 for both `sp` and `xzr`.
    pub const fn index(self) -> u8 {
        if self.id == SPN { 31 } else { self.id }
    }

    /// Whether `self` and `other` are the same architectural register,
    /// whatever their widths (`w5` and `x5`; `sp` and `wsp`).
    pub const fn same(self, other: Reg) -> bool {
        self.id == other.id
    }

    /// Parses a register name (case-insensitive): `x0`–`x30`, `w0`–`w30`,
    /// `sp`, `wsp`, `xzr`, `wzr`, and the aliases `fp` (x29) and `lr` (x30)
    /// that clang accepts.
    pub fn parse(name: &str) -> Option<Reg> {
        let lower = name.to_ascii_lowercase();
        let fixed = match lower.as_str() {
            "sp" => Some(regs::SP),
            "wsp" => Some(regs::WSP),
            "xzr" => Some(regs::XZR),
            "wzr" => Some(regs::WZR),
            "fp" => Some(regs::FP),
            "lr" => Some(regs::LR),
            _ => None,
        };
        if fixed.is_some() {
            return fixed;
        }
        let (x, digits) = match lower.as_bytes().first()? {
            b'x' => (true, &lower[1..]),
            b'w' => (false, &lower[1..]),
            _ => return None,
        };
        let n = small_number(digits)?;
        (n <= 30).then_some(Reg { id: n, x })
    }
}

/// Parses `0`..`99` without leading zeros (so `x01` is not a register).
fn small_number(digits: &str) -> Option<u8> {
    if digits.is_empty() || digits.len() > 2 || (digits.len() > 1 && digits.starts_with('0')) {
        return None;
    }
    digits.parse().ok()
}

impl fmt::Display for Reg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match (self.id, self.x) {
            (SPN, true) => f.write_str("sp"),
            (SPN, false) => f.write_str("wsp"),
            (ZR, true) => f.write_str("xzr"),
            (ZR, false) => f.write_str("wzr"),
            (n, true) => write!(f, "x{n}"),
            (n, false) => write!(f, "w{n}"),
        }
    }
}

impl fmt::Debug for Reg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(self, f)
    }
}

/// Precision of a scalar floating-point register view.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Fp {
    /// `s0`–`s31`: 32-bit `float`, Pascal `Single`.
    S,
    /// `d0`–`d31`: 64-bit `double`, Pascal `Real` and `Double`.
    D,
}

impl Fp {
    /// Size in bytes: 4 or 8.
    pub fn bytes(self) -> u32 {
        match self {
            Fp::S => 4,
            Fp::D => 8,
        }
    }

    /// The `ftype` field of floating-point instructions.
    pub(crate) fn ftype(self) -> u32 {
        match self {
            Fp::S => 0,
            Fp::D => 1,
        }
    }
}

/// A scalar view of a SIMD/FP register: `s0`–`s31` or `d0`–`d31` (the low
/// 32 or 64 bits of `v0`–`v31`). Writing one clears the rest of the vector
/// register.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct VReg {
    id: u8,
    fp: Fp,
}

impl VReg {
    /// `sN` for `n` in 0..=31.
    ///
    /// # Panics
    ///
    /// If `n > 31`.
    pub const fn s(n: u8) -> VReg {
        assert!(n <= 31, "SIMD/FP registers are v0 to v31");
        VReg { id: n, fp: Fp::S }
    }

    /// `dN` for `n` in 0..=31.
    ///
    /// # Panics
    ///
    /// If `n > 31`.
    pub const fn d(n: u8) -> VReg {
        assert!(n <= 31, "SIMD/FP registers are v0 to v31");
        VReg { id: n, fp: Fp::D }
    }

    /// The register `n` at precision `fp`.
    ///
    /// # Panics
    ///
    /// If `n > 31`.
    pub const fn new(fp: Fp, n: u8) -> VReg {
        assert!(n <= 31, "SIMD/FP registers are v0 to v31");
        VReg { id: n, fp }
    }

    /// The single-precision view of the same register.
    pub const fn to_s(self) -> VReg {
        VReg { id: self.id, fp: Fp::S }
    }

    /// The double-precision view of the same register.
    pub const fn to_d(self) -> VReg {
        VReg { id: self.id, fp: Fp::D }
    }

    /// The precision of this view.
    pub const fn fp(self) -> Fp {
        self.fp
    }

    /// Register number, 0 to 31.
    pub const fn index(self) -> u8 {
        self.id
    }

    /// Parses `s0`–`s31` or `d0`–`d31` (case-insensitive).
    pub fn parse(name: &str) -> Option<VReg> {
        let lower = name.to_ascii_lowercase();
        let fp = match lower.as_bytes().first()? {
            b's' => Fp::S,
            b'd' => Fp::D,
            _ => return None,
        };
        let n = small_number(&lower[1..])?;
        (n <= 31).then_some(VReg { id: n, fp })
    }
}

impl fmt::Display for VReg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let p = if self.fp == Fp::S { 's' } else { 'd' };
        write!(f, "{p}{}", self.id)
    }
}

impl fmt::Debug for VReg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(self, f)
    }
}

/// Register constants: `X0`..`X30`, `W0`..`W30`, `SP`, `WSP`, `XZR`, `WZR`,
/// the aliases `FP` (x29), `LR` (x30), `IP0` (x16) and `IP1` (x17), and
/// `S0`..`S31`, `D0`..`D31`. Meant for a glob import:
/// `use odin_asm::aarch64::regs::*;`.
pub mod regs {
    use super::{Fp, Reg, SPN, VReg, ZR};

    macro_rules! gp {
        ($($x:ident $w:ident $n:literal),* $(,)?) => {
            $(
                pub const $x: Reg = Reg { id: $n, x: true };
                pub const $w: Reg = Reg { id: $n, x: false };
            )*
        };
    }

    macro_rules! fp {
        ($($s:ident $d:ident $n:literal),* $(,)?) => {
            $(
                pub const $s: VReg = VReg { id: $n, fp: Fp::S };
                pub const $d: VReg = VReg { id: $n, fp: Fp::D };
            )*
        };
    }

    gp!(
        X0 W0 0, X1 W1 1, X2 W2 2, X3 W3 3, X4 W4 4, X5 W5 5, X6 W6 6, X7 W7 7,
        X8 W8 8, X9 W9 9, X10 W10 10, X11 W11 11, X12 W12 12, X13 W13 13, X14 W14 14, X15 W15 15,
        X16 W16 16, X17 W17 17, X18 W18 18, X19 W19 19, X20 W20 20, X21 W21 21, X22 W22 22,
        X23 W23 23, X24 W24 24, X25 W25 25, X26 W26 26, X27 W27 27, X28 W28 28, X29 W29 29,
        X30 W30 30,
    );

    fp!(
        S0 D0 0, S1 D1 1, S2 D2 2, S3 D3 3, S4 D4 4, S5 D5 5, S6 D6 6, S7 D7 7,
        S8 D8 8, S9 D9 9, S10 D10 10, S11 D11 11, S12 D12 12, S13 D13 13, S14 D14 14, S15 D15 15,
        S16 D16 16, S17 D17 17, S18 D18 18, S19 D19 19, S20 D20 20, S21 D21 21, S22 D22 22,
        S23 D23 23, S24 D24 24, S25 D25 25, S26 D26 26, S27 D27 27, S28 D28 28, S29 D29 29,
        S30 D30 30, S31 D31 31,
    );

    /// The stack pointer.
    pub const SP: Reg = Reg { id: SPN, x: true };
    /// The 32-bit view of the stack pointer.
    pub const WSP: Reg = Reg { id: SPN, x: false };
    /// The 64-bit zero register: reads as 0, writes are discarded.
    pub const XZR: Reg = Reg { id: ZR, x: true };
    /// The 32-bit zero register.
    pub const WZR: Reg = Reg { id: ZR, x: false };
    /// Frame pointer, x29.
    pub const FP: Reg = X29;
    /// Link register, x30.
    pub const LR: Reg = X30;
    /// Intra-procedure-call scratch register 0, x16: the encoder's scratch.
    pub const IP0: Reg = X16;
    /// Intra-procedure-call scratch register 1, x17: the encoder's second
    /// scratch.
    pub const IP1: Reg = X17;
}

/// Either kind of register, for instructions that take both (`ldr`, `str`,
/// `ldp`, `stp`, `fmov`). Built with `.into()` from [`Reg`] or [`VReg`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum AnyReg {
    Gp(Reg),
    Fp(VReg),
}

impl From<Reg> for AnyReg {
    fn from(r: Reg) -> AnyReg {
        AnyReg::Gp(r)
    }
}

impl From<VReg> for AnyReg {
    fn from(v: VReg) -> AnyReg {
        AnyReg::Fp(v)
    }
}

impl fmt::Display for AnyReg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AnyReg::Gp(r) => r.fmt(f),
            AnyReg::Fp(v) => v.fmt(f),
        }
    }
}

/// A condition code, as used by `b.cond`, `csel`, `ccmp` and friends.
///
/// After `cmp a, b`: `Eq`/`Ne`, signed `Lt`/`Le`/`Gt`/`Ge`, unsigned
/// `Lo`/`Ls`/`Hi`/`Hs`. After `fcmp`, an unordered result (a NaN operand)
/// sets C and V, so `Lo`/`Mi` ("less than") and `Ls` ("less or equal") are
/// false for NaNs, while `Lt`/`Le` are true for them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum Cond {
    /// Equal (Z = 1).
    Eq = 0,
    /// Not equal.
    Ne,
    /// Unsigned higher or same (C = 1), also called `cs`.
    Hs,
    /// Unsigned lower (C = 0), also called `cc`.
    Lo,
    /// Negative (N = 1).
    Mi,
    /// Positive or zero.
    Pl,
    /// Overflow (V = 1).
    Vs,
    /// No overflow.
    Vc,
    /// Unsigned higher.
    Hi,
    /// Unsigned lower or same.
    Ls,
    /// Signed greater or equal.
    Ge,
    /// Signed less than.
    Lt,
    /// Signed greater than.
    Gt,
    /// Signed less or equal.
    Le,
    /// Always.
    Al,
    /// Also always (an encoding of "always"; not "never").
    Nv,
}

impl Cond {
    /// Carry set: [`Cond::Hs`].
    pub const CS: Cond = Cond::Hs;
    /// Carry clear: [`Cond::Lo`].
    pub const CC: Cond = Cond::Lo;

    /// All sixteen conditions in encoding order.
    pub const ALL: [Cond; 16] = [
        Cond::Eq,
        Cond::Ne,
        Cond::Hs,
        Cond::Lo,
        Cond::Mi,
        Cond::Pl,
        Cond::Vs,
        Cond::Vc,
        Cond::Hi,
        Cond::Ls,
        Cond::Ge,
        Cond::Lt,
        Cond::Gt,
        Cond::Le,
        Cond::Al,
        Cond::Nv,
    ];

    /// The 4-bit condition field.
    pub fn code(self) -> u32 {
        self as u32
    }

    /// The opposite condition (`Eq` ↔ `Ne`, `Lt` ↔ `Ge`, ...). `Al` and
    /// `Nv` both mean "always" and have no opposite; they map to each other
    /// like the encoding does, so do not branch on an inverted `Al`.
    pub fn invert(self) -> Cond {
        Cond::ALL[(self as usize) ^ 1]
    }

    /// The mnemonic suffix, e.g. `"hs"` for `b.hs`.
    pub fn suffix(self) -> &'static str {
        ["eq", "ne", "hs", "lo", "mi", "pl", "vs", "vc", "hi", "ls", "ge", "lt", "gt", "le", "al", "nv"][self as usize]
    }

    /// Parses a condition name, accepting `cs` and `cc`. Case-insensitive.
    pub fn parse(name: &str) -> Option<Cond> {
        let lower = name.to_ascii_lowercase();
        match lower.as_str() {
            "cs" => Some(Cond::Hs),
            "cc" => Some(Cond::Lo),
            _ => Cond::ALL.iter().copied().find(|c| c.suffix() == lower),
        }
    }
}

/// Shift applied to the last register operand of data-processing
/// instructions. `Ror` is only valid for logical instructions.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Shift {
    Lsl = 0,
    Lsr = 1,
    Asr = 2,
    Ror = 3,
}

impl Shift {
    pub fn name(self) -> &'static str {
        ["lsl", "lsr", "asr", "ror"][self as usize]
    }
}

/// Extension of a register operand: take its low byte, halfword, word or
/// doubleword, zero- (`Uxt*`) or sign-extended (`Sxt*`), then shift it left.
/// The source register is a W register except for `Uxtx`/`Sxtx`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Extend {
    Uxtb = 0,
    Uxth = 1,
    Uxtw = 2,
    Uxtx = 3,
    Sxtb = 4,
    Sxth = 5,
    Sxtw = 6,
    Sxtx = 7,
}

impl Extend {
    /// The 3-bit `option` field.
    pub fn code(self) -> u32 {
        self as u32
    }

    pub fn name(self) -> &'static str {
        ["uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx"][self as usize]
    }

    /// Whether the extended register is an X register (`Uxtx`, `Sxtx`).
    pub fn takes_x(self) -> bool {
        matches!(self, Extend::Uxtx | Extend::Sxtx)
    }

    /// Parses an extend name (case-insensitive).
    pub fn parse(name: &str) -> Option<Extend> {
        const ALL: [Extend; 8] = [
            Extend::Uxtb,
            Extend::Uxth,
            Extend::Uxtw,
            Extend::Uxtx,
            Extend::Sxtb,
            Extend::Sxth,
            Extend::Sxtw,
            Extend::Sxtx,
        ];
        let lower = name.to_ascii_lowercase();
        ALL.iter().copied().find(|e| e.name() == lower)
    }
}

/// The flexible second source operand of data-processing instructions
/// (`add`, `sub`, `and`, `cmp`, `mov`, ...): an immediate, a register, a
/// shifted register or an extended register.
///
/// Built with `.into()` from integers and [`Reg`], or with the shift and
/// extend methods of [`Reg`]: `X2.lsl(3)`, `W2.sxtw(2)`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Op2 {
    /// An immediate. Its encoding depends on the instruction: 12 bits with
    /// optional `lsl #12` for `add`/`sub` (negative values flip the
    /// operation), a bitmask pattern for logical instructions.
    Imm(i64),
    Reg(Reg),
    /// `reg, shift #amount`.
    Shifted(Reg, Shift, u8),
    /// `reg, extend #amount` (amount 0–4).
    Extended(Reg, Extend, u8),
}

impl From<Reg> for Op2 {
    fn from(r: Reg) -> Op2 {
        Op2::Reg(r)
    }
}

impl From<i32> for Op2 {
    fn from(v: i32) -> Op2 {
        Op2::Imm(v as i64)
    }
}

impl From<i64> for Op2 {
    fn from(v: i64) -> Op2 {
        Op2::Imm(v)
    }
}

impl From<u32> for Op2 {
    fn from(v: u32) -> Op2 {
        Op2::Imm(v as i64)
    }
}

/// Bit patterns such as `0xffff_0000_ffff_0000` for logical immediates.
impl From<u64> for Op2 {
    fn from(v: u64) -> Op2 {
        Op2::Imm(v as i64)
    }
}

impl Reg {
    /// `self, lsl #amount` as an [`Op2`].
    pub fn lsl(self, amount: u8) -> Op2 {
        Op2::Shifted(self, Shift::Lsl, amount)
    }

    /// `self, lsr #amount` as an [`Op2`].
    pub fn lsr(self, amount: u8) -> Op2 {
        Op2::Shifted(self, Shift::Lsr, amount)
    }

    /// `self, asr #amount` as an [`Op2`].
    pub fn asr(self, amount: u8) -> Op2 {
        Op2::Shifted(self, Shift::Asr, amount)
    }

    /// `self, ror #amount` as an [`Op2`] (logical instructions only).
    pub fn ror(self, amount: u8) -> Op2 {
        Op2::Shifted(self, Shift::Ror, amount)
    }

    /// `self, extend #amount` as an [`Op2`].
    pub fn ext(self, extend: Extend, amount: u8) -> Op2 {
        Op2::Extended(self, extend, amount)
    }

    /// `self, uxtw #amount`: a W register zero-extended to 64 bits.
    pub fn uxtw(self, amount: u8) -> Op2 {
        Op2::Extended(self, Extend::Uxtw, amount)
    }

    /// `self, sxtw #amount`: a W register sign-extended to 64 bits.
    pub fn sxtw(self, amount: u8) -> Op2 {
        Op2::Extended(self, Extend::Sxtw, amount)
    }
}

/// A position in the code of one [`Assembler`](super::Assembler), created
/// unbound by [`Assembler::new_label`](super::Assembler::new_label) and bound
/// once with [`Assembler::bind`](super::Assembler::bind). Labels of different
/// assemblers must not be mixed.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Label(pub(crate) u32);

impl Label {
    /// Sequence number of the label in its assembler, starting at 0.
    pub fn index(self) -> u32 {
        self.0
    }
}

/// The destination of `b` and `bl`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Target {
    /// A label of the same assembler, resolved by
    /// [`finish`](super::Assembler::finish).
    Label(Label),
    /// A named symbol, reached through an
    /// [`Arm64Branch26`](crate::RelocKind::Arm64Branch26) relocation (±128
    /// MiB). Imported functions cannot be reached this way; call them with
    /// [`call_got`](super::Assembler::call_got).
    Sym(String),
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

/// How the index register of a register-offset address is extended:
/// `[base, index{, lsl|uxtw|sxtw|sxtx {#amount}}]`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum IndexExt {
    /// X index, `lsl` (no extension).
    Lsl,
    /// W index, zero-extended.
    Uxtw,
    /// W index, sign-extended.
    Sxtw,
    /// X index, `sxtx` (same value as `Lsl`, a different spelling).
    Sxtx,
}

impl IndexExt {
    /// The 3-bit `option` field.
    pub(crate) fn code(self) -> u32 {
        match self {
            IndexExt::Uxtw => 0b010,
            IndexExt::Lsl => 0b011,
            IndexExt::Sxtw => 0b110,
            IndexExt::Sxtx => 0b111,
        }
    }
}

/// A memory operand.
///
/// Only [`Mem::Offset`], [`Mem::Sym`] and (for `ldp`/`stp`) out-of-range
/// offsets may expand into several instructions; see the [module
/// docs](super) for the scratch registers they use.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Mem {
    /// `[base, #offset]`. Loads and stores pick the scaled unsigned 12-bit
    /// form when the offset is a non-negative multiple of the access size
    /// that fits, else the unscaled signed 9-bit form (`ldur`), else they
    /// put the offset in a scratch register and use the register-offset
    /// form. `base` may be `sp` but not `xzr`.
    Offset { base: Reg, offset: i64 },
    /// `[base, #offset]!`: add `offset` (signed 9 bits; 7 bits scaled for
    /// pairs) to `base`, then access.
    PreIndex { base: Reg, offset: i64 },
    /// `[base], #offset`: access, then add `offset` to `base`.
    PostIndex { base: Reg, offset: i64 },
    /// `[base, index{, ext {#amount}}]`. `shift` selects the scaled form:
    /// the index is shifted left by log2 of the access size (written
    /// `lsl #3` for an 8-byte access, `lsl #0` for a byte access).
    Index { base: Reg, index: Reg, ext: IndexExt, shift: bool },
    /// `[base, sym@PAGEOFF]` (Darwin) / `[base, :lo12:sym]` (ELF): the low
    /// 12 bits of `sym + addend`, after an `adrp` of the same symbol. Emits
    /// an [`Arm64PageOff12`](crate::RelocKind::Arm64PageOff12) scaled by the
    /// access size, so `sym + addend` must be aligned to it.
    PageOff { base: Reg, sym: String, addend: i64 },
    /// `[base, sym@GOTPAGEOFF]` / `[base, :got_lo12:sym]`: the GOT slot of
    /// `sym`, after `adrp base, sym@GOTPAGE`. 64-bit `ldr` only.
    GotPageOff { base: Reg, sym: String },
    /// The data at `sym + addend`, anywhere in the program: expands to
    /// `adrp x16, sym@PAGE` and an access through `[x16, sym@PAGEOFF]`
    /// (x17 instead of x16 when x16 is the register being stored). Like
    /// [`Mem::PageOff`], `sym + addend` must be aligned to the access size.
    Sym { sym: String, addend: i64 },
    /// A PC-relative literal: `ldr reg, label` (±1 MiB). Loads only, and
    /// not `ldrb`/`ldrh`/`ldrsb`/`ldrsh`.
    Label { label: Label, addend: i32 },
}

impl Mem {
    /// `[base, #offset]`.
    pub fn base(base: Reg, offset: i64) -> Mem {
        Mem::Offset { base, offset }
    }

    /// `[base, #offset]!` (pre-index).
    pub fn pre(base: Reg, offset: i64) -> Mem {
        Mem::PreIndex { base, offset }
    }

    /// `[base], #offset` (post-index).
    pub fn post(base: Reg, offset: i64) -> Mem {
        Mem::PostIndex { base, offset }
    }

    /// `[base, index]` with an X index.
    pub fn index(base: Reg, index: Reg) -> Mem {
        Mem::Index { base, index, ext: IndexExt::Lsl, shift: false }
    }

    /// `[base, index, lsl #log2(size)]`: an X index counting elements of the
    /// access size.
    pub fn index_scaled(base: Reg, index: Reg) -> Mem {
        Mem::Index { base, index, ext: IndexExt::Lsl, shift: true }
    }

    /// `[base, index, ext {#log2(size)}]`.
    pub fn index_ext(base: Reg, index: Reg, ext: IndexExt, shift: bool) -> Mem {
        Mem::Index { base, index, ext, shift }
    }

    /// `[base, sym@PAGEOFF + addend]`.
    pub fn page_off(base: Reg, sym: impl Into<String>, addend: i64) -> Mem {
        Mem::PageOff { base, sym: sym.into(), addend }
    }

    /// `[base, sym@GOTPAGEOFF]`.
    pub fn got_page_off(base: Reg, sym: impl Into<String>) -> Mem {
        Mem::GotPageOff { base, sym: sym.into() }
    }

    /// The data at `sym + addend` (expands through x16).
    pub fn sym(sym: impl Into<String>, addend: i64) -> Mem {
        Mem::Sym { sym: sym.into(), addend }
    }

    /// The literal at `label`.
    pub fn label(label: Label) -> Mem {
        Mem::Label { label, addend: 0 }
    }

    /// The literal at `label + addend`.
    pub fn label_plus(label: Label, addend: i32) -> Mem {
        Mem::Label { label, addend }
    }

    /// The same operand moved `delta` bytes further, e.g. to reach a record
    /// field.
    ///
    /// # Panics
    ///
    /// On [`Mem::Index`], [`Mem::GotPageOff`], pre/post-index operands (none
    /// of them have a displacement to move), or on overflow.
    pub fn offset(self, delta: i64) -> Mem {
        match self {
            Mem::Offset { base, offset } => {
                Mem::Offset { base, offset: offset.checked_add(delta).expect("offset overflow") }
            }
            Mem::PageOff { base, sym, addend } => {
                Mem::PageOff { base, sym, addend: addend.checked_add(delta).expect("offset overflow") }
            }
            Mem::Sym { sym, addend } => Mem::Sym { sym, addend: addend.checked_add(delta).expect("offset overflow") },
            Mem::Label { label, addend } => Mem::Label {
                label,
                addend: i32::try_from(delta).ok().and_then(|d| addend.checked_add(d)).expect("offset overflow"),
            },
            other => panic!("cannot offset {other}"),
        }
    }
}

impl fmt::Display for Mem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fn plus(v: i64) -> String {
            match v {
                0 => String::new(),
                v if v < 0 => format!("-{}", v.unsigned_abs()),
                v => format!("+{v}"),
            }
        }
        match self {
            Mem::Offset { base, offset: 0 } => write!(f, "[{base}]"),
            Mem::Offset { base, offset } => write!(f, "[{base}, #{offset}]"),
            Mem::PreIndex { base, offset } => write!(f, "[{base}, #{offset}]!"),
            Mem::PostIndex { base, offset } => write!(f, "[{base}], #{offset}"),
            Mem::Index { base, index, ext, shift } => {
                let name = match ext {
                    IndexExt::Lsl => "lsl",
                    IndexExt::Uxtw => "uxtw",
                    IndexExt::Sxtw => "sxtw",
                    IndexExt::Sxtx => "sxtx",
                };
                match (ext, shift) {
                    (IndexExt::Lsl, false) => write!(f, "[{base}, {index}]"),
                    (_, false) => write!(f, "[{base}, {index}, {name}]"),
                    (_, true) => write!(f, "[{base}, {index}, {name} #scale]"),
                }
            }
            Mem::PageOff { base, sym, addend } => write!(f, "[{base}, {sym}@PAGEOFF{}]", plus(*addend)),
            Mem::GotPageOff { base, sym } => write!(f, "[{base}, {sym}@GOTPAGEOFF]"),
            Mem::Sym { sym, addend } => write!(f, "{sym}{}", plus(*addend)),
            Mem::Label { label, addend } => write!(f, "L{}{}", label.0, plus(*addend as i64)),
        }
    }
}

/// System registers reachable with `mrs`/`msr`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SysReg {
    /// Condition flags N, Z, C, V (bits 31–28).
    Nzcv,
    /// Floating-point control: rounding mode (bits 23–22), flush-to-zero,
    /// default NaN, and exception trap enables (bits 8–12; Apple silicon
    /// ignores them, so FP exceptions never trap there).
    Fpcr,
    /// Floating-point status: cumulative exception flags IOC, DZC, OFC,
    /// UFC, IXC (bits 0–4) and IDC (bit 7).
    Fpsr,
}

impl SysReg {
    /// The 15-bit `o0:op1:CRn:CRm:op2` field of `mrs`/`msr`.
    pub(crate) fn encoding(self) -> u32 {
        // op0=3, op1=3, CRn=4; (CRm, op2) = (2, 0), (4, 0), (4, 1).
        let (crm, op2) = match self {
            SysReg::Nzcv => (2, 0),
            SysReg::Fpcr => (4, 0),
            SysReg::Fpsr => (4, 1),
        };
        1 << 14 | 3 << 11 | 4 << 7 | crm << 3 | op2
    }

    pub fn name(self) -> &'static str {
        match self {
            SysReg::Nzcv => "nzcv",
            SysReg::Fpcr => "fpcr",
            SysReg::Fpsr => "fpsr",
        }
    }

    /// Parses `nzcv`, `fpcr` or `fpsr` (case-insensitive).
    pub fn parse(name: &str) -> Option<SysReg> {
        match name.to_ascii_lowercase().as_str() {
            "nzcv" => Some(SysReg::Nzcv),
            "fpcr" => Some(SysReg::Fpcr),
            "fpsr" => Some(SysReg::Fpsr),
            _ => None,
        }
    }
}

/// Logical operations on general-purpose registers. `Bic`, `Orn`, `Eon`
/// and `Bics` invert the second operand.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum LogicOp {
    And,
    Orr,
    Eor,
    /// `and` that sets N and Z (C and V cleared).
    Ands,
    Bic,
    Orn,
    Eon,
    Bics,
}

impl LogicOp {
    pub fn name(self) -> &'static str {
        ["and", "orr", "eor", "ands", "bic", "orn", "eon", "bics"][self as usize]
    }

    /// `(opc, N)` of the register form.
    pub(crate) fn fields(self) -> (u32, u32) {
        let n = self as u32;
        (n & 3, n >> 2)
    }
}

/// Rounding of floating-point to integer conversions (`fcvt*s`, `fcvt*u`)
/// and of `frint*`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Round {
    /// To nearest, ties to even (`fcvtns`, `frintn`): Pascal `Round` on
    /// x86 rounds this way too with the default MXCSR.
    Nearest,
    /// To nearest, ties away from zero (`fcvtas`, `frinta`).
    Away,
    /// Toward minus infinity (`fcvtms`, `frintm`): `Floor`.
    Down,
    /// Toward plus infinity (`fcvtps`, `frintp`): `Ceil`.
    Up,
    /// Toward zero (`fcvtzs`, `frintz`): Pascal `Trunc` and `Int`.
    Zero,
}
