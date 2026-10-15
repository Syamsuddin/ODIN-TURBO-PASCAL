// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Minimal JSON: a writer for diagnostics, build results and the debug
//! protocol, and a reader for the protocol and `.odbg` files.

use std::collections::BTreeMap;
use std::fmt::Write as _;

/// Appends `s` as a JSON string literal.
pub fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Builds one JSON object field by field.
pub struct JsonWriter {
    out: String,
    first: bool,
}

impl JsonWriter {
    pub fn object() -> Self {
        JsonWriter { out: String::from("{"), first: true }
    }

    fn key(&mut self, key: &str) {
        if !self.first {
            self.out.push(',');
        }
        self.first = false;
        write_string(&mut self.out, key);
        self.out.push(':');
    }

    pub fn field_str(&mut self, key: &str, value: &str) {
        self.key(key);
        write_string(&mut self.out, value);
    }

    pub fn field_num(&mut self, key: &str, value: i64) {
        self.key(key);
        let _ = write!(self.out, "{value}");
    }

    pub fn field_bool(&mut self, key: &str, value: bool) {
        self.key(key);
        self.out.push_str(if value { "true" } else { "false" });
    }

    /// Inserts already-encoded JSON (an array or object built elsewhere).
    pub fn field_raw(&mut self, key: &str, json: &str) {
        self.key(key);
        self.out.push_str(json);
    }

    pub fn field_str_array<'a>(&mut self, key: &str, values: impl IntoIterator<Item = &'a str>) {
        self.key(key);
        self.out.push('[');
        for (i, v) in values.into_iter().enumerate() {
            if i > 0 {
                self.out.push(',');
            }
            write_string(&mut self.out, v);
        }
        self.out.push(']');
    }

    pub fn finish(mut self) -> String {
        self.out.push('}');
        self.out
    }
}

/// A parsed JSON value. Numbers keep integer precision when they have no
/// fraction or exponent.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    Array(Vec<Value>),
    Object(BTreeMap<String, Value>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(map) => map.get(key),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Value::Int(i) => Some(*i),
            Value::Float(f) if f.fract() == 0.0 => Some(*f as i64),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(a) => Some(a),
            _ => None,
        }
    }

    /// Re-encodes the value.
    pub fn to_json(&self) -> String {
        let mut out = String::new();
        self.write(&mut out);
        out
    }

    fn write(&self, out: &mut String) {
        match self {
            Value::Null => out.push_str("null"),
            Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Value::Int(i) => {
                let _ = write!(out, "{i}");
            }
            Value::Float(f) => {
                let _ = write!(out, "{f:?}");
            }
            Value::Str(s) => write_string(out, s),
            Value::Array(items) => {
                out.push('[');
                for (i, v) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    v.write(out);
                }
                out.push(']');
            }
            Value::Object(map) => {
                out.push('{');
                for (i, (k, v)) in map.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_string(out, k);
                    out.push(':');
                    v.write(out);
                }
                out.push('}');
            }
        }
    }
}

