// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Expressions: name resolution, operator typing (FPC `-Mtp` on 64-bit:
//! integer `+ - * div mod` in 64 bits), constant folding, implicit
//! conversions and calls.

use odin_base::{Diagnostic, Span, code};
use odin_ir::*;
use odin_syntax::{Switches, ast};

use crate::scope::{Builtin, ConstKind, ConstVal, Sym};
use crate::{Analyzer, SResult};

/// Operand classes for operator typing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Class {
    Int,
    Real,
    Bool,
    Char,
    Enum(TypeId),
    Str,
    Ptr,
    Nil,
    Set,
    Proc,
    /// A class instance reference.
    Obj,
    /// A class reference (`class of T`).
    Meta,
    Other,
}

/// What a name or qualified name denotes.
pub(crate) enum Resolved {
    Value(Expr),
    Type(TypeId, Span),
    Routine(RoutineId, Span),
    Builtin(Builtin, Span),
    Unit(#[allow(dead_code)] usize, Span),
    /// A method with the object it is called on.
    Method(Box<crate::object::MethodRef>),
    /// `TObj.Method` outside a method of TObj: only its address is usable.
    MethodName(RoutineId, Span),
    /// A property with the instance it belongs to.
    Property(Box<crate::object::PropRef>),
}

/// 256-bit set membership map used while building set constants.
pub(crate) type Bitmap = [u8; 32];

impl Analyzer<'_> {
    pub(crate) fn class(&self, ty: TypeId) -> Class {
        let b = self.types.base(ty);
        match self.types.get(b) {
            Type::Int(_) => Class::Int,
            Type::Real(_) => Class::Real,
            Type::Bool => Class::Bool,
            Type::Char => Class::Char,
            Type::Enum { .. } => Class::Enum(b),
            Type::ShortString(_) | Type::OpenString => Class::Str,
            Type::Pointer(_) => Class::Ptr,
            Type::Nil => Class::Nil,
            Type::Set { .. } => Class::Set,
            Type::Procedural(_) => Class::Proc,
            Type::Class(_) => Class::Obj,
            Type::ClassRef(_) => Class::Meta,
            _ => Class::Other,
        }
    }

    /// FPC types an integer constant as the smallest of ShortInt, Byte,
    /// SmallInt, Word, LongInt, LongWord and Int64 that holds it (this shows
    /// in `SizeOf`, `Hi` and `Lo`).
    pub(crate) fn int_literal_type(&self, v: i64) -> TypeId {
        let b = &self.types.builtin;
        match v {
            -128..=127 => b.shortint,
            128..=255 => b.byte,
            -32768..=32767 => b.smallint,
            32768..=65535 => b.word,
            -2147483648..=2147483647 => b.longint,
            2147483648..=4294967295 => b.longword,
            _ => b.int64,
        }
    }

    /// Smallest signed type holding `v` (type of a folded `not`).
    fn signed_literal_type(&self, v: i64) -> TypeId {
        let b = &self.types.builtin;
        match v {
            -128..=127 => b.shortint,
            -32768..=32767 => b.smallint,
            -2147483648..=2147483647 => b.longint,
            _ => b.int64,
        }
    }

    pub(crate) fn const_to_expr(&self, c: &ConstVal, span: Span) -> Expr {
        let kind = match &c.kind {
            ConstKind::Int(v) => ExprKind::Int(*v),
            ConstKind::Real(v) => ExprKind::Real(*v),
            ConstKind::Str(b) => ExprKind::Str(b.clone()),
            ConstKind::Set(b) => ExprKind::SetConst(b.clone()),
            ConstKind::Nil => ExprKind::Nil,
        };
        Expr::new(kind, c.ty, span)
    }

    /// The constant value of an already analysed expression.
    pub(crate) fn const_of(&self, e: &Expr) -> SResult<ConstVal> {
        let kind = match &e.kind {
            ExprKind::Int(v) => ConstKind::Int(*v),
            ExprKind::Real(v) => ConstKind::Real(*v),
            ExprKind::Str(b) => ConstKind::Str(b.clone()),
            ExprKind::SetConst(b) => ConstKind::Set(b.clone()),
            ExprKind::Nil => ConstKind::Nil,
            _ => return self.error(code::CONST_EXPECTED, e.span),
        };
        Ok(ConstVal { kind, ty: e.ty })
    }

    pub(crate) fn const_expr(&mut self, e: &ast::Expr) -> SResult<ConstVal> {
        let x = self.expr(e)?;
        self.const_of(&x)
    }

    pub(crate) fn const_int(&mut self, e: &ast::Expr) -> SResult<i64> {
        match self.const_expr(e)?.kind {
            ConstKind::Int(v) => Ok(v),
            _ => self.error(code::INTEGER_CONST_EXPECTED, e.span),
        }
    }

    pub(crate) fn const_string(&mut self, e: &ast::Expr) -> SResult<String> {
        let c = self.const_expr(e)?;
        match c.kind {
            ConstKind::Str(b) => Ok(String::from_utf8_lossy(&b).into_owned()),
            ConstKind::Int(v) if c.ty == self.types.builtin.char => Ok((v as u8 as char).to_string()),
            _ => self.error(code::STRING_CONST_EXPECTED, e.span),
        }
    }

    // ---- names -------------------------------------------------------------

    pub(crate) fn sym_to_resolved(&self, sym: Sym, span: Span) -> SResult<Resolved> {
        Ok(match sym {
            Sym::Const(c) => Resolved::Value(self.const_to_expr(&c, span)),
            Sym::Type(t) => Resolved::Type(t, span),
            Sym::Var(v, ty) => Resolved::Value(self.var_expr(v, ty, span)),
            Sym::Routine(r) => Resolved::Routine(r, span),
            Sym::Builtin(b) => Resolved::Builtin(b, span),
            Sym::Unit(u) => Resolved::Unit(u, span),
            Sym::Label(_) => return self.error(code::ERROR_IN_EXPR, span),
        })
    }

    /// Fields (and, for objects, methods) of the active `with` scopes.
    fn with_member(&self, key: &str, span: Span) -> SResult<Option<Resolved>> {
        let Some(frame) = self.frames.last() else { return Ok(None) };
        for w in frame.withs.iter().rev() {
            let ptr = Expr::new(ExprKind::Var(w.ptr), w.ptr_ty, span);
            let base = Expr::new(ExprKind::Deref(Box::new(ptr)), w.record, span);
            if self.types.object(w.record).is_some() {
                if let Some(r) = self.object_member(base, key, span)? {
                    return Ok(Some(r));
                }
            } else if let Some(f) = self.record_field(w.record, key) {
                let field = Expr::new(ExprKind::Field { base: Box::new(base), offset: f.offset }, f.ty, span);
                return Ok(Some(Resolved::Value(field)));
            }
        }
        Ok(None)
    }

    /// Member `field` of an analysed value: a record field, or a member of
    /// an object, class instance or class reference.
    pub(crate) fn member(&mut self, base: Expr, field: &ast::Ident, span: Span) -> SResult<Resolved> {
        let base_ty = base.ty;
        let unknown = |s: &Self| match s.hidden_member(base_ty, &field.key()) {
            Some(vis) => s.error_with(code::CANNOT_ACCESS, field.span, format!(": {} ({vis})", field.name)),
            None => s.error_with(code::UNKNOWN_IDENT, field.span, format!(": {}", field.name)),
        };
        if self.types.object(base.ty).is_some() {
            return match self.object_member(base, &field.key(), span)? {
                Some(r) => Ok(r),
                None => unknown(self),
            };
        }
        match self.types.get(base.ty).clone() {
            Type::Class(_) => {
                let instance = self.class_instance(base, span);
                match self.object_member(instance, &field.key(), span)? {
                    Some(r) => Ok(r),
                    None => unknown(self),
                }
            }
            Type::ClassRef(c) => match self.class_member(c, Some(base), &field.key(), span)? {
                Some(r) => Ok(r),
                None => unknown(self),
            },
            _ => Ok(Resolved::Value(self.field_access(base, field, span)?)),
        }
    }

