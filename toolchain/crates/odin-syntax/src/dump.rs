// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! S-expression rendering of the AST, for `odinpc check --dump-ast` and
//! golden tests. Spans are omitted so the output only changes with meaning.

use std::fmt::Write as _;

use crate::ast::*;

pub fn module(m: &Module) -> String {
    let mut d = Dumper::default();
    match m {
        Module::Program(p) => {
            d.open(&format!("program {}", p.name.as_ref().map_or("-", |n| &n.name)));
            if !p.uses.is_empty() {
                d.line(&format!("(uses {})", names(&p.uses)));
            }
            d.block(&p.block);
            d.close();
        }
        Module::Unit(u) => {
            d.open(&format!("unit {}", u.name.name));
            d.open("interface");
            if !u.interface_uses.is_empty() {
                d.line(&format!("(uses {})", names(&u.interface_uses)));
            }
            d.decls(&u.interface);
            d.close();
            d.open("implementation");
            if !u.implementation_uses.is_empty() {
                d.line(&format!("(uses {})", names(&u.implementation_uses)));
            }
            d.decls(&u.implementation);
            d.close();
            if let Some(init) = &u.init {
                d.open("init");
                for s in init {
                    d.stmt(s);
                }
                d.close();
            }
            d.close();
        }
    }
    d.out
}

#[derive(Default)]
struct Dumper {
    out: String,
    depth: usize,
}

fn names(ids: &[Ident]) -> String {
    ids.iter().map(|i| i.name.as_str()).collect::<Vec<_>>().join(" ")
}

impl Dumper {
    fn line(&mut self, text: &str) {
        for _ in 0..self.depth {
            self.out.push_str("  ");
        }
        self.out.push_str(text);
        self.out.push('\n');
    }

    fn open(&mut self, head: &str) {
        self.line(&format!("({head}"));
        self.depth += 1;
    }

    fn close(&mut self) {
        self.depth -= 1;
        // Attach ")" to the previous line.
        if self.out.ends_with('\n') {
            self.out.pop();
        }
        self.out.push_str(")\n");
    }

    fn block(&mut self, b: &Block) {
        self.decls(&b.decls);
        match &b.body {
            Body::Statements(stmts, _) => {
                self.open("begin");
                for s in stmts {
                    self.stmt(s);
                }
                self.close();
            }
            Body::Asm(a) => self.line(&format!("(asm {:?})", a.text.trim())),
        }
    }

    fn decls(&mut self, decls: &[Decl]) {
        for decl in decls {
            match decl {
                Decl::Labels(labels) => {
                    let l: Vec<String> = labels.iter().map(Label::key).collect();
                    self.line(&format!("(label {})", l.join(" ")));
                }
                Decl::Consts(items) => {
                    for c in items {
                        let ty = c.ty.as_ref().map(|t| format!(" : {}", ty(t))).unwrap_or_default();
                        self.line(&format!("(const {}{} = {})", c.name.name, ty, init(&c.value)));
                    }
                }
                Decl::Types(items) => {
                    for t in items {
                        self.line(&format!("(type {} = {})", t.name.name, ty(&t.ty)));
                    }
                }
                Decl::Vars(items) => {
                    for v in items {
                        let abs = match &v.absolute {
                            Some(Absolute::Var(e)) => format!(" absolute {}", expr(e)),
                            Some(Absolute::Address(s, o, _)) => format!(" absolute {}:{}", expr(s), expr(o)),
                            None => String::new(),
                        };
                        self.line(&format!("(var ({}) {}{})", names(&v.names), ty(&v.ty), abs));
                    }
                }
                Decl::Routine(r) => self.routine(r),
            }
        }
    }

