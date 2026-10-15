// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Evaluates Pascal expressions over a stopped program's memory, using the
//! types and frame layouts of `.odbg`, and formats values the way the
//! Turbo Pascal debugger shows them: `'abc'`, `(1, 2, 3)`, `(X:1; Y:2)`,
//! `[1, 3..5]`, `TRUE`, `PTR($...)`, enumeration names.
//!
//! Variables, fields, indices (bounds-checked), `^`, `@`, arithmetic,
//! comparisons, typecasts and `Ord`/`Chr`/`Length`/`High`/`Low`/`SizeOf`
//! (plus a few more pure builtins) are supported. Calls of program
//! routines are not: they would run code in the stopped program.

use odin_base::SourceMap;
use odin_debuginfo::{DebugInfo, FieldInfo, LocalKind, TypeKind};
use odin_syntax::ast::{self, BinOp, ExprKind, UnOp};
use odin_syntax::{LexOptions, Switches, parse_expression, tokenize};

pub type EResult<T> = Result<T, String>;

/// Access to the stopped program's memory (run-time addresses).
pub trait Memory {
    fn read(&mut self, addr: u64, len: usize) -> EResult<Vec<u8>>;
    fn write(&mut self, addr: u64, bytes: &[u8]) -> EResult<()>;
}

/// A frame of the stopped program: routine index and frame pointer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Frame {
    pub routine: u32,
    pub fp: u64,
}

/// The type of a value: an `.odbg` type or one made up by the evaluator.
#[derive(Clone, Debug, PartialEq)]
pub enum Ty {
    Id(u32),
    Int,
    Real,
    Bool,
    Char,
    Str,
    Nil,
    Pointer(Option<u32>),
    /// An open array parameter: elements `0..=high`.
    OpenArray {
        elem: u32,
        high: i64,
    },
    /// An open string parameter of capacity `max`.
    OpenStr {
        max: u8,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub enum Data {
    Int(i64),
    Real(f64),
    Str(Vec<u8>),
    Ptr(u64),
    /// A structured value; its contents stay in memory at the address.
    Mem,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Val {
    pub ty: Ty,
    pub data: Data,
    /// Where the value lives (variables, fields, elements).
    pub addr: Option<u64>,
}

impl Val {
    fn computed(ty: Ty, data: Data) -> Val {
        Val { ty, data, addr: None }
    }
}

/// Ordinal view of a type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum OrdClass {
    Int,
    Bool,
    Char,
    Enum(u32),
}

#[derive(Clone, Copy, Debug)]
struct Ord {
    class: OrdClass,
    lo: i64,
    hi: i64,
    size: u64,
    signed: bool,
}

/// Elements shown before an array or set is cut short with `...`.
const MAX_ITEMS: usize = 100;

/// Parses one Pascal expression.
pub fn parse(text: &str) -> EResult<ast::Expr> {
    let mut map = SourceMap::new();
    let file = map.add("<ekspresi>", text.as_bytes().to_vec());
    let options = LexOptions { defines: Default::default(), switches: Switches::tp_default(), include_paths: vec![] };
    let lexed = tokenize(&mut map, file, &options).map_err(|d| d.message)?;
    parse_expression(&lexed.tokens).map_err(|d| d.message)
}

pub struct Evaluator<'a, M: Memory> {
    pub info: &'a DebugInfo,
    /// Run-time address minus link-time address.
    pub slide: i64,
    /// The frame names are looked up in; `None` means globals only.
    pub frame: Option<Frame>,
    pub mem: &'a mut M,
}

fn upper(s: &str) -> String {
    s.to_ascii_uppercase()
}

impl<'a, M: Memory> Evaluator<'a, M> {
    // ---- public entry points --------------------------------------------------

    /// Evaluates `text` and formats the result: (value, type name).
    pub fn evaluate(&mut self, text: &str) -> EResult<(String, String)> {
        let e = parse(text)?;
        let v = self.eval(&e)?;
        Ok((self.format(&v)?, self.type_name(&v.ty)))
    }

    /// Stores `value` into the variable `target`; returns the new value as
    /// [`Evaluator::evaluate`] does.
    pub fn modify(&mut self, target: &str, value: &str) -> EResult<(String, String)> {
        let t = self.eval(&parse(target)?)?;
        let Some(addr) = t.addr else {
            return Err("Hanya variabel yang bisa diubah".into());
        };
        let v = self.eval(&parse(value)?)?;
        let bytes = self.encode(&v, &t.ty)?;
        self.mem.write(addr, &bytes)?;
        let back = self.load(addr, t.ty.clone())?;
        Ok((self.format(&back)?, self.type_name(&back.ty)))
    }

    /// The parameters, variables and result of the frame's routine.
    pub fn locals(&mut self) -> EResult<Vec<(String, String, String)>> {
        let Some(frame) = self.frame else { return Ok(Vec::new()) };
        let info = self.info;
        let routine = &info.routines[frame.routine as usize];
        let mut out = Vec::new();
        for (i, l) in routine.locals.iter().enumerate() {
            let name = match l.kind {
                // Hidden parameters ($vmt of constructors) stay hidden.
                LocalKind::Param if l.name.starts_with('$') => continue,
                LocalKind::Param | LocalKind::Var => l.name.clone(),
                LocalKind::Result => routine.name.rsplit('.').next().unwrap_or("Result").to_string(),
                _ => continue,
            };
            let text = match self.local(frame, i).and_then(|v| self.format(&v)) {
                Ok(t) => t,
                Err(e) => format!("<{e}>"),
            };
            let ty = self.local(frame, i).map(|v| self.type_name(&v.ty)).unwrap_or_default();
            out.push((name, text, ty));
        }
        Ok(out)
    }

    // ---- memory -------------------------------------------------------------------

    fn read_u64(&mut self, addr: u64) -> EResult<u64> {
        let b = self.mem.read(addr, 8)?;
        Ok(u64::from_le_bytes(b[..8].try_into().unwrap()))
    }

    fn runtime(&self, link_addr: u64) -> u64 {
        (link_addr as i64).wrapping_add(self.slide) as u64
    }

    // ---- types -------------------------------------------------------------------

    fn ty_kind(&self, id: u32) -> &'a TypeKind {
        &self.info.types[id as usize].kind
    }

