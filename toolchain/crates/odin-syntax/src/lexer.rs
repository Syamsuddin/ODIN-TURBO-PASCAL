// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Lexer with compiler directives, conditional compilation and include files.
//!
//! The whole file (and its includes) is turned into one token vector before
//! parsing. Like Turbo Pascal, lexing stops at the first error.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use odin_base::{Diagnostic, FileId, Severity, SourceMap, Span, code};

use crate::token::{Kw, Switches, Tok, Token};

/// Settings that come from the command line.
#[derive(Clone, Debug, Default)]
pub struct LexOptions {
    /// Conditional symbols, uppercase.
    pub defines: HashSet<String>,
    /// Switch state at the start of the file.
    pub switches: Switches,
    /// Directories searched for `{$I file}` after the including file's own
    /// directory.
    pub include_paths: Vec<PathBuf>,
}

/// Result of lexing one compilation unit.
#[derive(Debug)]
pub struct LexOutput {
    pub tokens: Vec<Token>,
    /// Warnings and hints (unknown directives and the like).
    pub warnings: Vec<Diagnostic>,
    /// Files pulled in with `{$I}`, for dependency tracking.
    pub includes: Vec<FileId>,
}

/// Lexes `file` and every file it includes.
pub fn tokenize(map: &mut SourceMap, file: FileId, options: &LexOptions) -> Result<LexOutput, Diagnostic> {
    let bytes: Rc<[u8]> = map.file(file).bytes.as_slice().into();
    let mut lexer = Lexer {
        map,
        stack: vec![Cursor { file, bytes, pos: 0 }],
        switches: options.switches,
        defines: options.defines.clone(),
        include_paths: options.include_paths.clone(),
        conds: Vec::new(),
        tokens: Vec::new(),
        warnings: Vec::new(),
        includes: Vec::new(),
    };
    lexer.run()?;
    Ok(LexOutput { tokens: lexer.tokens, warnings: lexer.warnings, includes: lexer.includes })
}

/// Finds `name` in `dir`, first exactly, then ignoring ASCII case (Linux
/// file systems are case-sensitive, while TP sources often say `UMATH`
/// for `umath.pas`).
pub fn find_file_ci(dir: &Path, name: &str) -> Option<PathBuf> {
    let exact = dir.join(name);
    if exact.is_file() {
        return Some(exact);
    }
    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let file_name = entry.file_name();
        if file_name.to_string_lossy().eq_ignore_ascii_case(name) && entry.path().is_file() {
            return Some(entry.path());
        }
    }
    None
}

struct Cursor {
    file: FileId,
    bytes: Rc<[u8]>,
    pos: usize,
}

struct Cond {
    /// Whether the region around this `{$IFxxx}` is active.
    parent_active: bool,
    /// Whether the `{$IFxxx}` condition was true.
    taken: bool,
    in_else: bool,
    active: bool,
    span: Span,
}

struct Lexer<'m> {
    map: &'m mut SourceMap,
    stack: Vec<Cursor>,
    switches: Switches,
    defines: HashSet<String>,
    include_paths: Vec<PathBuf>,
    conds: Vec<Cond>,
    tokens: Vec<Token>,
    warnings: Vec<Diagnostic>,
    includes: Vec<FileId>,
}

fn is_ident_start(c: u8) -> bool {
    c.is_ascii_alphabetic() || c == b'_'
}

fn is_ident_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}

