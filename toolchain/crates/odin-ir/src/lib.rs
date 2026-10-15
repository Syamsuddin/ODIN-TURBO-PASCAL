// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Types and the typed program representation (HIR) shared by semantic
//! analysis and the code generators.

pub mod hir;
pub mod types;

pub use hir::*;
pub use types::*;