    fn size(&self, ty: &Ty) -> u64 {
        match ty {
            Ty::Id(id) => self.info.types[*id as usize].size,
            Ty::Int | Ty::Real | Ty::Pointer(_) | Ty::Nil => 8,
            Ty::Bool | Ty::Char => 1,
            Ty::Str => 256,
            Ty::OpenArray { elem, high } => self.size(&Ty::Id(*elem)) * (*high as u64 + 1),
            Ty::OpenStr { max } => *max as u64 + 1,
        }
    }

    fn ord(&self, ty: &Ty) -> Option<Ord> {
        Some(match ty {
            Ty::Int => Ord { class: OrdClass::Int, lo: i64::MIN, hi: i64::MAX, size: 8, signed: true },
            Ty::Bool => Ord { class: OrdClass::Bool, lo: 0, hi: 1, size: 1, signed: false },
            Ty::Char => Ord { class: OrdClass::Char, lo: 0, hi: 255, size: 1, signed: false },
            Ty::Id(id) => {
                let size = self.info.types[*id as usize].size;
                match self.ty_kind(*id) {
                    TypeKind::Int { signed } => {
                        let (lo, hi) = int_range(size, *signed);
                        Ord { class: OrdClass::Int, lo, hi, size, signed: *signed }
                    }
                    TypeKind::Bool => Ord { class: OrdClass::Bool, lo: 0, hi: 1, size, signed: false },
                    TypeKind::Char => Ord { class: OrdClass::Char, lo: 0, hi: 255, size: 1, signed: false },
                    TypeKind::Enum { names } => {
                        Ord { class: OrdClass::Enum(*id), lo: 0, hi: names.len() as i64 - 1, size, signed: false }
                    }
                    TypeKind::Subrange { base, lo, hi } => {
                        let b = self.ord(&Ty::Id(*base))?;
                        Ord { class: b.class, lo: *lo, hi: *hi, size, signed: *lo < 0 }
                    }
                    _ => return None,
                }
            }
            _ => return None,
        })
    }

    fn is_real(&self, ty: &Ty) -> bool {
        match ty {
            Ty::Real => true,
            Ty::Id(id) => matches!(self.ty_kind(*id), TypeKind::Real),
            _ => false,
        }
    }

    fn string_max(&self, ty: &Ty) -> Option<u8> {
        match ty {
            Ty::Str => Some(255),
            Ty::OpenStr { max } => Some(*max),
            Ty::Id(id) => match self.ty_kind(*id) {
                TypeKind::String { max } => Some(*max),
                _ => None,
            },
            _ => None,
        }
    }

    fn pointer_target(&self, ty: &Ty) -> Option<Option<u32>> {
        match ty {
            Ty::Pointer(t) => Some(*t),
            Ty::Nil => Some(None),
            Ty::Id(id) => match self.ty_kind(*id) {
                TypeKind::Pointer { target } => Some(*target),
                TypeKind::Procedural => Some(None),
                _ => None,
            },
            _ => None,
        }
    }

    /// `(lo, hi, element type)` of an array value.
    fn array(&self, ty: &Ty) -> Option<(i64, i64, u32, Option<u32>)> {
        match ty {
            Ty::OpenArray { elem, high } => Some((0, *high, *elem, None)),
            Ty::Id(id) => match self.ty_kind(*id) {
                TypeKind::Array { index, lo, hi, elem } => Some((*lo, *hi, *elem, Some(*index))),
                _ => None,
            },
            _ => None,
        }
    }

    pub fn type_name(&self, ty: &Ty) -> String {
        match ty {
            Ty::Int => "Int64".into(),
            Ty::Real => "Real".into(),
            Ty::Bool => "Boolean".into(),
            Ty::Char => "Char".into(),
            Ty::Str => "String".into(),
            Ty::Nil => "Pointer".into(),
            Ty::Pointer(None) => "Pointer".into(),
            Ty::Pointer(Some(t)) => format!("^{}", self.type_name(&Ty::Id(*t))),
            Ty::OpenArray { elem, .. } => format!("array of {}", self.type_name(&Ty::Id(*elem))),
            Ty::OpenStr { .. } => "OpenString".into(),
            Ty::Id(id) => {
                let t = &self.info.types[*id as usize];
                if let Some(name) = &t.name {
                    return name.clone();
                }
                match &t.kind {
                    TypeKind::Int { .. } => "Integer".into(),
                    TypeKind::Bool => "Boolean".into(),
                    TypeKind::Char => "Char".into(),
                    TypeKind::Enum { names } => format!("({})", names.join(", ")),
                    TypeKind::Subrange { base, lo, hi } => {
                        let b = Ty::Id(*base);
                        format!("{}..{}", self.ord_text(&b, *lo), self.ord_text(&b, *hi))
                    }
                    TypeKind::Real => if t.size == 4 { "Single" } else { "Real" }.into(),
                    TypeKind::String { max } => format!("string[{max}]"),
                    TypeKind::Pointer { target: None } => "Pointer".into(),
                    TypeKind::Pointer { target: Some(p) } => format!("^{}", self.type_name(&Ty::Id(*p))),
                    TypeKind::Array { index, elem, .. } => {
                        format!("array[{}] of {}", self.type_name(&Ty::Id(*index)), self.type_name(&Ty::Id(*elem)))
                    }
                    TypeKind::OpenArray { elem } => format!("array of {}", self.type_name(&Ty::Id(*elem))),
                    TypeKind::OpenString => "OpenString".into(),
                    TypeKind::Record { .. } => "record".into(),
                    TypeKind::Set { base, .. } => format!("set of {}", self.type_name(&Ty::Id(*base))),
                    TypeKind::File { elem: Some(e) } => format!("file of {}", self.type_name(&Ty::Id(*e))),
                    TypeKind::File { elem: None } => "file".into(),
                    TypeKind::Procedural => "procedure".into(),
                    TypeKind::Nil => "Pointer".into(),
                    TypeKind::Untyped => "untyped".into(),
                }
            }
        }
    }

    fn named_type(&self, name: &str) -> Option<u32> {
        let key = upper(name);
        if key == "STRING" {
            return self.info.types.iter().position(|t| t.kind == TypeKind::String { max: 255 }).map(|i| i as u32);
        }
        self.info.types.iter().position(|t| t.name.as_deref().is_some_and(|n| upper(n) == key)).map(|i| i as u32)
    }

    // ---- loading and storing ---------------------------------------------------

