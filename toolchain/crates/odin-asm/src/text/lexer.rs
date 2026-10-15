// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Splits one source line into tokens and drops its comment.

/// A token of an assembly line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Tok {
    /// A name: label, symbol, directive (with its dot), mnemonic, register
    /// or size keyword. Starts with a letter, `_`, `.` or `$`.
    Ident(String),
    /// An integer literal or character constant. Kept wide so expressions
    /// can detect overflow before the value is narrowed.
    Num(i128),
    /// A string literal with escapes already processed.
    Str(Vec<u8>),
    /// `<<`
    Shl,
    /// `>>`
    Shr,
    /// Any other single punctuation character.
    Punct(char),
}

impl Tok {
    pub(crate) fn is_punct(&self, c: char) -> bool {
        matches!(self, Tok::Punct(p) if *p == c)
    }

    /// Short description for error messages.
    pub(crate) fn describe(&self) -> String {
        match self {
            Tok::Ident(s) => format!("`{s}`"),
            Tok::Num(n) => format!("`{n}`"),
            Tok::Str(_) => "a string".to_string(),
            Tok::Shl => "`<<`".to_string(),
            Tok::Shr => "`>>`".to_string(),
            Tok::Punct(c) => format!("`{c}`"),
        }
    }
}

fn ident_start(c: char) -> bool {
    c.is_ascii_alphabetic() || matches!(c, '_' | '.' | '$')
}

fn ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '$')
}

/// Tokenizes `line`. A `;` or `#` outside a string or character literal
/// starts a comment that runs to the end of the line.
pub(crate) fn lex(line: &str) -> Result<Vec<Tok>, String> {
    let chars: Vec<char> = line.chars().collect();
    let mut toks = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_whitespace() {
            i += 1;
        } else if c == ';' || c == '#' {
            break;
        } else if ident_start(c) {
            let start = i;
            while i < chars.len() && ident_char(chars[i]) {
                i += 1;
            }
            toks.push(Tok::Ident(chars[start..i].iter().collect()));
        } else if c.is_ascii_digit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_alphanumeric() {
                i += 1;
            }
            let text: String = chars[start..i].iter().collect();
            toks.push(Tok::Num(number(&text)?));
        } else if c == '"' {
            i += 1;
            let mut bytes = Vec::new();
            loop {
                match chars.get(i) {
                    None => return Err("unterminated string".into()),
                    Some('"') => {
                        i += 1;
                        break;
                    }
                    Some('\\') => {
                        let (b, next) = escape(&chars, i + 1)?;
                        bytes.push(b);
                        i = next;
                    }
                    Some(ch) => {
                        let mut buf = [0; 4];
                        bytes.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        i += 1;
                    }
                }
            }
            toks.push(Tok::Str(bytes));
        } else if c == '\'' {
            let (value, next) = match chars.get(i + 1) {
                Some('\\') => escape(&chars, i + 2)?,
                Some(ch) if *ch != '\'' && ch.is_ascii() => (*ch as u8, i + 2),
                _ => return Err("bad character constant".into()),
            };
            if chars.get(next) != Some(&'\'') {
                return Err("unterminated character constant".into());
            }
            toks.push(Tok::Num(value as i128));
            i = next + 1;
        } else if c == '<' && chars.get(i + 1) == Some(&'<') {
            toks.push(Tok::Shl);
            i += 2;
        } else if c == '>' && chars.get(i + 1) == Some(&'>') {
            toks.push(Tok::Shr);
            i += 2;
        } else if "[]()+-*/%,:@~&|^=".contains(c) {
            toks.push(Tok::Punct(c));
            i += 1;
        } else {
            return Err(format!("unexpected character `{c}`"));
        }
    }
    Ok(toks)
}

/// Decodes the escape sequence starting at `chars[i]` (just after the
/// backslash). Returns the byte and the index after the sequence.
fn escape(chars: &[char], i: usize) -> Result<(u8, usize), String> {
    let c = *chars.get(i).ok_or("unterminated escape sequence")?;
    Ok(match c {
        'n' => (b'\n', i + 1),
        't' => (b'\t', i + 1),
        'r' => (b'\r', i + 1),
        'b' => (8, i + 1),
        'f' => (12, i + 1),
        'v' => (11, i + 1),
        'a' => (7, i + 1),
        'e' => (27, i + 1),
        '\\' | '"' | '\'' => (c as u8, i + 1),
        'x' | 'X' => {
            let mut j = i + 1;
            let mut v: u32 = 0;
            while j < chars.len() && j < i + 3 && chars[j].is_ascii_hexdigit() {
                v = v * 16 + chars[j].to_digit(16).unwrap();
                j += 1;
            }
            if j == i + 1 {
                return Err("`\\x` needs hexadecimal digits".into());
            }
            (v as u8, j)
        }
        '0'..='7' => {
            let mut j = i;
            let mut v: u32 = 0;
            while j < chars.len() && j < i + 3 && ('0'..='7').contains(&chars[j]) {
                v = v * 8 + chars[j].to_digit(8).unwrap();
                j += 1;
            }
            if v > 255 {
                return Err("octal escape above \\377".into());
            }
            (v as u8, j)
        }
        _ => return Err(format!("unknown escape sequence `\\{c}`")),
    })
}

/// Parses an integer literal: decimal, `0x` hex, `0b` binary, `0o` octal or
/// Intel-style hex with an `h` suffix (`0FFh`). A decimal literal with a
/// leading zero is rejected, because GNU as reads it as octal.
fn number(text: &str) -> Result<i128, String> {
    let lower = text.to_ascii_lowercase();
    let (digits, radix) = if let Some(d) = lower.strip_prefix("0x") {
        (d, 16)
    } else if let Some(d) = lower.strip_prefix("0b") {
        (d, 2)
    } else if let Some(d) = lower.strip_prefix("0o") {
        (d, 8)
    } else if let Some(d) = lower.strip_suffix('h') {
        (d, 16)
    } else {
        if lower.len() > 1 && lower.starts_with('0') {
            return Err(format!("number `{text}` has a leading zero (write it in decimal, or with 0o for octal)"));
        }
        (lower.as_str(), 10)
    };
    let value = u128::from_str_radix(digits, radix).map_err(|_| format!("bad number `{text}`"))?;
    if value > u64::MAX as u128 {
        return Err(format!("number `{text}` does not fit in 64 bits"));
    }
    Ok(value as i128)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn comments_and_strings() {
        let t = lex(r#"  .ascii "a;b#c\n" # comment ; more"#).unwrap();
        assert_eq!(t, vec![Tok::Ident(".ascii".into()), Tok::Str(b"a;b#c\n".to_vec())]);
        assert_eq!(lex("mov al, '#' ; x").unwrap()[3], Tok::Num(35));
        assert_eq!(lex("; only a comment").unwrap(), vec![]);
    }

    #[test]
    fn numbers() {
        assert_eq!(number("0x1F").unwrap(), 31);
        assert_eq!(number("0FFh").unwrap(), 255);
        assert_eq!(number("0b101").unwrap(), 5);
        assert_eq!(number("0").unwrap(), 0);
        assert_eq!(number("18446744073709551615").unwrap(), u64::MAX as i128);
        assert!(number("18446744073709551616").is_err());
        assert!(number("010").is_err());
    }

    #[test]
    fn escapes() {
        let t = lex(r#""\x41\101\0\\\"""#).unwrap();
        assert_eq!(t, vec![Tok::Str(vec![0x41, 0o101, 0, b'\\', b'"'])]);
        assert!(lex(r#""abc"#).is_err());
        assert!(lex(r#""\q""#).is_err());
    }
}