    pub(crate) fn resolve_name(&mut self, id: &ast::Ident) -> SResult<Resolved> {
        let key = id.key();
        if let Some(r) = self.with_member(&key, id.span)? {
            return Ok(r);
        }
        if let Some(r) = self.self_member(&key, id.span)? {
            return Ok(r);
        }
        match self.lookup(&key) {
            Some(sym) => self.sym_to_resolved(sym, id.span),
            None => {
                // A member of the method's own class that it may not use.
                let own = self.method_frame().and_then(|(_, scope)| self.types.object(scope.ty)?.class);
                match own.and_then(|c| self.hidden_member(c, &key)) {
                    Some(vis) => self.error_with(code::CANNOT_ACCESS, id.span, format!(": {} ({vis})", id.name)),
                    None => self.error_with(code::UNKNOWN_IDENT, id.span, format!(": {}", id.name)),
                }
            }
        }
    }

    /// Resolves names, unit-qualified names and anything else (as a value).
    pub(crate) fn resolve(&mut self, e: &ast::Expr) -> SResult<Resolved> {
        match &e.kind {
            ast::ExprKind::Name(id) => self.resolve_name(id),
            ast::ExprKind::Field { base, field } => {
                if let ast::ExprKind::Name(b) = &base.kind
                    && self.with_member(&b.key(), b.span)?.is_none()
                    && self.self_member(&b.key(), b.span)?.is_none()
                {
                    match self.lookup(&b.key()) {
                        Some(Sym::Unit(u)) => {
                            return match self.units[u].interface.get(&field.key()).cloned() {
                                Some(sym) => self.sym_to_resolved(sym, e.span),
                                None => self.error_with(code::UNKNOWN_IDENT, field.span, format!(": {}", field.name)),
                            };
                        }
                        Some(Sym::Type(t)) if self.types.object(t).is_some() => {
                            return self.qualified_method(t, field, e.span);
                        }
                        Some(Sym::Type(t)) if self.types.class_object(t).is_some() => {
                            return match self.class_member(t, None, &field.key(), e.span)? {
                                Some(r) => Ok(r),
                                None => self.error_with(code::UNKNOWN_IDENT, field.span, format!(": {}", field.name)),
                            };
                        }
                        _ => {}
                    }
                }
                let base = self.expr(base)?;
                self.member(base, field, e.span)
            }
            ast::ExprKind::Inherited(Some(name)) => self.inherited_member(name),
            ast::ExprKind::Inherited(None) => {
                self.error_with(code::NO_INHERITED, e.span, ": inherited tanpa nama hanya sebagai statement")
            }
            _ => Ok(Resolved::Value(self.expr(e)?)),
        }
    }

    fn resolved_value(&mut self, r: Resolved, expected: Option<TypeId>, span: Span) -> SResult<Expr> {
        match r {
            Resolved::Value(e) => Ok(e),
            Resolved::Routine(id, s) => {
                if let Some(t) = expected
                    && matches!(self.types.get(t), Type::Procedural(_))
                {
                    return self.routine_value(id, t, s);
                }
                self.call_routine(id, &[], span, false)
            }
            Resolved::Builtin(b, s) => self.builtin_expr(b, &[], s),
            Resolved::Method(m) => self.method_value(*m, &[], span),
            Resolved::Property(p) => self.property_read(*p, &[], span),
            // A class name as a value is the class reference.
            Resolved::Type(t, s) if self.types.class_object(t).is_some() => self.class_value(t, s),
            Resolved::Type(_, s) | Resolved::Unit(_, s) | Resolved::MethodName(_, s) => {
                self.error(code::ERROR_IN_EXPR, s)
            }
        }
    }

    /// A routine used as a procedural value.
    fn routine_value(&mut self, id: RoutineId, ty: TypeId, span: Span) -> SResult<Expr> {
        let Type::Procedural(sig) = self.types.get(ty).clone() else { unreachable!() };
        let rsig = &self.routine(id).sig;
        let same = rsig.result == sig.result
            && rsig.params.len() == sig.params.len()
            && rsig.params.iter().zip(&sig.params).all(|(a, b)| a.mode == b.mode && a.ty == b.ty);
        if !same {
            return self.error(code::TYPE_MISMATCH, span);
        }
        if self.routine(id).parent.is_some_and(|p| !self.routine(p).symbol.ends_with(".$MAIN")) {
            return self.error_with(
                code::BAD_PROC_REFERENCE,
                span,
                ": prosedur lokal tidak bisa menjadi nilai prosedural",
            );
        }
        Ok(Expr::new(ExprKind::RoutineAddr(id), ty, span))
    }

    // ---- expressions -----------------------------------------------------

    pub(crate) fn expr(&mut self, e: &ast::Expr) -> SResult<Expr> {
        self.expr_expect(e, None)
    }

    pub(crate) fn expr_expect(&mut self, e: &ast::Expr, expected: Option<TypeId>) -> SResult<Expr> {
        let b = self.types.builtin;
        let span = e.span;
        match &e.kind {
            ast::ExprKind::Int(v) => {
                let Ok(v) = i64::try_from(*v) else {
                    return self.error_with(code::BAD_INTEGER, span, ": angka melewati batas Int64");
                };
                Ok(Expr::new(ExprKind::Int(v), self.int_literal_type(v), span))
            }
            ast::ExprKind::Real(v) => Ok(Expr::new(ExprKind::Real(*v), b.double, span)),
            ast::ExprKind::Str(bytes) => {
                if let Some(t) = expected
                    && t == b.pchar
                {
                    return Ok(self.pchar_literal(bytes, span));
                }
                if bytes.len() == 1 {
                    Ok(Expr::new(ExprKind::Int(bytes[0] as i64), b.char, span))
                } else {
                    Ok(Expr::new(ExprKind::Str(bytes.clone()), b.string, span))
                }
            }
            ast::ExprKind::Nil => Ok(Expr::new(ExprKind::Nil, b.nil, span)),
            ast::ExprKind::Name(_) => {
                let r = self.resolve(e)?;
                self.resolved_value(r, expected, span)
            }
            // A unit-qualified name, a record or object field, or a method.
            ast::ExprKind::Field { .. } | ast::ExprKind::Inherited(_) => {
                let r = self.resolve(e)?;
                self.resolved_value(r, expected, span)
            }
            ast::ExprKind::Set(items) => self.set_constructor(items, expected, span),
            ast::ExprKind::Unary(op, x) => self.unary(*op, x, span),
            ast::ExprKind::Binary(op, l, r) => {
                let (l, r) = self.binary_operands(*op, l, r)?;
                self.binary(*op, l, r, span)
            }
            ast::ExprKind::Call { callee, args } => self.call_expr(callee, args, span, expected),
            ast::ExprKind::Index { base, indices } => {
                let args: Vec<ast::Arg> =
                    indices.iter().map(|i| ast::Arg { value: i.clone(), width: None, decimals: None }).collect();
                // An array property (`Obj.Items[I]`), or the default one
                // (`Obj[I]`).
                let r = self.resolve(base)?;
                if let Resolved::Property(p) = r {
                    if !p.prop.params.is_empty() {
                        return self.property_read(*p, &args, span);
                    }
                    let v = self.property_read(*p, &[], base.span)?;
                    if let Some(p) = self.default_property(&v, span) {
                        return self.property_read(p, &args, span);
                    }
                    return self.index(v, indices);
                }
                let base_value = self.resolved_value(r, None, base.span)?;
                if let Some(p) = self.default_property(&base_value, span) {
                    return self.property_read(p, &args, span);
                }
                self.index(base_value, indices)
            }
            ast::ExprKind::Deref(x) => {
                let p = self.expr(x)?;
                self.deref(p, span)
            }
            ast::ExprKind::StringType => self.error(code::ERROR_IN_EXPR, span),
        }
    }

