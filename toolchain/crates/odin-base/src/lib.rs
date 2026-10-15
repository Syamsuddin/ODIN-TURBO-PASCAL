// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Foundations shared by every Odin toolchain crate: source positions,
//! diagnostics, a small JSON writer/reader and SHA-256.

pub mod diag;
pub mod json;
pub mod sha256;
pub mod source;

pub use diag::{Diagnostic, Severity, code};
pub use source::{FileId, Location, SourceMap, Span};