    pub fn load(&mut self, addr: u64, ty: Ty) -> EResult<Val> {
        let data = if let Some(o) = self.ord(&ty) {
            let b = self.mem.read(addr, o.size as usize)?;
            Data::Int(decode_int(&b, o.signed))
        } else if self.is_real(&ty) {
            let size = self.size(&ty);
            let b = self.mem.read(addr, size as usize)?;
            Data::Real(if size == 4 {
                f32::from_le_bytes(b[..4].try_into().unwrap()) as f64
            } else {
                f64::from_le_bytes(b[..8].try_into().unwrap())
            })
        } else if let Some(max) = self.string_max(&ty) {
            let len = (self.mem.read(addr, 1)?[0]).min(max) as usize;
            Data::Str(if len > 0 { self.mem.read(addr + 1, len)? } else { Vec::new() })
        } else if self.pointer_target(&ty).is_some() {
            Data::Ptr(self.read_u64(addr)?)
        } else {
            Data::Mem
        };
        Ok(Val { ty, data, addr: Some(addr) })
    }

    /// Bytes of `v` converted to type `ty` (Modify).
    fn encode(&mut self, v: &Val, ty: &Ty) -> EResult<Vec<u8>> {
        if let Some(o) = self.ord(ty) {
            let n = self.ordinal(v)?;
            let class = self.ord(&v.ty).map(|x| x.class);
            let compatible = match (o.class, class) {
                (OrdClass::Int, Some(OrdClass::Int)) => true,
                (a, Some(b)) => a == b,
                _ => false,
            };
            if !compatible {
                return Err(format!("Tipe tidak cocok: {} dan {}", self.type_name(ty), self.type_name(&v.ty)));
            }
            if n < o.lo || n > o.hi {
                return Err(format!("Nilai di luar jangkauan {}..{}", o.lo, o.hi));
            }
            return Ok(n.to_le_bytes()[..o.size as usize].to_vec());
        }
        if self.is_real(ty) {
            let x = match &v.data {
                Data::Int(n) if self.ord(&v.ty).is_some_and(|o| o.class == OrdClass::Int) => *n as f64,
                Data::Real(x) => *x,
                _ => return Err("Bilangan diharapkan".into()),
            };
            return Ok(if self.size(ty) == 4 { (x as f32).to_le_bytes().to_vec() } else { x.to_le_bytes().to_vec() });
        }
        if let Some(max) = self.string_max(ty) {
            let mut s = self.string_value(v)?;
            s.truncate(max as usize);
            let mut out = vec![s.len() as u8];
            out.extend(s);
            return Ok(out);
        }
        if self.pointer_target(ty).is_some() {
            return match (&v.data, self.pointer_target(&v.ty)) {
                (Data::Ptr(p), Some(_)) => Ok(p.to_le_bytes().to_vec()),
                _ => Err("Pointer diharapkan".into()),
            };
        }
        Err("Variabel bertipe ini tidak bisa diubah; ubah elemen atau field-nya".into())
    }

    // ---- names -------------------------------------------------------------------

    fn local(&mut self, frame: Frame, index: usize) -> EResult<Val> {
        let info = self.info;
        let routine = &info.routines[frame.routine as usize];
        let l = &routine.locals[index];
        let slot = (frame.fp as i64 + l.offset as i64) as u64;
        let addr = if l.indirect { self.read_u64(slot)? } else { slot };
        let ty = match self.ty_kind(l.ty) {
            TypeKind::OpenArray { elem } => {
                let high = self.high_of(frame, index)?;
                Ty::OpenArray { elem: *elem, high }
            }
            TypeKind::OpenString => {
                let high = self.high_of(frame, index)?;
                Ty::OpenStr { max: high.clamp(0, 255) as u8 }
            }
            _ => Ty::Id(l.ty),
        };
        // A method's Self is a pointer to the object; show the object.
        if l.kind == LocalKind::Param
            && l.name == "Self"
            && let TypeKind::Pointer { target: Some(object) } = self.ty_kind(l.ty)
        {
            let object = *object;
            let p = self.read_u64(addr)?;
            return self.load(p, Ty::Id(object));
        }
        self.load(addr, ty)
    }

    /// The hidden `High` value of open parameter `index`.
    fn high_of(&mut self, frame: Frame, index: usize) -> EResult<i64> {
        let info = self.info;
        let routine = &info.routines[frame.routine as usize];
        let Some(h) = routine.locals.iter().find(|l| l.kind == LocalKind::High(index as u32)) else {
            return Ok(0);
        };
        let addr = (frame.fp as i64 + h.offset as i64) as u64;
        Ok(self.read_u64(addr)? as i64)
    }

    fn global(&mut self, scope: Option<&str>, key: &str) -> EResult<Option<Val>> {
        let info = self.info;
        let found = info.globals.iter().find(|g| upper(&g.name) == key && scope.is_none_or(|s| g.scope == s));
        match found {
            Some(g) => {
                let addr = self.runtime(g.address);
                Ok(Some(self.load(addr, Ty::Id(g.ty))?))
            }
            None => Ok(None),
        }
    }

    fn lookup(&mut self, ident: &ast::Ident) -> EResult<Val> {
        let key = ident.key();
        // Locals of the frame's routine, then of its lexical parents.
        let mut frame = self.frame;
        while let Some(f) = frame {
            let info = self.info;
            let routine = &info.routines[f.routine as usize];
            let short = upper(routine.name.rsplit('.').next().unwrap_or(""));
            for (i, l) in routine.locals.iter().enumerate() {
                let hit = match l.kind {
                    LocalKind::Param | LocalKind::Var => upper(&l.name) == key,
                    LocalKind::Result => key == "RESULT" || key == short,
                    _ => false,
                };
                if hit {
                    return self.local(f, i);
                }
            }
            // Inside a method, the fields of Self by their bare names.
            if let Some(si) = routine.locals.iter().position(|l| l.kind == LocalKind::Param && l.name == "Self") {
                let object = self.local(f, si)?;
                if let (Ty::Id(id), Some(base)) = (&object.ty, object.addr)
                    && let TypeKind::Record { fields } = self.ty_kind(*id)
                    && let Some(field) = fields.iter().find(|x| upper(&x.name) == key)
                {
                    return self.load(base + field.offset, Ty::Id(field.ty));
                }
            }
            if let Some(v) = self.global(Some(&routine.symbol), &key)? {
                return Ok(v);
            }
            frame = match (routine.parent, routine.static_link) {
                (Some(parent), Some(link)) => {
                    let fp = self.read_u64((f.fp as i64 + link as i64) as u64)?;
                    Some(Frame { routine: parent, fp })
                }
                _ => None,
            };
        }
        if let Some(v) = self.global(Some("$PROGRAM"), &key)? {
            return Ok(v);
        }
        if let Some(v) = self.global(None, &key)? {
            return Ok(v);
        }
        match key.as_str() {
            "TRUE" => return Ok(Val::computed(Ty::Bool, Data::Int(1))),
            "FALSE" => return Ok(Val::computed(Ty::Bool, Data::Int(0))),
            "MAXINT" => return Ok(Val::computed(Ty::Int, Data::Int(32767))),
            "MAXLONGINT" => return Ok(Val::computed(Ty::Int, Data::Int(i32::MAX as i64))),
            _ => {}
        }
        for (id, t) in self.info.types.iter().enumerate() {
            if let TypeKind::Enum { names } = &t.kind
                && let Some(n) = names.iter().position(|n| upper(n) == key)
            {
                return Ok(Val::computed(Ty::Id(id as u32), Data::Int(n as i64)));
            }
        }
        Err(format!("Identifier tidak dikenal: {}", ident.name))
    }