    pub(crate) fn pchar_literal(&mut self, bytes: &[u8], span: Span) -> Expr {
        let mut data = bytes.to_vec();
        data.push(0);
        let n = self.globals.len();
        let symbol = format!("{}.$PCHAR{n}", self.unit_prefix());
        let arr = self.types.add(Type::Array {
            index: self.types.builtin.longint,
            lo: 0,
            hi: data.len() as i64 - 1,
            elem: self.types.builtin.char,
        });
        self.globals.push(Global {
            symbol,
            name: String::new(),
            ty: arr,
            init: Some(GlobalInit { bytes: data, pointers: Vec::new() }),
            readonly: true,
            span,
        });
        let g = Expr::new(ExprKind::Var(Var::Global(GlobalId(n as u32))), arr, span);
        Expr::new(ExprKind::AddrOf(Box::new(g)), self.types.builtin.pchar, span)
    }

    pub(crate) fn field_access(&mut self, base: Expr, field: &ast::Ident, span: Span) -> SResult<Expr> {
        let base = match self.types.get(base.ty) {
            Type::Class(_) => self.class_instance(base, span),
            _ => base,
        };
        if self.types.object(base.ty).is_some() {
            return match self.object_member(base, &field.key(), span)? {
                Some(Resolved::Value(e)) => Ok(e),
                Some(Resolved::Property(p)) => self.property_read(*p, &[], span),
                Some(_) => self.error(code::FIELD_IDENT_EXPECTED, field.span),
                None => self.error_with(code::UNKNOWN_IDENT, field.span, format!(": field {}", field.name)),
            };
        }
        match self.types.get(base.ty) {
            Type::Record { .. } => match self.record_field(base.ty, &field.key()) {
                Some(f) => Ok(Expr::new(ExprKind::Field { base: Box::new(base), offset: f.offset }, f.ty, span)),
                None => self.error_with(code::UNKNOWN_IDENT, field.span, format!(": field {}", field.name)),
            },
            _ => self.error(code::RECORD_VAR_EXPECTED, base.span),
        }
    }

    pub(crate) fn index(&mut self, base: Expr, indices: &[ast::Expr]) -> SResult<Expr> {
        let check = self.sw.get(Switches::RANGE);
        let mut cur = base;
        for ie in indices {
            let idx = self.expr(ie)?;
            let span = cur.span.to(ie.span);
            cur = match self.types.get(cur.ty).clone() {
                Type::Array { index, lo, hi, elem } => {
                    let idx = self.ordinal_index(idx, index)?;
                    Expr::new(ExprKind::Index { base: Box::new(cur), index: Box::new(idx), lo, hi, check }, elem, span)
                }
                Type::ShortString(max) => {
                    if self.class(idx.ty) != Class::Int {
                        return self.error(code::INTEGER_EXPR_EXPECTED, idx.span);
                    }
                    let ch = self.types.builtin.char;
                    Expr::new(
                        ExprKind::Index { base: Box::new(cur), index: Box::new(idx), lo: 0, hi: max as i64, check },
                        ch,
                        span,
                    )
                }
                Type::OpenString => {
                    if self.class(idx.ty) != Class::Int {
                        return self.error(code::INTEGER_EXPR_EXPECTED, idx.span);
                    }
                    let ch = self.types.builtin.char;
                    Expr::new(ExprKind::OpenIndex { base: Box::new(cur), index: Box::new(idx), check }, ch, span)
                }
                Type::OpenArray { elem } => {
                    if self.class(idx.ty) != Class::Int {
                        return self.error(code::INTEGER_EXPR_EXPECTED, idx.span);
                    }
                    Expr::new(ExprKind::OpenIndex { base: Box::new(cur), index: Box::new(idx), check }, elem, span)
                }
                Type::Pointer(Some(_)) if self.is_pchar(cur.ty) && self.sw.get(Switches::EXTENDED) => {
                    if self.class(idx.ty) != Class::Int {
                        return self.error(code::INTEGER_EXPR_EXPECTED, idx.span);
                    }
                    let ch = self.types.builtin.char;
                    let addr = self.pchar_offset(cur, idx, false, span);
                    Expr::new(ExprKind::Deref(Box::new(addr)), ch, span)
                }
                _ => return self.error(code::BAD_QUALIFIER, cur.span),
            };
        }
        Ok(cur)
    }

    /// An index value checked against an array's index type.
    fn ordinal_index(&mut self, idx: Expr, index_ty: TypeId) -> SResult<Expr> {
        let want = self.class(index_ty);
        let have = self.class(idx.ty);
        let ok = match (want, have) {
            (Class::Int, Class::Int) | (Class::Char, Class::Char) | (Class::Bool, Class::Bool) => true,
            (Class::Enum(a), Class::Enum(b)) => a == b,
            _ => false,
        };
        if !ok {
            return self.error(code::TYPE_MISMATCH, idx.span);
        }
        if let ExprKind::Int(v) = idx.kind {
            let (lo, hi) = self.types.bounds(index_ty);
            if v < lo || v > hi {
                return self.error(code::CONST_OUT_OF_RANGE, idx.span);
            }
        }
        Ok(idx)
    }

    pub(crate) fn deref(&mut self, p: Expr, span: Span) -> SResult<Expr> {
        match self.types.get(p.ty).clone() {
            Type::Pointer(Some(t)) => Ok(Expr::new(ExprKind::Deref(Box::new(p)), t, span)),
            Type::Pointer(None) => {
                let u = self.types.builtin.untyped;
                Ok(Expr::new(ExprKind::Deref(Box::new(p)), u, span))
            }
            _ => self.error(code::POINTER_VAR_EXPECTED, p.span),
        }
    }

    // ---- operators -------------------------------------------------------

