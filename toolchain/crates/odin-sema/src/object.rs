// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Turbo Pascal objects, lowered to what the code generator already knows:
//! an object is a record (with a VMT pointer when it has constructors,
//! destructors or virtual methods), a VMT is a read-only global of code
//! pointers, and a method is a routine whose first parameter is `Self`, a
//! pointer to the object.
//!
//! Constructors also take the VMT to store (`nil` for `inherited Init`) and
//! return `Self`, or `nil` after `Fail`. Called with `Self = nil` they
//! allocate the object (size from the VMT), which makes `New(P, Init)` and
//! `New(PType, Init)` ordinary calls. Layout matches FPC `-Mtp`: inherited
//! fields first, the VMT pointer after the fields of the first type in the
//! hierarchy that needs one.

use std::collections::HashSet;

use odin_base::{Span, code};
use odin_ir::*;
use odin_syntax::{Switches, ast};

use crate::expr::Resolved;
use crate::scope::Sym;
use crate::{Analyzer, Frame, SResult};

/// How a method call passes `Self`.
#[derive(Clone, Debug)]
pub(crate) enum SelfArg {
    /// An object variable; its address is passed.
    Instance(Expr),
    /// A pointer to the object; `nil` makes a constructor allocate.
    Pointer(Expr),
}

/// The VMT a constructor call passes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CtorVmt {
    /// The VMT of this object type, which the constructor stores.
    Of(TypeId),
    /// `nil`: `inherited Init` and `TParent.Init` keep the VMT already set.
    Keep,
}

/// A method together with the object it is called on.
#[derive(Clone, Debug)]
pub(crate) struct MethodRef {
    pub this: SelfArg,
    /// Static type of `Self` (gives the VMT offset).
    pub object: TypeId,
    pub method: Method,
    /// Virtual methods dispatch through the VMT, except for `inherited`
    /// and `TParent.Method` calls.
    pub dispatch: bool,
    pub vmt: CtorVmt,
}

/// The object a method body belongs to.
#[derive(Clone, Debug)]
pub(crate) struct ObjectScope {
    pub ty: TypeId,
    pub method: Method,
    /// Constructor: set when it allocated `Self` (so `Fail` frees it).
    pub allocated: Option<Var>,
}

fn align_up(v: u64, a: u64) -> u64 {
    v.div_ceil(a.max(1)) * a.max(1)
}

fn method_kind(k: ast::RoutineKind) -> MethodKind {
    match k {
        ast::RoutineKind::Procedure => MethodKind::Procedure,
        ast::RoutineKind::Function => MethodKind::Function,
        ast::RoutineKind::Constructor => MethodKind::Constructor,
        ast::RoutineKind::Destructor => MethodKind::Destructor,
    }
}

/// Hidden parameters before the declared ones: `Self`, and the VMT for
/// constructors.
pub(crate) fn hidden_params(kind: MethodKind) -> usize {
    if kind == MethodKind::Constructor { 2 } else { 1 }
}