    // ---- expressions -----------------------------------------------------------------

    pub fn eval(&mut self, e: &ast::Expr) -> EResult<Val> {
        match &e.kind {
            ExprKind::Int(n) => Ok(Val::computed(Ty::Int, Data::Int(*n as i64))),
            ExprKind::Real(x) => Ok(Val::computed(Ty::Real, Data::Real(*x))),
            ExprKind::Str(s) if s.len() == 1 => Ok(Val::computed(Ty::Char, Data::Int(s[0] as i64))),
            ExprKind::Str(s) => Ok(Val::computed(Ty::Str, Data::Str(s.clone()))),
            ExprKind::Nil => Ok(Val::computed(Ty::Nil, Data::Ptr(0))),
            ExprKind::Name(id) => self.lookup(id),
            ExprKind::Field { base, field } => self.field(base, field),
            ExprKind::Index { base, indices } => {
                let mut v = self.eval(base)?;
                for i in indices {
                    let index = self.eval(i)?;
                    v = self.index(v, &index)?;
                }
                Ok(v)
            }
            ExprKind::Deref(base) => {
                let p = self.eval(base)?;
                let Some(target) = self.pointer_target(&p.ty) else {
                    return Err("Pointer diharapkan".into());
                };
                let Data::Ptr(addr) = p.data else { return Err("Pointer diharapkan".into()) };
                let Some(target) = target else {
                    return Err("Pointer tanpa tipe tidak bisa diikuti; pakai typecast".into());
                };
                if addr == 0 {
                    return Err("Pointer bernilai NIL".into());
                }
                self.load(addr, Ty::Id(target))
            }
            ExprKind::Unary(op, x) => self.unary(*op, x),
            ExprKind::Binary(op, l, r) => {
                let l = self.eval(l)?;
                let r = self.eval(r)?;
                self.binary(*op, &l, &r)
            }
            ExprKind::Call { callee, args } => self.call(callee, args),
            ExprKind::Set(_) => Err("Konstruktor set tidak didukung di sini".into()),
            ExprKind::Inherited(_) | ExprKind::StringType => Err("Ekspresi tidak didukung".into()),
        }
    }

    fn field(&mut self, base: &ast::Expr, field: &ast::Ident) -> EResult<Val> {
        // `Unit.Name`: a unit-qualified global (the program's own name
        // qualifies its globals too).
        if let ExprKind::Name(unit) = &base.kind
            && self.lookup(unit).is_err()
        {
            let found = match self.global(Some(&unit.key()), &field.key())? {
                Some(v) => Some(v),
                None => self.global(Some("$PROGRAM"), &field.key())?,
            };
            return found.ok_or_else(|| format!("Identifier tidak dikenal: {}.{}", unit.name, field.name));
        }
        let v = self.eval(base)?;
        let Ty::Id(id) = v.ty else { return Err("Record diharapkan".into()) };
        let TypeKind::Record { fields } = self.ty_kind(id) else {
            return Err("Record diharapkan".into());
        };
        let key = field.key();
        let Some(f) = fields.iter().find(|f| upper(&f.name) == key) else {
            return Err(format!("Field tidak dikenal: {}", field.name));
        };
        let Some(addr) = v.addr else { return Err("Record tanpa alamat".into()) };
        self.load(addr + f.offset, Ty::Id(f.ty))
    }

    fn index(&mut self, v: Val, index: &Val) -> EResult<Val> {
        let i = self.ordinal(index)?;
        if let Some(max) = self.string_max(&v.ty) {
            if i < 0 || i > max as i64 {
                return Err(format!("Indeks di luar batas 0..{max}"));
            }
            return match (v.addr, &v.data) {
                (Some(addr), _) => self.load(addr + i as u64, Ty::Char),
                (None, Data::Str(s)) => {
                    let c = if i == 0 { s.len() as u8 } else { s.get(i as usize - 1).copied().unwrap_or(0) };
                    Ok(Val::computed(Ty::Char, Data::Int(c as i64)))
                }
                _ => Err("String diharapkan".into()),
            };
        }
        let Some((lo, hi, elem, _)) = self.array(&v.ty) else {
            return Err("Array atau string diharapkan".into());
        };
        if i < lo || i > hi {
            return Err(format!("Indeks di luar batas {lo}..{hi}"));
        }
        let Some(addr) = v.addr else { return Err("Array tanpa alamat".into()) };
        let size = self.size(&Ty::Id(elem));
        self.load(addr + (i - lo) as u64 * size, Ty::Id(elem))
    }

    fn ordinal(&self, v: &Val) -> EResult<i64> {
        match (&v.data, self.ord(&v.ty)) {
            (Data::Int(n), Some(_)) => Ok(*n),
            _ => Err("Ekspresi ordinal diharapkan".into()),
        }
    }

    fn real(&self, v: &Val) -> EResult<f64> {
        match &v.data {
            Data::Real(x) => Ok(*x),
            Data::Int(n) if self.ord(&v.ty).is_some_and(|o| o.class == OrdClass::Int) => Ok(*n as f64),
            _ => Err("Bilangan diharapkan".into()),
        }
    }

    fn int(&self, v: &Val) -> EResult<i64> {
        match (&v.data, self.ord(&v.ty)) {
            (Data::Int(n), Some(o)) if o.class == OrdClass::Int => Ok(*n),
            _ => Err("Integer diharapkan".into()),
        }
    }

    fn boolean(&self, v: &Val) -> Option<bool> {
        match (&v.data, self.ord(&v.ty)) {
            (Data::Int(n), Some(o)) if o.class == OrdClass::Bool => Some(*n != 0),
            _ => None,
        }
    }

