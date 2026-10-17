// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! `odinpc metrics`: the structure of the user's code, for the metrics
//! report. Step counts come from running a `--count-steps` build
//! (rtl/COMPILER_INTERFACE.md §8); this describes the source itself.
//!
//! Most of it comes from the checked program, so it agrees with the
//! compiler about which variable a name means: per-routine size, nesting and
//! cyclomatic complexity, recursion, unused variables, functions that never
//! set their result, `goto`, and globals written by procedures. Magic
//! numbers (other than 0, 1 and 2, written more than once or as an array
//! bound in a declaration; a number used once in a statement is usually just
//! that statement's value) and the shape used for similarity come from the
//! syntax tree,
//! which still has the literals and the statements as written. Only the
//! user's files are described, never the RTL.

use std::collections::{HashMap, HashSet};

use odin_base::json::{JsonWriter, write_string};
use odin_base::{FileId, SourceMap, Span};
use odin_ir::*;
use odin_syntax::ast;

/// A routine whose control structures nest deeper than this gets a note.
pub const MAX_NESTING: u32 = 4;
/// A routine whose cyclomatic complexity is higher than this gets a note.
pub const MAX_COMPLEXITY: u32 = 10;

pub struct RoutineInfo {
    pub name: String,
    pub file: FileId,
    pub line: u32,
    pub end_line: u32,
    /// Source statements; the pieces of one lowered statement count once.
    pub statements: u32,
    /// Deepest nesting of `if`, `case`, loops: 0 for straight-line code.
    pub nesting: u32,
    /// 1 + decisions (`if`, loops, `case` arms, `and`/`or`).
    pub complexity: u32,
    pub recursive: bool,
    /// Globals of the user's files this routine assigns (not for the main
    /// program and unit initializations).
    pub globals_written: Vec<String>,
}

pub struct Note {
    pub code: &'static str,
    /// `saran` (worth changing) or `info`.
    pub level: &'static str,
    pub file: FileId,
    pub line: u32,
    pub message: String,
}

#[derive(Default)]
pub struct Facts {
    /// Procedures and functions, without the main program.
    pub routines: u32,
    pub statements: u32,
    pub max_nesting: u32,
    pub gotos: u32,
    pub recursive: Vec<String>,
    pub arrays: bool,
    pub records: bool,
    pub pointers: bool,
    /// Bytes of the user's global variables (the program's static data).
    pub global_bytes: u64,
}

pub struct Metrics {
    pub routines: Vec<RoutineInfo>,
    pub notes: Vec<Note>,
    pub facts: Facts,
    /// The main file's statements and expressions in source order, names and
    /// literal values left out: `(line, token)`. Two programs that differ only
    /// in names, spacing and comments have the same shape.
    pub shape: Vec<(u32, &'static str)>,
}

fn line(map: &SourceMap, span: Span) -> u32 {
    map.file(span.file).line_col(span.start).0
}

fn end_line(map: &SourceMap, span: Span) -> u32 {
    map.file(span.file).line_col(span.end.max(span.start)).0
}

/// A hashable form of [`Var`].
fn key(v: Var) -> (u8, u32, u32) {
    match v {
        Var::Global(g) => (0, g.0, 0),
        Var::Local { routine, index } => (1, routine.0, index),
    }
}

/// The variable an assignment target stores into (through fields and
/// indexes; a pointer dereference stores elsewhere).
fn root(e: &Expr) -> Option<Var> {
    match &e.kind {
        ExprKind::Var(v) => Some(*v),
        ExprKind::Field { base, .. } | ExprKind::Index { base, .. } | ExprKind::OpenIndex { base, .. } => root(base),
        ExprKind::Convert(_, inner) => root(inner),
        _ => None,
    }
}

#[derive(Default)]
struct Walk {
    statements: u32,
    nesting: u32,
    deepest: Option<Span>,
    decisions: u32,
    refs: HashSet<(u8, u32, u32)>,
    calls: HashSet<u32>,
    writes: Vec<Var>,
    gotos: Vec<Span>,
}

impl Walk {
    fn stmts(&mut self, list: &[Stmt], depth: u32) {
        for s in list {
            self.stmt(s, depth);
        }
    }