impl Lexer<'_> {
    fn cur(&self) -> &Cursor {
        self.stack.last().unwrap()
    }

    fn peek(&self, k: usize) -> u8 {
        let c = self.cur();
        c.bytes.get(c.pos + k).copied().unwrap_or(0)
    }

    fn at_end(&self) -> bool {
        let c = self.cur();
        // Ctrl-Z marks the end of a DOS text file.
        c.pos >= c.bytes.len() || c.bytes[c.pos] == 0x1a
    }

    fn bump(&mut self, n: usize) {
        self.stack.last_mut().unwrap().pos += n;
    }

    fn pos(&self) -> usize {
        self.cur().pos
    }

    fn span(&self, start: usize) -> Span {
        Span::new(self.cur().file, start as u32, self.pos() as u32)
    }

    fn active(&self) -> bool {
        self.conds.last().is_none_or(|c| c.active)
    }

    fn error<T>(&self, code: u16, span: Span, detail: impl AsRef<str>) -> Result<T, Diagnostic> {
        Err(Diagnostic::error_with(code, span, detail))
    }

    fn push(&mut self, tok: Tok, start: usize) {
        if self.active() {
            let span = self.span(start);
            self.tokens.push(Token { tok, span, switches: self.switches });
        }
    }

    /// Whether a `^` here follows something that can be dereferenced.
    fn after_operand(&self) -> bool {
        matches!(self.tokens.last().map(|t| &t.tok), Some(Tok::Ident(_) | Tok::RParen | Tok::RBracket | Tok::Caret))
    }

    fn run(&mut self) -> Result<(), Diagnostic> {
        loop {
            self.skip_whitespace();
            if self.at_end() {
                if self.stack.len() > 1 {
                    self.stack.pop();
                    continue;
                }
                if let Some(cond) = self.conds.last() {
                    return self.error(code::ENDIF_MISSING, cond.span, "");
                }
                let end = self.cur().bytes.len().min(self.pos());
                let span = Span::new(self.cur().file, end as u32, end as u32);
                self.tokens.push(Token { tok: Tok::Eof, span, switches: self.switches });
                return Ok(());
            }
            self.token()?;
        }
    }

    fn skip_whitespace(&mut self) {
        while !self.at_end() && matches!(self.peek(0), b' ' | b'\t' | b'\r' | b'\n' | 0x0c) {
            self.bump(1);
        }
    }

    fn token(&mut self) -> Result<(), Diagnostic> {
        let start = self.pos();
        let c = self.peek(0);
        match c {
            b'{' => {
                if self.peek(1) == b'$' {
                    self.bump(2);
                    let body = self.comment_body(start, b"}")?;
                    self.directive(&body, self.span(start))?;
                } else {
                    self.bump(1);
                    self.comment_body(start, b"}")?;
                }
            }
            b'(' if self.peek(1) == b'*' => {
                self.bump(2);
                if self.peek(0) == b'$' {
                    self.bump(1);
                    let body = self.comment_body(start, b"*)")?;
                    self.directive(&body, self.span(start))?;
                } else {
                    self.comment_body(start, b"*)")?;
                }
            }
            b'/' if self.peek(1) == b'/' => {
                while !self.at_end() && !matches!(self.peek(0), b'\n' | b'\r') {
                    self.bump(1);
                }
            }
            c if is_ident_start(c) => self.ident(start)?,
            b'0'..=b'9' => self.number(start)?,
            b'$' => self.hex(start)?,
            b'\'' => self.string(start)?,
            b'#' => self.control_char(start)?,
            b'^' => self.caret(start),
            _ => self.punct(start)?,
        }
        Ok(())
    }

    /// Consumes a comment body up to `close`; returns the text before it.
    fn comment_body(&mut self, start: usize, close: &[u8]) -> Result<String, Diagnostic> {
        let body_start = self.pos();
        loop {
            if self.at_end() {
                let span = Span::new(self.cur().file, start as u32, start as u32 + 1);
                return self.error(code::UNEXPECTED_EOF, span, ": komentar tidak ditutup");
            }
            if self.peek(0) == close[0] && (close.len() == 1 || self.peek(1) == close[1]) {
                let text = String::from_utf8_lossy(&self.cur().bytes[body_start..self.pos()]).into_owned();
                self.bump(close.len());
                return Ok(text);
            }
            self.bump(1);
        }
    }

    fn ident(&mut self, start: usize) -> Result<(), Diagnostic> {
        while is_ident_char(self.peek(0)) {
            self.bump(1);
        }
        let text = std::str::from_utf8(&self.cur().bytes[start..self.pos()]).unwrap().to_string();
        match Kw::from_ident(&text) {
            Some(Kw::Asm) => {
                self.push(Tok::Keyword(Kw::Asm), start);
                self.asm_body()?;
            }
            Some(kw) => self.push(Tok::Keyword(kw), start),
            None => self.push(Tok::Ident(text), start),
        }
        Ok(())
    }

    /// Captures an `asm` block verbatim up to (not including) its `end`.
    fn asm_body(&mut self) -> Result<(), Diagnostic> {
        let start = self.pos();
        loop {
            if self.at_end() {
                let span = Span::new(self.cur().file, start as u32, start as u32);
                return self.error(code::END_EXPECTED, span, ": blok ASM tidak ditutup");
            }
            let c = self.peek(0);
            match c {
                b'{' => {
                    let s = self.pos();
                    self.bump(1);
                    self.comment_body(s, b"}")?;
                }
                b'(' if self.peek(1) == b'*' => {
                    let s = self.pos();
                    self.bump(2);
                    self.comment_body(s, b"*)")?;
                }
                b'\'' | b'"' => {
                    self.bump(1);
                    while !self.at_end() && self.peek(0) != c && self.peek(0) != b'\n' {
                        self.bump(1);
                    }
                    self.bump(1);
                }
                c if is_ident_start(c) || c == b'@' => {
                    let s = self.pos();
                    while is_ident_char(self.peek(0)) || self.peek(0) == b'@' {
                        self.bump(1);
                    }
                    if self.cur().bytes[s..self.pos()].eq_ignore_ascii_case(b"end") {
                        self.stack.last_mut().unwrap().pos = s;
                        let text = String::from_utf8_lossy(&self.cur().bytes[start..s]).into_owned();
                        self.push(Tok::AsmText(text), start);
                        return Ok(());
                    }
                }
                _ => self.bump(1),
            }
        }
    }

    fn number(&mut self, start: usize) -> Result<(), Diagnostic> {
        while self.peek(0).is_ascii_digit() {
            self.bump(1);
        }
        let mut real = false;
        if self.peek(0) == b'.' && self.peek(1).is_ascii_digit() {
            real = true;
            self.bump(1);
            while self.peek(0).is_ascii_digit() {
                self.bump(1);
            }
        }
        if matches!(self.peek(0), b'e' | b'E') {
            let sign = matches!(self.peek(1), b'+' | b'-') as usize;
            if self.peek(1 + sign).is_ascii_digit() {
                real = true;
                self.bump(1 + sign);
                while self.peek(0).is_ascii_digit() {
                    self.bump(1);
                }
            }
        }
        let text = std::str::from_utf8(&self.cur().bytes[start..self.pos()]).unwrap();
        if real {
            match text.parse::<f64>() {
                Ok(v) if v.is_finite() => {
                    self.push(Tok::Real(v), start);
                    Ok(())
                }
                _ => self.error(code::BAD_REAL, self.span(start), ""),
            }
        } else {
            match text.parse::<u64>() {
                Ok(v) => {
                    self.push(Tok::Int(v), start);
                    Ok(())
                }
                Err(_) => self.error(code::BAD_INTEGER, self.span(start), ": angka terlalu besar"),
            }
        }
    }

    fn hex(&mut self, start: usize) -> Result<(), Diagnostic> {
        self.bump(1);
        let digits = self.pos();
        while self.peek(0).is_ascii_hexdigit() {
            self.bump(1);
        }
        let text = std::str::from_utf8(&self.cur().bytes[digits..self.pos()]).unwrap();
        if text.is_empty() {
            return self.error(code::BAD_INTEGER, self.span(start), ": digit heksadesimal diharapkan setelah $");
        }
        match u64::from_str_radix(text, 16) {
            Ok(v) => {
                self.push(Tok::Int(v), start);
                Ok(())
            }
            Err(_) => self.error(code::BAD_INTEGER, self.span(start), ": angka terlalu besar"),
        }
    }

    fn string(&mut self, start: usize) -> Result<(), Diagnostic> {
        self.bump(1);
        let mut bytes = Vec::new();
        loop {
            if self.at_end() || matches!(self.peek(0), b'\n' | b'\r') {
                let span = Span::new(self.cur().file, start as u32, start as u32 + 1);
                return self.error(code::STRING_EXCEEDS_LINE, span, "");
            }
            let c = self.peek(0);
            self.bump(1);
            if c == b'\'' {
                if self.peek(0) == b'\'' {
                    bytes.push(b'\'');
                    self.bump(1);
                } else {
                    break;
                }
            } else {
                bytes.push(c);
            }
        }
        self.push(Tok::Str(bytes), start);
        Ok(())
    }

    fn control_char(&mut self, start: usize) -> Result<(), Diagnostic> {
        self.bump(1);
        let value = if self.peek(0) == b'$' {
            self.bump(1);
            let s = self.pos();
            while self.peek(0).is_ascii_hexdigit() {
                self.bump(1);
            }
            u32::from_str_radix(std::str::from_utf8(&self.cur().bytes[s..self.pos()]).unwrap(), 16).ok()
        } else {
            let s = self.pos();
            while self.peek(0).is_ascii_digit() {
                self.bump(1);
            }
            std::str::from_utf8(&self.cur().bytes[s..self.pos()]).unwrap().parse::<u32>().ok()
        };
        match value {
            Some(v) if v <= 255 => {
                self.push(Tok::Str(vec![v as u8]), start);
                Ok(())
            }
            Some(_) => self.error(code::CONST_OUT_OF_RANGE, self.span(start), ": kode karakter harus 0..255"),
            None => self.error(code::SYNTAX_ERROR, self.span(start), ": angka diharapkan setelah #"),
        }
    }

    fn caret(&mut self, start: usize) {
        let next = self.peek(1);
        let control =
            !self.after_operand() && (b'@'..=b'_').contains(&next.to_ascii_uppercase()) && !is_ident_char(self.peek(2));
        if control {
            self.bump(2);
            self.push(Tok::CaretChar(next.to_ascii_uppercase() ^ 0x40), start);
        } else {
            self.bump(1);
            self.push(Tok::Caret, start);
        }
    }

    fn punct(&mut self, start: usize) -> Result<(), Diagnostic> {
        let (tok, len) = match (self.peek(0), self.peek(1)) {
            (b':', b'=') => (Tok::Assign, 2),
            (b'<', b'=') => (Tok::Le, 2),
            (b'>', b'=') => (Tok::Ge, 2),
            (b'<', b'>') => (Tok::Ne, 2),
            (b'.', b'.') => (Tok::DotDot, 2),
            (b'(', b'.') => (Tok::LBracket, 2),
            (b'.', b')') => (Tok::RBracket, 2),
            (b'+', _) => (Tok::Plus, 1),
            (b'-', _) => (Tok::Minus, 1),
            (b'*', _) => (Tok::Star, 1),
            (b'/', _) => (Tok::Slash, 1),
            (b'=', _) => (Tok::Eq, 1),
            (b'<', _) => (Tok::Lt, 1),
            (b'>', _) => (Tok::Gt, 1),
            (b':', _) => (Tok::Colon, 1),
            (b';', _) => (Tok::Semi, 1),
            (b',', _) => (Tok::Comma, 1),
            (b'.', _) => (Tok::Dot, 1),
            (b'(', _) => (Tok::LParen, 1),
            (b')', _) => (Tok::RParen, 1),
            (b'[', _) => (Tok::LBracket, 1),
            (b']', _) => (Tok::RBracket, 1),
            (b'@', _) => (Tok::At, 1),
            (c, _) => {
                self.bump(1);
                let shown = if c.is_ascii_graphic() { format!("'{}'", c as char) } else { format!("#{c}") };
                return self.error(code::SYNTAX_ERROR, self.span(start), format!(": karakter {shown} tidak valid"));
            }
        };
        self.bump(len);
        self.push(tok, start);
        Ok(())
    }

    // ---- directives ----------------------------------------------------

    fn directive(&mut self, body: &str, span: Span) -> Result<(), Diagnostic> {
        let body = body.trim();
        let name_len = body.bytes().take_while(|c| c.is_ascii_alphabetic()).count();
        let name = body[..name_len].to_ascii_uppercase();
        let arg = body[name_len..].trim();

        // Conditionals are processed even inside inactive regions.
        match name.as_str() {
            "IFDEF" | "IFNDEF" | "IFOPT" => {
                let parent_active = self.active();
                let taken = match name.as_str() {
                    "IFDEF" => self.defines.contains(&first_word(arg)),
                    "IFNDEF" => !self.defines.contains(&first_word(arg)),
                    _ => self.ifopt(arg, span)?,
                };
                self.conds.push(Cond { parent_active, taken, in_else: false, active: parent_active && taken, span });
                return Ok(());
            }
            "ELSE" => {
                let Some(cond) = self.conds.last_mut() else {
                    return self.error(code::MISPLACED_CONDITIONAL, span, ": {$ELSE} tanpa {$IFDEF}");
                };
                if cond.in_else {
                    return self.error(code::MISPLACED_CONDITIONAL, span, ": {$ELSE} ganda");
                }
                cond.in_else = true;
                cond.active = cond.parent_active && !cond.taken;
                return Ok(());
            }
            "ENDIF" | "IFEND" => {
                if self.conds.pop().is_none() {
                    return self.error(code::MISPLACED_CONDITIONAL, span, ": {$ENDIF} tanpa {$IFDEF}");
                }
                return Ok(());
            }
            "IF" | "ELSEIF" if self.active() || name == "IF" => {
                return self.error(code::NOT_SUPPORTED, span, ": {$IF} dan {$ELSEIF}; pakai {$IFDEF}");
            }
            _ => {}
        }
        if !self.active() {
            return Ok(());
        }

        if is_switch_list(body) {
            for item in body.split(',') {
                let item = item.trim().as_bytes();
                let on = item[1] == b'+';
                if item[0].eq_ignore_ascii_case(&b'H') && on {
                    return self.error(
                        code::NOT_SUPPORTED,
                        span,
                        ": {$H+} (AnsiString) bukan bagian dari Turbo Pascal",
                    );
                }
                if let Some(flag) = Switches::letter(item[0]) {
                    self.switches.set(flag, on);
                }
            }
            return Ok(());
        }

        match name.as_str() {
            "I" | "INCLUDE" => self.include(arg, span),
            "DEFINE" => {
                self.defines.insert(first_word(arg));
                Ok(())
            }
            "UNDEF" => {
                self.defines.remove(&first_word(arg));
                Ok(())
            }
            "L" | "LINK" | "LINKLIB" => self.error(code::NOT_SUPPORTED, span, ": menautkan berkas objek luar ({$L})"),
            "MODE" => {
                if first_word(arg) == "TP" {
                    Ok(())
                } else {
                    self.error(
                        code::NOT_SUPPORTED,
                        span,
                        format!(": mode {}; Odin hanya mendukung mode TP", arg.trim()),
                    )
                }
            }
            "RANGECHECKS" | "OVERFLOWCHECKS" | "IOCHECKS" | "BOOLEVAL" | "EXTENDEDSYNTAX" | "TYPEDADDRESS"
            | "VARSTRINGCHECKS" | "OPENSTRINGS" | "STACKCHECKS" | "DEBUGINFO" => {
                let flag = match name.as_str() {
                    "RANGECHECKS" => Switches::RANGE,
                    "OVERFLOWCHECKS" => Switches::OVERFLOW,
                    "IOCHECKS" => Switches::IO,
                    "BOOLEVAL" => Switches::BOOL_EVAL,
                    "EXTENDEDSYNTAX" => Switches::EXTENDED,
                    "TYPEDADDRESS" => Switches::TYPED_AT,
                    "VARSTRINGCHECKS" => Switches::VAR_STRING,
                    "OPENSTRINGS" => Switches::OPEN_STRING,
                    "STACKCHECKS" => Switches::STACK,
                    _ => Switches::DEBUG,
                };
                let on = match first_word(arg).as_str() {
                    "ON" | "+" => true,
                    "OFF" | "-" => false,
                    _ => return self.error(code::BAD_DIRECTIVE, span, ": ON atau OFF diharapkan"),
                };
                self.switches.set(flag, on);
                Ok(())
            }
            // Memory sizes, code attributes, descriptions, resources,
            // assembler syntax: meaningless on a 64-bit target.
            "M" | "C" | "D" | "R" | "S" | "ASMMODE" | "APPTYPE" | "G" | "N" | "E" | "F" | "O" | "A" | "Y" => {
                self.warnings.push(Diagnostic::new(
                    Severity::Hint,
                    code::IGNORED_DIRECTIVE,
                    span,
                    code::message(code::IGNORED_DIRECTIVE),
                ));
                Ok(())
            }
            _ => {
                self.warnings.push(Diagnostic::new(
                    Severity::Warning,
                    code::UNKNOWN_DIRECTIVE,
                    span,
                    format!("{}: {{${}}}", code::message(code::UNKNOWN_DIRECTIVE), body),
                ));
                Ok(())
            }
        }
    }

    fn ifopt(&self, arg: &str, span: Span) -> Result<bool, Diagnostic> {
        let a = arg.trim().as_bytes();
        if a.len() >= 2 && matches!(a[1], b'+' | b'-') {
            let on = a[1] == b'+';
            return Ok(match Switches::letter(a[0]) {
                Some(flag) => self.switches.get(flag) == on,
                None => !on,
            });
        }
        self.error(code::BAD_DIRECTIVE, span, ": {$IFOPT} memerlukan sakelar seperti R+")
    }

    fn include(&mut self, arg: &str, span: Span) -> Result<(), Diagnostic> {
        let name = arg.trim().trim_matches('\'').trim_matches('"').trim();
        if name.is_empty() {
            return self.error(code::BAD_DIRECTIVE, span, ": nama berkas include diharapkan");
        }
        if self.stack.len() > 16 {
            return self.error(code::INCLUDE_NOT_ALLOWED, span, ": include bersarang terlalu dalam");
        }
        let current = self.map.file(self.cur().file).path.clone();
        let mut dirs = vec![current.parent().map(Path::to_path_buf).unwrap_or_default()];
        dirs.extend(self.include_paths.iter().cloned());
        let has_ext = Path::new(name).extension().is_some();
        let candidates: Vec<String> = if has_ext {
            vec![name.to_string()]
        } else {
            vec![name.to_string(), format!("{name}.inc"), format!("{name}.pas")]
        };
        let found = dirs.iter().find_map(|dir| candidates.iter().find_map(|c| find_file_ci(dir, c)));
        let Some(path) = found else {
            return self.error(code::FILE_NOT_FOUND, span, format!(": {name}"));
        };
        let id = match self.map.load(&path) {
            Ok(id) => id,
            Err(e) => return self.error(code::FILE_NOT_FOUND, span, format!(": {name} ({e})")),
        };
        if self.stack.iter().any(|c| c.file == id) {
            return self.error(code::INCLUDE_NOT_ALLOWED, span, format!(": {name} meng-include dirinya sendiri"));
        }
        self.includes.push(id);
        let bytes: Rc<[u8]> = self.map.file(id).bytes.as_slice().into();
        self.stack.push(Cursor { file: id, bytes, pos: 0 });
        Ok(())
    }
}