    fn string_value(&self, v: &Val) -> EResult<Vec<u8>> {
        match (&v.data, self.ord(&v.ty)) {
            (Data::Str(s), _) => Ok(s.clone()),
            (Data::Int(n), Some(o)) if o.class == OrdClass::Char => Ok(vec![*n as u8]),
            _ => Err("String diharapkan".into()),
        }
    }

    fn unary(&mut self, op: UnOp, x: &ast::Expr) -> EResult<Val> {
        if op == UnOp::AddrOf {
            let v = self.eval(x)?;
            let Some(addr) = v.addr else { return Err("Variabel diharapkan".into()) };
            let target = if let Ty::Id(id) = v.ty { Some(id) } else { None };
            return Ok(Val::computed(Ty::Pointer(target), Data::Ptr(addr)));
        }
        let v = self.eval(x)?;
        match op {
            UnOp::Pos => Ok(v),
            UnOp::Neg => match v.data {
                Data::Real(r) => Ok(Val::computed(Ty::Real, Data::Real(-r))),
                _ => Ok(Val::computed(Ty::Int, Data::Int(self.int(&v)?.wrapping_neg()))),
            },
            UnOp::Not => match self.boolean(&v) {
                Some(b) => Ok(Val::computed(Ty::Bool, Data::Int(!b as i64))),
                None => Ok(Val::computed(Ty::Int, Data::Int(!self.int(&v)?))),
            },
            UnOp::AddrOf => unreachable!(),
        }
    }

    fn binary(&mut self, op: BinOp, l: &Val, r: &Val) -> EResult<Val> {
        use std::cmp::Ordering;
        let bool_val = |b: bool| Val::computed(Ty::Bool, Data::Int(b as i64));
        if op == BinOp::In {
            return self.member(l, r).map(bool_val);
        }
        let reals = matches!(l.data, Data::Real(_)) || matches!(r.data, Data::Real(_));
        let compare = matches!(op, BinOp::Eq | BinOp::Ne | BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge);
        if compare {
            let ord = if let (Some(a), Some(b)) = (self.pointer_target(&l.ty), self.pointer_target(&r.ty)) {
                let _ = (a, b);
                let (Data::Ptr(x), Data::Ptr(y)) = (&l.data, &r.data) else { unreachable!() };
                if !matches!(op, BinOp::Eq | BinOp::Ne) {
                    return Err("Pointer hanya bisa dibandingkan dengan = dan <>".into());
                }
                x.cmp(y)
            } else if reals {
                self.real(l)?.partial_cmp(&self.real(r)?).unwrap_or(Ordering::Less)
            } else if self.string_max(&l.ty).is_some() || self.string_max(&r.ty).is_some() {
                self.string_value(l)?.cmp(&self.string_value(r)?)
            } else {
                let (a, b) = (self.ordinal(l)?, self.ordinal(r)?);
                let (ca, cb) = (self.ord(&l.ty).unwrap().class, self.ord(&r.ty).unwrap().class);
                if ca != cb {
                    return Err("Tipe tidak cocok".into());
                }
                a.cmp(&b)
            };
            return Ok(bool_val(match op {
                BinOp::Eq => ord == Ordering::Equal,
                BinOp::Ne => ord != Ordering::Equal,
                BinOp::Lt => ord == Ordering::Less,
                BinOp::Le => ord != Ordering::Greater,
                BinOp::Gt => ord == Ordering::Greater,
                _ => ord != Ordering::Less,
            }));
        }
        if let (Some(a), Some(b)) = (self.boolean(l), self.boolean(r)) {
            return match op {
                BinOp::And => Ok(bool_val(a && b)),
                BinOp::Or => Ok(bool_val(a || b)),
                BinOp::Xor => Ok(bool_val(a != b)),
                _ => Err("Operator tidak berlaku untuk Boolean".into()),
            };
        }
        if op == BinOp::Add && (self.string_max(&l.ty).is_some() || self.string_max(&r.ty).is_some()) {
            let mut s = self.string_value(l)?;
            s.extend(self.string_value(r)?);
            s.truncate(255);
            return Ok(Val::computed(Ty::Str, Data::Str(s)));
        }
        if op == BinOp::RealDiv || (reals && matches!(op, BinOp::Add | BinOp::Sub | BinOp::Mul)) {
            let (a, b) = (self.real(l)?, self.real(r)?);
            if op == BinOp::RealDiv && b == 0.0 {
                return Err("Pembagian dengan nol".into());
            }
            let x = match op {
                BinOp::Add => a + b,
                BinOp::Sub => a - b,
                BinOp::Mul => a * b,
                _ => a / b,
            };
            return Ok(Val::computed(Ty::Real, Data::Real(x)));
        }
        let (a, b) = (self.int(l)?, self.int(r)?);
        let n = match op {
            BinOp::Add => a.wrapping_add(b),
            BinOp::Sub => a.wrapping_sub(b),
            BinOp::Mul => a.wrapping_mul(b),
            BinOp::Div | BinOp::Mod if b == 0 => return Err("Pembagian dengan nol".into()),
            BinOp::Div => a.wrapping_div(b),
            BinOp::Mod => a.wrapping_rem(b),
            BinOp::And => a & b,
            BinOp::Or => a | b,
            BinOp::Xor => a ^ b,
            BinOp::Shl => a.wrapping_shl(b as u32),
            BinOp::Shr => ((a as u64).wrapping_shr(b as u32)) as i64,
            _ => return Err("Operator tidak didukung".into()),
        };
        Ok(Val::computed(Ty::Int, Data::Int(n)))
    }

    fn member(&mut self, l: &Val, r: &Val) -> EResult<bool> {
        let n = self.ordinal(l)?;
        let Ty::Id(id) = r.ty else { return Err("Set diharapkan".into()) };
        let TypeKind::Set { first_byte, .. } = self.ty_kind(id) else {
            return Err("Set diharapkan".into());
        };
        let size = self.info.types[id as usize].size;
        let Some(addr) = r.addr else { return Err("Set tanpa alamat".into()) };
        let byte = n / 8 - *first_byte as i64;
        if byte < 0 || byte >= size as i64 {
            return Ok(false);
        }
        let b = self.mem.read(addr + byte as u64, 1)?[0];
        Ok(b >> (n % 8) & 1 != 0)
    }