    fn nested(&mut self, list: &[Stmt], depth: u32, span: Span) {
        let inner = depth + 1;
        if !list.is_empty() && inner > self.nesting {
            self.nesting = inner;
            self.deepest = Some(span);
        }
        self.stmts(list, inner);
    }

    fn stmt(&mut self, s: &Stmt, depth: u32) {
        if !matches!(s.kind, StmtKind::Label(_)) {
            self.statements += 1;
        }
        match &s.kind {
            StmtKind::Assign { target, value } => {
                self.writes.extend(root(target));
                self.expr(target);
                self.expr(value);
            }
            StmtKind::Call(e) => self.expr(e),
            StmtKind::If { cond, then, otherwise } => {
                self.decisions += 1;
                self.expr(cond);
                self.nested(then, depth, s.span);
                self.nested(otherwise, depth, s.span);
            }
            StmtKind::While { cond, body } => {
                self.decisions += 1;
                self.expr(cond);
                self.nested(body, depth, s.span);
            }
            StmtKind::Repeat { body, cond } => {
                self.decisions += 1;
                self.nested(body, depth, s.span);
                self.expr(cond);
            }
            StmtKind::For { var, from, to, body, .. } => {
                self.decisions += 1;
                self.writes.extend(root(var));
                self.expr(var);
                self.expr(from);
                self.expr(to);
                self.nested(body, depth, s.span);
            }
            StmtKind::Case { selector, arms, otherwise } => {
                self.decisions += arms.len() as u32;
                self.expr(selector);
                for arm in arms {
                    self.nested(&arm.body, depth, s.span);
                }
                self.nested(otherwise, depth, s.span);
            }
            StmtKind::Goto(_) => self.gotos.push(s.span),
            StmtKind::Label(_) | StmtKind::Break | StmtKind::Continue | StmtKind::Exit => {}
            StmtKind::Block(list) => {
                // One source statement: its pieces are walked for the names
                // they use, not counted again.
                let counted = self.statements;
                self.stmts(list, depth);
                self.statements = counted;
            }
        }
    }

    fn expr(&mut self, e: &Expr) {
        match &e.kind {
            ExprKind::Var(v) => {
                self.refs.insert(key(*v));
            }
            ExprKind::Field { base, .. }
            | ExprKind::Deref(base)
            | ExprKind::AddrOf(base)
            | ExprKind::Unary(_, base)
            | ExprKind::Convert(_, base) => self.expr(base),
            ExprKind::Index { base, index, .. } | ExprKind::OpenIndex { base, index, .. } => {
                self.expr(base);
                self.expr(index);
            }
            ExprKind::Binary(op, a, b) => {
                if matches!(op, BinOp::AndThen | BinOp::OrElse | BinOp::BoolAnd | BinOp::BoolOr) {
                    self.decisions += 1;
                }
                self.expr(a);
                self.expr(b);
            }
            ExprKind::Call { callee, args } => {
                match callee {
                    Callee::Routine(id) | Callee::Virtual { routine: id, .. } => {
                        self.calls.insert(id.0);
                    }
                    Callee::Indirect(target) => self.expr(target),
                }
                for a in args {
                    self.expr(a);
                }
            }
            ExprKind::Concat(list) | ExprKind::Intrinsic(_, list) => {
                for x in list {
                    self.expr(x);
                }
            }
            ExprKind::SetBuild(items) => {
                for (lo, hi) in items {
                    self.expr(lo);
                    if let Some(hi) = hi {
                        self.expr(hi);
                    }
                }
            }
            ExprKind::Int(_)
            | ExprKind::Real(_)
            | ExprKind::Str(_)
            | ExprKind::Nil
            | ExprKind::SetConst(_)
            | ExprKind::RoutineAddr(_) => {}
        }
    }
}

/// What the syntax tree of the user's files gives: literals that look like
/// magic numbers, where each routine declares its variables, and the main
/// file's shape.
#[derive(Default)]
struct Syntax {
    /// `(file, line, text as written, in a declaration)`.
    magic: Vec<(FileId, u32, String, bool)>,
    /// `(file, routine start, routine end, upper-case name -> line)`.
    decls: Vec<(FileId, u32, u32, HashMap<String, u32>)>,
    shape: Vec<(u32, &'static str)>,
}

/// Walks one parsed file. `tmp` is the map it was parsed into, `file` the
/// id of the same file in the compiler's map.
struct SyntaxWalk<'a> {
    tmp: &'a SourceMap,
    file: FileId,
    out: &'a mut Syntax,
    shape: bool,
}

impl SyntaxWalk<'_> {
    fn line(&self, span: Span) -> u32 {
        self.tmp.file(span.file).line_col(span.start).0
    }

