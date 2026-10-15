// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Instrumented debugger: `odinpc debug` runs a `--debug` build, talks to
//! its RTL hook (rtl/COMPILER_INTERFACE.md) and to the IDE (JSON lines,
//! IMPLEMENTATION_PLAN.md section 6.2), and evaluates Pascal expressions.

pub mod eval;
pub mod session;