impl Analyzer<'_> {
    // ---- object types --------------------------------------------------------------

    /// Fills in object type `ty`, already declared under `name` so that its
    /// methods can mention it.
    pub(crate) fn object_type(&mut self, ty: TypeId, name: &ast::Ident, obj: &ast::ObjectType) -> SResult<()> {
        if !self.frames.is_empty() {
            return self.error(code::LOCAL_OBJECT_TYPE, name.span);
        }
        let parent = match &obj.parent {
            Some(q) => match self.lookup_type(q)? {
                Some(t) if self.types.object(t).is_some() && t != ty => Some(t),
                Some(_) => return self.error(code::OBJECT_TYPE_EXPECTED, q.span()),
                None => return self.error_with(code::UNKNOWN_IDENT, q.span(), format!(": {}", q.name.name)),
            },
            None => None,
        };
        let base = parent.and_then(|p| self.types.object(p).cloned());
        let mut fields = base.as_ref().map(|b| b.fields.clone()).unwrap_or_default();
        let mut private_fields = base.as_ref().map(|b| b.private_fields.clone()).unwrap_or_default();
        let mut methods = base.as_ref().map(|b| b.methods.clone()).unwrap_or_default();
        let mut slots = base.as_ref().map_or(0, |b| b.slots);
        let mut vmt_offset = base.as_ref().and_then(|b| b.vmt_offset);
        let start = base.as_ref().map_or(0, |b| b.size);
        let mut align = base.as_ref().map_or(1, |b| b.align);

        // Fields.
        let mut seen: HashSet<String> = fields.iter().map(|f| f.name.to_ascii_uppercase()).collect();
        let mut list = Vec::new();
        for m in &obj.members {
            let ast::ObjectMember::Field { decl, private } = m else { continue };
            let fty = self.resolve_type(&decl.ty)?;
            if fty == ty {
                return self.error(code::ERROR_IN_TYPE, decl.ty.span);
            }
            for n in &decl.names {
                if !seen.insert(n.key()) {
                    return self.error_with(code::DUPLICATE_IDENT, n.span, format!(": {}", n.name));
                }
                list.push((n.name.clone(), fty));
                if *private {
                    private_fields.push(n.key());
                }
            }
        }
        let (own, mut end, own_align) = self.types.layout_fields(&list, start);
        fields.extend(own);
        align = align.max(own_align);
        let needs_vmt = obj.members.iter().any(|m| match m {
            ast::ObjectMember::Method { heading, .. } => {
                matches!(heading.kind, ast::RoutineKind::Constructor | ast::RoutineKind::Destructor)
                    || heading.has(|d| matches!(d, ast::DirectiveKind::Virtual(_)))
            }
            _ => false,
        });
        if vmt_offset.is_none() && needs_vmt {
            let off = align_up(end, 8);
            vmt_offset = Some(off);
            end = off + 8;
            align = align.max(8);
        }
        let size = align_up(end, align as u64);
        if size > i32::MAX as u64 {
            return self.error(code::STRUCTURE_TOO_LARGE, name.span);
        }
        let module = self.cur_unit;
        let provisional = |methods: Vec<Method>, slots: u32, vmt: Option<u32>| ObjectType {
            parent,
            fields: fields.clone(),
            private_fields: private_fields.clone(),
            methods,
            size,
            align,
            vmt_offset,
            vmt,
            slots,
            module,
        };
        // The type is complete enough for method signatures that mention it.
        self.types.set(ty, Type::Object(Box::new(provisional(methods.clone(), slots, None))));

        // Methods.
        let object_key = name.key();
        let mut own_methods = HashSet::new();
        for m in &obj.members {
            let ast::ObjectMember::Method { heading: h, private } = m else { continue };
            let key = h.name.key();
            if !own_methods.insert(key.clone()) || seen.contains(&key) {
                return self.error_with(code::DUPLICATE_IDENT, h.name.span, format!(": {}", h.name.name));
            }
            let kind = method_kind(h.kind);
            let is_virtual = h.has(|d| matches!(d, ast::DirectiveKind::Virtual(_)));
            if is_virtual && kind == MethodKind::Constructor {
                return self.error(code::VIRTUAL_CONSTRUCTOR, h.name.span);
            }
            let sig = self.method_signature(ty, kind, h)?;
            let inherited = methods.iter().position(|x| x.name.eq_ignore_ascii_case(&h.name.name));
            let slot = match inherited.map(|i| methods[i].clone()) {
                Some(old) if old.slot.is_some() => {
                    if !is_virtual {
                        return self.error(code::VIRTUAL_EXPECTED, h.name.span);
                    }
                    let old_sig = self.routine(old.routine).sig.clone();
                    if old.kind != kind || !self.same_user_signature(&old_sig, &sig, hidden_params(kind)) {
                        return self.error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
                    }
                    old.slot
                }
                _ if is_virtual => {
                    slots += 1;
                    Some(slots - 1)
                }
                _ => None,
            };
            let symbol = format!("{}.{}.{}", self.unit_prefix(), object_key, key);
            let display = match self.cur_unit {
                Some(u) => format!("{}.{}.{}", self.unit_display(u), name.name, h.name.name),
                None => format!("{}.{}", name.name, h.name.name),
            };
            let id = self.new_routine(&symbol, &display, h.span);
            self.set_signature(id, sig);
            self.missing_methods.push((id, h.name.span, self.cur_unit));
            let entry = Method { name: h.name.name.clone(), routine: id, kind, slot, private: *private, owner: ty };
            match inherited {
                Some(i) => methods[i] = entry,
                None => methods.push(entry),
            }
        }
        let vmt = vmt_offset.map(|_| self.vmt_global(&object_key, parent, size, &methods, slots, name.span));
        self.types.set(ty, Type::Object(Box::new(provisional(methods, slots, vmt))));
        Ok(())
    }

    fn method_signature(&mut self, obj: TypeId, kind: MethodKind, h: &ast::RoutineHeading) -> SResult<Signature> {
        let mut sig = self.signature(h)?;
        if kind == MethodKind::Function && sig.result.is_none() {
            return self.error(code::COLON_EXPECTED, h.span.end_point());
        }
        let self_ty = self.pointer_to(obj);
        let mut params = vec![Param { name: "Self".into(), mode: ParamMode::Value, ty: self_ty }];
        if kind == MethodKind::Constructor {
            params.push(Param { name: "$vmt".into(), mode: ParamMode::Value, ty: self.types.builtin.pointer });
            sig.result = Some(self_ty);
        }
        params.append(&mut sig.params);
        sig.params = params;
        Ok(sig)
    }

    /// Same declared parameters and result (hidden parameters excluded).
    fn same_user_signature(&self, a: &Signature, b: &Signature, hidden: usize) -> bool {
        let result = match (a.result, b.result) {
            (Some(x), Some(y)) => x == y || hidden == 2,
            (None, None) => true,
            _ => false,
        };
        result
            && a.params.len() == b.params.len()
            && a.params
                .iter()
                .zip(&b.params)
                .skip(hidden)
                .all(|(x, y)| x.mode == y.mode && self.same_param_type(x.ty, y.ty))
    }

    /// The VMT of an object type: size, -size, parent VMT, code pointers.
    fn vmt_global(
        &mut self,
        object_key: &str,
        parent: Option<TypeId>,
        size: u64,
        methods: &[Method],
        slots: u32,
        span: Span,
    ) -> u32 {
        let count = VMT_HEADER as usize / 8 + slots as usize;
        let mut bytes = vec![0u8; count * 8];
        bytes[0..8].copy_from_slice(&(size as i64).to_le_bytes());
        bytes[8..16].copy_from_slice(&(-(size as i64)).to_le_bytes());
        let mut pointers = Vec::new();
        if let Some(pv) = parent.and_then(|p| self.types.object(p)).and_then(|o| o.vmt) {
            pointers.push((16, self.globals[pv as usize].symbol.clone()));
        }
        for m in methods {
            if let Some(slot) = m.slot {
                pointers.push((VMT_HEADER + 8 * slot as u64, self.routine(m.routine).symbol.clone()));
            }
        }
        let b = self.types.builtin;
        let ty = self.types.add(Type::Array { index: b.longint, lo: 0, hi: count as i64 - 1, elem: b.int64 });
        self.globals.push(Global {
            symbol: format!("{}.{}.$VMT", self.unit_prefix(), object_key),
            name: "$VMT".into(),
            ty,
            init: Some(GlobalInit { bytes, pointers }),
            readonly: true,
            span,
        });
        self.globals.len() as u32 - 1
    }

    /// Address of the VMT of object type `ty`.
    pub(crate) fn vmt_address(&self, ty: TypeId, span: Span) -> SResult<Expr> {
        let Some(g) = self.types.object(ty).and_then(|o| o.vmt) else {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        };
        let global = &self.globals[g as usize];
        let var = Expr::new(ExprKind::Var(Var::Global(GlobalId(g))), global.ty, span);
        Ok(Expr::new(ExprKind::AddrOf(Box::new(var)), self.types.builtin.pointer, span))
    }

    /// The VMT pointer stored in an object variable.
    pub(crate) fn vmt_of_instance(&self, instance: Expr, span: Span) -> SResult<Expr> {
        let Some(offset) = self.types.object(instance.ty).and_then(|o| o.vmt_offset) else {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        };
        Ok(Expr::new(ExprKind::Field { base: Box::new(instance), offset }, self.types.builtin.pointer, span))
    }

    /// Methods still waiting for their body; reported at the end of the
    /// unit or program that declares their type.
    pub(crate) fn check_methods_implemented(&self) -> SResult<()> {
        if let Some((id, span, _)) = self.missing_methods.iter().find(|(_, _, m)| *m == self.cur_unit) {
            return self.error_with(code::UNDEFINED_FORWARD, *span, format!(": {}", self.routine(*id).display));
        }
        Ok(())
    }

    // ---- method bodies --------------------------------------------------------------

    /// `procedure TObj.Name(...); begin ... end;`
    pub(crate) fn method_decl(&mut self, r: &ast::Routine, owner: &ast::Ident) -> SResult<()> {
        let h = &r.heading;
        let ty = match self.lookup(&owner.key()) {
            Some(Sym::Type(t)) if self.types.object(t).is_some() => t,
            Some(_) => return self.error(code::OBJECT_TYPE_EXPECTED, owner.span),
            None => return self.error_with(code::UNKNOWN_IDENT, owner.span, format!(": {}", owner.name)),
        };
        let object = self.types.object(ty).cloned().expect("object type");
        let Some(method) = object.method(&h.name.key()).filter(|m| m.owner == ty).cloned() else {
            return self.error_with(code::METHOD_IDENT_EXPECTED, h.name.span, format!(": {}", h.name.name));
        };
        if method.kind != method_kind(h.kind) {
            return self.error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
        }
        if !h.params.is_empty() || h.result.is_some() {
            let sig = self.method_signature(ty, method.kind, h)?;
            let declared = self.routine(method.routine).sig.clone();
            if !self.same_user_signature(&declared, &sig, hidden_params(method.kind)) {
                return self.error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
            }
        }
        let Some(pos) = self.missing_methods.iter().position(|(id, _, _)| *id == method.routine) else {
            return self.error_with(code::DUPLICATE_IDENT, h.name.span, format!(": {}", h.name.name));
        };
        self.missing_methods.remove(pos);
        match &r.body {
            ast::RoutineBody::Block(block) => self.method_body(&method, ty, h, block),
            ast::RoutineBody::Inline(span) => self.error_with(code::DOS_ONLY, *span, ": inline(...)"),
            _ => self.error_with(code::NOT_SUPPORTED, h.span, ": metode external atau forward"),
        }
    }

    fn method_body(&mut self, method: &Method, ty: TypeId, h: &ast::RoutineHeading, block: &ast::Block) -> SResult<()> {
        let id = method.routine;
        let mut frame = Frame::new(id);
        frame.object = Some(ObjectScope { ty, method: method.clone(), allocated: None });
        self.frames.push(frame);
        let params = self.routine(id).sig.params.clone();
        let hidden = hidden_params(method.kind);
        let spans: Vec<Span> = if h.params.is_empty() {
            vec![h.name.span; params.len()]
        } else {
            h.params.iter().flat_map(|g| g.names.iter().map(|n| n.span)).collect()
        };
        for (i, p) in params.iter().enumerate().skip(hidden) {
            let span = spans.get(i - hidden).copied().unwrap_or(h.name.span);
            let ident = ast::Ident { name: p.name.clone(), span };
            self.declare(&ident, Sym::Var(Var::Local { routine: id, index: i as u32 }, p.ty))?;
        }
        let mut body = Vec::new();
        if method.kind == MethodKind::Constructor {
            body = self.constructor_prologue(id, ty, h.span)?;
        }
        self.decls(&block.decls)?;
        match &block.body {
            ast::Body::Statements(stmts, _) => body.extend(self.stmt_list(stmts)?),
            ast::Body::Asm(a) => return self.error_with(code::NOT_SUPPORTED, a.span, ": metode assembler"),
        }
        self.finish_frame()?;
        self.routine_mut(id).body = RoutineBody::Code(body);
        Ok(())
    }

    /// Allocates `Self` when it is nil, stores the VMT (unless nil), and
    /// makes `Self` the result.
    fn constructor_prologue(&mut self, id: RoutineId, ty: TypeId, span: Span) -> SResult<Vec<Stmt>> {
        let b = self.types.builtin;
        let stmt = |kind| Stmt { kind, span };
        let self_ty = self.routine(id).sig.params[0].ty;
        let this = self.var_expr(Var::Local { routine: id, index: 0 }, self_ty, span);
        let vmt = self.var_expr(Var::Local { routine: id, index: 1 }, b.pointer, span);
        let allocated = self.add_temp(b.boolean);
        if let Some(scope) = self.frames.last_mut().and_then(|f| f.object.as_mut()) {
            scope.allocated = Some(allocated);
        }
        let flag = self.var_expr(allocated, b.boolean, span);
        let nil = Expr::new(ExprKind::Nil, b.nil, span);
        let is = |op, l: &Expr| {
            Expr::new(ExprKind::Binary(BinOp::Cmp(op), Box::new(l.clone()), Box::new(nil.clone())), b.boolean, span)
        };
        let int64_ptr = self.pointer_to(b.int64);
        let size_ptr = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(vmt.clone())), int64_ptr, span);
        let size = Expr::new(ExprKind::Deref(Box::new(size_ptr)), b.int64, span);
        let memory = self.rtl_call("ODIN_GETMEM", vec![size], span)?;
        let memory = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(memory)), self_ty, span);
        let mut out = vec![
            stmt(StmtKind::Assign { target: flag.clone(), value: Expr::new(ExprKind::Int(0), b.boolean, span) }),
            stmt(StmtKind::If {
                cond: is(Cond::Eq, &this),
                then: vec![
                    stmt(StmtKind::Assign { target: this.clone(), value: memory }),
                    stmt(StmtKind::Assign { target: flag, value: Expr::new(ExprKind::Int(1), b.boolean, span) }),
                ],
                otherwise: vec![],
            }),
        ];
        let object = Expr::new(ExprKind::Deref(Box::new(this.clone())), ty, span);
        if let Ok(slot) = self.vmt_of_instance(object, span) {
            out.push(stmt(StmtKind::If {
                cond: is(Cond::Ne, &vmt),
                then: vec![stmt(StmtKind::Assign { target: slot, value: vmt })],
                otherwise: vec![],
            }));
        }
        let index = self.routine(id).result_local().expect("constructor result");
        let result = self.var_expr(Var::Local { routine: id, index }, self_ty, span);
        out.push(stmt(StmtKind::Assign { target: result, value: this }));
        Ok(out)
    }

    /// `Fail`: frees `Self` if this constructor allocated it, returns nil.
    pub(crate) fn fail_stmt(&mut self, span: Span) -> SResult<Vec<Stmt>> {
        let b = self.types.builtin;
        let stmt = |kind| Stmt { kind, span };
        let Some(frame) = self.frames.last() else { return self.error(code::FAIL_OUTSIDE_CONSTRUCTOR, span) };
        let Some(ObjectScope { ty, allocated: Some(flag), .. }) = frame.object.clone() else {
            return self.error(code::FAIL_OUTSIDE_CONSTRUCTOR, span);
        };
        let id = frame.routine;
        let self_ty = self.routine(id).sig.params[0].ty;
        let this = self.var_expr(Var::Local { routine: id, index: 0 }, self_ty, span);
        let size = Expr::new(ExprKind::Int(self.types.size(ty) as i64), b.int64, span);
        let pointer = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(this)), b.pointer, span);
        let free = self.rtl_call("ODIN_FREEMEM", vec![pointer, size], span)?;
        let index = self.routine(id).result_local().expect("constructor result");
        let result = self.var_expr(Var::Local { routine: id, index }, self_ty, span);
        Ok(vec![
            stmt(StmtKind::If {
                cond: self.var_expr(flag, b.boolean, span),
                then: vec![stmt(StmtKind::Call(free))],
                otherwise: vec![],
            }),
            stmt(StmtKind::Assign { target: result, value: Expr::new(ExprKind::Nil, b.nil, span) }),
            stmt(StmtKind::Exit),
        ])
    }

    // ---- names inside methods ---------------------------------------------------------

    /// The innermost frame that is a method body.
    pub(crate) fn method_frame(&self) -> Option<(usize, ObjectScope)> {
        self.frames.iter().enumerate().rev().find_map(|(i, f)| f.object.clone().map(|o| (i, o)))
    }

    /// `Self` of the innermost method.
    pub(crate) fn self_expr(&self, span: Span) -> Option<Expr> {
        let (i, scope) = self.method_frame()?;
        let id = self.frames[i].routine;
        let self_ty = self.routine(id).sig.params[0].ty;
        let p = self.var_expr(Var::Local { routine: id, index: 0 }, self_ty, span);
        Some(Expr::new(ExprKind::Deref(Box::new(p)), scope.ty, span))
    }

    fn private_visible(&self, object: TypeId) -> bool {
        self.types.object(object).is_some_and(|o| o.module == self.cur_unit)
    }

    /// Field or method `key` of `instance` (an object variable).
    pub(crate) fn object_member(&self, instance: Expr, key: &str, span: Span) -> SResult<Option<Resolved>> {
        let Some(o) = self.types.object(instance.ty) else { return Ok(None) };
        let visible = self.private_visible(instance.ty);
        if let Some(f) = o.field(key) {
            if o.private_fields.iter().any(|p| p == key) && !visible {
                return Ok(None);
            }
            let (offset, ty) = (f.offset, f.ty);
            return Ok(Some(Resolved::Value(Expr::new(
                ExprKind::Field { base: Box::new(instance), offset },
                ty,
                span,
            ))));
        }
        if let Some(m) = o.method(key) {
            if m.private && !visible {
                return Ok(None);
            }
            let object = instance.ty;
            return Ok(Some(Resolved::Method(Box::new(MethodRef {
                this: SelfArg::Instance(instance),
                object,
                method: m.clone(),
                dispatch: true,
                vmt: CtorVmt::Of(object),
            }))));
        }
        Ok(None)
    }

    /// A name inside a method: `Self`, then the method's (and nested
    /// routines') own declarations, then the object's fields and methods.
    pub(crate) fn self_member(&self, key: &str, span: Span) -> SResult<Option<Resolved>> {
        let Some((i, _)) = self.method_frame() else { return Ok(None) };
        if key == "SELF" {
            return Ok(self.self_expr(span).map(Resolved::Value));
        }
        if self.frames[i..].iter().any(|f| f.scope.contains(key)) {
            return Ok(None);
        }
        let instance = self.self_expr(span).expect("method frame");
        self.object_member(instance, key, span)
    }

    /// `inherited Name`: the parent's method, called statically on `Self`.
    pub(crate) fn inherited_member(&self, name: &ast::Ident) -> SResult<Resolved> {
        let Some((_, scope)) = self.method_frame() else { return self.error(code::NO_INHERITED, name.span) };
        let Some(parent) = self.types.object(scope.ty).and_then(|o| o.parent) else {
            return self.error(code::NO_INHERITED, name.span);
        };
        let Some(m) = self.types.object(parent).and_then(|o| o.method(&name.key())).cloned() else {
            return self.error_with(code::UNKNOWN_IDENT, name.span, format!(": {}", name.name));
        };
        let this = self.self_expr(name.span).expect("method frame");
        Ok(Resolved::Method(Box::new(MethodRef {
            this: SelfArg::Instance(this),
            object: parent,
            method: m,
            dispatch: false,
            vmt: CtorVmt::Keep,
        })))
    }

    /// `TObj.Method`: inside a method of `TObj` or a descendant, a static
    /// call on `Self`; elsewhere only its address can be taken.
    pub(crate) fn qualified_method(&self, ty: TypeId, field: &ast::Ident, span: Span) -> SResult<Resolved> {
        let Some(m) = self.types.object(ty).and_then(|o| o.method(&field.key())).cloned() else {
            return self.error_with(code::UNKNOWN_IDENT, field.span, format!(": {}", field.name));
        };
        match (self.method_frame(), self.self_expr(span)) {
            (Some((_, scope)), Some(this)) if self.types.is_descendant(scope.ty, ty) => {
                Ok(Resolved::Method(Box::new(MethodRef {
                    this: SelfArg::Instance(this),
                    object: ty,
                    method: m,
                    dispatch: false,
                    vmt: CtorVmt::Keep,
                })))
            }
            _ => Ok(Resolved::MethodName(m.routine, span)),
        }
    }

    /// The function result of the method being analysed, when `key` is its
    /// name (`Area := 3.14` inside `TCircle.Area`).
    pub(crate) fn method_result(&self, key: &str, span: Span) -> Option<Expr> {
        let (i, scope) = self.method_frame()?;
        if !scope.method.name.eq_ignore_ascii_case(key) || self.frames[i + 1..].iter().any(|f| f.scope.contains(key)) {
            return None;
        }
        let id = self.frames[i].routine;
        let index = self.routine(id).result_local()?;
        let ty = self.routine(id).locals[index as usize].ty;
        if scope.method.kind != MethodKind::Function {
            return None;
        }
        Some(self.var_expr(Var::Local { routine: id, index }, ty, span))
    }

    // ---- calls ------------------------------------------------------------------------

    /// The call itself. A constructor call has the pointer type of its
    /// `Self` (nil after `Fail`).
    pub(crate) fn method_call(
        &mut self,
        m: MethodRef,
        args: &[ast::Arg],
        span: Span,
        statement: bool,
    ) -> SResult<Expr> {
        let b = self.types.builtin;
        let rid = m.method.routine;
        let sig = self.routine(rid).sig.clone();
        let hidden = hidden_params(m.method.kind);
        let self_ty = sig.params[0].ty;
        let this = match m.this {
            SelfArg::Instance(x) => {
                if !x.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, x.span);
                }
                Expr::new(ExprKind::AddrOf(Box::new(x)), self_ty, span)
            }
            SelfArg::Pointer(p) => Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), self_ty, span),
        };
        let mut values = vec![this];
        if m.method.kind == MethodKind::Constructor {
            values.push(match m.vmt {
                CtorVmt::Of(t) => self.vmt_address(t, span)?,
                CtorVmt::Keep => Expr::new(ExprKind::Nil, b.pointer, span),
            });
        }
        let declared = Signature { params: sig.params[hidden..].to_vec(), result: sig.result };
        values.extend(self.arguments(&declared, args, span)?);
        let callee = match m.method.slot {
            Some(slot) if m.dispatch => {
                let vmt_offset = self.types.object(m.object).and_then(|o| o.vmt_offset).expect("virtual needs a VMT");
                Callee::Virtual { routine: rid, vmt_offset, slot, check: self.sw.get(Switches::RANGE) }
            }
            _ => Callee::Routine(rid),
        };
        let ty = match sig.result {
            Some(t) => t,
            None if statement => b.untyped,
            None => return self.error_with(code::NO_VALUE, span, format!(": {}", self.routine(rid).display)),
        };
        Ok(Expr::new(ExprKind::Call { callee, args: values }, ty, span))
    }

    /// A method call used as a value: a constructor gives TRUE unless it
    /// failed.
    pub(crate) fn method_value(&mut self, m: MethodRef, args: &[ast::Arg], span: Span) -> SResult<Expr> {
        let ctor = m.method.kind == MethodKind::Constructor;
        let call = self.method_call(m, args, span, false)?;
        if !ctor {
            return Ok(call);
        }
        let b = self.types.builtin;
        let nil = Expr::new(ExprKind::Nil, b.nil, span);
        Ok(Expr::new(ExprKind::Binary(BinOp::Cmp(Cond::Ne), Box::new(call), Box::new(nil)), b.boolean, span))
    }

    /// `Ctor(args)` (or a bare name) as the second argument of New/Dispose:
    /// the method of `object` it names, and its arguments.
    pub(crate) fn extended_method<'e>(
        &self,
        object: TypeId,
        e: &'e ast::Expr,
        want: MethodKind,
    ) -> SResult<(Method, &'e [ast::Arg])> {
        let (name, args): (&ast::Ident, &[ast::Arg]) = match &e.kind {
            ast::ExprKind::Name(n) => (n, &[]),
            ast::ExprKind::Call { callee, args } => match &callee.kind {
                ast::ExprKind::Name(n) => (n, args),
                _ => return self.error(code::METHOD_IDENT_EXPECTED, callee.span),
            },
            _ => return self.error(code::METHOD_IDENT_EXPECTED, e.span),
        };
        let found = self.types.object(object).and_then(|o| o.method(&name.key())).cloned();
        match found {
            Some(m) if m.kind == want => Ok((m, args)),
            _ if want == MethodKind::Constructor => self.error(code::CONSTRUCTOR_EXPECTED, name.span),
            _ => self.error(code::DESTRUCTOR_EXPECTED, name.span),
        }
    }

    /// `New(P, Init(...))` / `New(PType, Init(...))`: the constructor
    /// called with `Self = nil` allocates the object.
    pub(crate) fn new_object(&mut self, pointer_ty: TypeId, ctor: &ast::Expr, span: Span) -> SResult<Expr> {
        let Type::Pointer(Some(object)) = self.types.get(pointer_ty).clone() else {
            return self.error(code::POINTER_VAR_EXPECTED, span);
        };
        if self.types.object(object).is_none() {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        }
        let (method, args) = self.extended_method(object, ctor, MethodKind::Constructor)?;
        let nil = Expr::new(ExprKind::Nil, self.types.builtin.nil, span);
        let m = MethodRef { this: SelfArg::Pointer(nil), object, method, dispatch: false, vmt: CtorVmt::Of(object) };
        let call = self.method_call(m, args, span, false)?;
        Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(call)), pointer_ty, span))
    }

    /// `Dispose(P, Done(...))`: the destructor (virtual when declared so),
    /// then the memory.
    pub(crate) fn dispose_object(&mut self, p: Expr, dtor: &ast::Expr, span: Span) -> SResult<Vec<Stmt>> {
        let b = self.types.builtin;
        let Type::Pointer(Some(object)) = self.types.get(p.ty).clone() else {
            return self.error(code::POINTER_VAR_EXPECTED, span);
        };
        if self.types.object(object).is_none() {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        }
        let (method, args) = self.extended_method(object, dtor, MethodKind::Destructor)?;
        let instance = Expr::new(ExprKind::Deref(Box::new(p.clone())), object, span);
        let m = MethodRef { this: SelfArg::Instance(instance), object, method, dispatch: true, vmt: CtorVmt::Keep };
        let call = self.method_call(m, args, span, true)?;
        let size = Expr::new(ExprKind::Int(self.types.size(object) as i64), b.int64, span);
        let pointer = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), b.pointer, span);
        let free = self.rtl_call("ODIN_FREEMEM", vec![pointer, size], span)?;
        Ok(vec![Stmt { kind: StmtKind::Call(call), span }, Stmt { kind: StmtKind::Call(free), span }])
    }
}