    fn token(&mut self, span: Span, t: &'static str) {
        if self.shape {
            let l = self.line(span);
            self.out.shape.push((l, t));
        }
    }

    fn magic(&mut self, e: &ast::Expr, declaration: bool) {
        let is_magic = match e.kind {
            ast::ExprKind::Int(v) => v > 2,
            ast::ExprKind::Real(v) => v != 0.0 && v != 1.0,
            _ => false,
        };
        if is_magic {
            let bytes = &self.tmp.file(e.span.file).bytes;
            let (start, end) = (e.span.start as usize, (e.span.end as usize).min(bytes.len()));
            let text = String::from_utf8_lossy(bytes.get(start..end).unwrap_or_default()).trim().to_string();
            let l = self.line(e.span);
            self.out.magic.push((self.file, l, text, declaration));
        }
    }

    fn module(&mut self, m: &ast::Module) {
        match m {
            ast::Module::Program(p) => {
                self.decls(&p.block.decls);
                if let ast::Body::Statements(list, _) = &p.block.body {
                    self.stmts(list);
                }
            }
            ast::Module::Unit(u) => {
                self.decls(&u.interface);
                self.decls(&u.implementation);
                if let Some(list) = &u.init {
                    self.stmts(list);
                }
            }
        }
    }

    fn decls(&mut self, list: &[ast::Decl]) {
        for d in list {
            match d {
                ast::Decl::Types(types) => {
                    for t in types {
                        self.type_expr(&t.ty);
                    }
                }
                ast::Decl::Vars(vars) => {
                    for v in vars {
                        self.type_expr(&v.ty);
                    }
                }
                ast::Decl::Routine(r) => self.routine(r),
                ast::Decl::Labels(_) | ast::Decl::Consts(_) => {}
            }
        }
    }

    fn routine(&mut self, r: &ast::Routine) {
        let ast::RoutineBody::Block(block) = &r.body else { return };
        let mut names = HashMap::new();
        for d in &block.decls {
            if let ast::Decl::Vars(vars) = d {
                for v in vars {
                    for n in &v.names {
                        names.insert(n.key(), self.line(n.span));
                    }
                }
            }
        }
        self.out.decls.push((self.file, r.span.start, r.span.end, names));
        let kind = if r.heading.result.is_some() { "function" } else { "procedure" };
        self.token(r.span, kind);
        self.decls(&block.decls);
        if let ast::Body::Statements(list, _) = &block.body {
            self.stmts(list);
        }
    }

    /// Array bounds written as numbers in `var` and `type` sections.
    fn type_expr(&mut self, t: &ast::TypeExpr) {
        match &t.kind {
            ast::TypeKind::Array { index, elem, .. } => {
                for ix in index {
                    if let ast::TypeKind::Subrange(lo, hi) = &ix.kind {
                        self.magic(lo, true);
                        self.magic(hi, true);
                    }
                }
                self.type_expr(elem);
            }
            ast::TypeKind::Pointer(inner) => self.type_expr(inner),
            _ => {}
        }
    }

    fn stmts(&mut self, list: &[ast::Stmt]) {
        for s in list {
            self.stmt(s);
        }
    }