    fn routine(&mut self, r: &Routine) {
        self.open(&heading(&r.heading));
        match &r.body {
            RoutineBody::Declaration => self.line("declaration"),
            RoutineBody::External { library, name } => {
                let lib = library.as_ref().map(expr).unwrap_or_default();
                let sym = name.as_ref().map(|n| format!(" name {}", expr(n))).unwrap_or_default();
                self.line(&format!("(external {lib}{sym})"));
            }
            RoutineBody::Inline(_) => self.line("inline"),
            RoutineBody::Block(b) => self.block(b),
        }
        self.close();
    }

    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::Empty => self.line("(empty)"),
            StmtKind::Assign { target, value } => self.line(&format!("(:= {} {})", expr(target), expr(value))),
            StmtKind::Call(e) => self.line(&format!("(do {})", expr(e))),
            StmtKind::Compound(stmts) => {
                self.open("begin");
                for s in stmts {
                    self.stmt(s);
                }
                self.close();
            }
            StmtKind::If { cond, then, otherwise } => {
                self.open(&format!("if {}", expr(cond)));
                self.stmt(then);
                if let Some(o) = otherwise {
                    self.open("else");
                    self.stmt(o);
                    self.close();
                }
                self.close();
            }
            StmtKind::Case { expr: e, arms, otherwise } => {
                self.open(&format!("case {}", expr(e)));
                for arm in arms {
                    self.open(&format!("arm {}", case_labels(&arm.labels)));
                    self.stmt(&arm.body);
                    self.close();
                }
                if let Some(o) = otherwise {
                    self.open("else");
                    for s in o {
                        self.stmt(s);
                    }
                    self.close();
                }
                self.close();
            }
            StmtKind::While { cond, body } => {
                self.open(&format!("while {}", expr(cond)));
                self.stmt(body);
                self.close();
            }
            StmtKind::Repeat { body, cond } => {
                self.open(&format!("repeat-until {}", expr(cond)));
                for s in body {
                    self.stmt(s);
                }
                self.close();
            }
            StmtKind::For { var, from, to, down, body } => {
                let dir = if *down { "downto" } else { "to" };
                self.open(&format!("for {} {} {} {}", var.name, expr(from), dir, expr(to)));
                self.stmt(body);
                self.close();
            }
            StmtKind::With { records, body } => {
                let r: Vec<String> = records.iter().map(expr).collect();
                self.open(&format!("with {}", r.join(" ")));
                self.stmt(body);
                self.close();
            }
            StmtKind::Goto(l) => self.line(&format!("(goto {})", l.key())),
            StmtKind::Labeled(l, inner) => {
                self.open(&format!("label {}", l.key()));
                self.stmt(inner);
                self.close();
            }
            StmtKind::Asm(a) => self.line(&format!("(asm {:?})", a.text.trim())),
        }
    }
}

