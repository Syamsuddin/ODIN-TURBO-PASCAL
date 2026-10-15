// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Debug descriptions written next to an executable as `NAME.odbg` (JSON):
//! line tables, routines with their frame layout, globals and types. The
//! compiler writes them; `odinpc debug` and the IDE read them.
//!
//! Addresses are link-time (unslid) addresses. At run time the program
//! reports where [`DebugInfo::anchor`] really is; the difference is the
//! slide to add to every other address.

use std::collections::BTreeMap;

use odin_base::json::{self, Value};

/// Format version; readers reject other versions.
pub const VERSION: i64 = 1;

#[derive(Clone, Debug, PartialEq, Default)]
pub struct DebugInfo {
    pub files: Vec<String>,
    /// Link-time address of the executable's header: a run-time code
    /// address minus the run-time header address, plus this, is the
    /// link-time address.
    pub image_base: u64,
    /// Link-time address of `SYSTEM.ODIN_DBG_LINE` (0 without `--debug`).
    pub anchor: u64,
    /// Link-time address of `SYSTEM.ODIN_DBG_STACK` (0 without `--debug`).
    pub stack: u64,
    /// Debugger stop points: `(file, line)` for every line id.
    pub lines: Vec<(u32, u32)>,
    /// Start address of every statement, sorted, for mapping a code address
    /// (a runtime error) back to a source line: `(address, file, line)`.
    pub addresses: Vec<(u64, u32, u32)>,
    pub routines: Vec<RoutineInfo>,
    pub globals: Vec<GlobalInfo>,
    pub types: Vec<TypeInfo>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RoutineInfo {
    /// Source-level name (`Faktorial`, `UMath.Kuadrat`).
    pub name: String,
    pub symbol: String,
    /// Lexically enclosing routine (index), for nested routines.
    pub parent: Option<u32>,
    pub file: u32,
    pub line: u32,
    /// Compiled with debugger hooks.
    pub instrumented: bool,
    /// Frame offset of the static link (nested routines only).
    pub static_link: Option<i32>,
    pub locals: Vec<LocalInfo>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LocalKind {
    Param,
    Var,
    Result,
    /// Hidden `High` of open array/string parameter `index`.
    High(u32),
    Temp,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LocalInfo {
    pub name: String,
    pub ty: u32,
    pub kind: LocalKind,
    /// Offset from the frame pointer.
    pub offset: i32,
    /// The slot holds the address of the value.
    pub indirect: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct GlobalInfo {
    pub name: String,
    /// Symbol prefix: the unit (`$PROGRAM`, `CRT`) or, for typed constants
    /// inside routines, the routine's symbol.
    pub scope: String,
    pub ty: u32,
    pub address: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TypeInfo {
    pub name: Option<String>,
    pub size: u64,
    pub kind: TypeKind,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TypeKind {
    Int {
        signed: bool,
    },
    Bool,
    Char,
    Enum {
        names: Vec<String>,
    },
    Subrange {
        base: u32,
        lo: i64,
        hi: i64,
    },
    /// `size` 4 is Single, 8 is Real/Double.
    Real,
    /// `string[max]`.
    String {
        max: u8,
    },
    Pointer {
        target: Option<u32>,
    },
    Array {
        index: u32,
        lo: i64,
        hi: i64,
        elem: u32,
    },
    OpenArray {
        elem: u32,
    },
    OpenString,
    Record {
        fields: Vec<FieldInfo>,
    },
    Set {
        base: u32,
        first_byte: u32,
    },
    File {
        elem: Option<u32>,
    },
    Procedural,
    Nil,
    Untyped,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FieldInfo {
    pub name: String,
    pub ty: u32,
    pub offset: u64,
}

// ---- writing -------------------------------------------------------------------

fn obj(pairs: Vec<(&str, Value)>) -> Value {
    Value::Object(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect::<BTreeMap<_, _>>())
}

fn int(v: impl TryInto<i64>) -> Value {
    Value::Int(v.try_into().unwrap_or(i64::MAX))
}

fn opt(v: Option<u32>) -> Value {
    v.map(int).unwrap_or(Value::Null)
}

fn string(s: &str) -> Value {
    Value::Str(s.to_string())
}

impl LocalKind {
    fn to_value(self) -> Value {
        match self {
            LocalKind::Param => string("param"),
            LocalKind::Var => string("var"),
            LocalKind::Result => string("result"),
            LocalKind::High(i) => obj(vec![("high", int(i))]),
            LocalKind::Temp => string("temp"),
        }
    }

    fn from_value(v: &Value) -> Result<Self, String> {
        if let Some(i) = v.get("high").and_then(Value::as_i64) {
            return Ok(LocalKind::High(i as u32));
        }
        Ok(match v.as_str() {
            Some("param") => LocalKind::Param,
            Some("var") => LocalKind::Var,
            Some("result") => LocalKind::Result,
            Some("temp") => LocalKind::Temp,
            _ => return Err("jenis local tidak dikenal".into()),
        })
    }
}

impl TypeKind {
    fn to_value(&self) -> Value {
        let mut pairs = vec![];
        let kind = match self {
            TypeKind::Int { signed } => {
                pairs.push(("signed", Value::Bool(*signed)));
                "int"
            }
            TypeKind::Bool => "bool",
            TypeKind::Char => "char",
            TypeKind::Enum { names } => {
                pairs.push(("names", Value::Array(names.iter().map(|n| string(n)).collect())));
                "enum"
            }
            TypeKind::Subrange { base, lo, hi } => {
                pairs.extend([("base", int(*base)), ("lo", int(*lo)), ("hi", int(*hi))]);
                "subrange"
            }
            TypeKind::Real => "real",
            TypeKind::String { max } => {
                pairs.push(("max", int(*max)));
                "string"
            }
            TypeKind::Pointer { target } => {
                pairs.push(("target", opt(*target)));
                "pointer"
            }
            TypeKind::Array { index, lo, hi, elem } => {
                pairs.extend([("index", int(*index)), ("lo", int(*lo)), ("hi", int(*hi)), ("elem", int(*elem))]);
                "array"
            }
            TypeKind::OpenArray { elem } => {
                pairs.push(("elem", int(*elem)));
                "openarray"
            }
            TypeKind::OpenString => "openstring",
            TypeKind::Record { fields } => {
                let list = fields
                    .iter()
                    .map(|f| obj(vec![("name", string(&f.name)), ("type", int(f.ty)), ("offset", int(f.offset))]))
                    .collect();
                pairs.push(("fields", Value::Array(list)));
                "record"
            }
            TypeKind::Set { base, first_byte } => {
                pairs.extend([("base", int(*base)), ("first_byte", int(*first_byte))]);
                "set"
            }
            TypeKind::File { elem } => {
                pairs.push(("elem", opt(*elem)));
                "file"
            }
            TypeKind::Procedural => "procedural",
            TypeKind::Nil => "nil",
            TypeKind::Untyped => "untyped",
        };
        pairs.push(("kind", string(kind)));
        obj(pairs)
    }
}

impl DebugInfo {
    pub fn to_json(&self) -> String {
        let pair = |a: u32, b: u32| Value::Array(vec![int(a), int(b)]);
        let routines = self
            .routines
            .iter()
            .map(|r| {
                let locals = r
                    .locals
                    .iter()
                    .map(|l| {
                        obj(vec![
                            ("name", string(&l.name)),
                            ("type", int(l.ty)),
                            ("kind", l.kind.to_value()),
                            ("offset", int(l.offset)),
                            ("indirect", Value::Bool(l.indirect)),
                        ])
                    })
                    .collect();
                obj(vec![
                    ("name", string(&r.name)),
                    ("symbol", string(&r.symbol)),
                    ("parent", opt(r.parent)),
                    ("file", int(r.file)),
                    ("line", int(r.line)),
                    ("instrumented", Value::Bool(r.instrumented)),
                    ("static_link", r.static_link.map(int).unwrap_or(Value::Null)),
                    ("locals", Value::Array(locals)),
                ])
            })
            .collect();
        let globals = self
            .globals
            .iter()
            .map(|g| {
                obj(vec![
                    ("name", string(&g.name)),
                    ("scope", string(&g.scope)),
                    ("type", int(g.ty)),
                    ("address", int(g.address)),
                ])
            })
            .collect();
        let types = self
            .types
            .iter()
            .map(|t| {
                let Value::Object(mut map) = t.kind.to_value() else { unreachable!() };
                map.insert("size".into(), int(t.size));
                if let Some(name) = &t.name {
                    map.insert("name".into(), string(name));
                }
                Value::Object(map)
            })
            .collect();
        obj(vec![
            ("version", int(VERSION)),
            ("files", Value::Array(self.files.iter().map(|f| string(f)).collect())),
            ("image_base", int(self.image_base)),
            ("anchor", int(self.anchor)),
            ("stack", int(self.stack)),
            ("lines", Value::Array(self.lines.iter().map(|&(f, l)| pair(f, l)).collect())),
            (
                "addresses",
                Value::Array(
                    self.addresses.iter().map(|&(a, f, l)| Value::Array(vec![int(a), int(f), int(l)])).collect(),
                ),
            ),
            ("routines", Value::Array(routines)),
            ("globals", Value::Array(globals)),
            ("types", Value::Array(types)),
        ])
        .to_json()
    }

    /// The source line of the statement containing link-time `address`.
    pub fn line_at(&self, address: u64) -> Option<(u32, u32)> {
        let i = self.addresses.partition_point(|&(a, _, _)| a <= address);
        let &(_, file, line) = self.addresses.get(i.checked_sub(1)?)?;
        Some((file, line))
    }
}

// ---- reading -------------------------------------------------------------------

fn field<'a>(v: &'a Value, key: &str) -> Result<&'a Value, String> {
    v.get(key).ok_or_else(|| format!(".odbg: field `{key}` hilang"))
}

fn num(v: &Value, key: &str) -> Result<i64, String> {
    field(v, key)?.as_i64().ok_or_else(|| format!(".odbg: `{key}` bukan bilangan"))
}

fn text(v: &Value, key: &str) -> Result<String, String> {
    Ok(field(v, key)?.as_str().ok_or_else(|| format!(".odbg: `{key}` bukan teks"))?.to_string())
}

fn list<'a>(v: &'a Value, key: &str) -> Result<&'a [Value], String> {
    field(v, key)?.as_array().ok_or_else(|| format!(".odbg: `{key}` bukan array"))
}

fn opt_num(v: &Value, key: &str) -> Option<i64> {
    v.get(key).and_then(Value::as_i64)
}

fn type_kind(v: &Value) -> Result<TypeKind, String> {
    let u = |key: &str| num(v, key).map(|n| n as u32);
    Ok(match text(v, "kind")?.as_str() {
        "int" => TypeKind::Int { signed: field(v, "signed")?.as_bool().unwrap_or(true) },
        "bool" => TypeKind::Bool,
        "char" => TypeKind::Char,
        "enum" => {
            TypeKind::Enum { names: list(v, "names")?.iter().map(|n| n.as_str().unwrap_or("?").to_string()).collect() }
        }
        "subrange" => TypeKind::Subrange { base: u("base")?, lo: num(v, "lo")?, hi: num(v, "hi")? },
        "real" => TypeKind::Real,
        "string" => TypeKind::String { max: num(v, "max")? as u8 },
        "pointer" => TypeKind::Pointer { target: opt_num(v, "target").map(|n| n as u32) },
        "array" => TypeKind::Array { index: u("index")?, lo: num(v, "lo")?, hi: num(v, "hi")?, elem: u("elem")? },
        "openarray" => TypeKind::OpenArray { elem: u("elem")? },
        "openstring" => TypeKind::OpenString,
        "record" => TypeKind::Record {
            fields: list(v, "fields")?
                .iter()
                .map(|f| {
                    Ok(FieldInfo {
                        name: text(f, "name")?,
                        ty: num(f, "type")? as u32,
                        offset: num(f, "offset")? as u64,
                    })
                })
                .collect::<Result<_, String>>()?,
        },
        "set" => TypeKind::Set { base: u("base")?, first_byte: u("first_byte")? },
        "file" => TypeKind::File { elem: opt_num(v, "elem").map(|n| n as u32) },
        "procedural" => TypeKind::Procedural,
        "nil" => TypeKind::Nil,
        "untyped" => TypeKind::Untyped,
        other => return Err(format!(".odbg: jenis tipe `{other}` tidak dikenal")),
    })
}

impl DebugInfo {
    pub fn from_json(source: &str) -> Result<DebugInfo, String> {
        let v = json::parse(source)?;
        if num(&v, "version")? != VERSION {
            return Err(".odbg: versi tidak didukung; build ulang program".into());
        }
        let pair = |item: &Value| -> Result<Vec<i64>, String> {
            item.as_array()
                .ok_or(".odbg: entri bukan array")?
                .iter()
                .map(|n| n.as_i64().ok_or_else(|| ".odbg: entri bukan bilangan".to_string()))
                .collect()
        };
        let lines = list(&v, "lines")?
            .iter()
            .map(|item| pair(item).map(|p| (p[0] as u32, p[1] as u32)))
            .collect::<Result<_, _>>()?;
        let addresses = list(&v, "addresses")?
            .iter()
            .map(|item| pair(item).map(|p| (p[0] as u64, p[1] as u32, p[2] as u32)))
            .collect::<Result<_, _>>()?;
        let routines = list(&v, "routines")?
            .iter()
            .map(|r| {
                let locals = list(r, "locals")?
                    .iter()
                    .map(|l| {
                        Ok(LocalInfo {
                            name: text(l, "name")?,
                            ty: num(l, "type")? as u32,
                            kind: LocalKind::from_value(field(l, "kind")?)?,
                            offset: num(l, "offset")? as i32,
                            indirect: field(l, "indirect")?.as_bool().unwrap_or(false),
                        })
                    })
                    .collect::<Result<_, String>>()?;
                Ok(RoutineInfo {
                    name: text(r, "name")?,
                    symbol: text(r, "symbol")?,
                    parent: opt_num(r, "parent").map(|n| n as u32),
                    file: num(r, "file")? as u32,
                    line: num(r, "line")? as u32,
                    instrumented: field(r, "instrumented")?.as_bool().unwrap_or(false),
                    static_link: opt_num(r, "static_link").map(|n| n as i32),
                    locals,
                })
            })
            .collect::<Result<_, String>>()?;
        let globals = list(&v, "globals")?
            .iter()
            .map(|g| {
                Ok(GlobalInfo {
                    name: text(g, "name")?,
                    scope: text(g, "scope")?,
                    ty: num(g, "type")? as u32,
                    address: num(g, "address")? as u64,
                })
            })
            .collect::<Result<_, String>>()?;
        let types = list(&v, "types")?
            .iter()
            .map(|t| {
                Ok(TypeInfo {
                    name: t.get("name").and_then(Value::as_str).map(str::to_string),
                    size: num(t, "size")? as u64,
                    kind: type_kind(t)?,
                })
            })
            .collect::<Result<_, String>>()?;
        Ok(DebugInfo {
            files: list(&v, "files")?.iter().map(|f| f.as_str().unwrap_or("").to_string()).collect(),
            image_base: num(&v, "image_base")? as u64,
            anchor: num(&v, "anchor")? as u64,
            stack: num(&v, "stack")? as u64,
            lines,
            addresses,
            routines,
            globals,
            types,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let info = DebugInfo {
            files: vec!["/a/B.PAS".into()],
            image_base: 0x1_0000_0000,
            anchor: 0x1_0000_4000,
            stack: 0x1_0000_5000,
            lines: vec![(0, 4), (0, 6)],
            addresses: vec![(0x1_0000_1000, 0, 4), (0x1_0000_1010, 0, 6)],
            routines: vec![RoutineInfo {
                name: "F".into(),
                symbol: "$PROGRAM.F".into(),
                parent: None,
                file: 0,
                line: 3,
                instrumented: true,
                static_link: None,
                locals: vec![
                    LocalInfo { name: "N".into(), ty: 1, kind: LocalKind::Param, offset: -16, indirect: false },
                    LocalInfo { name: "$high".into(), ty: 1, kind: LocalKind::High(0), offset: -24, indirect: false },
                ],
            }],
            globals: vec![GlobalInfo { name: "I".into(), scope: "$PROGRAM".into(), ty: 1, address: 0x1_0000_6000 }],
            types: vec![
                TypeInfo { name: Some("Integer".into()), size: 2, kind: TypeKind::Int { signed: true } },
                TypeInfo {
                    name: None,
                    size: 4,
                    kind: TypeKind::Record { fields: vec![FieldInfo { name: "X".into(), ty: 0, offset: 2 }] },
                },
                TypeInfo { name: None, size: 8, kind: TypeKind::Pointer { target: None } },
            ],
        };
        let back = DebugInfo::from_json(&info.to_json()).unwrap();
        assert_eq!(back, info);
        assert_eq!(info.line_at(0x1_0000_100f), Some((0, 4)));
        assert_eq!(info.line_at(0x1_0000_1010), Some((0, 6)));
        assert_eq!(info.line_at(0x1_0000_0fff), None);
    }
}