    fn call(&mut self, callee: &ast::Expr, args: &[ast::Arg]) -> EResult<Val> {
        let ExprKind::Name(name) = &callee.kind else {
            return Err("Pemanggilan fungsi tidak didukung di debugger".into());
        };
        let key = name.key();
        let one = |args: &[ast::Arg]| -> EResult<()> {
            if args.len() == 1 { Ok(()) } else { Err(format!("{} memerlukan satu argumen", name.name)) }
        };
        // SizeOf/High/Low accept a type name where no variable has that name.
        let type_arg = |this: &mut Self, a: &ast::Arg| -> Option<Ty> {
            if let ExprKind::Name(n) = &a.value.kind
                && this.lookup(n).is_err()
            {
                return this.named_type(&n.name).map(Ty::Id);
            }
            None
        };
        match key.as_str() {
            "ORD" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                Ok(Val::computed(Ty::Int, Data::Int(self.ordinal(&v)?)))
            }
            "CHR" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                Ok(Val::computed(Ty::Char, Data::Int(self.int(&v)? & 255)))
            }
            "ODD" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                Ok(Val::computed(Ty::Bool, Data::Int(self.int(&v)? & 1)))
            }
            "ABS" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                match v.data {
                    Data::Real(x) => Ok(Val::computed(Ty::Real, Data::Real(x.abs()))),
                    _ => Ok(Val::computed(Ty::Int, Data::Int(self.int(&v)?.wrapping_abs()))),
                }
            }
            "TRUNC" | "ROUND" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                let x = self.real(&v)?;
                let n = if key == "TRUNC" { x.trunc() } else { x.round_ties_even() };
                Ok(Val::computed(Ty::Int, Data::Int(n as i64)))
            }
            "SUCC" | "PRED" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                let n = self.ordinal(&v)? + if key == "SUCC" { 1 } else { -1 };
                Ok(Val::computed(v.ty, Data::Int(n)))
            }
            "LENGTH" => {
                one(args)?;
                let v = self.eval(&args[0].value)?;
                if let Some((lo, hi, _, _)) = self.array(&v.ty) {
                    return Ok(Val::computed(Ty::Int, Data::Int(hi - lo + 1)));
                }
                Ok(Val::computed(Ty::Int, Data::Int(self.string_value(&v)?.len() as i64)))
            }
            "SIZEOF" => {
                one(args)?;
                let ty = match type_arg(self, &args[0]) {
                    Some(t) => t,
                    None => self.eval(&args[0].value)?.ty,
                };
                Ok(Val::computed(Ty::Int, Data::Int(self.size(&ty) as i64)))
            }
            "HIGH" | "LOW" => {
                one(args)?;
                let ty = match type_arg(self, &args[0]) {
                    Some(t) => t,
                    None => self.eval(&args[0].value)?.ty,
                };
                let high = key == "HIGH";
                if let Some((lo, hi, _, index)) = self.array(&ty) {
                    let n = if high { hi } else { lo };
                    let t = index.map(Ty::Id).unwrap_or(Ty::Int);
                    return Ok(Val::computed(t, Data::Int(n)));
                }
                if let Some(max) = self.string_max(&ty) {
                    return Ok(Val::computed(Ty::Int, Data::Int(if high { max as i64 } else { 0 })));
                }
                let Some(o) = self.ord(&ty) else { return Err("Tipe ordinal, array, atau string diharapkan".into()) };
                Ok(Val::computed(ty, Data::Int(if high { o.hi } else { o.lo })))
            }
            _ => {
                let Some(target) = self.named_type(&name.name) else {
                    return Err("Pemanggilan fungsi tidak didukung di debugger".into());
                };
                one(args)?;
                let v = self.eval(&args[0].value)?;
                self.cast(v, Ty::Id(target))
            }
        }
    }

    /// `T(x)`: ordinal and pointer conversions, or a variable seen as `T`.
    fn cast(&mut self, v: Val, target: Ty) -> EResult<Val> {
        if let Some(o) = self.ord(&target)
            && let Ok(n) = self.ordinal(&v)
        {
            let bits = o.size * 8;
            let n = if bits >= 64 {
                n
            } else if o.signed {
                (n << (64 - bits)) >> (64 - bits)
            } else {
                n & ((1i64 << bits) - 1)
            };
            return Ok(Val { ty: target, data: Data::Int(n), addr: v.addr });
        }
        if self.pointer_target(&target).is_some() {
            if let Data::Ptr(p) = v.data {
                return Ok(Val { ty: target, data: Data::Ptr(p), addr: v.addr });
            }
            if let Data::Int(n) = v.data {
                return Ok(Val::computed(target, Data::Ptr(n as u64)));
            }
        }
        match v.addr {
            Some(addr) if self.size(&v.ty) == self.size(&target) => self.load(addr, target),
            _ => Err("Typecast tidak valid".into()),
        }
    }

    // ---- formatting -----------------------------------------------------------------

    fn ord_text(&self, ty: &Ty, n: i64) -> String {
        match self.ord(ty).map(|o| o.class) {
            Some(OrdClass::Bool) => if n != 0 { "TRUE" } else { "FALSE" }.into(),
            Some(OrdClass::Char) => char_literal(n as u8),
            Some(OrdClass::Enum(id)) => match self.ty_kind(id) {
                TypeKind::Enum { names } => names.get(n as usize).cloned().unwrap_or_else(|| n.to_string()),
                _ => n.to_string(),
            },
            _ => n.to_string(),
        }
    }

    pub fn format(&mut self, v: &Val) -> EResult<String> {
        match &v.data {
            Data::Int(n) => Ok(self.ord_text(&v.ty, *n)),
            Data::Real(x) => Ok(real_text(*x)),
            Data::Str(s) => Ok(string_literal(s)),
            Data::Ptr(0) => Ok("NIL".into()),
            Data::Ptr(p) => Ok(format!("PTR(${p:X})")),
            Data::Mem => self.format_mem(v),
        }
    }

    fn format_mem(&mut self, v: &Val) -> EResult<String> {
        let addr = v.addr.unwrap_or(0);
        if let Some((lo, hi, elem, _)) = self.array(&v.ty) {
            let size = self.size(&Ty::Id(elem));
            if matches!(self.ty_kind(elem), TypeKind::Char) && hi >= lo {
                let n = ((hi - lo + 1) as usize).min(255);
                return Ok(string_literal(&self.mem.read(addr, n)?));
            }
            let mut items = Vec::new();
            for i in lo..=hi {
                if items.len() == MAX_ITEMS {
                    items.push("...".to_string());
                    break;
                }
                let e = self.load(addr + (i - lo) as u64 * size, Ty::Id(elem))?;
                items.push(self.format(&e)?);
            }
            return Ok(format!("({})", items.join(", ")));
        }
        let Ty::Id(id) = v.ty else { return Ok("?".into()) };
        match self.ty_kind(id) {
            TypeKind::Record { fields } => {
                let fields: Vec<FieldInfo> = fields.clone();
                let mut items = Vec::new();
                for f in &fields {
                    let e = self.load(addr + f.offset, Ty::Id(f.ty))?;
                    items.push(format!("{}:{}", f.name, self.format(&e)?));
                }
                Ok(format!("({})", items.join("; ")))
            }
            TypeKind::Set { base, first_byte } => {
                let size = self.info.types[id as usize].size as usize;
                let bytes = self.mem.read(addr, size)?;
                let base = Ty::Id(*base);
                let first = *first_byte as i64 * 8;
                let members: Vec<i64> = (0..size as i64 * 8)
                    .filter(|b| bytes[(b / 8) as usize] >> (b % 8) & 1 != 0)
                    .map(|b| b + first)
                    .collect();
                let mut items = Vec::new();
                let mut i = 0;
                while i < members.len() {
                    let mut j = i;
                    while j + 1 < members.len() && members[j + 1] == members[j] + 1 {
                        j += 1;
                    }
                    if items.len() == MAX_ITEMS {
                        items.push("...".to_string());
                        break;
                    }
                    let start = self.ord_text(&base, members[i]);
                    items.push(if j > i + 1 {
                        format!("{start}..{}", self.ord_text(&base, members[j]))
                    } else if j == i + 1 {
                        format!("{start}, {}", self.ord_text(&base, members[j]))
                    } else {
                        start
                    });
                    i = j + 1;
                }
                Ok(format!("[{}]", items.join(", ")))
            }
            TypeKind::File { .. } => {
                // FileRec and TextRec keep the name at offset 48.
                let name = self.mem.read(addr + 48, 256)?;
                let end = name.iter().position(|&b| b == 0).unwrap_or(0);
                Ok(format!("(file {})", string_literal(&name[..end])))
            }
            _ => Ok("?".into()),
        }
    }
}

