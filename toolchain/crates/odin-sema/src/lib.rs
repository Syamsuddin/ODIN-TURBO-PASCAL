// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Semantic analysis: name resolution, type checking and lowering of the
//! AST to the typed HIR of `odin-ir`.
//!
//! Units are analysed in two passes: every interface first (in dependency
//! order), then every implementation, then the program. Like TP, analysis
//! stops at the first error.

mod builtin;
mod decl;
mod expr;
mod object;
pub mod scope;
mod stmt;
mod typeres;

use std::collections::HashMap;

use odin_base::{Diagnostic, SourceMap, Span, code};
use odin_ir::*;
use odin_syntax::Switches;
use odin_syntax::ast;

pub use scope::{Builtin, ConstKind, ConstVal, Scope, Sym};

pub type SResult<T> = Result<T, Diagnostic>;

/// One parsed unit (or the program, last) handed to [`analyze`].
pub struct UnitSource {
    /// Uppercase unit name; `$PROGRAM` for the main program.
    pub name: String,
    pub module: ast::Module,
}

/// Analysis results: the program and any warnings.
pub struct Analysis {
    pub program: Program,
    pub warnings: Vec<Diagnostic>,
}

/// Analyses `units` in order: `System` first, the program last. Every unit
/// must come after the units its interface uses.
pub fn analyze(map: &SourceMap, units: Vec<UnitSource>) -> SResult<Analysis> {
    let mut a = Analyzer::new(map);
    let mut program = None;
    for (i, u) in units.iter().enumerate() {
        match &u.module {
            ast::Module::Unit(_) => {
                a.units.push(UnitInfo::new(&u.name));
                a.unit_index.insert(u.name.clone(), i);
            }
            ast::Module::Program(p) => program = Some(p),
        }
    }
    for (i, u) in units.iter().enumerate() {
        if let ast::Module::Unit(unit) = &u.module {
            a.unit_interface(i, unit)?;
        }
    }
    for (i, u) in units.iter().enumerate() {
        if let ast::Module::Unit(unit) = &u.module {
            a.unit_implementation(i, unit)?;
        }
    }
    let Some(program) = program else {
        return Err(Diagnostic::error_with(code::INTERNAL, Span::default(), ": tidak ada program utama"));
    };
    let main = a.program(program)?;
    let files = (0..map.len()).map(|i| map.file(odin_base::FileId(i as u32)).path.clone()).collect();
    Ok(Analysis {
        program: Program {
            types: a.types,
            globals: a.globals,
            routines: a.routines,
            init_order: a.init_order,
            main,
            files,
        },
        warnings: a.warnings,
    })
}

pub(crate) struct UnitInfo {
    pub name: String,
    pub interface: Scope,
    pub implementation: Scope,
    pub interface_uses: Vec<usize>,
    pub implementation_uses: Vec<usize>,
}

impl UnitInfo {
    fn new(name: &str) -> Self {
        UnitInfo {
            name: name.to_string(),
            interface: Scope::default(),
            implementation: Scope::default(),
            interface_uses: Vec::new(),
            implementation_uses: Vec::new(),
        }
    }
}

/// An active `with` record: a temporary holding its address.
#[derive(Clone)]
pub(crate) struct WithScope {
    pub ptr: Var,
    pub ptr_ty: TypeId,
    pub record: TypeId,
}

pub(crate) struct LabelInfo {
    pub id: LabelId,
    pub placed: bool,
    pub span: Span,
}

/// A routine whose declarations or body are being analysed.
pub(crate) struct Frame {
    pub routine: RoutineId,
    pub scope: Scope,
    pub withs: Vec<WithScope>,
    pub labels: HashMap<String, LabelInfo>,
    pub loops: u32,
    /// Forward-declared nested routines still waiting for a body.
    pub forwards: Vec<(RoutineId, Span)>,
    /// A method body: its object type and `Self`.
    pub object: Option<object::ObjectScope>,
}