fn case_labels(labels: &[CaseLabel]) -> String {
    labels
        .iter()
        .map(|l| match &l.hi {
            Some(hi) => format!("{}..{}", expr(&l.lo), expr(hi)),
            None => expr(&l.lo),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn heading(h: &RoutineHeading) -> String {
    let kind = match h.kind {
        RoutineKind::Procedure => "procedure",
        RoutineKind::Function => "function",
        RoutineKind::Constructor => "constructor",
        RoutineKind::Destructor => "destructor",
    };
    let mut s = String::from(kind);
    s.push(' ');
    if let Some(o) = &h.owner {
        let _ = write!(s, "{}.", o.name);
    }
    s.push_str(&h.name.name);
    if !h.params.is_empty() {
        let _ = write!(s, " ({})", params(&h.params));
    }
    if let Some(r) = &h.result {
        let _ = write!(s, " : {}", ty(r));
    }
    for d in &h.directives {
        let name = match &d.kind {
            DirectiveKind::Forward => "forward".to_string(),
            DirectiveKind::External => "external".to_string(),
            DirectiveKind::Assembler => "assembler".to_string(),
            DirectiveKind::Far => "far".to_string(),
            DirectiveKind::Near => "near".to_string(),
            DirectiveKind::Interrupt => "interrupt".to_string(),
            DirectiveKind::Cdecl => "cdecl".to_string(),
            DirectiveKind::Export => "export".to_string(),
            DirectiveKind::Virtual(None) => "virtual".to_string(),
            DirectiveKind::Virtual(Some(e)) => format!("virtual {}", expr(e)),
            DirectiveKind::Other(o) => o.to_ascii_lowercase(),
        };
        let _ = write!(s, " [{name}]");
    }
    s
}

fn params(groups: &[ParamGroup]) -> String {
    groups
        .iter()
        .map(|g| {
            let mode = match g.mode {
                ParamMode::Value => "",
                ParamMode::Var => "var ",
                ParamMode::Const => "const ",
            };
            let t = g.ty.as_ref().map(|t| format!(": {}", ty(t))).unwrap_or_default();
            format!("{mode}{}{t}", names(&g.names))
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn qual(q: &QualIdent) -> String {
    match &q.unit {
        Some(u) => format!("{}.{}", u.name, q.name.name),
        None => q.name.name.clone(),
    }
}

pub fn ty(t: &TypeExpr) -> String {
    match &t.kind {
        TypeKind::Named(q) => qual(q),
        TypeKind::String(None) => "string".into(),
        TypeKind::String(Some(n)) => format!("string[{}]", expr(n)),
        TypeKind::File(None) => "file".into(),
        TypeKind::File(Some(e)) => format!("(file-of {})", ty(e)),
        TypeKind::Subrange(lo, hi) => format!("(.. {} {})", expr(lo), expr(hi)),
        TypeKind::Enum(items) => format!("(enum {})", names(items)),
        TypeKind::Array { packed, index, elem } => {
            let i: Vec<String> = index.iter().map(ty).collect();
            format!("({}array [{}] {})", if *packed { "packed-" } else { "" }, i.join(" "), ty(elem))
        }
        TypeKind::OpenArray(e) => format!("(array-of {})", ty(e)),
        TypeKind::Record { packed, fields } => {
            format!("({}record{})", if *packed { "packed-" } else { "" }, field_list(fields))
        }
        TypeKind::Object(o) => {
            let mut s = String::from("(object");
            if let Some(p) = &o.parent {
                let _ = write!(s, " ({})", qual(p));
            }
            for m in &o.members {
                match m {
                    ObjectMember::Field { decl, private } => {
                        let _ = write!(
                            s,
                            " ({}{}: {})",
                            if *private { "private " } else { "" },
                            names(&decl.names),
                            ty(&decl.ty)
                        );
                    }
                    ObjectMember::Method { heading: h, private } => {
                        let _ = write!(s, " ({}{})", if *private { "private " } else { "" }, heading(h));
                    }
                }
            }
            s.push(')');
            s
        }
        TypeKind::Set { base, .. } => format!("(set-of {})", ty(base)),
        TypeKind::Pointer(target) => format!("(^ {})", ty(target)),
        TypeKind::Procedural { function, params: p, result } => {
            let mut s = String::from(if *function { "(function" } else { "(procedure" });
            if !p.is_empty() {
                let _ = write!(s, " ({})", params(p));
            }
            if let Some(r) = result {
                let _ = write!(s, " : {}", ty(r));
            }
            s.push(')');
            s
        }
    }
}

fn field_list(f: &FieldList) -> String {
    let mut s = String::new();
    for decl in &f.fields {
        let _ = write!(s, " ({}: {})", names(&decl.names), ty(&decl.ty));
    }
    if let Some(v) = &f.variant {
        let tag = v.tag.as_ref().map(|t| format!("{}: ", t.name)).unwrap_or_default();
        let _ = write!(s, " (case {}{}", tag, qual(&v.tag_type));
        for c in &v.cases {
            let _ = write!(s, " ({}{})", case_labels(&c.labels), field_list(&c.fields));
        }
        s.push(')');
    }
    s
}

fn init(i: &ConstInit) -> String {
    match i {
        ConstInit::Expr(e) => expr(e),
        ConstInit::List(items, _) => format!("({})", items.iter().map(init).collect::<Vec<_>>().join(", ")),
        ConstInit::Record(fields, _) => {
            let f: Vec<String> = fields.iter().map(|(n, v)| format!("{}: {}", n.name, init(v))).collect();
            format!("({})", f.join("; "))
        }
    }
}

fn string_literal(bytes: &[u8]) -> String {
    let mut s = String::new();
    let mut quoted = false;
    for &b in bytes {
        if (0x20..0x7f).contains(&b) {
            if !quoted {
                s.push('\'');
                quoted = true;
            }
            if b == b'\'' {
                s.push_str("''");
            } else {
                s.push(b as char);
            }
        } else {
            if quoted {
                s.push('\'');
                quoted = false;
            }
            let _ = write!(s, "#{b}");
        }
    }
    if quoted {
        s.push('\'');
    }
    if s.is_empty() {
        s.push_str("''");
    }
    s
}

pub fn expr(e: &Expr) -> String {
    match &e.kind {
        ExprKind::Int(v) => v.to_string(),
        ExprKind::Real(v) => format!("{v:?}"),
        ExprKind::Str(b) => string_literal(b),
        ExprKind::Nil => "nil".into(),
        ExprKind::Name(i) => i.name.clone(),
        ExprKind::Set(items) => {
            let i: Vec<String> = items
                .iter()
                .map(|it| match &it.hi {
                    Some(hi) => format!("{}..{}", expr(&it.lo), expr(hi)),
                    None => expr(&it.lo),
                })
                .collect();
            format!("[{}]", i.join(", "))
        }
        ExprKind::Unary(op, x) => {
            let o = match op {
                UnOp::Neg => "neg",
                UnOp::Pos => "pos",
                UnOp::Not => "not",
                UnOp::AddrOf => "@",
            };
            format!("({o} {})", expr(x))
        }
        ExprKind::Binary(op, a, b) => format!("({} {} {})", op.symbol(), expr(a), expr(b)),
        ExprKind::Call { callee, args } => {
            let mut s = format!("(call {}", expr(callee));
            for a in args {
                let _ = write!(s, " {}", expr(&a.value));
                if let Some(w) = &a.width {
                    let _ = write!(s, ":{}", expr(w));
                }
                if let Some(d) = &a.decimals {
                    let _ = write!(s, ":{}", expr(d));
                }
            }
            s.push(')');
            s
        }
        ExprKind::Index { base, indices } => {
            let i: Vec<String> = indices.iter().map(expr).collect();
            format!("(index {} {})", expr(base), i.join(" "))
        }
        ExprKind::Field { base, field } => format!("(. {} {})", expr(base), field.name),
        ExprKind::Deref(x) => format!("(^ {})", expr(x)),
        ExprKind::Inherited(n) => format!("(inherited {})", n.name),
        ExprKind::StringType => "string".into(),
    }
}
