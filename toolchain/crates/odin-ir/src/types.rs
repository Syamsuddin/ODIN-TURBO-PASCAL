// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Type table: every Pascal type of a compilation, with sizes and layout.
//!
//! Layout follows FPC `-Mtp` on 64-bit targets (the behaviour Odin 1.0
//! users already know): natural record alignment, Integer = 2 bytes,
//! Real = Double, pointers 8 bytes, sets packed like TP.

/// Index into a [`TypeTable`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct TypeId(pub u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct IntKind {
    /// Size in bytes: 1, 2, 4 or 8.
    pub size: u8,
    pub signed: bool,
}

impl IntKind {
    pub fn min(self) -> i64 {
        if !self.signed {
            0
        } else if self.size >= 8 {
            i64::MIN
        } else {
            -(1i64 << (self.size * 8 - 1))
        }
    }

    pub fn max(self) -> i64 {
        match (self.size, self.signed) {
            (8, _) => i64::MAX,
            (s, true) => (1i64 << (s * 8 - 1)) - 1,
            (s, false) => (1i64 << (s * 8)) - 1,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RealKind {
    Single,
    Double,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ParamMode {
    Value,
    Var,
    Const,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Param {
    pub name: String,
    pub mode: ParamMode,
    pub ty: TypeId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Signature {
    pub params: Vec<Param>,
    pub result: Option<TypeId>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub name: String,
    pub ty: TypeId,
    pub offset: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MethodKind {
    Procedure,
    Function,
    Constructor,
    Destructor,
}

/// A method visible in an object type (declared there or inherited).
#[derive(Clone, Debug, PartialEq)]
pub struct Method {
    pub name: String,
    pub routine: crate::hir::RoutineId,
    pub kind: MethodKind,
    /// VMT slot of a virtual method.
    pub slot: Option<u32>,
    pub private: bool,
    /// The object type whose declaration introduced or overrode it.
    pub owner: TypeId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ObjectType {
    pub parent: Option<TypeId>,
    /// Inherited fields first, then the object's own.
    pub fields: Vec<Field>,
    /// Upper-case names of private fields (own and inherited).
    pub private_fields: Vec<String>,
    /// Inherited methods (replaced by overrides), then new ones.
    pub methods: Vec<Method>,
    pub size: u64,
    pub align: u32,
    /// Offset of the VMT pointer, when the type has one (constructors,
    /// destructors or virtual methods anywhere in the hierarchy).
    pub vmt_offset: Option<u64>,
    /// The global (index into `Program::globals`) holding the VMT: size,
    /// -size, parent VMT, then one code pointer per slot.
    pub vmt: Option<u32>,
    pub slots: u32,
    /// Unit (index) or program (`None`) declaring the type: private members
    /// are visible only there.
    pub module: Option<usize>,
}

impl ObjectType {
    pub fn method(&self, key: &str) -> Option<&Method> {
        self.methods.iter().find(|m| m.name.eq_ignore_ascii_case(key))
    }

    pub fn field(&self, key: &str) -> Option<&Field> {
        self.fields.iter().find(|f| f.name.eq_ignore_ascii_case(key))
    }
}

/// Bytes of a VMT before the method slots.
pub const VMT_HEADER: u64 = 24;

#[derive(Clone, Debug, PartialEq)]
pub enum Type {
    Int(IntKind),
    Bool,
    Char,
    /// Enumeration with ordinals `0..names.len()`.
    Enum {
        names: Vec<String>,
    },
    /// Subrange of an ordinal base type.
    Subrange {
        base: TypeId,
        lo: i64,
        hi: i64,
    },
    Real(RealKind),
    /// `string[max]`: a length byte followed by `max` characters.
    ShortString(u8),
    /// Typed pointer, or untyped `Pointer` when `None`.
    Pointer(Option<TypeId>),
    Array {
        index: TypeId,
        lo: i64,
        hi: i64,
        elem: TypeId,
    },
    /// `array of T`, only as a parameter type: passed as address + high.
    OpenArray {
        elem: TypeId,
    },
    /// `OpenString` (or `var S: String` under `{$P+}`): a string parameter
    /// passed as address + maximum length of the actual variable.
    OpenString,
    Record {
        fields: Vec<Field>,
        size: u64,
        align: u32,
    },
    /// A Turbo Pascal `object`.
    Object(Box<ObjectType>),
    /// Set of an ordinal type. Bit `v - first_byte * 8` of byte
    /// `v / 8 - first_byte` is set for member `v`.
    Set {
        base: TypeId,
        first_byte: u32,
        size: u32,
    },
    /// `file` / `file of T`; storage is the RTL's `FileRec` record.
    File {
        elem: Option<TypeId>,
        rec: TypeId,
    },
    Procedural(Signature),
    /// Type of the `nil` literal.
    Nil,
    /// Untyped `var`/`const` parameter.
    Untyped,
}

#[derive(Clone, Debug)]
struct Entry {
    ty: Type,
    name: Option<String>,
}

/// Well-known types created by [`TypeTable::new`].
#[derive(Clone, Copy, Debug)]
pub struct Builtins {
    pub shortint: TypeId,
    pub smallint: TypeId,
    pub longint: TypeId,
    pub int64: TypeId,
    pub byte: TypeId,
    pub word: TypeId,
    pub longword: TypeId,
    pub qword: TypeId,
    pub boolean: TypeId,
    pub char: TypeId,
    pub single: TypeId,
    pub double: TypeId,
    pub string: TypeId,
    pub pointer: TypeId,
    pub pchar: TypeId,
    pub nil: TypeId,
    pub untyped: TypeId,
    pub openstring: TypeId,
}

pub struct TypeTable {
    entries: Vec<Entry>,
    pub builtin: Builtins,
}

impl Default for TypeTable {
    fn default() -> Self {
        Self::new()
    }
}

impl TypeTable {
    pub fn new() -> Self {
        let mut t = TypeTable { entries: Vec::new(), builtin: placeholder_builtins() };
        let int = |size, signed| Type::Int(IntKind { size, signed });
        let shortint = t.add_named(int(1, true), "ShortInt");
        let smallint = t.add_named(int(2, true), "Integer");
        let longint = t.add_named(int(4, true), "LongInt");
        let int64 = t.add_named(int(8, true), "Int64");
        let byte = t.add_named(int(1, false), "Byte");
        let word = t.add_named(int(2, false), "Word");
        let longword = t.add_named(int(4, false), "LongWord");
        let qword = t.add_named(int(8, false), "QWord");
        let boolean = t.add_named(Type::Bool, "Boolean");
        let char = t.add_named(Type::Char, "Char");
        let single = t.add_named(Type::Real(RealKind::Single), "Single");
        let double = t.add_named(Type::Real(RealKind::Double), "Real");
        let string = t.add_named(Type::ShortString(255), "String");
        let pointer = t.add_named(Type::Pointer(None), "Pointer");
        let pchar = t.add_named(Type::Pointer(Some(char)), "PChar");
        let nil = t.add_named(Type::Nil, "Nil");
        let untyped = t.add_named(Type::Untyped, "Untyped");
        let openstring = t.add_named(Type::OpenString, "OpenString");
        t.builtin = Builtins {
            shortint,
            smallint,
            longint,
            int64,
            byte,
            word,
            longword,
            qword,
            boolean,
            char,
            single,
            double,
            string,
            pointer,
            pchar,
            nil,
            untyped,
            openstring,
        };
        t
    }

    pub fn add(&mut self, ty: Type) -> TypeId {
        self.entries.push(Entry { ty, name: None });
        TypeId(self.entries.len() as u32 - 1)
    }

    pub fn add_named(&mut self, ty: Type, name: &str) -> TypeId {
        self.entries.push(Entry { ty, name: Some(name.to_string()) });
        TypeId(self.entries.len() as u32 - 1)
    }

    /// Replaces a placeholder created for a forward pointer target or a
    /// record being laid out.
    pub fn set(&mut self, id: TypeId, ty: Type) {
        self.entries[id.0 as usize].ty = ty;
    }

    pub fn set_name(&mut self, id: TypeId, name: &str) {
        let e = &mut self.entries[id.0 as usize];
        if e.name.is_none() {
            e.name = Some(name.to_string());
        }
    }

    pub fn get(&self, id: TypeId) -> &Type {
        &self.entries[id.0 as usize].ty
    }

    pub fn name(&self, id: TypeId) -> Option<&str> {
        self.entries[id.0 as usize].name.as_deref()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Strips subranges: the type that carries the representation.
    pub fn base(&self, id: TypeId) -> TypeId {
        match self.get(id) {
            Type::Subrange { base, .. } => self.base(*base),
            _ => id,
        }
    }

    pub fn size(&self, id: TypeId) -> u64 {
        match self.get(id) {
            Type::Int(k) => k.size as u64,
            Type::Bool | Type::Char => 1,
            Type::Enum { names } => {
                if names.len() <= 256 {
                    1
                } else if names.len() <= 65536 {
                    2
                } else {
                    4
                }
            }
            Type::Subrange { base, lo, hi } => {
                // Like FPC: a subrange of an integer type uses the smallest
                // integer size that holds both bounds.
                match self.get(self.base(*base)) {
                    Type::Int(_) => smallest_int(*lo, *hi).size as u64,
                    _ => self.size(*base),
                }
            }
            Type::Real(RealKind::Single) => 4,
            Type::Real(RealKind::Double) => 8,
            Type::ShortString(max) => *max as u64 + 1,
            Type::Pointer(_) | Type::Procedural(_) | Type::Nil => 8,
            Type::Array { lo, hi, elem, .. } => {
                let count = (*hi - *lo + 1).max(0) as u64;
                count * self.size(*elem)
            }
            Type::OpenArray { .. } | Type::OpenString | Type::Untyped => 0,
            Type::Record { size, .. } => *size,
            Type::Object(o) => o.size,
            Type::Set { size, .. } => *size as u64,
            Type::File { rec, .. } => self.size(*rec),
        }
    }

    pub fn align(&self, id: TypeId) -> u32 {
        match self.get(id) {
            Type::Int(_) | Type::Bool | Type::Char | Type::Enum { .. } | Type::Subrange { .. } => {
                self.size(id).max(1) as u32
            }
            Type::Real(RealKind::Single) => 4,
            Type::Real(RealKind::Double) => 8,
            Type::ShortString(_) => 1,
            Type::Pointer(_) | Type::Procedural(_) | Type::Nil => 8,
            Type::Array { elem, .. } | Type::OpenArray { elem } => self.align(*elem),
            Type::Record { align, .. } => *align,
            Type::Object(o) => o.align,
            Type::Set { size, .. } => match size {
                1 | 2 | 4 | 8 => *size,
                _ => 1,
            },
            Type::File { rec, .. } => self.align(*rec),
            Type::Untyped | Type::OpenString => 1,
        }
    }

    pub fn is_ordinal(&self, id: TypeId) -> bool {
        matches!(self.get(self.base(id)), Type::Int(_) | Type::Bool | Type::Char | Type::Enum { .. })
    }

    pub fn is_integer(&self, id: TypeId) -> bool {
        matches!(self.get(self.base(id)), Type::Int(_))
    }

    pub fn is_real(&self, id: TypeId) -> bool {
        matches!(self.get(id), Type::Real(_))
    }

    pub fn is_string(&self, id: TypeId) -> bool {
        matches!(self.get(id), Type::ShortString(_) | Type::OpenString)
    }

    pub fn is_pointer(&self, id: TypeId) -> bool {
        matches!(self.get(id), Type::Pointer(_) | Type::Nil)
    }

    /// Lowest and highest ordinal value of an ordinal type.
    pub fn bounds(&self, id: TypeId) -> (i64, i64) {
        match self.get(id) {
            Type::Int(k) => (k.min(), k.max()),
            Type::Bool => (0, 1),
            Type::Char => (0, 255),
            Type::Enum { names } => (0, names.len() as i64 - 1),
            Type::Subrange { lo, hi, .. } => (*lo, *hi),
            _ => (0, 0),
        }
    }

    /// Integer representation of an ordinal type's storage.
    pub fn int_kind(&self, id: TypeId) -> IntKind {
        match self.get(id) {
            Type::Int(k) => *k,
            Type::Subrange { lo, hi, base } => match self.get(self.base(*base)) {
                Type::Int(_) => smallest_int(*lo, *hi),
                _ => self.int_kind(*base),
            },
            Type::Enum { .. } => IntKind { size: self.size(id) as u8, signed: false },
            Type::Bool | Type::Char => IntKind { size: 1, signed: false },
            _ => IntKind { size: 8, signed: false },
        }
    }

    /// A readable name for diagnostics.
    pub fn display(&self, id: TypeId) -> String {
        if let Some(n) = self.name(id) {
            return n.to_string();
        }
        match self.get(id) {
            Type::Int(k) => format!("{}{}", if k.signed { "Int" } else { "UInt" }, k.size * 8),
            Type::Bool => "Boolean".into(),
            Type::Char => "Char".into(),
            Type::Enum { names } => format!("({})", names.join(", ")),
            Type::Subrange { lo, hi, base } => match self.get(self.base(*base)) {
                Type::Char => format!("#{lo}..#{hi}"),
                _ => format!("{lo}..{hi}"),
            },
            Type::Real(RealKind::Single) => "Single".into(),
            Type::Real(RealKind::Double) => "Real".into(),
            Type::ShortString(255) => "String".into(),
            Type::ShortString(n) => format!("String[{n}]"),
            Type::Pointer(None) => "Pointer".into(),
            Type::Pointer(Some(t)) => format!("^{}", self.display(*t)),
            Type::Array { lo, hi, elem, .. } => format!("Array[{lo}..{hi}] of {}", self.display(*elem)),
            Type::OpenArray { elem } => format!("Array of {}", self.display(*elem)),
            Type::OpenString => "OpenString".into(),
            Type::Record { .. } => "Record".into(),
            Type::Object(_) => "Object".into(),
            Type::Set { base, .. } => format!("Set of {}", self.display(*base)),
            Type::File { elem: Some(e), .. } => format!("File of {}", self.display(*e)),
            Type::File { elem: None, .. } => "File".into(),
            Type::Procedural(s) => {
                if s.result.is_some() {
                    "Function".into()
                } else {
                    "Procedure".into()
                }
            }
            Type::Nil => "Nil".into(),
            Type::Untyped => "Untyped".into(),
        }
    }

    /// Lays out a record: natural alignment, total size rounded up to the
    /// record's alignment. Variant parts share `variant_offset`.
    /// `packed record`: fields one after another, no padding, alignment 1
    /// (as FPC lays them out).
    pub fn layout_fields_packed(&self, fields: &[(String, TypeId)], start: u64) -> (Vec<Field>, u64, u32) {
        let mut offset = start;
        let mut out = Vec::new();
        for (name, ty) in fields {
            out.push(Field { name: name.clone(), ty: *ty, offset });
            offset += self.size(*ty);
        }
        (out, offset, 1)
    }

    pub fn layout_fields(&self, fields: &[(String, TypeId)], start: u64) -> (Vec<Field>, u64, u32) {
        let mut offset = start;
        let mut align = 1u32;
        let mut out = Vec::new();
        for (name, ty) in fields {
            let a = self.align(*ty).max(1);
            align = align.max(a);
            offset = offset.div_ceil(a as u64) * a as u64;
            out.push(Field { name: name.clone(), ty: *ty, offset });
            offset += self.size(*ty);
        }
        (out, offset, align)
    }

    /// Set layout for an ordinal base type with ordinals `lo..=hi` (TP
    /// packing: whole bytes from `lo div 8` to `hi div 8`).
    pub fn set_layout(lo: i64, hi: i64) -> (u32, u32) {
        let first = (lo.max(0) / 8) as u32;
        let last = (hi.clamp(0, 255) / 8) as u32;
        (first, last - first + 1)
    }
}

/// The smallest FPC integer type holding `lo..=hi`.
pub fn smallest_int(lo: i64, hi: i64) -> IntKind {
    for (size, signed) in [(1u8, false), (1, true), (2, false), (2, true), (4, false), (4, true), (8, true)] {
        let k = IntKind { size, signed };
        if lo >= k.min() && hi <= k.max() {
            return k;
        }
    }
    IntKind { size: 8, signed: true }
}

fn placeholder_builtins() -> Builtins {
    let z = TypeId(0);
    Builtins {
        shortint: z,
        smallint: z,
        longint: z,
        int64: z,
        byte: z,
        word: z,
        longword: z,
        qword: z,
        boolean: z,
        char: z,
        single: z,
        double: z,
        string: z,
        pointer: z,
        pchar: z,
        nil: z,
        untyped: z,
        openstring: z,
    }
}

impl TypeTable {
    pub fn object(&self, id: TypeId) -> Option<&ObjectType> {
        match self.get(id) {
            Type::Object(o) => Some(o),
            _ => None,
        }
    }

    /// Whether object type `ty` is `ancestor` or derives from it.
    pub fn is_descendant(&self, ty: TypeId, ancestor: TypeId) -> bool {
        let mut cur = Some(ty);
        while let Some(t) = cur {
            if t == ancestor {
                return true;
            }
            cur = self.object(t).and_then(|o| o.parent);
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_match_fpc_tp_mode() {
        let mut t = TypeTable::new();
        let b = t.builtin;
        // record a: byte; b: integer end = 4
        let (_, size, align) = t.layout_fields(&[("a".into(), b.byte), ("b".into(), b.smallint)], 0);
        assert_eq!((size.div_ceil(align as u64) * align as u64, align), (4, 2));
        // record a: byte; b: longint; c: byte end = 12
        let (_, size, align) =
            t.layout_fields(&[("a".into(), b.byte), ("b".into(), b.longint), ("c".into(), b.byte)], 0);
        assert_eq!(size.div_ceil(align as u64) * align as u64, 12);
        // record a: byte; d: real end = 16
        let (_, size, align) = t.layout_fields(&[("a".into(), b.byte), ("d".into(), b.double)], 0);
        assert_eq!(size.div_ceil(align as u64) * align as u64, 16);
        assert_eq!(TypeTable::set_layout(0, 31), (0, 4));
        assert_eq!(TypeTable::set_layout(0, 255), (0, 32));
        assert_eq!(TypeTable::set_layout(1, 10), (0, 2));
        assert_eq!(TypeTable::set_layout(0, 2), (0, 1));
        assert_eq!(t.size(b.string), 256);
        let e = t.add(Type::Enum { names: vec!["x".into(), "y".into(), "z".into()] });
        assert_eq!(t.size(e), 1);
        let sub = t.add(Type::Subrange { base: b.smallint, lo: 0, hi: 9 });
        assert_eq!(t.size(sub), 1);
        assert_eq!(t.size(b.pointer), 8);
    }

    #[test]
    fn int_bounds() {
        assert_eq!(IntKind { size: 2, signed: true }.min(), -32768);
        assert_eq!(IntKind { size: 2, signed: true }.max(), 32767);
        assert_eq!(IntKind { size: 4, signed: false }.max(), 4294967295);
        assert_eq!(smallest_int(-1, 200), IntKind { size: 2, signed: true });
    }
}