pub(crate) struct Analyzer<'m> {
    _map: std::marker::PhantomData<&'m SourceMap>,
    pub types: TypeTable,
    pub globals: Vec<Global>,
    pub routines: Vec<Routine>,
    pub init_order: Vec<RoutineId>,
    pub root: Scope,
    pub units: Vec<UnitInfo>,
    pub unit_index: HashMap<String, usize>,
    /// Index of the unit being analysed; `None` for the program.
    pub cur_unit: Option<usize>,
    pub in_interface: bool,
    /// Units the program uses (only while analysing the program).
    pub program_uses: Vec<usize>,
    pub program_scope: Scope,
    pub frames: Vec<Frame>,
    /// Switches of the statement being analysed.
    pub sw: Switches,
    pub warnings: Vec<Diagnostic>,
    pub next_label: u32,
    /// Interface routines of the current unit still waiting for a body.
    pub unit_forwards: Vec<(RoutineId, Span)>,
    /// Interface routines of every unit, kept between the two passes.
    pub pending_bodies: HashMap<usize, Vec<(RoutineId, Span)>>,
    /// `SYSTEM.TEXT`, `SYSTEM.FILEREC`, once System declares them.
    pub text_type: Option<TypeId>,
    pub filerec_type: Option<TypeId>,
    /// Declared methods without a body yet: (routine, name span, module).
    pub missing_methods: Vec<(RoutineId, Span, Option<usize>)>,
    /// `SYSTEM.TOBJECT`, the root class, once System declares it.
    pub tobject: Option<TypeId>,
    /// `class of T` types made for class names used as values, per class.
    pub class_refs: HashMap<TypeId, TypeId>,
    /// `TFoo = class;` declarations of the current type section still
    /// waiting for their class: (class type, name key, span).
    pub forward_classes: Vec<(TypeId, String, Span)>,
    /// Upper-case names the type section being analysed declares.
    pub section_types: std::collections::HashSet<String>,
}

impl<'m> Analyzer<'m> {
    fn new(_map: &'m SourceMap) -> Self {
        let types = TypeTable::new();
        let mut root = Scope::default();
        let b = types.builtin;
        let mut put = |name: &str, sym: Sym| {
            root.replace(name.to_string(), sym, Span::default());
        };
        for (name, ty) in [
            ("SHORTINT", b.shortint),
            ("SMALLINT", b.smallint),
            ("INTEGER", b.smallint),
            ("LONGINT", b.longint),
            ("INT64", b.int64),
            ("BYTE", b.byte),
            ("WORD", b.word),
            ("LONGWORD", b.longword),
            ("CARDINAL", b.longword),
            ("DWORD", b.longword),
            ("QWORD", b.qword),
            ("BOOLEAN", b.boolean),
            ("CHAR", b.char),
            ("REAL", b.double),
            ("DOUBLE", b.double),
            ("EXTENDED", b.double),
            ("COMP", b.double),
            ("SINGLE", b.single),
            ("STRING", b.string),
            ("POINTER", b.pointer),
            ("PCHAR", b.pchar),
            ("OPENSTRING", b.openstring),
        ] {
            put(name, Sym::Type(ty));
        }
        let int = |v: i64, ty| Sym::Const(ConstVal { kind: ConstKind::Int(v), ty });
        put("TRUE", int(1, b.boolean));
        put("FALSE", int(0, b.boolean));
        put("MAXINT", int(32767, b.smallint));
        put("MAXLONGINT", int(i32::MAX as i64, b.longint));
        for (name, builtin) in scope::BUILTINS {
            put(name, Sym::Builtin(*builtin));
        }
        Analyzer {
            _map: std::marker::PhantomData,
            types,
            globals: Vec::new(),
            routines: Vec::new(),
            init_order: Vec::new(),
            root,
            units: Vec::new(),
            unit_index: HashMap::new(),
            cur_unit: None,
            in_interface: false,
            program_uses: Vec::new(),
            program_scope: Scope::default(),
            frames: Vec::new(),
            sw: Switches::tp_default(),
            warnings: Vec::new(),
            next_label: 0,
            unit_forwards: Vec::new(),
            pending_bodies: HashMap::new(),
            text_type: None,
            filerec_type: None,
            missing_methods: Vec::new(),
            tobject: None,
            class_refs: HashMap::new(),
            forward_classes: Vec::new(),
            section_types: Default::default(),
        }
    }