fn first_word(arg: &str) -> String {
    arg.split_whitespace().next().unwrap_or("").to_ascii_uppercase()
}

/// `R+`, `R+,Q-`, `I-` ...
fn is_switch_list(body: &str) -> bool {
    !body.is_empty()
        && body.split(',').all(|item| {
            let b = item.trim().as_bytes();
            b.len() == 2 && b[0].is_ascii_alphabetic() && matches!(b[1], b'+' | b'-')
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lex(src: &str) -> Vec<Tok> {
        lex_with(src, &LexOptions::default()).unwrap().tokens.into_iter().map(|t| t.tok).collect()
    }

    fn lex_with(src: &str, options: &LexOptions) -> Result<LexOutput, Diagnostic> {
        let mut map = SourceMap::new();
        let id = map.add("test.pas", src.as_bytes().to_vec());
        tokenize(&mut map, id, options)
    }

    fn ident(s: &str) -> Tok {
        Tok::Ident(s.to_string())
    }

    #[test]
    fn basic_tokens() {
        assert_eq!(
            lex("x := a[1..$1F] + 2.5e1; { c } (* d *) // e\n p^.f <> 'it''s'"),
            vec![
                ident("x"),
                Tok::Assign,
                ident("a"),
                Tok::LBracket,
                Tok::Int(1),
                Tok::DotDot,
                Tok::Int(31),
                Tok::RBracket,
                Tok::Plus,
                Tok::Real(25.0),
                Tok::Semi,
                ident("p"),
                Tok::Caret,
                Tok::Dot,
                ident("f"),
                Tok::Ne,
                Tok::Str(b"it's".to_vec()),
                Tok::Eof
            ]
        );
    }

    #[test]
    fn keywords_any_case() {
        assert_eq!(lex("BeGiN end"), vec![Tok::Keyword(Kw::Begin), Tok::Keyword(Kw::End), Tok::Eof]);
    }

    #[test]
    fn control_characters() {
        assert_eq!(
            lex("s := 'a'#13#$0A^M;"),
            vec![
                ident("s"),
                Tok::Assign,
                Tok::Str(b"a".to_vec()),
                Tok::Str(vec![13]),
                Tok::Str(vec![10]),
                Tok::CaretChar(13),
                Tok::Semi,
                Tok::Eof
            ]
        );
        // Pointer types are not control characters.
        assert_eq!(lex("= ^Integer")[1], Tok::Caret);
    }

    #[test]
    fn numbers_and_ranges() {
        assert_eq!(lex("1..10")[..3], [Tok::Int(1), Tok::DotDot, Tok::Int(10)]);
        assert_eq!(lex("2.75")[0], Tok::Real(2.75));
        assert_eq!(lex("1E3")[0], Tok::Real(1000.0));
        assert!(lex_with("99999999999999999999", &LexOptions::default()).is_err());
    }

    #[test]
    fn switches_follow_directives() {
        let out = lex_with("a {$R+} b {$R-,Q+} c", &LexOptions::default()).unwrap();
        assert!(!out.tokens[0].switches.get(Switches::RANGE));
        assert!(out.tokens[1].switches.get(Switches::RANGE));
        assert!(!out.tokens[2].switches.get(Switches::RANGE));
        assert!(out.tokens[2].switches.get(Switches::OVERFLOW));
    }

    #[test]
    fn conditional_compilation() {
        let mut options = LexOptions::default();
        options.defines.insert("ODIN".into());
        let toks: Vec<Tok> = lex_with(
            "{$IFDEF ODIN} a {$IFDEF X} b {$ELSE} c {$ENDIF} {$ELSE} d {$IFDEF ODIN} e {$ENDIF} {$ENDIF} f",
            &options,
        )
        .unwrap()
        .tokens
        .into_iter()
        .map(|t| t.tok)
        .collect();
        assert_eq!(toks, vec![ident("a"), ident("c"), ident("f"), Tok::Eof]);
        let toks = lex("{$DEFINE Z}{$IFNDEF Z} a {$ENDIF}{$UNDEF Z}{$IFNDEF Z} b {$ENDIF}");
        assert_eq!(toks, vec![ident("b"), Tok::Eof]);
        let toks = lex("{$R+}{$IFOPT R+} r {$ENDIF}{$IFOPT Q+} q {$ENDIF}");
        assert_eq!(toks, vec![ident("r"), Tok::Eof]);
        assert_eq!(lex_with("{$IFDEF A}", &options).unwrap_err().code, code::ENDIF_MISSING);
        assert_eq!(lex_with("{$ENDIF}", &options).unwrap_err().code, code::MISPLACED_CONDITIONAL);
    }

    #[test]
    fn skipped_regions_hide_errors() {
        // A stray character inside an inactive region is still lexed (so
        // strings and comments are honoured) but produces no token.
        assert_eq!(lex("{$IFDEF NOPE} 'x' {$ENDIF} y"), vec![ident("y"), Tok::Eof]);
    }

    #[test]
    fn asm_blocks_are_raw() {
        let toks = lex("asm mov ax, 1; @@x: { end } end;");
        assert_eq!(toks[0], Tok::Keyword(Kw::Asm));
        assert_eq!(toks[1], Tok::AsmText(" mov ax, 1; @@x: { end } ".into()));
        assert_eq!(toks[2], Tok::Keyword(Kw::End));
    }

    #[test]
    fn errors_point_at_token_start() {
        let mut map = SourceMap::new();
        let id = map.add("d.pas", b"program p;\nbegin\n  writeln('abc);\nend.\n".to_vec());
        let err = tokenize(&mut map, id, &LexOptions::default()).unwrap_err();
        assert_eq!(err.code, code::STRING_EXCEEDS_LINE);
        let loc = map.location(err.span);
        assert_eq!((loc.line, loc.column), (3, 11));
    }

    #[test]
    fn includes_are_resolved_case_insensitively() {
        let dir = std::env::temp_dir().join(format!("odin-lex-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("defs.inc"), "b {$R+} c").unwrap();
        let main = dir.join("main.pas");
        std::fs::write(&main, "a {$I DEFS.INC} d").unwrap();
        let mut map = SourceMap::new();
        let id = map.load(&main).unwrap();
        let out = tokenize(&mut map, id, &LexOptions::default()).unwrap();
        let toks: Vec<Tok> = out.tokens.iter().map(|t| t.tok.clone()).collect();
        assert_eq!(toks, vec![ident("a"), ident("b"), ident("c"), ident("d"), Tok::Eof]);
        assert_ne!(out.tokens[1].span.file, out.tokens[0].span.file);
        // Switches set inside an include stay in effect afterwards.
        assert!(out.tokens[3].switches.get(Switches::RANGE));
        assert_eq!(out.includes.len(), 1);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn unknown_directive_warns() {
        let out = lex_with("{$FOO bar} x", &LexOptions::default()).unwrap();
        assert_eq!(out.warnings.len(), 1);
        assert_eq!(out.warnings[0].code, code::UNKNOWN_DIRECTIVE);
        assert!(lex_with("{$MODE OBJFPC}", &LexOptions::default()).is_err());
        assert!(lex_with("{$H+}", &LexOptions::default()).is_err());
    }
}