fn int_range(size: u64, signed: bool) -> (i64, i64) {
    match (size, signed) {
        (8, true) => (i64::MIN, i64::MAX),
        (8, false) => (0, i64::MAX),
        (s, true) => (-(1i64 << (s * 8 - 1)), (1i64 << (s * 8 - 1)) - 1),
        (s, false) => (0, (1i64 << (s * 8)) - 1),
    }
}

fn decode_int(b: &[u8], signed: bool) -> i64 {
    let mut raw = [0u8; 8];
    raw[..b.len()].copy_from_slice(b);
    let n = i64::from_le_bytes(raw);
    let bits = b.len() as u32 * 8;
    if bits >= 64 {
        n
    } else if signed {
        (n << (64 - bits)) >> (64 - bits)
    } else {
        n
    }
}

/// `'A'`, or `#13` for control characters.
fn char_literal(c: u8) -> String {
    if c == b'\'' {
        "''''".into()
    } else if (32..127).contains(&c) {
        format!("'{}'", c as char)
    } else {
        format!("#{c}")
    }
}

/// `'abc'`, `'it''s'`, `'ab'#13#10'cd'`, `''`.
pub fn string_literal(s: &[u8]) -> String {
    if s.is_empty() {
        return "''".into();
    }
    let mut out = String::new();
    let mut quoted = false;
    for &c in s {
        if (32..127).contains(&c) {
            if !quoted {
                out.push('\'');
                quoted = true;
            }
            if c == b'\'' {
                out.push_str("''");
            } else {
                out.push(c as char);
            }
        } else {
            if quoted {
                out.push('\'');
                quoted = false;
            }
            out.push_str(&format!("#{c}"));
        }
    }
    if quoted {
        out.push('\'');
    }
    out
}

/// Shortest text that reads back as the same Double, TP style exponent.
pub fn real_text(x: f64) -> String {
    if x.is_nan() {
        return "NAN".into();
    }
    if x.is_infinite() {
        return if x > 0.0 { "+INF".into() } else { "-INF".into() };
    }
    let a = x.abs();
    if a == 0.0 || (1e-4..1e15).contains(&a) {
        return format!("{x}");
    }
    let s = format!("{x:e}");
    let (mantissa, exp) = s.split_once('e').unwrap_or((&s, "0"));
    let exp: i32 = exp.parse().unwrap_or(0);
    format!("{mantissa}E{}{:02}", if exp < 0 { '-' } else { '+' }, exp.abs())
}

#[cfg(test)]
mod tests {
    use super::*;
    use odin_debuginfo::{GlobalInfo, LocalInfo, RoutineInfo, TypeInfo};

    struct Fake {
        bytes: Vec<u8>,
    }

    impl Memory for Fake {
        fn read(&mut self, addr: u64, len: usize) -> EResult<Vec<u8>> {
            let a = addr as usize;
            self.bytes.get(a..a + len).map(<[u8]>::to_vec).ok_or_else(|| "alamat tidak valid".to_string())
        }
        fn write(&mut self, addr: u64, bytes: &[u8]) -> EResult<()> {
            let a = addr as usize;
            self.bytes[a..a + bytes.len()].copy_from_slice(bytes);
            Ok(())
        }
    }

    fn ty(name: Option<&str>, size: u64, kind: TypeKind) -> TypeInfo {
        TypeInfo { name: name.map(str::to_string), size, kind }
    }