    fn stmt(&mut self, s: &ast::Stmt) {
        match &s.kind {
            ast::StmtKind::Empty => {}
            ast::StmtKind::Assign { target, value } => {
                self.token(s.span, "assign");
                self.expr(target);
                self.expr(value);
            }
            ast::StmtKind::Call(e) => {
                self.token(s.span, "statement-call");
                self.expr(e);
            }
            ast::StmtKind::Compound(list) => self.stmts(list),
            ast::StmtKind::If { cond, then, otherwise } => {
                self.token(s.span, "if");
                self.expr(cond);
                self.stmt(then);
                if let Some(o) = otherwise {
                    self.token(o.span, "else");
                    self.stmt(o);
                }
            }
            ast::StmtKind::Case { expr, arms, otherwise } => {
                self.token(s.span, "case");
                self.expr(expr);
                // Case labels name the choices; they are not magic numbers.
                for arm in arms {
                    self.token(arm.span, "arm");
                    self.stmt(&arm.body);
                }
                if let Some(list) = otherwise {
                    self.token(s.span, "else");
                    self.stmts(list);
                }
            }
            ast::StmtKind::While { cond, body } => {
                self.token(s.span, "while");
                self.expr(cond);
                self.stmt(body);
            }
            ast::StmtKind::Repeat { body, cond } => {
                self.token(s.span, "repeat");
                self.stmts(body);
                self.token(cond.span, "until");
                self.expr(cond);
            }
            ast::StmtKind::For { from, to, down, body, .. } => {
                self.token(s.span, if *down { "for-downto" } else { "for" });
                self.expr(from);
                self.expr(to);
                self.stmt(body);
            }
            ast::StmtKind::With { records, body } => {
                self.token(s.span, "with");
                for r in records {
                    self.expr(r);
                }
                self.stmt(body);
            }
            ast::StmtKind::Goto(_) => self.token(s.span, "goto"),
            ast::StmtKind::Labeled(_, inner) => self.stmt(inner),
            ast::StmtKind::Asm(_) => self.token(s.span, "asm"),
        }
    }

    fn expr(&mut self, e: &ast::Expr) {
        self.magic(e, false);
        match &e.kind {
            ast::ExprKind::Int(_) => self.token(e.span, "int"),
            ast::ExprKind::Real(_) => self.token(e.span, "real"),
            ast::ExprKind::Str(_) => self.token(e.span, "str"),
            ast::ExprKind::Nil => self.token(e.span, "nil"),
            ast::ExprKind::Name(_) => self.token(e.span, "name"),
            ast::ExprKind::Set(items) => {
                self.token(e.span, "set");
                for item in items {
                    self.expr(&item.lo);
                    if let Some(hi) = &item.hi {
                        self.expr(hi);
                    }
                }
            }
            ast::ExprKind::Unary(op, inner) => {
                let t = match op {
                    ast::UnOp::Neg => "neg",
                    ast::UnOp::Pos => "pos",
                    ast::UnOp::Not => "not",
                    ast::UnOp::AddrOf => "addr",
                };
                self.token(e.span, t);
                self.expr(inner);
            }
            ast::ExprKind::Binary(op, a, b) => {
                self.token(e.span, op.symbol());
                self.expr(a);
                self.expr(b);
            }
            ast::ExprKind::Call { callee, args } => {
                self.token(e.span, "call");
                self.expr(callee);
                // Write widths (`x:10:2`) are layout, not magic numbers.
                for a in args {
                    self.expr(&a.value);
                }
            }
            ast::ExprKind::Index { base, indices } => {
                self.token(e.span, "index");
                self.expr(base);
                for i in indices {
                    self.expr(i);
                }
            }
            ast::ExprKind::Field { base, .. } => {
                self.token(e.span, "field");
                self.expr(base);
            }
            ast::ExprKind::Deref(inner) => {
                self.token(e.span, "deref");
                self.expr(inner);
            }
            ast::ExprKind::Inherited(_) => self.token(e.span, "inherited"),
            ast::ExprKind::StringType => self.token(e.span, "string"),
        }
    }
}