    // ---- names -----------------------------------------------------------

    /// Prefix for mangled symbols of the current unit.
    pub fn unit_prefix(&self) -> String {
        match self.cur_unit {
            Some(i) => self.units[i].name.clone(),
            None => "$PROGRAM".into(),
        }
    }

    /// Mangled name for a declaration in the current context.
    pub fn mangle(&self, name: &str) -> String {
        // Inside a routine its symbol is the prefix: it already names the
        // enclosing routines, and the object of a method.
        let mut s = match self.frames.last().map(|f| &self.routines[f.routine.0 as usize].symbol) {
            Some(r) if !r.ends_with(".$MAIN") && !r.ends_with(".$INIT") => r.clone(),
            _ => self.unit_prefix(),
        };
        s.push('.');
        s.push_str(&name.to_ascii_uppercase());
        s
    }

    fn scope_chain_units(&self) -> Vec<usize> {
        // Later units in a uses clause shadow earlier ones.
        let mut order = Vec::new();
        match self.cur_unit {
            Some(i) => {
                if !self.in_interface {
                    order.extend(self.units[i].implementation_uses.iter().rev());
                }
                order.extend(self.units[i].interface_uses.iter().rev());
            }
            None => order.extend(self.program_uses.iter().rev()),
        }
        if self.cur_unit != Some(0) && !self.units.is_empty() && !order.contains(&0) {
            order.push(0);
        }
        order
    }

    /// Looks up a name (uppercase key) in the current context. `with`
    /// fields are handled by the caller.
    pub fn lookup(&self, key: &str) -> Option<Sym> {
        for f in self.frames.iter().rev() {
            if let Some(s) = f.scope.get(key) {
                return Some(s.clone());
            }
        }
        match self.cur_unit {
            Some(i) => {
                if !self.in_interface {
                    if let Some(s) = self.units[i].implementation.get(key) {
                        return Some(s.clone());
                    }
                }
                if let Some(s) = self.units[i].interface.get(key) {
                    return Some(s.clone());
                }
                if self.units[i].name == key {
                    return Some(Sym::Unit(i));
                }
            }
            None => {
                if let Some(s) = self.program_scope.get(key) {
                    return Some(s.clone());
                }
            }
        }
        for u in self.scope_chain_units() {
            if let Some(s) = self.units[u].interface.get(key) {
                return Some(s.clone());
            }
        }
        for u in self.scope_chain_units() {
            if self.units[u].name == key {
                return Some(Sym::Unit(u));
            }
        }
        self.root.get(key).cloned()
    }

    /// Declares `name` in the innermost scope.
    pub fn declare(&mut self, name: &ast::Ident, sym: Sym) -> SResult<()> {
        let key = name.key();
        let duplicate = |earlier: Span| {
            let _ = earlier;
            Diagnostic::error_with(code::DUPLICATE_IDENT, name.span, format!(": {}", name.name))
        };
        if let Some(f) = self.frames.last_mut() {
            return f.scope.insert(key, sym, name.span).map_err(duplicate);
        }
        match self.cur_unit {
            Some(i) => {
                let unit = &mut self.units[i];
                if self.in_interface {
                    unit.interface.insert(key, sym, name.span).map_err(duplicate)
                } else {
                    if unit.interface.contains(&key) {
                        return Err(duplicate(name.span));
                    }
                    unit.implementation.insert(key, sym, name.span).map_err(duplicate)
                }
            }
            None => self.program_scope.insert(key, sym, name.span).map_err(duplicate),
        }
    }

