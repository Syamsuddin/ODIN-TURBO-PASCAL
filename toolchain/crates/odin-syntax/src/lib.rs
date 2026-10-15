// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Lexer, compiler directives and parser for Turbo Pascal 7.

pub mod ast;
pub mod dump;
pub mod lexer;
pub mod parser;
pub mod token;

pub use lexer::{LexOptions, LexOutput, find_file_ci, tokenize};
pub use parser::{parse_expression, parse_module};
pub use token::{Kw, Switches, Tok, Token};

use odin_base::{Diagnostic, FileId, SourceMap};

/// A parsed source file.
#[derive(Debug)]
pub struct Parsed {
    pub module: ast::Module,
    pub warnings: Vec<Diagnostic>,
    pub includes: Vec<FileId>,
}

/// Lexes and parses `file`. Stops at the first error.
pub fn parse_file(map: &mut SourceMap, file: FileId, options: &LexOptions) -> Result<Parsed, Diagnostic> {
    let lexed = tokenize(map, file, options)?;
    let module = parse_module(&lexed.tokens)?;
    Ok(Parsed { module, warnings: lexed.warnings, includes: lexed.includes })
}