/// Parses the user's files again (their syntax trees are not kept after
/// checking) and walks them.
fn syntax(map: &SourceMap, user: &HashSet<FileId>, main: FileId, lex: &odin_syntax::LexOptions) -> Syntax {
    let mut out = Syntax::default();
    let mut files: Vec<FileId> = user.iter().copied().collect();
    files.sort_by_key(|f| f.0);
    for file in files {
        let source = map.file(file);
        let mut tmp = SourceMap::new();
        let id = tmp.add(source.path.clone(), source.bytes.clone());
        // An include file has no module of its own; its statements belong to
        // the file that includes it.
        let Ok(parsed) = odin_syntax::parse_file(&mut tmp, id, lex) else { continue };
        let mut walk = SyntaxWalk { tmp: &tmp, file, out: &mut out, shape: file == main };
        walk.module(&parsed.module);
    }
    out
}

pub fn describe(
    map: &SourceMap,
    program: &Program,
    user: &HashSet<FileId>,
    main: FileId,
    lex: &odin_syntax::LexOptions,
) -> Metrics {
    let syntax = syntax(map, user, main, lex);
    let is_user = |span: Span| user.contains(&span.file);
    let code = |r: &Routine| matches!(r.body, RoutineBody::Code(_)) && is_user(r.span);
    let walks: Vec<Option<Walk>> = program
        .routines
        .iter()
        .map(|r| match &r.body {
            RoutineBody::Code(body) if is_user(r.span) => {
                let mut w = Walk::default();
                w.stmts(body, 0);
                Some(w)
            }
            _ => None,
        })
        .collect();
    let mut refs: HashSet<(u8, u32, u32)> = HashSet::new();
    for w in walks.iter().flatten() {
        refs.extend(w.refs.iter().copied());
    }
    // A routine is recursive when it can reach itself through calls.
    let reaches_itself = |start: usize| {
        let mut seen = HashSet::new();
        let mut stack: Vec<u32> = walks[start].as_ref().map(|w| w.calls.iter().copied().collect()).unwrap_or_default();
        while let Some(r) = stack.pop() {
            if r as usize == start {
                return true;
            }
            if seen.insert(r)
                && let Some(Some(w)) = walks.get(r as usize)
            {
                stack.extend(w.calls.iter().copied());
            }
        }
        false
    };
    let entry: HashSet<u32> = program.init_order.iter().map(|r| r.0).chain([program.main.0]).collect();
    let mut metrics = Metrics { routines: Vec::new(), notes: Vec::new(), facts: Facts::default(), shape: syntax.shape };
    let mut notes: Vec<Note> = Vec::new();
    let mut note = |code: &'static str, level: &'static str, span: Span, line: u32, message: String| {
        notes.push(Note { code, level, file: span.file, line, message });
    };
    for (i, r) in program.routines.iter().enumerate() {
        let Some(w) = &walks[i] else { continue };
        let name = r.display.clone();
        let first = line(map, r.span);
        let main_like = entry.contains(&(i as u32));
        let recursive = reaches_itself(i);
        let mut globals_written: Vec<String> = Vec::new();
        if !main_like {
            for v in &w.writes {
                if let Var::Global(g) = v {
                    let global = &program.globals[g.0 as usize];
                    if is_user(global.span) && !globals_written.contains(&global.name) {
                        globals_written.push(global.name.clone());
                    }
                }
            }
        }
        // Where this routine declares its variables, from the syntax tree.
        let decl_lines = syntax
            .decls
            .iter()
            .filter(|(f, start, end, _)| {
                *f == r.span.file && *start <= r.span.start && r.span.start < (*end).max(*start + 1)
            })
            .min_by_key(|(_, start, end, _)| end - start)
            .map(|(_, _, _, names)| names);
        for (index, local) in r.locals.iter().enumerate() {
            if local.kind == LocalKind::Var
                && !refs.contains(&key(Var::Local { routine: RoutineId(i as u32), index: index as u32 }))
            {
                let at = decl_lines.and_then(|d| d.get(&local.name.to_ascii_uppercase())).copied().unwrap_or(first);
                note(
                    "unused-var",
                    "saran",
                    r.span,
                    at,
                    format!("Variabel `{}` dideklarasikan tetapi tidak dipakai.", local.name),
                );
            }
        }
        if r.sig.result.is_some()
            && let Some(result) = r.result_local()
            && !refs.contains(&key(Var::Local { routine: RoutineId(i as u32), index: result }))
        {
            note("result-unset", "saran", r.span, first, format!("Fungsi `{name}` tidak pernah mengisi hasilnya."));
        }
        for g in &w.gotos {
            note("goto", "saran", *g, line(map, *g), "`goto` bisa diganti perulangan, `Break`, atau `Exit`.".into());
        }
        if w.nesting > MAX_NESTING {
            let at = w.deepest.map(|s| line(map, s)).unwrap_or(first);
            note(
                "deep-nesting",
                "saran",
                r.span,
                at,
                format!("Blok di `{name}` bersarang {} tingkat; pertimbangkan prosedur terpisah.", w.nesting),
            );
        }
        let complexity = 1 + w.decisions;
        if complexity > MAX_COMPLEXITY {
            note(
                "complexity",
                "saran",
                r.span,
                first,
                format!("`{name}` punya kompleksitas siklomatik {complexity}; pertimbangkan memecahnya."),
            );
        }
        if !globals_written.is_empty() {
            let list: Vec<String> = globals_written.iter().map(|g| format!("`{g}`")).collect();
            note(
                "global-write",
                "info",
                r.span,
                first,
                format!("`{name}` mengubah variabel global {}.", list.join(", ")),
            );
        }
        if !main_like {
            metrics.facts.routines += 1;
        }
        if recursive {
            metrics.facts.recursive.push(name.clone());
        }
        metrics.facts.statements += w.statements;
        metrics.facts.max_nesting = metrics.facts.max_nesting.max(w.nesting);
        metrics.facts.gotos += w.gotos.len() as u32;
        metrics.routines.push(RoutineInfo {
            name,
            file: r.span.file,
            line: first,
            end_line: end_line(map, r.span),
            statements: w.statements,
            nesting: w.nesting,
            complexity,
            recursive,
            globals_written,
        });
    }
    for (gi, g) in program.globals.iter().enumerate() {
        if g.init.is_none() && is_user(g.span) && !refs.contains(&key(Var::Global(GlobalId(gi as u32)))) {
            note(
                "unused-var",
                "saran",
                g.span,
                line(map, g.span),
                format!("Variabel `{}` dideklarasikan tetapi tidak dipakai.", g.name),
            );
        }
    }
    // Magic numbers: one note per value, at its first use, for a value written
    // more than once or as an array bound.
    let mut values: Vec<(FileId, u32, String, u32, bool)> = Vec::new();
    for (file, l, text, declaration) in syntax.magic {
        match values.iter_mut().find(|(f, _, t, _, _)| *f == file && t.eq_ignore_ascii_case(&text)) {
            Some(v) => {
                v.3 += 1;
                v.4 |= declaration;
            }
            None => values.push((file, l, text, 1, declaration)),
        }
    }
    for (file, l, text, n, declaration) in values {
        if n < 2 && !declaration {
            continue;
        }
        let message = if n > 1 {
            format!("Angka {text} muncul {n} kali; jadikan `const`.")
        } else {
            format!("Angka {text} sebaiknya dijadikan `const`.")
        };
        note("magic-number", "saran", Span::new(file, 0, 0), l, message);
    }
    metrics.notes = notes;
    // Types of the user's variables, for requirements such as "uses an array".
    let mut types: Vec<TypeId> =
        program.globals.iter().filter(|g| g.init.is_none() && is_user(g.span)).map(|g| g.ty).collect();
    for r in program.routines.iter().filter(|r| code(r)) {
        types.extend(r.locals.iter().filter(|l| matches!(l.kind, LocalKind::Var | LocalKind::Param(_))).map(|l| l.ty));
    }
    metrics.facts.global_bytes = program
        .globals
        .iter()
        .filter(|g| g.init.is_none() && is_user(g.span))
        .map(|g| program.types.size(g.ty))
        .sum();
    for ty in types {
        match program.types.get(ty) {
            Type::Array { .. } => metrics.facts.arrays = true,
            Type::Record { .. } => metrics.facts.records = true,
            Type::Pointer(_) => metrics.facts.pointers = true,
            _ => {}
        }
    }
    metrics.routines.sort_by_key(|r| (r.file.0, r.line));
    metrics.notes.sort_by_key(|n| (n.file.0, n.line));
    metrics
}