    /// Types: 0 Integer, 1 Char, 2 Boolean, 3 string, 4 array[1..3] of Integer,
    /// 5 record X,Y: Integer, 6 ^Integer, 7 (Red, Green, Blue), 8 set of 0..15,
    /// 9 Real, 10 Byte.
    fn info() -> DebugInfo {
        DebugInfo {
            types: vec![
                ty(Some("Integer"), 2, TypeKind::Int { signed: true }),
                ty(Some("Char"), 1, TypeKind::Char),
                ty(Some("Boolean"), 1, TypeKind::Bool),
                ty(Some("String"), 256, TypeKind::String { max: 255 }),
                ty(None, 6, TypeKind::Array { index: 0, lo: 1, hi: 3, elem: 0 }),
                ty(
                    Some("TPoint"),
                    4,
                    TypeKind::Record {
                        fields: vec![
                            FieldInfo { name: "X".into(), ty: 0, offset: 0 },
                            FieldInfo { name: "Y".into(), ty: 0, offset: 2 },
                        ],
                    },
                ),
                ty(None, 8, TypeKind::Pointer { target: Some(0) }),
                ty(Some("TColor"), 1, TypeKind::Enum { names: vec!["Red".into(), "Green".into(), "Blue".into()] }),
                ty(None, 2, TypeKind::Set { base: 0, first_byte: 0 }),
                ty(Some("Real"), 8, TypeKind::Real),
                ty(Some("Byte"), 1, TypeKind::Int { signed: false }),
            ],
            routines: vec![RoutineInfo {
                name: "F".into(),
                symbol: "$PROGRAM.F".into(),
                parent: None,
                file: 0,
                line: 1,
                instrumented: true,
                static_link: None,
                locals: vec![
                    LocalInfo { name: "N".into(), ty: 0, kind: LocalKind::Param, offset: -16, indirect: false },
                    LocalInfo { name: "Result".into(), ty: 0, kind: LocalKind::Result, offset: -18, indirect: false },
                ],
            }],
            globals: vec![
                GlobalInfo { name: "A".into(), scope: "$PROGRAM".into(), ty: 4, address: 100 },
                GlobalInfo { name: "P".into(), scope: "$PROGRAM".into(), ty: 5, address: 110 },
                GlobalInfo { name: "Q".into(), scope: "$PROGRAM".into(), ty: 6, address: 120 },
                GlobalInfo { name: "S".into(), scope: "$PROGRAM".into(), ty: 3, address: 200 },
                GlobalInfo { name: "C".into(), scope: "$PROGRAM".into(), ty: 7, address: 130 },
                GlobalInfo { name: "Bits".into(), scope: "$PROGRAM".into(), ty: 8, address: 132 },
                GlobalInfo { name: "R".into(), scope: "$PROGRAM".into(), ty: 9, address: 136 },
                GlobalInfo { name: "B".into(), scope: "$PROGRAM".into(), ty: 10, address: 144 },
            ],
            ..Default::default()
        }
    }

    fn memory() -> Fake {
        let mut bytes = vec![0u8; 1024];
        for (i, v) in [10i16, 20, 30].iter().enumerate() {
            bytes[100 + i * 2..102 + i * 2].copy_from_slice(&v.to_le_bytes());
        }
        bytes[110..112].copy_from_slice(&3i16.to_le_bytes());
        bytes[112..114].copy_from_slice(&(-4i16).to_le_bytes());
        bytes[120..128].copy_from_slice(&102u64.to_le_bytes());
        bytes[130] = 2;
        bytes[132] = 0b0011_1010;
        bytes[136..144].copy_from_slice(&2.5f64.to_le_bytes());
        bytes[200] = 5;
        bytes[201..206].copy_from_slice(b"it's\r");
        // frame at 600: N = 7 at 584, Result = 5040 at 582
        bytes[584..586].copy_from_slice(&7i16.to_le_bytes());
        bytes[582..584].copy_from_slice(&5040i16.to_le_bytes());
        Fake { bytes }
    }

    fn eval(text: &str) -> String {
        let info = info();
        let mut mem = memory();
        let mut e = Evaluator { info: &info, slide: 0, frame: Some(Frame { routine: 0, fp: 600 }), mem: &mut mem };
        match e.evaluate(text) {
            Ok((v, _)) => v,
            Err(m) => format!("error: {m}"),
        }
    }

    #[test]
    fn values_are_formatted_like_turbo_pascal() {
        assert_eq!(eval("A"), "(10, 20, 30)");
        assert_eq!(eval("P"), "(X:3; Y:-4)");
        assert_eq!(eval("S"), "'it''s'#13");
        assert_eq!(eval("C"), "Blue");
        assert_eq!(eval("Bits"), "[1, 3..5]");
        assert_eq!(eval("R"), "2.5");
        assert_eq!(eval("Q^"), "20");
        assert_eq!(eval("Q"), "PTR($66)");
        assert_eq!(eval("N"), "7");
        assert_eq!(eval("F"), "5040");
        assert_eq!(eval("S[1]"), "'i'");
        assert_eq!(eval("S[0]"), "#5");
        assert_eq!(eval("N * 2 + A[3]"), "44");
        assert_eq!(eval("N > 5"), "TRUE");
        assert_eq!(eval("(N > 5) and (C = Green)"), "FALSE");
        assert_eq!(eval("Ord(C)"), "2");
        assert_eq!(eval("Chr(65)"), "'A'");
        assert_eq!(eval("Length(S)"), "5");
        assert_eq!(eval("High(A)"), "3");
        assert_eq!(eval("SizeOf(TPoint)"), "4");
        assert_eq!(eval("TColor(1)"), "Green");
        assert_eq!(eval("Byte(-1)"), "255");
        assert_eq!(eval("3 in Bits"), "TRUE");
        assert_eq!(eval("R / 2"), "1.25");
        assert_eq!(eval("1e30"), "1E+30");
    }

    #[test]
    fn errors_are_explained() {
        assert_eq!(eval("A[4]"), "error: Indeks di luar batas 1..3");
        assert_eq!(eval("Zork"), "error: Identifier tidak dikenal: Zork");
        assert_eq!(eval("P.Z"), "error: Field tidak dikenal: Z");
        assert_eq!(eval("N div 0"), "error: Pembagian dengan nol");
        assert!(eval("N +").starts_with("error: "));
    }

    #[test]
    fn modify_checks_range_and_writes() {
        let info = info();
        let mut mem = memory();
        let mut e = Evaluator { info: &info, slide: 0, frame: Some(Frame { routine: 0, fp: 600 }), mem: &mut mem };
        assert_eq!(e.modify("N", "N + 1").unwrap().0, "8");
        assert_eq!(e.modify("A[2]", "99").unwrap().0, "99");
        assert_eq!(e.modify("S", "'hello'").unwrap().0, "'hello'");
        assert_eq!(e.modify("C", "Red").unwrap().0, "Red");
        assert_eq!(e.modify("R", "3").unwrap().0, "3");
        assert!(e.modify("B", "256").unwrap_err().contains("jangkauan"));
        assert!(e.modify("C", "1").unwrap_err().contains("Tipe tidak cocok"));
        assert!(e.modify("N + 1", "2").is_err());
        assert_eq!(e.evaluate("A").unwrap().0, "(10, 99, 30)");
        let locals = e.locals().unwrap();
        assert_eq!(locals[0], ("N".to_string(), "8".to_string(), "Integer".to_string()));
        assert_eq!(locals[1].0, "F");
    }
}
