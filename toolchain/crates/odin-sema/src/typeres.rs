// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Type expressions to [`TypeId`]s, record layout and type sections.

use std::collections::HashSet;

use odin_base::code;
use odin_ir::*;
use odin_syntax::ast;

use crate::scope::{ConstKind, ConstVal, Sym};
use crate::{Analyzer, SResult};

/// A pointer type whose target was not declared yet: `PNode = ^TNode`.
type PendingPointer = (TypeId, ast::QualIdent);

impl Analyzer<'_> {
    pub(crate) fn type_section(&mut self, items: &[ast::TypeDecl]) -> SResult<()> {
        let mut pending: Vec<PendingPointer> = Vec::new();
        for item in items {
            if let ast::TypeKind::Object(obj) = &item.ty.kind {
                // Declared first: methods may mention their own type.
                let ty = self.types.add(Type::Record { fields: Vec::new(), size: 0, align: 1 });
                self.types.set_name(ty, &item.name.name);
                self.declare(&item.name, Sym::Type(ty))?;
                self.object_type(ty, &item.name, obj)?;
                continue;
            }
            let ty = self.resolve_type_inner(&item.ty, Some(&mut pending))?;
            self.types.set_name(ty, &item.name.name);
            self.declare(&item.name, Sym::Type(ty))?;
        }
        for (ptr, q) in pending {
            match self.lookup_type(&q)? {
                Some(t) => self.types.set(ptr, Type::Pointer(Some(t))),
                None => {
                    return self.error_with(code::UNDEFINED_POINTER_TYPE, q.span(), format!(": {}", q.name.name));
                }
            }
        }
        Ok(())
    }

    /// `Some(type)` if the name denotes a type, `None` if it is undeclared,
    /// an error if it names something else.
    pub(crate) fn lookup_type(&self, q: &ast::QualIdent) -> SResult<Option<TypeId>> {
        let sym = match &q.unit {
            Some(u) => match self.lookup(&u.key()) {
                Some(Sym::Unit(i)) => self.units[i].interface.get(&q.name.key()).cloned(),
                _ => return self.error_with(code::UNKNOWN_IDENT, u.span, format!(": {}", u.name)),
            },
            None => self.lookup(&q.name.key()),
        };
        match sym {
            Some(Sym::Type(t)) => Ok(Some(t)),
            Some(_) => self.error(code::TYPE_IDENT_EXPECTED, q.span()),
            None => Ok(None),
        }
    }

    pub(crate) fn resolve_type(&mut self, t: &ast::TypeExpr) -> SResult<TypeId> {
        self.resolve_type_inner(t, None)
    }

    /// Parameter types may also be open arrays.
    pub(crate) fn resolve_param_type(&mut self, t: &ast::TypeExpr) -> SResult<TypeId> {
        if let ast::TypeKind::OpenArray(elem) = &t.kind {
            let elem = self.resolve_type(elem)?;
            return Ok(self.types.add(Type::OpenArray { elem }));
        }
        self.resolve_type(t)
    }

    fn ordinal_bounds(&self, ty: TypeId, span: odin_base::Span) -> SResult<(i64, i64)> {
        if !self.types.is_ordinal(ty) {
            return self.error(code::ORDINAL_TYPE_EXPECTED, span);
        }
        Ok(self.types.bounds(ty))
    }

    fn resolve_type_inner(&mut self, t: &ast::TypeExpr, pending: Option<&mut Vec<PendingPointer>>) -> SResult<TypeId> {
        let b = self.types.builtin;
        match &t.kind {
            ast::TypeKind::Named(q) => match self.lookup_type(q)? {
                Some(ty) => Ok(ty),
                None => self.error_with(code::UNKNOWN_IDENT, q.span(), format!(": {}", q.name.name)),
            },
            ast::TypeKind::String(None) => Ok(b.string),
            ast::TypeKind::String(Some(len)) => {
                let n = self.const_int(len)?;
                if !(1..=255).contains(&n) {
                    return self.error(code::BAD_STRING_LENGTH, len.span);
                }
                if n == 255 {
                    return Ok(b.string);
                }
                Ok(self.types.add(Type::ShortString(n as u8)))
            }
            ast::TypeKind::File(elem) => {
                let Some(rec) = self.filerec_type else {
                    return self.error_with(code::NOT_SUPPORTED, t.span, ": tipe file (FileRec belum ada di System)");
                };
                let elem = match elem {
                    Some(e) => Some(self.resolve_type(e)?),
                    None => None,
                };
                Ok(self.types.add(Type::File { elem, rec }))
            }
            ast::TypeKind::Subrange(lo, hi) => {
                let l = self.const_expr(lo)?;
                let h = self.const_expr(hi)?;
                let (ConstKind::Int(lv), ConstKind::Int(hv)) = (&l.kind, &h.kind) else {
                    return self.error(code::ORDINAL_TYPE_EXPECTED, lo.span);
                };
                let lb = self.types.base(l.ty);
                let hb = self.types.base(h.ty);
                let compatible = lb == hb || (self.types.is_integer(lb) && self.types.is_integer(hb));
                if !self.types.is_ordinal(lb) || !compatible {
                    return self.error(code::BAD_SUBRANGE_BASE, t.span);
                }
                if lv > hv {
                    return self.error(code::LOWER_GREATER_UPPER, t.span);
                }
                let base = if self.types.is_integer(lb) { b.int64 } else { lb };
                Ok(self.types.add(Type::Subrange { base, lo: *lv, hi: *hv }))
            }
            ast::TypeKind::Enum(names) => {
                let ty = self.types.add(Type::Enum { names: names.iter().map(|n| n.name.clone()).collect() });
                for (i, n) in names.iter().enumerate() {
                    self.declare(n, Sym::Const(ConstVal { kind: ConstKind::Int(i as i64), ty }))?;
                }
                Ok(ty)
            }
            ast::TypeKind::Array { index, elem, .. } => {
                let mut ty = self.resolve_type(elem)?;
                for ix in index.iter().rev() {
                    let it = self.resolve_type(ix)?;
                    let (lo, hi) = self.ordinal_bounds(it, ix.span)?;
                    let total = (hi as i128 - lo as i128 + 1) * self.types.size(ty) as i128;
                    if total > i32::MAX as i128 {
                        return self.error(code::STRUCTURE_TOO_LARGE, t.span);
                    }
                    ty = self.types.add(Type::Array { index: it, lo, hi, elem: ty });
                }
                Ok(ty)
            }
            ast::TypeKind::OpenArray(_) => self.error(code::ERROR_IN_TYPE, t.span),
            ast::TypeKind::Record { fields, packed } => {
                let mut seen = HashSet::new();
                let (fields, end, align) = self.record_fields(fields, &mut seen, *packed)?;
                let size = end.div_ceil(align as u64) * align as u64;
                if size > i32::MAX as u64 {
                    return self.error(code::STRUCTURE_TOO_LARGE, t.span);
                }
                Ok(self.types.add(Type::Record { fields, size, align }))
            }
            // Object types only appear as declarations of a type section.
            ast::TypeKind::Object(_) => self.error(code::LOCAL_OBJECT_TYPE, t.span),
            ast::TypeKind::Set { base, .. } => {
                let bt = self.resolve_type(base)?;
                let (lo, hi) = self.ordinal_bounds(bt, base.span)?;
                if lo < 0 || hi > 255 {
                    return self.error(code::SET_BASE_RANGE, base.span);
                }
                let (first_byte, size) = TypeTable::set_layout(lo, hi);
                Ok(self.types.add(Type::Set { base: bt, first_byte, size }))
            }
            ast::TypeKind::Pointer(target) => match &target.kind {
                ast::TypeKind::Named(q) => match self.lookup_type(q)? {
                    Some(tt) => Ok(self.types.add(Type::Pointer(Some(tt)))),
                    None => match pending {
                        Some(list) => {
                            let p = self.types.add(Type::Pointer(None));
                            list.push((p, q.clone()));
                            Ok(p)
                        }
                        None => self.error_with(code::UNKNOWN_IDENT, q.span(), format!(": {}", q.name.name)),
                    },
                },
                _ => {
                    let tt = self.resolve_type(target)?;
                    Ok(self.types.add(Type::Pointer(Some(tt))))
                }
            },
            ast::TypeKind::Procedural { params, result, .. } => {
                let heading = ast::RoutineHeading {
                    kind: if result.is_some() { ast::RoutineKind::Function } else { ast::RoutineKind::Procedure },
                    owner: None,
                    name: ast::Ident { name: String::new(), span: t.span },
                    params: params.clone(),
                    result: result.as_ref().map(|r| (**r).clone()),
                    directives: Vec::new(),
                    span: t.span,
                    switches: self.sw,
                };
                let sig = self.signature(&heading)?;
                Ok(self.types.add(Type::Procedural(sig)))
            }
        }
    }

    /// Lays out a field list (fixed part, then a variant part shared like
    /// a C union). Returns fields, end offset and alignment.
    fn record_fields(
        &mut self,
        fl: &ast::FieldList,
        seen: &mut HashSet<String>,
        packed: bool,
    ) -> SResult<(Vec<Field>, u64, u32)> {
        let mut list = Vec::new();
        for f in &fl.fields {
            let ty = self.resolve_type(&f.ty)?;
            for n in &f.names {
                if !seen.insert(n.key()) {
                    return self.error_with(code::DUPLICATE_IDENT, n.span, format!(": {}", n.name));
                }
                list.push((n.name.clone(), ty));
            }
        }
        if let Some(v) = &fl.variant {
            let tag_ty = match self.lookup_type(&v.tag_type)? {
                Some(t) => t,
                None => {
                    return self.error_with(
                        code::UNKNOWN_IDENT,
                        v.tag_type.span(),
                        format!(": {}", v.tag_type.name.name),
                    );
                }
            };
            if !self.types.is_ordinal(tag_ty) {
                return self.error(code::ORDINAL_TYPE_EXPECTED, v.tag_type.span());
            }
            if let Some(tag) = &v.tag {
                if !seen.insert(tag.key()) {
                    return self.error_with(code::DUPLICATE_IDENT, tag.span, format!(": {}", tag.name));
                }
                list.push((tag.name.clone(), tag_ty));
            }
        }
        let (mut fields, mut end, mut align) =
            if packed { self.types.layout_fields_packed(&list, 0) } else { self.types.layout_fields(&list, 0) };
        if let Some(v) = &fl.variant {
            let mut cases = Vec::new();
            let mut union_align = 1u32;
            for case in &v.cases {
                for l in &case.labels {
                    self.const_expr(&l.lo)?;
                    if let Some(h) = &l.hi {
                        self.const_expr(h)?;
                    }
                }
                let (cf, ce, ca) = self.record_fields(&case.fields, seen, packed)?;
                union_align = union_align.max(ca);
                cases.push((cf, ce));
            }
            let start = end.div_ceil(union_align as u64) * union_align as u64;
            let mut union_end = start;
            for (cf, ce) in cases {
                for mut f in cf {
                    f.offset += start;
                    fields.push(f);
                }
                union_end = union_end.max(start + ce);
            }
            end = union_end;
            align = align.max(union_align);
        }
        Ok((fields, end, align))
    }

    /// Fields of a record type, or `None`.
    pub(crate) fn record_field(&self, record: TypeId, key: &str) -> Option<Field> {
        match self.types.get(record) {
            Type::Record { fields, .. } => fields.iter().find(|f| f.name.eq_ignore_ascii_case(key)).cloned(),
            Type::Object(o) => o.field(key).cloned(),
            _ => None,
        }
    }

    /// A pointer type to `target`, reusing an existing one when possible.
    pub(crate) fn pointer_to(&mut self, target: TypeId) -> TypeId {
        if target == self.types.builtin.char {
            return self.types.builtin.pchar;
        }
        self.types.add(Type::Pointer(Some(target)))
    }

    /// A set type of the given ordinal base covering `lo..=hi`.
    pub(crate) fn set_type(&mut self, base: TypeId) -> TypeId {
        let (lo, hi) = self.types.bounds(base);
        let (first_byte, size) = TypeTable::set_layout(lo.max(0), hi.min(255));
        self.types.add(Type::Set { base, first_byte, size })
    }
}