fn json_str(s: &str) -> String {
    let mut out = String::new();
    write_string(&mut out, s);
    out
}

impl Metrics {
    /// One line of JSON: `{"type":"metrics","version":1,...}`.
    pub fn to_json(&self, map: &SourceMap) -> String {
        let path = |f: FileId| map.file(f).path.to_string_lossy().into_owned();
        let routines: Vec<String> = self
            .routines
            .iter()
            .map(|r| {
                let mut w = JsonWriter::object();
                w.field_str("name", &r.name);
                w.field_str("file", &path(r.file));
                w.field_num("line", r.line as i64);
                w.field_num("end_line", r.end_line as i64);
                w.field_num("statements", r.statements as i64);
                w.field_num("nesting", r.nesting as i64);
                w.field_num("complexity", r.complexity as i64);
                w.field_bool("recursive", r.recursive);
                w.field_str_array("globals_written", r.globals_written.iter().map(String::as_str));
                w.finish()
            })
            .collect();
        let notes: Vec<String> = self
            .notes
            .iter()
            .map(|n| {
                let mut w = JsonWriter::object();
                w.field_str("code", n.code);
                w.field_str("level", n.level);
                w.field_str("file", &path(n.file));
                w.field_num("line", n.line as i64);
                w.field_str("message", &n.message);
                w.finish()
            })
            .collect();
        let mut facts = JsonWriter::object();
        facts.field_num("routines", self.facts.routines as i64);
        facts.field_num("statements", self.facts.statements as i64);
        facts.field_num("max_nesting", self.facts.max_nesting as i64);
        facts.field_num("gotos", self.facts.gotos as i64);
        facts.field_str_array("recursive", self.facts.recursive.iter().map(String::as_str));
        facts.field_bool("arrays", self.facts.arrays);
        facts.field_bool("records", self.facts.records);
        facts.field_bool("pointers", self.facts.pointers);
        facts.field_num("global_bytes", self.facts.global_bytes as i64);
        let shape: Vec<String> = self.shape.iter().map(|(l, t)| format!("[{l},{}]", json_str(t))).collect();
        let mut w = JsonWriter::object();
        w.field_str("type", "metrics");
        w.field_num("version", 1);
        w.field_raw("routines", &format!("[{}]", routines.join(",")));
        w.field_raw("notes", &format!("[{}]", notes.join(",")));
        w.field_raw("facts", &facts.finish());
        w.field_raw("shape", &format!("[{}]", shape.join(",")));
        w.finish()
    }

