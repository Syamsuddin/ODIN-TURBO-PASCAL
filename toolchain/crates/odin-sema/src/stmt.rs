// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Statements.

use odin_base::{Span, code};
use odin_ir::*;
use odin_syntax::{Switches, ast};

use crate::expr::{Class, Resolved};
use crate::object::PropRef;
use crate::scope::Sym;
use crate::{Analyzer, SResult, WithScope};

fn stmt(kind: StmtKind, span: Span) -> Stmt {
    Stmt { kind, span }
}

impl Analyzer<'_> {
    pub(crate) fn stmt_list(&mut self, stmts: &[ast::Stmt]) -> SResult<Vec<Stmt>> {
        let mut out = Vec::new();
        for s in stmts {
            self.stmt(s, &mut out)?;
        }
        Ok(out)
    }

    fn body(&mut self, s: &ast::Stmt) -> SResult<Vec<Stmt>> {
        let mut out = Vec::new();
        self.stmt(s, &mut out)?;
        Ok(out)
    }

    fn loop_body(&mut self, s: &ast::Stmt) -> SResult<Vec<Stmt>> {
        self.frames.last_mut().unwrap().loops += 1;
        let body = self.body(s);
        self.frames.last_mut().unwrap().loops -= 1;
        body
    }

    fn condition(&mut self, e: &ast::Expr) -> SResult<Expr> {
        let c = self.expr(e)?;
        if self.class(c.ty) != Class::Bool {
            return self.error(code::BOOLEAN_EXPR_EXPECTED, e.span);
        }
        Ok(c)
    }

    fn stmt(&mut self, s: &ast::Stmt, out: &mut Vec<Stmt>) -> SResult<()> {
        self.sw = s.switches;
        let span = s.span;
        match &s.kind {
            ast::StmtKind::Empty => {}
            ast::StmtKind::Assign { target, value } => {
                if let Some((p, index)) = self.property_target(target)? {
                    out.extend(self.property_write(p, &index, value, span)?);
                    return Ok(());
                }
                let t = self.assign_target(target)?;
                let v = self.expr_expect(value, Some(t.ty))?;
                if matches!(self.types.get(t.ty), Type::File { .. }) || Some(t.ty) == self.text_type {
                    return self.error(code::ILLEGAL_ASSIGNMENT, target.span);
                }
                let v = self.coerce(v, t.ty, value.span)?;
                out.push(stmt(StmtKind::Assign { target: t, value: v }, span));
            }
            ast::StmtKind::Call(e) => self.call_stmt(e, span, out)?,
            ast::StmtKind::Compound(list) => {
                let body = self.stmt_list(list)?;
                out.extend(body);
            }
            ast::StmtKind::If { cond, then, otherwise } => {
                let cond = self.condition(cond)?;
                let then = self.body(then)?;
                let otherwise = match otherwise {
                    Some(o) => self.body(o)?,
                    None => Vec::new(),
                };
                out.push(stmt(StmtKind::If { cond, then, otherwise }, span));
            }
            ast::StmtKind::While { cond, body } => {
                let cond = self.condition(cond)?;
                let body = self.loop_body(body)?;
                out.push(stmt(StmtKind::While { cond, body }, span));
            }
            ast::StmtKind::Repeat { body, cond } => {
                self.frames.last_mut().unwrap().loops += 1;
                let list = self.stmt_list(body);
                self.frames.last_mut().unwrap().loops -= 1;
                let body = list?;
                self.sw = s.switches;
                let cond = self.condition(cond)?;
                out.push(stmt(StmtKind::Repeat { body, cond }, span));
            }
            ast::StmtKind::For { var, from, to, down, body } => {
                let v = match self.resolve_name(var)? {
                    Resolved::Value(e) => e,
                    _ => return self.error(code::BAD_FOR_VAR, var.span),
                };
                let ok_var = match &v.kind {
                    ExprKind::Var(Var::Global(_)) => true,
                    ExprKind::Var(Var::Local { routine, .. }) => Some(*routine) == self.current_routine(),
                    _ => false,
                };
                if !ok_var || !self.types.is_ordinal(v.ty) {
                    return self.error(code::BAD_FOR_VAR, var.span);
                }
                let from = self.expr_expect(from, Some(v.ty))?;
                let from = self.coerce(from, v.ty, span)?;
                let to = self.expr_expect(to, Some(v.ty))?;
                let to = self.coerce(to, v.ty, span)?;
                let limit = self.add_temp(v.ty);
                let body = self.loop_body(body)?;
                out.push(stmt(StmtKind::For { var: v, from, to, limit, down: *down, body }, span));
            }
            ast::StmtKind::Case { expr, arms, otherwise } => {
                let selector = self.expr(expr)?;
                if !self.types.is_ordinal(selector.ty) {
                    return self.error(code::ORDINAL_EXPR_EXPECTED, expr.span);
                }
                let mut seen: Vec<(i64, i64)> = Vec::new();
                let mut harms = Vec::new();
                for arm in arms {
                    let mut ranges = Vec::new();
                    for l in &arm.labels {
                        let lo = self.case_label(&l.lo, selector.ty)?;
                        let hi = match &l.hi {
                            Some(h) => self.case_label(h, selector.ty)?,
                            None => lo,
                        };
                        if lo > hi {
                            return self.error(code::LOWER_GREATER_UPPER, l.lo.span);
                        }
                        if seen.iter().any(|&(a, b)| lo <= b && a <= hi) {
                            return self.error_with(code::DUPLICATE_IDENT, l.lo.span, ": label CASE ganda");
                        }
                        seen.push((lo, hi));
                        ranges.push((lo, hi));
                    }
                    let body = self.body(&arm.body)?;
                    harms.push(CaseArm { ranges, body });
                }
                let otherwise = match otherwise {
                    Some(list) => self.stmt_list(list)?,
                    None => Vec::new(),
                };
                out.push(stmt(StmtKind::Case { selector, arms: harms, otherwise }, span));
            }
            ast::StmtKind::With { records, body } => {
                let mut inner = Vec::new();
                let pushed = records.len();
                for r in records {
                    let rec = self.expr(r)?;
                    // A class instance stands for the object it refers to.
                    let rec = match self.types.get(rec.ty) {
                        Type::Class(_) => self.class_instance(rec, r.span),
                        _ => rec,
                    };
                    if !matches!(self.types.get(rec.ty), Type::Record { .. } | Type::Object(_)) {
                        return self.error(code::RECORD_VAR_EXPECTED, r.span);
                    }
                    if !rec.is_lvalue() {
                        return self.error(code::BAD_VAR_REFERENCE, r.span);
                    }
                    let record = rec.ty;
                    let ptr_ty = self.pointer_to(record);
                    let ptr = self.add_temp(ptr_ty);
                    let addr = Expr::new(ExprKind::AddrOf(Box::new(rec)), ptr_ty, r.span);
                    inner.push(stmt(
                        StmtKind::Assign { target: self.var_expr(ptr, ptr_ty, r.span), value: addr },
                        r.span,
                    ));
                    self.frames.last_mut().unwrap().withs.push(WithScope { ptr, ptr_ty, record });
                }
                let result = self.body(body);
                let frame = self.frames.last_mut().unwrap();
                frame.withs.truncate(frame.withs.len() - pushed);
                inner.extend(result?);
                // Not a Block: the body's statements are source statements
                // (the debugger stops at each of them).
                out.extend(inner);
            }
            ast::StmtKind::Goto(label) => {
                let key = label.key();
                let Some(info) = self.frames.last().and_then(|f| f.labels.get(&key)) else {
                    return self.error_with(code::LABEL_NOT_IN_BLOCK, label.span(), format!(": {key}"));
                };
                out.push(stmt(StmtKind::Goto(info.id), span));
            }
            ast::StmtKind::Labeled(label, inner) => {
                let key = label.key();
                let Some(info) = self.frames.last_mut().and_then(|f| f.labels.get_mut(&key)) else {
                    return self.error_with(code::LABEL_NOT_IN_BLOCK, label.span(), format!(": {key}"));
                };
                if info.placed {
                    return self.error_with(code::LABEL_ALREADY_DEFINED, label.span(), format!(": {key}"));
                }
                info.placed = true;
                let id = info.id;
                out.push(stmt(StmtKind::Label(id), label.span()));
                self.stmt(inner, out)?;
            }
            ast::StmtKind::Asm(a) => return self.error_with(code::NOT_SUPPORTED, a.span, ": blok asm"),
        }
        Ok(())
    }

    fn case_label(&mut self, e: &ast::Expr, selector: TypeId) -> SResult<i64> {
        let v = self.expr(e)?;
        let ExprKind::Int(n) = v.kind else {
            return self.error(code::CONST_EXPECTED, e.span);
        };
        if !self.ordinals_compatible(v.ty, selector) {
            return self.error(code::CASE_CONST_TYPE, e.span);
        }
        Ok(n)
    }

    /// Whether a qualified name starts with a unit or type name
    /// (`Crt.TextAttr`, `TFoo.Count`) rather than a value.
    fn qualifier(&self, base: &ast::Expr) -> bool {
        matches!(&base.kind, ast::ExprKind::Name(b)
            if matches!(self.lookup(&b.key()), Some(Sym::Unit(_) | Sym::Type(_))))
    }

    /// An assignment to a property: the property and the indices of an
    /// array property. `None` for every other target.
    fn property_target(&mut self, e: &ast::Expr) -> SResult<Option<(PropRef, Vec<ast::Arg>)>> {
        let args = |indices: &[ast::Expr]| -> Vec<ast::Arg> {
            indices.iter().map(|i| ast::Arg { value: i.clone(), width: None, decimals: None }).collect()
        };
        match &e.kind {
            ast::ExprKind::Name(id) => {
                if self.method_result(&id.key(), id.span).is_some() {
                    return Ok(None);
                }
                match self.resolve_name(id) {
                    Ok(Resolved::Property(p)) => Ok(Some((*p, Vec::new()))),
                    _ => Ok(None),
                }
            }
            ast::ExprKind::Field { base, field } => {
                if self.qualifier(base) {
                    return Ok(None);
                }
                let b = self.lvalue_chain(base)?;
                match self.member(b, field, e.span)? {
                    Resolved::Property(p) => Ok(Some((*p, Vec::new()))),
                    _ => Ok(None),
                }
            }
            ast::ExprKind::Inherited(Some(_)) => match self.resolve(e) {
                Ok(Resolved::Property(p)) => Ok(Some((*p, Vec::new()))),
                _ => Ok(None),
            },
            ast::ExprKind::Index { base, indices } => {
                let named = match &base.kind {
                    ast::ExprKind::Field { base: bb, field } if !self.qualifier(bb) => {
                        let b = self.lvalue_chain(bb)?;
                        Some(self.member(b, field, base.span)?)
                    }
                    ast::ExprKind::Name(id) => self.resolve_name(id).ok(),
                    ast::ExprKind::Inherited(Some(_)) => self.resolve(base).ok(),
                    _ => None,
                };
                match named {
                    Some(Resolved::Property(p)) if !p.prop.params.is_empty() => {
                        return Ok(Some((*p, args(indices))));
                    }
                    Some(Resolved::Property(_)) => return Ok(None),
                    _ => {}
                }
                let b = self.lvalue_chain(base)?;
                Ok(self.default_property(&b, e.span).map(|p| (p, args(indices))))
            }
            _ => Ok(None),
        }
    }

    /// The target of `:=`; inside a function its own name denotes the
    /// result variable.
    fn assign_target(&mut self, e: &ast::Expr) -> SResult<Expr> {
        // `@P := Addr` stores a pointer into the procedural variable P.
        if let ast::ExprKind::Unary(ast::UnOp::AddrOf, inner) = &e.kind {
            let v = self.lvalue_chain(inner)?;
            if v.is_lvalue() && matches!(self.types.get(v.ty), Type::Procedural(_)) {
                let pointer = self.types.builtin.pointer;
                let pty = self.pointer_to(pointer);
                let addr = Expr::new(ExprKind::AddrOf(Box::new(v)), pty, e.span);
                return Ok(Expr::new(ExprKind::Deref(Box::new(addr)), pointer, e.span));
            }
            return self.error(code::ILLEGAL_ASSIGNMENT, e.span);
        }
        let x = self.lvalue_chain(e)?;
        if !x.is_lvalue() {
            return self.error(code::ILLEGAL_ASSIGNMENT, e.span);
        }
        Ok(x)
    }

    /// The function's own name at the start of an assignment target
    /// denotes its result (`F := x`, and for record results `F.X := x`).
    fn lvalue_chain(&mut self, e: &ast::Expr) -> SResult<Expr> {
        match &e.kind {
            ast::ExprKind::Name(id) => {
                let key = id.key();
                if let Some(result) = self.method_result(&key, id.span) {
                    return Ok(result);
                }
                let in_with = self
                    .frames
                    .last()
                    .is_some_and(|f| f.withs.iter().any(|w| self.record_field(w.record, &key).is_some()));
                if !in_with
                    && let Some(Sym::Routine(r)) = self.lookup(&key)
                    && self.frames.iter().any(|f| f.routine == r)
                    && let Some(index) = self.routine(r).result_local()
                {
                    let ty = self.routine(r).locals[index as usize].ty;
                    return Ok(self.var_expr(Var::Local { routine: r, index }, ty, id.span));
                }
                self.expr(e)
            }
            ast::ExprKind::Field { base, field } => {
                let unit_qualified = matches!(&base.kind, ast::ExprKind::Name(b)
                    if matches!(self.lookup(&b.key()), Some(Sym::Unit(_))));
                if unit_qualified {
                    return self.expr(e);
                }
                if self.qualifier(base) {
                    return self.expr(e);
                }
                let b = self.lvalue_chain(base)?;
                match self.member(b, field, e.span)? {
                    Resolved::Value(v) => Ok(v),
                    Resolved::Property(p) => self.property_read(*p, &[], e.span),
                    _ => self.error(code::FIELD_IDENT_EXPECTED, field.span),
                }
            }
            ast::ExprKind::Index { base, indices } => {
                let args: Vec<ast::Arg> =
                    indices.iter().map(|i| ast::Arg { value: i.clone(), width: None, decimals: None }).collect();
                if let ast::ExprKind::Field { base: bb, field } = &base.kind
                    && !self.qualifier(bb)
                {
                    let b = self.lvalue_chain(bb)?;
                    let v = match self.member(b, field, base.span)? {
                        Resolved::Property(p) if !p.prop.params.is_empty() => {
                            return self.property_read(*p, &args, e.span);
                        }
                        Resolved::Property(p) => self.property_read(*p, &[], base.span)?,
                        Resolved::Value(v) => v,
                        _ => return self.error(code::FIELD_IDENT_EXPECTED, field.span),
                    };
                    if let Some(p) = self.default_property(&v, e.span) {
                        return self.property_read(p, &args, e.span);
                    }
                    return self.index(v, indices);
                }
                let b = self.lvalue_chain(base)?;
                if let Some(p) = self.default_property(&b, e.span) {
                    return self.property_read(p, &args, e.span);
                }
                self.index(b, indices)
            }
            ast::ExprKind::Deref(inner) => {
                let p = self.lvalue_chain(inner)?;
                self.deref(p, e.span)
            }
            _ => self.expr(e),
        }
    }

    fn call_stmt(&mut self, e: &ast::Expr, span: Span, out: &mut Vec<Stmt>) -> SResult<()> {
        let (callee, args): (&ast::Expr, &[ast::Arg]) = match &e.kind {
            ast::ExprKind::Call { callee, args } => (callee, args),
            _ => (e, &[]),
        };
        // A bare `inherited;`.
        if let ast::ExprKind::Inherited(None) = &callee.kind {
            out.extend(self.inherited_same(span)?);
            return Ok(());
        }
        // `Fail` inside a constructor.
        if let ast::ExprKind::Name(n) = &callee.kind
            && n.key() == "FAIL"
            && args.is_empty()
            && self.lookup("FAIL").is_none()
        {
            out.extend(self.fail_stmt(span)?);
            return Ok(());
        }
        match self.resolve(callee)? {
            Resolved::Builtin(b, _) => {
                let stmts = self.builtin_stmt(b, args, span)?;
                out.extend(stmts);
            }
            Resolved::Routine(id, _) => {
                if self.routine(id).sig.result.is_some() && !self.sw.get(Switches::EXTENDED) {
                    return self.error(code::ERROR_IN_STATEMENT, span);
                }
                let call = self.call_routine(id, args, span, true)?;
                out.push(stmt(StmtKind::Call(call), span));
            }
            Resolved::Value(v) if matches!(self.types.get(v.ty), Type::Procedural(_)) => {
                let call = self.call_indirect(v, args, span, true)?;
                out.push(stmt(StmtKind::Call(call), span));
            }
            Resolved::Method(m) => out.extend(self.method_stmt(*m, args, span)?),
            _ => return self.error(code::ERROR_IN_STATEMENT, span),
        }
        Ok(())
    }
}