    fn unary(&mut self, op: ast::UnOp, x: &ast::Expr, span: Span) -> SResult<Expr> {
        let b = self.types.builtin;
        if op == ast::UnOp::AddrOf {
            // @@P: the address of the procedural variable itself.
            if let ast::ExprKind::Unary(ast::UnOp::AddrOf, inner) = &x.kind {
                let v = self.expr(inner)?;
                if v.is_lvalue() && matches!(self.types.get(v.ty), Type::Procedural(_)) {
                    return Ok(Expr::new(ExprKind::AddrOf(Box::new(v)), b.pointer, span));
                }
                return self.error(code::BAD_AT_ARGUMENT, inner.span);
            }
            let r = self.resolve(x)?;
            return match r {
                Resolved::Routine(id, s) => {
                    let _ = s;
                    Ok(Expr::new(ExprKind::RoutineAddr(id), b.pointer, span))
                }
                // @Obj.Method, @TObj.Method: the code address of the method.
                Resolved::Method(m) => Ok(Expr::new(ExprKind::RoutineAddr(m.method.routine), b.pointer, span)),
                Resolved::MethodName(id, _) => Ok(Expr::new(ExprKind::RoutineAddr(id), b.pointer, span)),
                Resolved::Property(p) => {
                    let v = self.property_read(*p, &[], x.span)?;
                    if !v.is_lvalue() {
                        return self.error(code::BAD_AT_ARGUMENT, x.span);
                    }
                    let ty = if self.sw.get(Switches::TYPED_AT) { self.pointer_to(v.ty) } else { b.pointer };
                    Ok(Expr::new(ExprKind::AddrOf(Box::new(v)), ty, span))
                }
                // @P on a procedural variable is the routine address it holds (TP).
                Resolved::Value(v) if matches!(self.types.get(v.ty), Type::Procedural(_)) => {
                    Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(v)), b.pointer, span))
                }
                Resolved::Value(v) => {
                    if !v.is_lvalue() {
                        return self.error(code::BAD_AT_ARGUMENT, x.span);
                    }
                    let ty = if self.sw.get(Switches::TYPED_AT) && v.ty != b.untyped {
                        self.pointer_to(v.ty)
                    } else {
                        b.pointer
                    };
                    Ok(Expr::new(ExprKind::AddrOf(Box::new(v)), ty, span))
                }
                _ => self.error(code::BAD_AT_ARGUMENT, x.span),
            };
        }
        let v = self.expr(x)?;
        let class = self.class(v.ty);
        let (kind, ty) = match (op, class) {
            (ast::UnOp::Neg, Class::Int) => {
                if let ExprKind::Int(n) = v.kind {
                    return Ok(Expr::new(
                        ExprKind::Int(n.wrapping_neg()),
                        self.int_literal_type(n.wrapping_neg()),
                        span,
                    ));
                }
                (ExprKind::Unary(UnOp::Neg, Box::new(v)), b.int64)
            }
            (ast::UnOp::Neg, Class::Real) => {
                if let ExprKind::Real(r) = v.kind {
                    return Ok(Expr::new(ExprKind::Real(-r), b.double, span));
                }
                (ExprKind::Unary(UnOp::RealNeg, Box::new(v)), b.double)
            }
            (ast::UnOp::Pos, Class::Int | Class::Real) => return Ok(Expr { span, ..v }),
            (ast::UnOp::Not, Class::Bool) => {
                if let ExprKind::Int(n) = v.kind {
                    return Ok(Expr::new(ExprKind::Int((n == 0) as i64), b.boolean, span));
                }
                (ExprKind::Unary(UnOp::BoolNot, Box::new(v)), b.boolean)
            }
            (ast::UnOp::Not, Class::Int) => {
                // FPC keeps the operand type: "not" on a Byte is a Byte.
                let ty = self.types.base(v.ty);
                let ty = if ty == b.int64 || self.types.size(ty) >= 8 { b.int64 } else { ty };
                if let ExprKind::Int(n) = v.kind {
                    return Ok(Expr::new(ExprKind::Int(!n), self.signed_literal_type(!n), span));
                }
                let inner = Expr::new(ExprKind::Unary(UnOp::Not, Box::new(v)), b.int64, span);
                (ExprKind::Convert(Conv::Resize, Box::new(inner)), ty)
            }
            _ => return self.error(code::OPERAND_TYPES, span),
        };
        Ok(Expr::new(kind, ty, span))
    }

    /// Analyses both operands; a set constructor takes its element type
    /// from the other side.
    fn binary_operands(&mut self, op: ast::BinOp, l: &ast::Expr, r: &ast::Expr) -> SResult<(Expr, Expr)> {
        if op == ast::BinOp::In {
            let left = self.expr(l)?;
            let right = if matches!(r.kind, ast::ExprKind::Set(_)) && self.types.is_ordinal(left.ty) {
                let base = self.types.base(left.ty);
                let st = self.set_type(base);
                self.expr_expect(r, Some(st))?
            } else {
                self.expr(r)?
            };
            return Ok((left, right));
        }
        let l_is_set = matches!(l.kind, ast::ExprKind::Set(_));
        let r_is_set = matches!(r.kind, ast::ExprKind::Set(_));
        if l_is_set && !r_is_set {
            let right = self.expr(r)?;
            let expected = (self.class(right.ty) == Class::Set).then_some(right.ty);
            let left = self.expr_expect(l, expected)?;
            return Ok((left, right));
        }
        let left = self.expr(l)?;
        let expected = (self.class(left.ty) == Class::Set).then_some(left.ty);
        let right = self.expr_expect(r, expected)?;
        Ok((left, right))
    }

    pub(crate) fn binary(&mut self, op: ast::BinOp, l: Expr, r: Expr, span: Span) -> SResult<Expr> {
        use ast::BinOp as B;
        let b = self.types.builtin;
        let (lc, rc) = (self.class(l.ty), self.class(r.ty));
        let numeric = |c: Class| matches!(c, Class::Int | Class::Real);
        let checked = self.sw.get(Switches::OVERFLOW);
        let result = match op {
            B::Add | B::Sub | B::Mul if lc == Class::Int && rc == Class::Int => {
                let hop = match (op, checked) {
                    (B::Add, false) => BinOp::Add,
                    (B::Sub, false) => BinOp::Sub,
                    (B::Mul, false) => BinOp::Mul,
                    (B::Add, true) => BinOp::AddChecked,
                    (B::Sub, true) => BinOp::SubChecked,
                    _ => BinOp::MulChecked,
                };
                (hop, l, r, b.int64)
            }
            B::Add | B::Sub | B::Mul | B::RealDiv if numeric(lc) && numeric(rc) => {
                let hop = match op {
                    B::Add => BinOp::RealAdd,
                    B::Sub => BinOp::RealSub,
                    B::Mul => BinOp::RealMul,
                    _ => BinOp::RealDiv,
                };
                let l = self.to_real(l);
                let r = self.to_real(r);
                (hop, l, r, b.double)
            }
            B::Add if matches!(lc, Class::Str | Class::Char) && matches!(rc, Class::Str | Class::Char) => {
                return Ok(self.concat(vec![l, r], span));
            }
            B::Add | B::Sub if self.is_pchar(l.ty) && rc == Class::Int && self.sw.get(Switches::EXTENDED) => {
                return Ok(self.pchar_offset(l, r, op == B::Sub, span));
            }
            B::Add if lc == Class::Int && self.is_pchar(r.ty) && self.sw.get(Switches::EXTENDED) => {
                return Ok(self.pchar_offset(r, l, false, span));
            }
            B::Sub if self.is_pchar(l.ty) && self.is_pchar(r.ty) && self.sw.get(Switches::EXTENDED) => {
                let li = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(l)), b.int64, span);
                let ri = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(r)), b.int64, span);
                (BinOp::Sub, li, ri, b.int64)
            }
            B::Add | B::Sub | B::Mul if lc == Class::Set && rc == Class::Set => {
                let r = self.coerce(r, l.ty, span)?;
                let hop = match op {
                    B::Add => BinOp::SetUnion,
                    B::Sub => BinOp::SetDiff,
                    _ => BinOp::SetIntersect,
                };
                let ty = l.ty;
                (hop, l, r, ty)
            }
            B::Div | B::Mod if lc == Class::Int && rc == Class::Int => {
                if r.int_value() == Some(0) {
                    return self.error(code::DIVISION_BY_ZERO, r.span);
                }
                (if op == B::Div { BinOp::Div } else { BinOp::Mod }, l, r, b.int64)
            }
            B::And | B::Or | B::Xor if lc == Class::Bool && rc == Class::Bool => {
                let full = self.sw.get(Switches::BOOL_EVAL);
                let hop = match (op, full) {
                    (B::And, false) => BinOp::AndThen,
                    (B::Or, false) => BinOp::OrElse,
                    (B::And, true) => BinOp::BoolAnd,
                    (B::Or, true) => BinOp::BoolOr,
                    _ => BinOp::BoolXor,
                };
                (hop, l, r, b.boolean)
            }
            B::And | B::Or | B::Xor if lc == Class::Int && rc == Class::Int => {
                let hop = match op {
                    B::And => BinOp::And,
                    B::Or => BinOp::Or,
                    _ => BinOp::Xor,
                };
                (hop, l, r, b.int64)
            }
            B::Shl | B::Shr if lc == Class::Int && rc == Class::Int => {
                let wide = self.types.size(self.types.base(l.ty)) >= 8 || (l.is_const() && r.is_const());
                (if op == B::Shl { BinOp::Shl } else { BinOp::Shr }, l, r, if wide { b.int64 } else { b.longint })
            }
            B::Eq | B::Ne | B::Lt | B::Le | B::Gt | B::Ge => return self.comparison(op, l, r, span),
            B::Is | B::As => return self.class_test(op, l, r, span),
            B::In => {
                if rc != Class::Set || !self.types.is_ordinal(l.ty) {
                    return self.error(code::OPERAND_TYPES, span);
                }
                let Type::Set { base, .. } = self.types.get(r.ty).clone() else { unreachable!() };
                if !self.ordinals_compatible(l.ty, base) {
                    return self.error(code::OPERAND_TYPES, span);
                }
                (BinOp::In, l, r, b.boolean)
            }
            _ => return self.error(code::OPERAND_TYPES, span),
        };
        let (hop, l, r, ty) = result;
        if let Some(folded) = self.fold(hop, &l, &r, ty, span)? {
            return Ok(folded);
        }
        Ok(Expr::new(ExprKind::Binary(hop, Box::new(l), Box::new(r)), ty, span))
    }

    pub(crate) fn is_pchar(&self, ty: TypeId) -> bool {
        matches!(self.types.get(ty), Type::Pointer(Some(t)) if *t == self.types.builtin.char)
    }

    fn is_zero_based_chars(&self, ty: TypeId) -> bool {
        matches!(self.types.get(ty), Type::Array { lo: 0, elem, .. } if *elem == self.types.builtin.char)
    }

    /// `p + n` / `p - n` on a PChar.
    fn pchar_offset(&self, p: Expr, n: Expr, subtract: bool, span: Span) -> Expr {
        let b = self.types.builtin;
        let pty = p.ty;
        let pi = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), b.int64, span);
        let op = if subtract { BinOp::Sub } else { BinOp::Add };
        let sum = Expr::new(ExprKind::Binary(op, Box::new(pi), Box::new(n)), b.int64, span);
        Expr::new(ExprKind::Convert(Conv::Bits, Box::new(sum)), pty, span)
    }

    pub(crate) fn ordinals_compatible(&self, a: TypeId, b: TypeId) -> bool {
        match (self.class(a), self.class(b)) {
            (Class::Int, Class::Int) | (Class::Char, Class::Char) | (Class::Bool, Class::Bool) => true,
            (Class::Enum(x), Class::Enum(y)) => x == y,
            _ => false,
        }
    }

    fn comparison(&mut self, op: ast::BinOp, l: Expr, r: Expr, span: Span) -> SResult<Expr> {
        use ast::BinOp as B;
        let b = self.types.builtin;
        let cond = match op {
            B::Eq => Cond::Eq,
            B::Ne => Cond::Ne,
            B::Lt => Cond::Lt,
            B::Le => Cond::Le,
            B::Gt => Cond::Gt,
            _ => Cond::Ge,
        };
        let (lc, rc) = (self.class(l.ty), self.class(r.ty));
        let eq_only = matches!(cond, Cond::Eq | Cond::Ne);
        let (hop, l, r) = if self.ordinals_compatible(l.ty, r.ty) {
            (BinOp::Cmp(cond), l, r)
        } else if matches!(lc, Class::Int | Class::Real) && matches!(rc, Class::Int | Class::Real) {
            let l = self.to_real(l);
            let r = self.to_real(r);
            (BinOp::RealCmp(cond), l, r)
        } else if matches!(lc, Class::Str | Class::Char) && matches!(rc, Class::Str | Class::Char) {
            let l = self.to_string_value(l);
            let r = self.to_string_value(r);
            (BinOp::StrCmp(cond), l, r)
        } else if matches!(lc, Class::Ptr | Class::Nil | Class::Proc | Class::Obj | Class::Meta)
            && matches!(rc, Class::Ptr | Class::Nil | Class::Proc | Class::Obj | Class::Meta)
            && eq_only
        {
            (BinOp::Cmp(cond), l, r)
        } else if lc == Class::Set && rc == Class::Set && !matches!(cond, Cond::Lt | Cond::Gt) {
            let r = self.coerce(r, l.ty, span)?;
            (BinOp::SetCmp(cond), l, r)
        } else {
            return self.error(code::OPERAND_TYPES, span);
        };
        if let Some(folded) = self.fold(hop, &l, &r, b.boolean, span)? {
            return Ok(folded);
        }
        Ok(Expr::new(ExprKind::Binary(hop, Box::new(l), Box::new(r)), b.boolean, span))
    }

    pub(crate) fn to_real(&self, e: Expr) -> Expr {
        let d = self.types.builtin.double;
        match (self.class(e.ty), &e.kind) {
            (Class::Int, ExprKind::Int(v)) => Expr::new(ExprKind::Real(*v as f64), d, e.span),
            (Class::Int, _) => {
                let span = e.span;
                Expr::new(ExprKind::Convert(Conv::IntToReal, Box::new(e)), d, span)
            }
            _ => e,
        }
    }

    /// A Char becomes a one-character string; strings stay as they are.
    pub(crate) fn to_string_value(&self, e: Expr) -> Expr {
        let s = self.types.builtin.string;
        if self.class(e.ty) == Class::Char {
            if let ExprKind::Int(c) = e.kind {
                return Expr::new(ExprKind::Str(vec![c as u8]), s, e.span);
            }
            let span = e.span;
            return Expr::new(ExprKind::Convert(Conv::CharToStr, Box::new(e)), s, span);
        }
        e
    }

    pub(crate) fn concat(&self, parts: Vec<Expr>, span: Span) -> Expr {
        let s = self.types.builtin.string;
        let mut items: Vec<Expr> = Vec::new();
        for p in parts {
            match p.kind {
                ExprKind::Concat(inner) => items.extend(inner),
                _ => items.push(self.to_string_value(p)),
            }
        }
        // Merge adjacent constants.
        let mut merged: Vec<Expr> = Vec::new();
        for it in items {
            if let (Some(Expr { kind: ExprKind::Str(a), .. }), ExprKind::Str(bb)) = (merged.last_mut(), &it.kind) {
                a.extend_from_slice(bb);
                a.truncate(255);
                continue;
            }
            merged.push(it);
        }
        if merged.len() == 1 {
            let only = merged.pop().unwrap();
            return Expr { span, ..only };
        }
        Expr::new(ExprKind::Concat(merged), s, span)
    }

    /// Constant folding; `None` when an operand is not constant.
    fn fold(&self, op: BinOp, l: &Expr, r: &Expr, ty: TypeId, span: Span) -> SResult<Option<Expr>> {
        let b = self.types.builtin;
        let int = |v: i64| Some(Expr::new(ExprKind::Int(v), ty, span));
        let boolean = |v: bool| Some(Expr::new(ExprKind::Int(v as i64), b.boolean, span));
        Ok(match (&l.kind, &r.kind) {
            (ExprKind::Int(x), ExprKind::Int(y)) => {
                let (x, y) = (*x, *y);
                match op {
                    BinOp::Add => int(x.wrapping_add(y)),
                    BinOp::Sub => int(x.wrapping_sub(y)),
                    BinOp::Mul => int(x.wrapping_mul(y)),
                    BinOp::AddChecked | BinOp::SubChecked | BinOp::MulChecked => {
                        let v = match op {
                            BinOp::AddChecked => x.checked_add(y),
                            BinOp::SubChecked => x.checked_sub(y),
                            _ => x.checked_mul(y),
                        };
                        match v {
                            Some(v) => int(v),
                            None => return self.error(code::ARITH_OVERFLOW, span),
                        }
                    }
                    BinOp::Div => int(x.wrapping_div(y)),
                    BinOp::Mod => int(x.wrapping_rem(y)),
                    BinOp::And => int(x & y),
                    BinOp::Or => int(x | y),
                    BinOp::Xor => int(x ^ y),
                    BinOp::Shl => int(if (0..64).contains(&y) { x.wrapping_shl(y as u32) } else { 0 }),
                    BinOp::Shr => int(if (0..64).contains(&y) { ((x as u64) >> y) as i64 } else { 0 }),
                    BinOp::Cmp(c) => boolean(c.eval(x, y)),
                    BinOp::AndThen | BinOp::BoolAnd => boolean(x != 0 && y != 0),
                    BinOp::OrElse | BinOp::BoolOr => boolean(x != 0 || y != 0),
                    BinOp::BoolXor => boolean((x != 0) != (y != 0)),
                    _ => None,
                }
            }
            (ExprKind::Real(x), ExprKind::Real(y)) => {
                let real = |v: f64| Some(Expr::new(ExprKind::Real(v), ty, span));
                match op {
                    BinOp::RealAdd => real(x + y),
                    BinOp::RealSub => real(x - y),
                    BinOp::RealMul => real(x * y),
                    BinOp::RealDiv => {
                        if *y == 0.0 {
                            return self.error(code::DIVISION_BY_ZERO, r.span);
                        }
                        real(x / y)
                    }
                    BinOp::RealCmp(c) => boolean(c.eval(*x, *y)),
                    _ => None,
                }
            }
            (ExprKind::Str(x), ExprKind::Str(y)) => match op {
                BinOp::StrCmp(c) => boolean(c.eval(x, y)),
                _ => None,
            },
            (ExprKind::Nil, ExprKind::Nil) => match op {
                BinOp::Cmp(c) => boolean(c.eval(0, 0)),
                _ => None,
            },
            (ExprKind::SetConst(x), ExprKind::SetConst(y)) => {
                let set = |v: Vec<u8>| Some(Expr::new(ExprKind::SetConst(v), ty, span));
                match op {
                    BinOp::SetUnion => set(x.iter().zip(y).map(|(a, b)| a | b).collect()),
                    BinOp::SetDiff => set(x.iter().zip(y).map(|(a, b)| a & !b).collect()),
                    BinOp::SetIntersect => set(x.iter().zip(y).map(|(a, b)| a & b).collect()),
                    BinOp::SetCmp(Cond::Eq) => boolean(x == y),
                    BinOp::SetCmp(Cond::Ne) => boolean(x != y),
                    BinOp::SetCmp(Cond::Le) => boolean(x.iter().zip(y).all(|(a, b)| a & !b == 0)),
                    BinOp::SetCmp(Cond::Ge) => boolean(x.iter().zip(y).all(|(a, b)| b & !a == 0)),
                    _ => None,
                }
            }
            (ExprKind::Int(v), ExprKind::SetConst(bytes)) if op == BinOp::In => {
                let bm = self.set_bitmap(r.ty, bytes);
                boolean((0..256).contains(v) && bm[(*v / 8) as usize] & (1 << (*v % 8)) != 0)
            }
            _ => None,
        })
    }

    // ---- sets ------------------------------------------------------------

    pub(crate) fn set_bitmap(&self, ty: TypeId, bytes: &[u8]) -> Bitmap {
        let mut bm = [0u8; 32];
        if let Type::Set { first_byte, .. } = self.types.get(ty) {
            for (i, byte) in bytes.iter().enumerate() {
                bm[*first_byte as usize + i] = *byte;
            }
        }
        bm
    }

    pub(crate) fn set_bytes(&self, ty: TypeId, bm: &Bitmap) -> Vec<u8> {
        match self.types.get(ty) {
            Type::Set { first_byte, size, .. } => bm[*first_byte as usize..(*first_byte + *size) as usize].to_vec(),
            _ => Vec::new(),
        }
    }

    fn set_constructor(&mut self, items: &[ast::SetItem], expected: Option<TypeId>, span: Span) -> SResult<Expr> {
        let mut elems = Vec::new();
        for it in items {
            let lo = self.expr(&it.lo)?;
            let hi = match &it.hi {
                Some(h) => Some(self.expr(h)?),
                None => None,
            };
            elems.push((lo, hi));
        }
        let ty = match expected {
            Some(t) if matches!(self.types.get(t), Type::Set { .. }) => t,
            _ => match elems.first() {
                None => {
                    let byte = self.types.builtin.byte;
                    self.set_type(byte)
                }
                Some((first, _)) => {
                    if !self.types.is_ordinal(first.ty) {
                        return self.error(code::ORDINAL_EXPR_EXPECTED, first.span);
                    }
                    let base = self.types.base(first.ty);
                    let base = if self.types.is_integer(base) { self.types.builtin.byte } else { base };
                    self.set_type(base)
                }
            },
        };
        let Type::Set { base, first_byte, size } = self.types.get(ty).clone() else { unreachable!() };
        let (lo_bound, hi_bound) = (first_byte as i64 * 8, (first_byte + size) as i64 * 8 - 1);
        let mut bm = [0u8; 32];
        let mut all_const = true;
        for (lo, hi) in &elems {
            for e in std::iter::once(lo).chain(hi.iter()) {
                if !self.ordinals_compatible(e.ty, base) {
                    return self.error(code::TYPE_MISMATCH, e.span);
                }
            }
            // `None` when an end is not constant; an empty range like
            // [5..1] adds nothing.
            let top = match hi {
                Some(h) => h.int_value(),
                None => lo.int_value(),
            };
            match (lo.int_value(), top) {
                (Some(a), Some(top)) => {
                    for v in a..=top {
                        if v < lo_bound || v > hi_bound {
                            return self.error(code::CONST_OUT_OF_RANGE, lo.span);
                        }
                        bm[(v / 8) as usize] |= 1 << (v % 8);
                    }
                }
                _ => all_const = false,
            }
        }
        if all_const {
            return Ok(Expr::new(ExprKind::SetConst(self.set_bytes(ty, &bm)), ty, span));
        }
        Ok(Expr::new(ExprKind::SetBuild(elems), ty, span))
    }

    // ---- conversions -----------------------------------------------------

    /// Implicit conversion for assignments, value parameters and typed
    /// constants; adds a range check under `{$R+}`.
    pub(crate) fn coerce(&mut self, e: Expr, target: TypeId, span: Span) -> SResult<Expr> {
        let b = self.types.builtin;
        if e.ty == target {
            return Ok(e);
        }
        let tc = self.class(target);
        let sc = self.class(e.ty);
        let mismatch = |a: &Self| {
            Err(Diagnostic::error_with(
                code::TYPE_MISMATCH,
                span,
                format!(": {} dan {}", a.types.display(e.ty), a.types.display(target)),
            ))
        };
        match (tc, sc) {
            (Class::Int, Class::Int) | (Class::Char, Class::Char) | (Class::Bool, Class::Bool) => {
                self.ordinal_into(e, target, span)
            }
            (Class::Enum(x), Class::Enum(y)) if x == y => self.ordinal_into(e, target, span),
            (Class::Real, Class::Int) => Ok(self.to_real(e)),
            (Class::Real, Class::Real) => Ok(e),
            (Class::Str, Class::Str) => Ok(e),
            (Class::Str, Class::Char) => Ok(self.to_string_value(e)),
            (Class::Char, Class::Str) => match &e.kind {
                ExprKind::Str(bytes) if bytes.len() == 1 => Ok(Expr::new(ExprKind::Int(bytes[0] as i64), target, span)),
                _ => mismatch(self),
            },
            (Class::Ptr, Class::Nil) | (Class::Proc, Class::Nil) => Ok(Expr { ty: target, ..e }),
            (Class::Obj | Class::Meta, Class::Nil) => Ok(Expr { ty: target, ..e }),
            // An instance of a descendant class for its ancestor.
            (Class::Obj, Class::Obj) if self.types.is_descendant(e.ty, target) => Ok(Expr { ty: target, ..e }),
            (Class::Meta, Class::Meta) => match (self.class_of_ref(e.ty), self.class_of_ref(target)) {
                (Some(s), Some(t)) if self.types.is_descendant(s, t) => Ok(Expr { ty: target, ..e }),
                _ => mismatch(self),
            },
            // Any instance or class reference fits an untyped Pointer.
            (Class::Ptr, Class::Obj | Class::Meta) if target == b.pointer => Ok(Expr { ty: target, ..e }),
            (Class::Ptr, Class::Ptr) => {
                let (Type::Pointer(t), Type::Pointer(s)) =
                    (self.types.get(target).clone(), self.types.get(e.ty).clone())
                else {
                    unreachable!()
                };
                match (t, s) {
                    (None, _) | (_, None) => Ok(e),
                    (Some(a), Some(c)) if a == c => Ok(e),
                    // A pointer to a descendant object is a pointer to its ancestor.
                    (Some(a), Some(c)) if self.types.object(a).is_some() && self.types.is_descendant(c, a) => {
                        Ok(Expr { ty: target, ..e })
                    }
                    // A string literal for a PChar parameter.
                    _ => mismatch(self),
                }
            }
            (Class::Ptr, Class::Str) if target == b.pchar => match &e.kind {
                ExprKind::Str(bytes) => {
                    let bytes = bytes.clone();
                    Ok(self.pchar_literal(&bytes, span))
                }
                _ => mismatch(self),
            },
            (Class::Ptr, Class::Other)
                if self.is_pchar(target)
                    && e.is_lvalue()
                    && self.sw.get(Switches::EXTENDED)
                    && self.is_zero_based_chars(e.ty) =>
            {
                let ty = target;
                Ok(Expr::new(ExprKind::AddrOf(Box::new(e)), ty, span))
            }
            (Class::Ptr, Class::Char) if target == b.pchar => match &e.kind {
                ExprKind::Int(c) => {
                    let c = *c as u8;
                    Ok(self.pchar_literal(&[c], span))
                }
                _ => mismatch(self),
            },
            (Class::Proc, Class::Proc) => {
                if self.types.get(target) == self.types.get(e.ty) {
                    Ok(Expr { ty: target, ..e })
                } else {
                    mismatch(self)
                }
            }
            (Class::Set, Class::Set) => {
                let (
                    Type::Set { base: tb, first_byte: tf, size: ts },
                    Type::Set { base: sb, first_byte: sf, size: ss },
                ) = (self.types.get(target).clone(), self.types.get(e.ty).clone())
                else {
                    unreachable!()
                };
                if !self.ordinals_compatible(tb, sb) {
                    return mismatch(self);
                }
                match e.kind {
                    ExprKind::SetConst(bytes) => {
                        let bm = self.set_bitmap(e.ty, &bytes);
                        Ok(Expr::new(ExprKind::SetConst(self.set_bytes(target, &bm)), target, span))
                    }
                    ExprKind::SetBuild(items) => Ok(Expr::new(ExprKind::SetBuild(items), target, span)),
                    kind if tf == sf && ts == ss => Ok(Expr { kind, ty: target, span: e.span }),
                    _ => self.error_with(
                        code::NOT_SUPPORTED,
                        span,
                        ": konversi antar tipe set dengan tata letak berbeda",
                    ),
                }
            }
            _ if matches!(self.types.get(target), Type::Untyped) => Ok(e),
            // A descendant object assigned to its ancestor: the ancestor's
            // part is copied, VMT pointer included (as FPC does).
            _ if self.types.object(target).is_some()
                && self.types.object(e.ty).is_some()
                && self.types.is_descendant(e.ty, target)
                && e.is_lvalue() =>
            {
                let ptr = self.pointer_to(target);
                let addr = Expr::new(ExprKind::AddrOf(Box::new(e)), ptr, span);
                Ok(Expr::new(ExprKind::Deref(Box::new(addr)), target, span))
            }
            _ => mismatch(self),
        }
    }

    /// Ordinal into ordinal: compile-time check for constants, run-time
    /// check under `{$R+}` when the source range does not fit.
    fn ordinal_into(&mut self, e: Expr, target: TypeId, span: Span) -> SResult<Expr> {
        let (lo, hi) = self.types.bounds(target);
        if let ExprKind::Int(v) = e.kind {
            if v < lo || v > hi {
                // Like FPC: an error under {$R+}, otherwise a warning and the
                // value wraps to the target size.
                let detail = format!(": {v} tidak di dalam {lo}..{hi}");
                if self.sw.get(Switches::RANGE) {
                    return self.error_with(code::CONST_OUT_OF_RANGE, span, detail);
                }
                self.warnings.push(Diagnostic::warning(
                    code::CONST_OUT_OF_RANGE,
                    span,
                    format!("{}{detail}", code::message(code::CONST_OUT_OF_RANGE)),
                ));
                let wrapped = wrap(v, self.types.int_kind(target));
                return Ok(Expr::new(ExprKind::Int(wrapped), target, e.span));
            }
            return Ok(Expr::new(ExprKind::Int(v), target, e.span));
        }
        let (slo, shi) = self.types.bounds(e.ty);
        if self.sw.get(Switches::RANGE) && (slo < lo || shi > hi) {
            return Ok(Expr::new(ExprKind::Convert(Conv::RangeCheck { lo, hi }, Box::new(e)), target, span));
        }
        Ok(e)
    }

    /// Explicit value typecast `T(x)`.
    fn typecast(&mut self, target: TypeId, arg: &ast::Expr, span: Span) -> SResult<Expr> {
        let v = self.expr(arg)?;
        let tc = self.class(target);
        let sc = self.class(v.ty);
        let ordinal = |c: Class| matches!(c, Class::Int | Class::Char | Class::Bool | Class::Enum(_));
        let reference = |c: Class| matches!(c, Class::Ptr | Class::Proc | Class::Obj | Class::Meta);
        if ordinal(tc) && (ordinal(sc) || matches!(sc, Class::Ptr | Class::Obj | Class::Meta)) {
            if let ExprKind::Int(n) = v.kind {
                let k = self.types.int_kind(target);
                return Ok(Expr::new(ExprKind::Int(wrap(n, k)), target, span));
            }
            return Ok(Expr::new(ExprKind::Convert(Conv::Resize, Box::new(v)), target, span));
        }
        if reference(tc) && (reference(sc) || matches!(sc, Class::Int | Class::Nil)) {
            return Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(v)), target, span));
        }
        if tc == Class::Real && sc == Class::Int {
            return Ok(self.to_real(v));
        }
        if tc == Class::Real && sc == Class::Real {
            return Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(v)), target, span));
        }
        if tc == Class::Str && matches!(sc, Class::Str | Class::Char) {
            return Ok(self.to_string_value(v));
        }
        // Variable typecast: reinterpret the storage of an lvalue.
        if v.is_lvalue() {
            let ptr_ty = self.pointer_to(target);
            let addr = Expr::new(ExprKind::AddrOf(Box::new(v)), ptr_ty, span);
            return Ok(Expr::new(ExprKind::Deref(Box::new(addr)), target, span));
        }
        self.error(code::BAD_TYPECAST, span)
    }

    // ---- calls -----------------------------------------------------------

    fn call_expr(
        &mut self,
        callee: &ast::Expr,
        args: &[ast::Arg],
        span: Span,
        expected: Option<TypeId>,
    ) -> SResult<Expr> {
        let _ = expected;
        match self.resolve(callee)? {
            Resolved::Routine(id, _) => self.call_routine(id, args, span, false),
            Resolved::Builtin(b, s) => self.builtin_expr(b, args, s.to(span)),
            Resolved::Type(t, _) => {
                if args.len() != 1 || args[0].width.is_some() {
                    return self.error(code::BAD_TYPECAST, span);
                }
                self.typecast(t, &args[0].value, span)
            }
            Resolved::Value(v) if matches!(self.types.get(v.ty), Type::Procedural(_)) => {
                self.call_indirect(v, args, span, false)
            }
            Resolved::Method(m) => self.method_value(*m, args, span),
            _ => self.error(code::BAD_PROC_REFERENCE, callee.span),
        }
    }

    pub(crate) fn call_routine(
        &mut self,
        id: RoutineId,
        args: &[ast::Arg],
        span: Span,
        statement: bool,
    ) -> SResult<Expr> {
        let sig = self.routine(id).sig.clone();
        let args = self.arguments(&sig, args, span)?;
        let ty = match sig.result {
            Some(t) => t,
            None if statement => self.types.builtin.untyped,
            None => return self.error_with(code::NO_VALUE, span, format!(": {}", self.routine(id).display)),
        };
        Ok(Expr::new(ExprKind::Call { callee: Callee::Routine(id), args }, ty, span))
    }

    pub(crate) fn call_indirect(
        &mut self,
        target: Expr,
        args: &[ast::Arg],
        span: Span,
        statement: bool,
    ) -> SResult<Expr> {
        let Type::Procedural(sig) = self.types.get(target.ty).clone() else { unreachable!() };
        let args = self.arguments(&sig, args, span)?;
        let ty = match sig.result {
            Some(t) => t,
            None if statement => self.types.builtin.untyped,
            None => return self.error(code::NO_VALUE, span),
        };
        Ok(Expr::new(ExprKind::Call { callee: Callee::Indirect(Box::new(target)), args }, ty, span))
    }

    pub(crate) fn arguments(&mut self, sig: &Signature, args: &[ast::Arg], span: Span) -> SResult<Vec<Expr>> {
        if args.len() != sig.params.len() {
            return self.error_with(
                code::WRONG_ARG_COUNT,
                span,
                format!(": diharapkan {}, diberikan {}", sig.params.len(), args.len()),
            );
        }
        let mut out = Vec::new();
        for (p, a) in sig.params.iter().zip(args) {
            if a.width.is_some() {
                return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
            }
            out.push(self.argument(p, &a.value)?);
        }
        Ok(out)
    }

    pub(crate) fn argument(&mut self, p: &Param, a: &ast::Expr) -> SResult<Expr> {
        match passing(&self.types, p.mode, p.ty) {
            Passing::Value => {
                let v = self.expr_expect(a, Some(p.ty))?;
                self.coerce(v, p.ty, a.span)
            }
            Passing::RefCopy => {
                let v = self.expr_expect(a, Some(p.ty))?;
                self.coerce(v, p.ty, a.span)
            }
            Passing::Ref if p.mode == ParamMode::Const => {
                let v = self.expr_expect(a, Some(p.ty))?;
                if p.ty == self.types.builtin.untyped {
                    if !v.is_lvalue() {
                        return self.error(code::VAR_IDENT_EXPECTED, a.span);
                    }
                    return Ok(v);
                }
                self.coerce(v, p.ty, a.span)
            }
            Passing::Ref => {
                let v = self.expr(a)?;
                if !v.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, a.span);
                }
                if p.ty == self.types.builtin.untyped || v.ty == p.ty {
                    return Ok(v);
                }
                // A descendant object for a var parameter of its ancestor's type.
                if self.types.object(p.ty).is_some() && self.types.is_descendant(v.ty, p.ty) {
                    return Ok(v);
                }
                let same_string = match (self.types.get(v.ty), self.types.get(p.ty)) {
                    (Type::ShortString(x), Type::ShortString(y)) => x == y || !self.sw.get(Switches::VAR_STRING),
                    (Type::OpenString, Type::ShortString(_)) => true,
                    _ => false,
                };
                if same_string {
                    return Ok(v);
                }
                // Identical ordinal representation (e.g. Integer vs SmallInt).
                if self.types.is_ordinal(v.ty)
                    && self.types.is_ordinal(p.ty)
                    && self.types.base(v.ty) == self.types.base(p.ty)
                    && self.types.size(v.ty) == self.types.size(p.ty)
                {
                    return Ok(v);
                }
                self.error_with(
                    code::TYPE_MISMATCH,
                    a.span,
                    format!(": parameter var memerlukan {}", self.types.display(p.ty)),
                )
            }
            Passing::OpenArray if p.ty == self.types.builtin.openstring => {
                let v = self.expr(a)?;
                if !v.is_lvalue() || self.class(v.ty) != Class::Str {
                    return self.error(code::STRING_VAR_EXPECTED, a.span);
                }
                Ok(v)
            }
            Passing::OpenArray => {
                let Type::OpenArray { elem } = self.types.get(p.ty).clone() else { unreachable!() };
                let v = self.expr(a)?;
                match self.types.get(v.ty).clone() {
                    Type::Array { elem: e, .. } | Type::OpenArray { elem: e } if e == elem => Ok(v),
                    _ => self.error(code::TYPE_MISMATCH, a.span),
                }
            }
        }
    }

    /// The RTL routine `name` of the System unit.
    pub(crate) fn rtl(&self, name: &str, span: Span) -> SResult<RoutineId> {
        match self.units.first().and_then(|u| u.interface.get(name)) {
            Some(Sym::Routine(id)) => Ok(*id),
            _ => self.error_with(code::INTERNAL, span, format!(": RTL tidak lengkap, {name} tidak ada di unit System")),
        }
    }

    /// The System variable `name` (Input, Output, ...).
    pub(crate) fn rtl_var(&self, name: &str, span: Span) -> SResult<Expr> {
        match self.units.first().and_then(|u| u.interface.get(name)) {
            Some(Sym::Var(v, ty)) => Ok(self.var_expr(*v, *ty, span)),
            _ => self.error_with(code::INTERNAL, span, format!(": RTL tidak lengkap, {name} tidak ada di unit System")),
        }
    }

    /// Calls RTL routine `name` with already analysed arguments.
    pub(crate) fn rtl_call(&self, name: &str, args: Vec<Expr>, span: Span) -> SResult<Expr> {
        let id = self.rtl(name, span)?;
        let ty = self.routine(id).sig.result.unwrap_or(self.types.builtin.untyped);
        Ok(Expr::new(ExprKind::Call { callee: Callee::Routine(id), args }, ty, span))
    }
}

/// Wraps a 64-bit value to an integer kind (truncate, then extend).
pub(crate) fn wrap(v: i64, k: IntKind) -> i64 {
    match (k.size, k.signed) {
        (1, true) => v as i8 as i64,
        (1, false) => v as u8 as i64,
        (2, true) => v as i16 as i64,
        (2, false) => v as u16 as i64,
        (4, true) => v as i32 as i64,
        (4, false) => v as u32 as i64,
        _ => v,
    }
}