    /// Looks up a name declared in the innermost scope only.
    pub fn lookup_local(&self, key: &str) -> Option<Sym> {
        if let Some(f) = self.frames.last() {
            return f.scope.get(key).cloned();
        }
        match self.cur_unit {
            Some(i) => {
                let unit = &self.units[i];
                if !self.in_interface {
                    if let Some(s) = unit.implementation.get(key) {
                        return Some(s.clone());
                    }
                }
                unit.interface.get(key).cloned()
            }
            None => self.program_scope.get(key).cloned(),
        }
    }

    pub fn current_routine(&self) -> Option<RoutineId> {
        self.frames.last().map(|f| f.routine)
    }

    pub fn routine(&self, id: RoutineId) -> &Routine {
        &self.routines[id.0 as usize]
    }

    pub fn routine_mut(&mut self, id: RoutineId) -> &mut Routine {
        &mut self.routines[id.0 as usize]
    }

    /// Adds a local variable (or temporary) to the current routine.
    pub fn add_local(&mut self, name: &str, ty: TypeId, kind: LocalKind) -> Var {
        let routine = self.current_routine().expect("locals need a routine");
        let r = self.routine_mut(routine);
        r.locals.push(Local { name: name.to_string(), ty, kind });
        Var::Local { routine, index: r.locals.len() as u32 - 1 }
    }

    pub fn add_temp(&mut self, ty: TypeId) -> Var {
        self.add_local("$temp", ty, LocalKind::Temp)
    }

    pub fn add_global(&mut self, name: &str, ty: TypeId, init: Option<GlobalInit>, span: Span) -> GlobalId {
        let symbol = self.mangle(name);
        self.globals.push(Global { symbol, name: name.to_string(), ty, init, readonly: false, span });
        GlobalId(self.globals.len() as u32 - 1)
    }

    pub fn new_label(&mut self) -> LabelId {
        self.next_label += 1;
        LabelId(self.next_label - 1)
    }

    pub fn error<T>(&self, code: u16, span: Span) -> SResult<T> {
        Err(Diagnostic::error(code, span))
    }

    pub fn error_with<T>(&self, code: u16, span: Span, detail: impl AsRef<str>) -> SResult<T> {
        Err(Diagnostic::error_with(code, span, detail))
    }

    pub fn var_expr(&self, var: Var, ty: TypeId, span: Span) -> Expr {
        Expr::new(ExprKind::Var(var), ty, span)
    }

    // ---- units and program -----------------------------------------------

    fn resolve_uses(&self, names: &[ast::Ident]) -> SResult<Vec<usize>> {
        let mut out = Vec::new();
        for n in names {
            let key = n.key();
            if key == "SYSTEM" {
                continue;
            }
            match self.unit_index.get(&key) {
                Some(&i) => out.push(i),
                None => return self.error_with(code::FILE_NOT_FOUND, n.span, format!(": unit {}", n.name)),
            }
        }
        Ok(out)
    }

    fn unit_interface(&mut self, index: usize, unit: &ast::Unit) -> SResult<()> {
        self.cur_unit = Some(index);
        self.in_interface = true;
        self.units[index].interface_uses = self.resolve_uses(&unit.interface_uses)?;
        self.unit_forwards.clear();
        self.decls(&unit.interface)?;
        // Keep the interface routines that need bodies for pass 2.
        let pending = std::mem::take(&mut self.unit_forwards);
        self.pending_bodies.insert(index, pending);
        if index == 0 {
            self.find_system_types();
        }
        Ok(())
    }

    fn find_system_types(&mut self) {
        if let Some(Sym::Type(t)) = self.units[0].interface.get("TEXT") {
            self.text_type = Some(*t);
        }
        if let Some(Sym::Type(t)) = self.units[0].interface.get("FILEREC") {
            self.filerec_type = Some(*t);
        }
        if let Some(Sym::Type(t)) = self.units[0].interface.get("TOBJECT")
            && self.types.class_object(*t).is_some()
        {
            self.tobject = Some(*t);
        }
    }

