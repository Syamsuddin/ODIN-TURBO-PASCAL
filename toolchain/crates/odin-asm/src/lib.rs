// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Object model and machine code encoders.
//!
//! [`object`] is the contract between producers (code generator, `.s`
//! assembler) and the linker. Encoders live in per-architecture modules:
//! [`x86_64`] encodes x86-64 machine code and [`aarch64`] AArch64 machine
//! code, and [`text`] assembles `.s` files (the RTL shims) into an
//! [`Object`] through either encoder: Intel syntax for x86-64, the clang
//! syntax for AArch64.

pub mod aarch64;
pub mod object;
pub mod text;
pub mod x86_64;

pub use object::{Atom, Import, Object, Reloc, RelocKind, SectionKind};