    /// The same for people reading a terminal.
    pub fn to_text(&self, map: &SourceMap) -> String {
        let name = |f: FileId| {
            let p = &map.file(f).path;
            p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| p.display().to_string())
        };
        let mut out = String::from("Rutin:\n");
        for r in &self.routines {
            out.push_str(&format!(
                "  {} ({} baris {}-{}): {} pernyataan, nesting {}, kompleksitas {}{}\n",
                r.name,
                name(r.file),
                r.line,
                r.end_line,
                r.statements,
                r.nesting,
                r.complexity,
                if r.recursive { ", rekursif" } else { "" }
            ));
        }
        out.push_str(&format!("Catatan ({}):\n", self.notes.len()));
        for n in &self.notes {
            let level = if n.level == "saran" { "Saran" } else { "Info" };
            out.push_str(&format!("  {}({}) {level}: {}\n", name(n.file), n.line, n.message));
        }
        let yes = |b: bool| if b { "ya" } else { "tidak" };
        out.push_str(&format!(
            "Fakta: {} rutin, {} pernyataan, nesting maks. {}, goto {}, rekursif: {}, larik {}, record {}, pointer {}, memori global {} B\n",
            self.facts.routines,
            self.facts.statements,
            self.facts.max_nesting,
            self.facts.gotos,
            if self.facts.recursive.is_empty() { "-".to_string() } else { self.facts.recursive.join(", ") },
            yes(self.facts.arrays),
            yes(self.facts.records),
            yes(self.facts.pointers),
            self.facts.global_bytes
        ));
        out
    }
}
