// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Declarations: labels, constants, typed constants, variables, routines.

use odin_base::{Span, code};
use odin_ir::*;
use odin_syntax::ast;

use crate::scope::{ConstKind, Sym};
use crate::{Analyzer, Frame, LabelInfo, SResult};

impl Analyzer<'_> {
    pub(crate) fn decls(&mut self, decls: &[ast::Decl]) -> SResult<()> {
        for d in decls {
            match d {
                ast::Decl::Labels(labels) => {
                    if self.frames.is_empty() {
                        return self.error_with(code::NOT_SUPPORTED, labels[0].span(), ": label di luar prosedur");
                    }
                    self.declare_labels(labels)?;
                }
                ast::Decl::Consts(items) => {
                    for c in items {
                        self.const_decl(c)?;
                    }
                }
                ast::Decl::Types(items) => self.type_section(items)?,
                ast::Decl::Vars(items) => {
                    for v in items {
                        self.var_decl(v)?;
                    }
                }
                ast::Decl::Routine(r) => self.routine_decl(r)?,
            }
        }
        Ok(())
    }

    /// Program-level declarations: labels belong to the main routine and
    /// are declared when its body is analysed.
    pub(crate) fn decls_program(&mut self, decls: &[ast::Decl], _main: RoutineId) -> SResult<()> {
        for d in decls {
            if !matches!(d, ast::Decl::Labels(_)) {
                self.decls(std::slice::from_ref(d))?;
            }
        }
        Ok(())
    }

    pub(crate) fn declare_labels_from(&mut self, decls: &[ast::Decl]) -> SResult<()> {
        for d in decls {
            if let ast::Decl::Labels(labels) = d {
                self.declare_labels(labels)?;
            }
        }
        Ok(())
    }

    fn declare_labels(&mut self, labels: &[ast::Label]) -> SResult<()> {
        for l in labels {
            let id = self.new_label();
            let key = l.key();
            let frame = self.frames.last_mut().expect("labels need a routine");
            if frame.labels.contains_key(&key) {
                return self.error_with(code::DUPLICATE_IDENT, l.span(), format!(": label {key}"));
            }
            frame.labels.insert(key, LabelInfo { id, placed: false, span: l.span() });
        }
        Ok(())
    }

    fn const_decl(&mut self, c: &ast::ConstDecl) -> SResult<()> {
        match &c.ty {
            None => {
                let ast::ConstInit::Expr(e) = &c.value else {
                    return self.error(code::CONST_EXPECTED, c.value.span());
                };
                let value = self.const_expr(e)?;
                self.declare(&c.name, Sym::Const(value))
            }
            Some(t) => {
                let ty = self.resolve_type(t)?;
                let init = self.const_init(&c.value, ty)?;
                let g = self.add_global(&c.name.name, ty, Some(init), c.span);
                self.declare(&c.name, Sym::global(g, ty))
            }
        }
    }

    /// Initial bytes of a typed constant.
    pub(crate) fn const_init(&mut self, init: &ast::ConstInit, ty: TypeId) -> SResult<GlobalInit> {
        let size = self.types.size(ty) as usize;
        let mut out = GlobalInit { bytes: vec![0; size], pointers: Vec::new() };
        self.write_init(init, ty, 0, &mut out)?;
        Ok(out)
    }

    fn write_init(&mut self, init: &ast::ConstInit, ty: TypeId, offset: u64, out: &mut GlobalInit) -> SResult<()> {
        match self.types.get(ty).clone() {
            Type::Array { lo, hi, elem, .. } => {
                let count = (hi - lo + 1) as usize;
                let esize = self.types.size(elem);
                match init {
                    ast::ConstInit::List(items, span) => {
                        if items.len() != count {
                            return self.error_with(
                                code::TYPE_MISMATCH,
                                *span,
                                format!(": diharapkan {count} elemen, ada {}", items.len()),
                            );
                        }
                        for (i, item) in items.iter().enumerate() {
                            self.write_init(item, elem, offset + i as u64 * esize, out)?;
                        }
                        Ok(())
                    }
                    ast::ConstInit::Expr(e) if matches!(self.types.get(elem), Type::Char) => {
                        let v = self.const_expr(e)?;
                        let bytes = match v.kind {
                            ConstKind::Str(b) => b,
                            ConstKind::Int(c) => vec![c as u8],
                            _ => return self.error(code::TYPE_MISMATCH, e.span),
                        };
                        if bytes.len() != count {
                            return self.error_with(
                                code::STRING_LENGTH_MISMATCH,
                                e.span,
                                format!(": diharapkan {count}"),
                            );
                        }
                        out.bytes[offset as usize..offset as usize + count].copy_from_slice(&bytes);
                        Ok(())
                    }
                    other => self.error(code::TYPE_MISMATCH, other.span()),
                }
            }
            Type::Record { fields, .. } => match init {
                ast::ConstInit::Record(items, _) => {
                    for (name, value) in items {
                        let key = name.key();
                        let Some(f) = fields.iter().find(|f| f.name.eq_ignore_ascii_case(&key)) else {
                            return self.error_with(code::UNKNOWN_IDENT, name.span, format!(": field {}", name.name));
                        };
                        let (fty, foff) = (f.ty, f.offset);
                        self.write_init(value, fty, offset + foff, out)?;
                    }
                    Ok(())
                }
                other => self.error(code::TYPE_MISMATCH, other.span()),
            },
            // Typed object constant: fields like a record; the VMT pointer
            // (when the type has one) points at the type's VMT.
            Type::Object(obj) => match init {
                ast::ConstInit::Record(items, _) => {
                    if let (Some(at), Some(vmt)) = (obj.vmt_offset, obj.vmt) {
                        out.pointers.push((offset + at, self.globals[vmt as usize].symbol.clone()));
                    }
                    for (name, value) in items {
                        let Some(f) = obj.field(&name.key()) else {
                            return self.error_with(code::UNKNOWN_IDENT, name.span, format!(": field {}", name.name));
                        };
                        let (fty, foff) = (f.ty, f.offset);
                        self.write_init(value, fty, offset + foff, out)?;
                    }
                    Ok(())
                }
                other => self.error(code::TYPE_MISMATCH, other.span()),
            },
            _ => {
                let e = match init {
                    ast::ConstInit::Expr(e) => e,
                    ast::ConstInit::List(items, _) if items.len() == 1 => {
                        return self.write_init(&items[0], ty, offset, out);
                    }
                    other => return self.error(code::TYPE_MISMATCH, other.span()),
                };
                let value = self.expr_expect(e, Some(ty))?;
                let value = self.coerce(value, ty, e.span)?;
                self.write_scalar(&value, ty, offset, out)
            }
        }
    }

    fn write_scalar(&mut self, value: &Expr, ty: TypeId, offset: u64, out: &mut GlobalInit) -> SResult<()> {
        let size = self.types.size(ty) as usize;
        let at = offset as usize;
        match &value.kind {
            ExprKind::Int(v) => out.bytes[at..at + size].copy_from_slice(&v.to_le_bytes()[..size]),
            ExprKind::Real(v) => {
                if size == 4 {
                    out.bytes[at..at + 4].copy_from_slice(&(*v as f32).to_le_bytes());
                } else {
                    out.bytes[at..at + 8].copy_from_slice(&v.to_le_bytes());
                }
            }
            ExprKind::Str(b) => {
                let max = size - 1;
                let n = b.len().min(max);
                out.bytes[at] = n as u8;
                out.bytes[at + 1..at + 1 + n].copy_from_slice(&b[..n]);
            }
            ExprKind::Nil => {}
            ExprKind::SetConst(b) => out.bytes[at..at + b.len()].copy_from_slice(b),
            ExprKind::AddrOf(inner) => match &inner.kind {
                ExprKind::Var(Var::Global(g)) => out.pointers.push((offset, self.globals[g.0 as usize].symbol.clone())),
                _ => return self.error(code::CONST_EXPECTED, value.span),
            },
            ExprKind::RoutineAddr(r) => out.pointers.push((offset, self.routine(*r).symbol.clone())),
            ExprKind::Convert(Conv::Bits, inner) => return self.write_scalar(inner, ty, offset, out),
            _ => return self.error(code::CONST_EXPECTED, value.span),
        }
        Ok(())
    }

    fn var_decl(&mut self, v: &ast::VarDecl) -> SResult<()> {
        let ty = self.resolve_type(&v.ty)?;
        if matches!(self.types.get(ty), Type::OpenArray { .. } | Type::OpenString | Type::Untyped) {
            return self.error(code::ERROR_IN_TYPE, v.ty.span);
        }
        if let Some(abs) = &v.absolute {
            let ast::Absolute::Var(target) = abs else {
                return self.error_with(code::DOS_ONLY, v.span, ": absolute ke alamat memori");
            };
            let t = self.expr(target)?;
            let ExprKind::Var(var) = t.kind else {
                return self.error(code::VAR_IDENT_EXPECTED, target.span);
            };
            for name in &v.names {
                self.declare(name, Sym::Var(var, ty))?;
            }
            return Ok(());
        }
        for name in &v.names {
            let sym = if self.frames.is_empty() {
                let g = self.add_global(&name.name, ty, None, name.span);
                Sym::global(g, ty)
            } else {
                Sym::Var(self.add_local(&name.name, ty, LocalKind::Var), ty)
            };
            self.declare(name, sym)?;
        }
        Ok(())
    }

    // ---- routines --------------------------------------------------------

    pub(crate) fn signature(&mut self, h: &ast::RoutineHeading) -> SResult<Signature> {
        let mut params = Vec::new();
        for g in &h.params {
            let mode = match g.mode {
                ast::ParamMode::Value => ParamMode::Value,
                ast::ParamMode::Var => ParamMode::Var,
                ast::ParamMode::Const => ParamMode::Const,
            };
            let ty = match &g.ty {
                Some(t) => {
                    let ty = self.resolve_param_type(t)?;
                    // {$P+}: a var String parameter is an open string.
                    let open = h.switches.get(odin_syntax::Switches::OPEN_STRING);
                    if open && mode == ParamMode::Var && ty == self.types.builtin.string {
                        self.types.builtin.openstring
                    } else {
                        ty
                    }
                }
                None if mode == ParamMode::Value => return self.error(code::COLON_EXPECTED, g.span),
                None => self.types.builtin.untyped,
            };
            for n in &g.names {
                params.push(Param { name: n.name.clone(), mode, ty });
            }
        }
        let result = match &h.result {
            Some(t) => {
                let ty = self.resolve_type(t)?;
                if matches!(self.types.get(ty), Type::File { .. } | Type::OpenArray { .. }) {
                    return self.error(code::BAD_RESULT_TYPE, t.span);
                }
                Some(ty)
            }
            None => None,
        };
        Ok(Signature { params, result })
    }

    fn same_signature(&self, a: &Signature, b: &Signature) -> bool {
        a.result == b.result
            && a.params.len() == b.params.len()
            && a.params.iter().zip(&b.params).all(|(x, y)| x.mode == y.mode && self.same_param_type(x.ty, y.ty))
    }

    /// Parameter types of two headings of the same routine: open arrays are
    /// created anew for every heading, so they compare by element type.
    pub(crate) fn same_param_type(&self, a: TypeId, b: TypeId) -> bool {
        a == b
            || match (self.types.get(a), self.types.get(b)) {
                (Type::OpenArray { elem: x }, Type::OpenArray { elem: y }) => x == y,
                (Type::OpenString, Type::OpenString) => true,
                _ => false,
            }
    }

    /// Fills in parameter, open-array and result locals.
    pub(crate) fn set_signature(&mut self, id: RoutineId, sig: Signature) {
        let mut locals: Vec<Local> = sig
            .params
            .iter()
            .enumerate()
            .map(|(i, p)| Local { name: p.name.clone(), ty: p.ty, kind: LocalKind::Param(i as u32) })
            .collect();
        for (i, p) in sig.params.iter().enumerate() {
            if matches!(self.types.get(p.ty), Type::OpenArray { .. } | Type::OpenString) {
                locals.push(Local {
                    name: format!("high({})", p.name),
                    ty: self.types.builtin.int64,
                    kind: LocalKind::OpenHigh(i as u32),
                });
            }
        }
        if let Some(r) = sig.result {
            locals.push(Local { name: "Result".into(), ty: r, kind: LocalKind::Result });
        }
        let routine = self.routine_mut(id);
        routine.sig = sig;
        routine.locals = locals;
    }

    fn take_forward(&mut self, key: &str) -> Option<(RoutineId, Span)> {
        let list = match self.frames.last_mut() {
            Some(f) => &mut f.forwards,
            None => &mut self.unit_forwards,
        };
        let pos = list.iter().position(|(id, _)| {
            self.routines[id.0 as usize].symbol.rsplit('.').next().is_some_and(|last| last == key)
        })?;
        Some(list.remove(pos))
    }

    fn routine_decl(&mut self, r: &ast::Routine) -> SResult<()> {
        let h = &r.heading;
        if let Some(owner) = &h.owner {
            return self.method_decl(r, owner);
        }
        if matches!(h.kind, ast::RoutineKind::Constructor | ast::RoutineKind::Destructor) {
            return self.error(code::METHOD_IDENT_EXPECTED, h.name.span);
        }
        if let ast::RoutineBody::Inline(span) = &r.body {
            return self.error_with(code::DOS_ONLY, *span, ": inline(...) berisi kode mesin 16-bit");
        }
        if h.has(|d| matches!(d, ast::DirectiveKind::Interrupt)) {
            return self.error_with(code::DOS_ONLY, h.span, ": prosedur interrupt");
        }
        let key = h.name.key();
        let is_declaration = matches!(r.body, ast::RoutineBody::Declaration);
        let forward = if is_declaration { None } else { self.take_forward(&key) };
        let id = match forward {
            Some((id, _)) => {
                if !h.params.is_empty() || h.result.is_some() {
                    let sig = self.signature(h)?;
                    if !self.same_signature(&sig, &self.routine(id).sig) {
                        return self.error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
                    }
                }
                id
            }
            None => {
                if self.lookup_local(&key).is_some() {
                    return self.error_with(code::DUPLICATE_IDENT, h.name.span, format!(": {}", h.name.name));
                }
                let sig = self.signature(h)?;
                if h.kind == ast::RoutineKind::Function && sig.result.is_none() {
                    return self.error(code::COLON_EXPECTED, h.span.end_point());
                }
                let display = match (self.current_routine(), self.cur_unit) {
                    (Some(p), _) if !self.routine(p).symbol.ends_with(".$MAIN") => {
                        format!("{}.{}", self.routine(p).display, h.name.name)
                    }
                    (_, Some(u)) => format!("{}.{}", self.unit_display(u), h.name.name),
                    _ => h.name.name.clone(),
                };
                let symbol = self.mangle(&h.name.name);
                let id = self.new_routine(&symbol, &display, r.span);
                self.set_signature(id, sig);
                self.declare(&h.name, Sym::Routine(id))?;
                id
            }
        };
        match &r.body {
            ast::RoutineBody::Declaration => {
                let entry = (id, h.name.span);
                match self.frames.last_mut() {
                    Some(f) => f.forwards.push(entry),
                    None => self.unit_forwards.push(entry),
                }
            }
            ast::RoutineBody::External { library, name } => {
                let Some(library) = library else {
                    return self.error_with(code::NOT_SUPPORTED, h.span, ": external tanpa nama pustaka (berkas .OBJ)");
                };
                let library = self.const_string(library)?;
                let symbol = match name {
                    Some(n) => self.const_string(n)?,
                    None => h.name.name.clone(),
                };
                self.routine_mut(id).body = RoutineBody::External { symbol, library };
            }
            ast::RoutineBody::Block(block) => self.routine_body(id, h, block)?,
            ast::RoutineBody::Inline(_) => unreachable!(),
        }
        Ok(())
    }

    pub(crate) fn unit_display(&self, unit: usize) -> String {
        let name = &self.units[unit].name;
        let mut chars = name.chars();
        match chars.next() {
            Some(c) => c.to_string() + &chars.as_str().to_ascii_lowercase(),
            None => String::new(),
        }
    }

    fn routine_body(&mut self, id: RoutineId, h: &ast::RoutineHeading, block: &ast::Block) -> SResult<()> {
        self.frames.push(Frame::new(id));
        let params = self.routine(id).sig.params.clone();
        let spans: Vec<Span> = if h.params.is_empty() {
            vec![h.name.span; params.len()]
        } else {
            h.params.iter().flat_map(|g| g.names.iter().map(|n| n.span)).collect()
        };
        for (i, p) in params.iter().enumerate() {
            let ident = ast::Ident { name: p.name.clone(), span: spans[i] };
            self.declare(&ident, Sym::Var(Var::Local { routine: id, index: i as u32 }, p.ty))?;
        }
        self.decls(&block.decls)?;
        let body = match &block.body {
            ast::Body::Statements(stmts, _) => self.stmt_list(stmts)?,
            ast::Body::Asm(a) => return self.error_with(code::NOT_SUPPORTED, a.span, ": prosedur assembler"),
        };
        self.finish_frame()?;
        self.routine_mut(id).body = RoutineBody::Code(body);
        Ok(())
    }
}