    fn unit_implementation(&mut self, index: usize, unit: &ast::Unit) -> SResult<()> {
        self.cur_unit = Some(index);
        self.in_interface = false;
        self.units[index].implementation_uses = self.resolve_uses(&unit.implementation_uses)?;
        self.unit_forwards = self.pending_bodies.remove(&index).unwrap_or_default();
        self.decls(&unit.implementation)?;
        if let Some((id, span)) = self.unit_forwards.first() {
            let name = self.routine(*id).display.clone();
            return self.error_with(code::UNDEFINED_FORWARD, *span, format!(": {name}"));
        }
        self.check_methods_implemented()?;
        if let Some(stmts) = &unit.init {
            let id = self.new_routine(
                &format!("{}.$INIT", self.unit_prefix()),
                &format!("{}.init", unit.name.name),
                unit.span,
            );
            self.frames.push(Frame::new(id));
            let body = self.stmt_list(stmts)?;
            self.finish_frame()?;
            self.routine_mut(id).body = RoutineBody::Code(body);
            self.init_order.push(id);
        }
        Ok(())
    }

    fn program(&mut self, p: &ast::Program) -> SResult<RoutineId> {
        self.cur_unit = None;
        self.in_interface = false;
        self.program_uses = self.resolve_uses(&p.uses)?;
        let name = p.name.as_ref().map_or("Program".to_string(), |n| n.name.clone());
        let id = self.new_routine("$PROGRAM.$MAIN", &name, p.span);
        // Program-level variables are globals; labels and temporaries
        // belong to the main routine.
        self.unit_forwards.clear();
        self.decls_program(&p.block.decls, id)?;
        if let Some((rid, span)) = self.unit_forwards.first() {
            let name = self.routine(*rid).display.clone();
            return self.error_with(code::UNDEFINED_FORWARD, *span, format!(": {name}"));
        }
        self.check_methods_implemented()?;
        let body = match &p.block.body {
            ast::Body::Statements(stmts, _) => {
                self.frames.push(Frame::new(id));
                self.declare_labels_from(&p.block.decls)?;
                let body = self.stmt_list(stmts)?;
                self.finish_frame()?;
                body
            }
            ast::Body::Asm(a) => return self.error_with(code::NOT_SUPPORTED, a.span, ": blok asm"),
        };
        self.routine_mut(id).body = RoutineBody::Code(body);
        Ok(id)
    }

    pub fn new_routine(&mut self, symbol: &str, display: &str, span: Span) -> RoutineId {
        self.routines.push(Routine {
            symbol: symbol.to_string(),
            display: display.to_string(),
            sig: Signature { params: Vec::new(), result: None },
            parent: self.current_routine(),
            locals: Vec::new(),
            body: RoutineBody::Code(Vec::new()),
            span,
        });
        RoutineId(self.routines.len() as u32 - 1)
    }

    /// Pops the innermost frame after checking its labels.
    pub fn finish_frame(&mut self) -> SResult<()> {
        let frame = self.frames.pop().expect("frame");
        if let Some((rid, span)) = frame.forwards.first() {
            let name = self.routine(*rid).display.clone();
            return self.error_with(code::UNDEFINED_FORWARD, *span, format!(": {name}"));
        }
        for (name, info) in &frame.labels {
            if !info.placed {
                return self.error_with(code::UNDEFINED_LABEL, info.span, format!(": {name}"));
            }
        }
        Ok(())
    }
}

impl Frame {
    pub fn new(routine: RoutineId) -> Self {
        Frame {
            routine,
            scope: Scope::default(),
            withs: Vec::new(),
            labels: HashMap::new(),
            loops: 0,
            forwards: Vec::new(),
            object: None,
        }
    }
}