/// Parses one JSON document.
pub fn parse(text: &str) -> Result<Value, String> {
    let mut p = Parser { s: text.as_bytes(), i: 0 };
    let v = p.value()?;
    p.ws();
    if p.i != p.s.len() {
        return Err(format!("teks berlebih setelah JSON pada posisi {}", p.i));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }

    fn err<T>(&self, what: &str) -> Result<T, String> {
        Err(format!("JSON tidak valid pada posisi {}: {what}", self.i))
    }

    fn eat(&mut self, lit: &str) -> bool {
        if self.s[self.i..].starts_with(lit.as_bytes()) {
            self.i += lit.len();
            true
        } else {
            false
        }
    }

    fn value(&mut self) -> Result<Value, String> {
        self.ws();
        match self.s.get(self.i) {
            None => self.err("akhir teks"),
            Some(b'{') => {
                self.i += 1;
                let mut map = BTreeMap::new();
                self.ws();
                if self.eat("}") {
                    return Ok(Value::Object(map));
                }
                loop {
                    self.ws();
                    let key = self.string()?;
                    self.ws();
                    if !self.eat(":") {
                        return self.err("':' diharapkan");
                    }
                    let v = self.value()?;
                    map.insert(key, v);
                    self.ws();
                    if self.eat(",") {
                        continue;
                    }
                    if self.eat("}") {
                        return Ok(Value::Object(map));
                    }
                    return self.err("',' atau '}' diharapkan");
                }
            }
            Some(b'[') => {
                self.i += 1;
                let mut items = Vec::new();
                self.ws();
                if self.eat("]") {
                    return Ok(Value::Array(items));
                }
                loop {
                    items.push(self.value()?);
                    self.ws();
                    if self.eat(",") {
                        continue;
                    }
                    if self.eat("]") {
                        return Ok(Value::Array(items));
                    }
                    return self.err("',' atau ']' diharapkan");
                }
            }
            Some(b'"') => Ok(Value::Str(self.string()?)),
            Some(b't') if self.eat("true") => Ok(Value::Bool(true)),
            Some(b'f') if self.eat("false") => Ok(Value::Bool(false)),
            Some(b'n') if self.eat("null") => Ok(Value::Null),
            Some(c) if *c == b'-' || c.is_ascii_digit() => self.number(),
            Some(_) => self.err("nilai diharapkan"),
        }
    }

    fn number(&mut self) -> Result<Value, String> {
        let start = self.i;
        let mut float = false;
        while self.i < self.s.len() {
            match self.s[self.i] {
                b'0'..=b'9' | b'-' | b'+' => {}
                b'.' | b'e' | b'E' => float = true,
                _ => break,
            }
            self.i += 1;
        }
        let text = std::str::from_utf8(&self.s[start..self.i]).unwrap();
        if !float {
            if let Ok(i) = text.parse::<i64>() {
                return Ok(Value::Int(i));
            }
        }
        text.parse::<f64>().map(Value::Float).or_else(|_| self.err("angka tidak valid"))
    }

    fn string(&mut self) -> Result<String, String> {
        if !self.eat("\"") {
            return self.err("string diharapkan");
        }
        let mut out = String::new();
        loop {
            let Some(&c) = self.s.get(self.i) else { return self.err("string tidak ditutup") };
            self.i += 1;
            match c {
                b'"' => return Ok(out),
                b'\\' => {
                    let Some(&e) = self.s.get(self.i) else { return self.err("escape terpotong") };
                    self.i += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'u' => {
                            let mut code = self.hex4()?;
                            if (0xd800..0xdc00).contains(&code) && self.eat("\\u") {
                                let low = self.hex4()?;
                                code = 0x10000 + ((code - 0xd800) << 10) + (low.wrapping_sub(0xdc00) & 0x3ff);
                            }
                            out.push(char::from_u32(code).unwrap_or('\u{fffd}'));
                        }
                        _ => return self.err("escape tidak valid"),
                    }
                }
                _ => {
                    // Copy a whole UTF-8 sequence.
                    let start = self.i - 1;
                    let len = match c {
                        0x00..=0x7f => 1,
                        0xc0..=0xdf => 2,
                        0xe0..=0xef => 3,
                        _ => 4,
                    };
                    let end = (start + len).min(self.s.len());
                    out.push_str(&String::from_utf8_lossy(&self.s[start..end]));
                    self.i = end;
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let Some(digits) = self.s.get(self.i..self.i + 4) else { return self.err("\\u terpotong") };
        let text = std::str::from_utf8(digits).map_err(|_| "\\u tidak valid".to_string())?;
        let code = u32::from_str_radix(text, 16).map_err(|_| "\\u tidak valid".to_string())?;
        self.i += 4;
        Ok(code)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writer_escapes() {
        let mut w = JsonWriter::object();
        w.field_str("a", "x\"y\\z\n\u{1}é");
        w.field_num("n", -5);
        w.field_bool("b", true);
        w.field_str_array("l", ["p", "q"]);
        assert_eq!(w.finish(), r#"{"a":"x\"y\\z\n\u0001é","n":-5,"b":true,"l":["p","q"]}"#);
    }

    #[test]
    fn round_trip() {
        let text = r#"{"cmd":"evaluate","id":7,"expr":"A[I]","x":[1,2.5,null,false],"u":"é😀"}"#;
        let v = parse(text).unwrap();
        assert_eq!(v.get("id").and_then(Value::as_i64), Some(7));
        assert_eq!(v.get("expr").and_then(Value::as_str), Some("A[I]"));
        assert_eq!(v.get("u").and_then(Value::as_str), Some("é😀"));
        assert_eq!(parse(&v.to_json()).unwrap(), v);
    }

    #[test]
    fn errors() {
        assert!(parse("{\"a\":}").is_err());
        assert!(parse("[1,2").is_err());
        assert!(parse("1 2").is_err());
    }
}
