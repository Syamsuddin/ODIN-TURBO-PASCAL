// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! x86-64 code generation (System V / Darwin ABI) by walking the HIR.
//!
//! Every variable lives in memory at a fixed frame offset; there is no
//! register allocation. Expressions are evaluated into RAX (ordinals,
//! pointers), XMM0 (reals, always as double) or, for strings, records,
//! arrays and sets, as an address in RAX. Intermediate values go on the
//! machine stack. Calls follow the C ABI, plus a static link in R10 for
//! nested routines. Simple, predictable code that a debugger can follow.
//!
//! On Windows the same code follows the Win64 convention instead: the first
//! four arguments go by position in RCX, RDX, R8, R9 or XMM0-XMM3, the caller
//! leaves 32 bytes of shadow space above the return address, RSI and RDI
//! belong to the caller (every routine keeps them in fixed frame slots), and
//! every prologue probes its frame page by page through ODIN_CHKSTK, since
//! Windows grows the stack only through its guard page.

use std::collections::{BTreeMap, HashMap};

use odin_asm::x86_64::{Assembler, Cond as XCond, Label, Mem, Reg, Width, Xmm};
use odin_asm::{Atom, Import, Object, RelocKind, SectionKind};
use odin_base::Span;
use odin_ir::*;

use crate::{
    CResult, CodegenError, LineEntry, LocalSlot, Options, Os, Output, RTL_ASM_LIBRARY, STEP_COUNTS, import_library,
};

use Reg::*;
use Width::*;

const INT_ARGS: [Reg; 6] = [Rdi, Rsi, Rdx, Rcx, R8, R9];
const FLOAT_ARGS: [Xmm; 8] = [Xmm::Xmm0, Xmm::Xmm1, Xmm::Xmm2, Xmm::Xmm3, Xmm::Xmm4, Xmm::Xmm5, Xmm::Xmm6, Xmm::Xmm7];
/// Win64: the first four arguments, integer or real, go by position.
const WIN_INT_ARGS: [Reg; 4] = [Rcx, Rdx, R8, R9];
/// Win64: stack the caller reserves for the callee's four register arguments.
const SHADOW: i32 = 32;
/// Win64: frame slots keeping the caller's RSI and RDI ([rbp-8] is the static link).
const WIN_SAVE_RSI: i32 = -16;
const WIN_SAVE_RDI: i32 = -24;
/// Win64: shim probing the pages of a new frame (size in RAX), like MSVC's __chkstk.
const CHKSTK: &str = "ODIN_CHKSTK";
/// Placeholder for the frame size, patched once all temporaries are known.
const FRAME_PLACEHOLDER: i32 = 0x1000_0000;

/// Where a local lives, relative to RBP.
#[derive(Clone, Copy, Debug)]
enum Slot {
    /// The storage itself.
    Value(i32),
    /// A pointer to the storage (`var` parameters, by-reference results).
    Pointer(i32),
}

struct Layout {
    slots: Vec<Slot>,
    /// For value parameters copied on entry: slot of the incoming pointer.
    scratch: Vec<Option<i32>>,
    size: u32,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum VClass {
    Int,
    Real,
    Mem,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ArgClass {
    Callee,
    Int,
    Float,
}

fn err<T>(message: impl Into<String>, span: Span) -> CResult<T> {
    Err(CodegenError { message: message.into(), span })
}

fn fits_i32(v: i64) -> bool {
    i32::try_from(v).is_ok()
}

fn align_up(v: u32, a: u32) -> u32 {
    v.div_ceil(a.max(1)) * a.max(1)
}

/// Generates the whole program as one object.
pub fn generate(p: &Program, options: &Options) -> CResult<Output> {
    let mut g = Gen {
        p,
        os: options.os,
        atoms: Vec::new(),
        imports: BTreeMap::new(),
        strings: HashMap::new(),
        sets: HashMap::new(),
        layouts: Vec::new(),
        lines: Vec::new(),
        counter: 0,
        debug_points: Vec::new(),
        count_steps: options.count_steps,
    };
    g.layouts = (0..p.routines.len()).map(|i| g.layout(RoutineId(i as u32))).collect();
    for global in &p.globals {
        g.global(global);
    }
    let instrumented: Vec<bool> = p
        .routines
        .iter()
        .map(|r| matches!(r.body, RoutineBody::Code(_)) && options.debug_files.contains(&r.span.file))
        .collect();
    for (i, r) in p.routines.iter().enumerate() {
        if let RoutineBody::Code(body) = &r.body {
            let mut rg = Rg::new(&mut g, RoutineId(i as u32));
            rg.instrument = instrumented[i];
            let atom = rg.routine(body)?;
            g.atoms.push(atom);
        }
    }
    let entry = g.main_stub(!options.debug_files.is_empty());
    let frames = g
        .layouts
        .iter()
        .map(|l| {
            l.slots
                .iter()
                .map(|slot| match *slot {
                    Slot::Value(offset) => LocalSlot { offset, indirect: false },
                    Slot::Pointer(offset) => LocalSlot { offset, indirect: true },
                })
                .collect()
        })
        .collect();
    Ok(Output {
        object: Object { name: "program".into(), atoms: g.atoms, imports: g.imports.into_values().collect() },
        lines: g.lines,
        entry,
        debug_points: g.debug_points,
        frames,
        instrumented,
    })
}

struct Gen<'p> {
    p: &'p Program,
    os: Os,
    atoms: Vec<Atom>,
    imports: BTreeMap<String, Import>,
    strings: HashMap<Vec<u8>, String>,
    sets: HashMap<Vec<u8>, String>,
    layouts: Vec<Layout>,
    lines: Vec<LineEntry>,
    counter: u32,
    debug_points: Vec<Span>,
    /// `--count-steps`: instrumented routines count instead of calling the debugger.
    count_steps: bool,
}

impl<'p> Gen<'p> {
    fn types(&self) -> &'p TypeTable {
        &self.p.types
    }

    fn layout(&self, id: RoutineId) -> Layout {
        let t = self.types();
        let r = &self.p.routines[id.0 as usize];
        // [rbp-8] is the static link; on Windows [rbp-16] and [rbp-24] keep RSI and RDI.
        let mut off: u32 = if self.os == Os::Windows { 24 } else { 8 };
        let mut slots = Vec::new();
        let mut scratch = Vec::new();
        let place = |size: u32, align: u32, off: &mut u32| -> i32 {
            *off = align_up(*off + size.max(1), align.max(1));
            -(*off as i32)
        };
        for local in &r.locals {
            let ty = local.ty;
            let size = t.size(ty) as u32;
            let align = t.align(ty);
            let (slot, extra) = match local.kind {
                LocalKind::Param(i) => match passing(t, r.sig.params[i as usize].mode, ty) {
                    Passing::Value => (Slot::Value(place(size, align, &mut off)), None),
                    Passing::Ref | Passing::OpenArray => (Slot::Pointer(place(8, 8, &mut off)), None),
                    Passing::RefCopy => {
                        let s = place(size, align, &mut off);
                        let p = place(8, 8, &mut off);
                        (Slot::Value(s), Some(p))
                    }
                },
                LocalKind::Result if result_by_ref(t, ty) => (Slot::Pointer(place(8, 8, &mut off)), None),
                LocalKind::OpenHigh(_) => (Slot::Value(place(8, 8, &mut off)), None),
                _ => (Slot::Value(place(size, align, &mut off)), None),
            };
            slots.push(slot);
            scratch.push(extra);
        }
        Layout { slots, scratch, size: off }
    }

    fn global(&mut self, g: &Global) {
        let t = self.types();
        let size = t.size(g.ty).max(1);
        let align = t.align(g.ty).clamp(1, 16).next_power_of_two();
        let atom = match &g.init {
            None => Atom::bss(&g.symbol, size, align),
            Some(init) => {
                let section =
                    if g.readonly && init.pointers.is_empty() { SectionKind::ReadOnly } else { SectionKind::Data };
                let mut bytes = init.bytes.clone();
                bytes.resize(size as usize, 0);
                let mut atom = Atom::new(&g.symbol, section, align, bytes);
                for (offset, sym) in &init.pointers {
                    atom = atom.reloc(*offset as u32, RelocKind::Abs64, sym, 0);
                }
                atom
            }
        };
        self.atoms.push(atom);
    }

    /// A length-prefixed string constant in read-only data.
    fn string_literal(&mut self, bytes: &[u8]) -> String {
        let mut data = vec![bytes.len().min(255) as u8];
        data.extend_from_slice(&bytes[..bytes.len().min(255)]);
        if let Some(name) = self.strings.get(&data) {
            return name.clone();
        }
        self.counter += 1;
        let name = format!("$STR{}", self.counter);
        self.atoms.push(Atom::new(&name, SectionKind::ReadOnly, 1, data.clone()));
        self.strings.insert(data, name.clone());
        name
    }

    fn set_literal(&mut self, bytes: &[u8]) -> String {
        if let Some(name) = self.sets.get(bytes) {
            return name.clone();
        }
        self.counter += 1;
        let name = format!("$SET{}", self.counter);
        self.atoms.push(Atom::new(&name, SectionKind::ReadOnly, 8, bytes.to_vec()));
        self.sets.insert(bytes.to_vec(), name.clone());
        name
    }

    /// Symbol to call for an external function of `library` (the resolved
    /// library name, see [`import_library`]), registering the import.
    fn import(&mut self, symbol: &str, library: String) -> String {
        let name = match self.os {
            Os::Darwin => format!("_{symbol}"),
            Os::Linux | Os::Windows => symbol.to_string(),
        };
        self.imports.entry(name.clone()).or_insert_with(|| Import { name: name.clone(), library });
        name
    }

    /// `_main`: startup, debugger connection (debug builds) or step
    /// counters (step-counting builds), unit initializations, program, halt.
    fn main_stub(&mut self, debug: bool) -> String {
        let win64 = self.os == Os::Windows;
        let arg0 = if win64 { Rcx } else { Rdi };
        let arg1 = if win64 { Rdx } else { Rsi };
        let mut a = Assembler::new();
        a.push(Rbp);
        a.mov(W64, Rbp, Rsp);
        if win64 {
            a.sub(W64, Rsp, SHADOW);
        }
        // argc and argv are still in the first two argument registers.
        a.call(rtl::STARTUP);
        if debug && self.count_steps {
            let points = self.debug_points.len();
            self.atoms.push(Atom::bss(STEP_COUNTS, (points.max(1) * 8) as u64, 8));
            a.mov(W32, arg0, points as i32);
            a.lea(W64, arg1, Mem::rip(STEP_COUNTS, 0));
            a.call(rtl::STEPS_INIT);
        } else if debug {
            a.mov(W32, arg0, self.debug_points.len() as i32);
            a.call(rtl::DBG_INIT);
        }
        for id in &self.p.init_order {
            a.call(self.p.routines[id.0 as usize].symbol.as_str());
        }
        a.call(self.p.routines[self.p.main.0 as usize].symbol.as_str());
        a.xor(W32, arg0, arg0);
        a.call(rtl::HALT);
        a.ud2();
        let name = match self.os {
            Os::Darwin => "_main",
            Os::Linux | Os::Windows => "main",
        };
        let code = a.finish().expect("entry stub encodes");
        self.atoms.push(code.into_atom(name, 16).keep());
        name.to_string()
    }
}

/// Code generation state of one routine.
struct Rg<'g, 'p> {
    g: &'g mut Gen<'p>,
    p: &'p Program,
    id: RoutineId,
    a: Assembler,
    temp_top: u32,
    temp_max: u32,
    /// 8-byte values pushed on the machine stack and not yet popped.
    depth: u32,
    exit: Label,
    labels: HashMap<LabelId, Label>,
    /// (continue, break) targets of the enclosing loops.
    loops: Vec<(Label, Label)>,
    marks: Vec<(Label, Span)>,
    /// Debug build: emit a debugger hook before each source statement.
    instrument: bool,
}

impl<'g, 'p> Rg<'g, 'p> {
    fn new(g: &'g mut Gen<'p>, id: RoutineId) -> Self {
        let p = g.p;
        let mut a = Assembler::new();
        let exit = a.new_label();
        let size = g.layouts[id.0 as usize].size;
        Rg {
            g,
            p,
            id,
            a,
            temp_top: size,
            temp_max: size,
            depth: 0,
            exit,
            labels: HashMap::new(),
            loops: Vec::new(),
            marks: Vec::new(),
            instrument: false,
        }
    }

    fn types(&self) -> &'p TypeTable {
        &self.p.types
    }

    fn routine_ref(&self, id: RoutineId) -> &'p Routine {
        &self.p.routines[id.0 as usize]
    }

    fn me(&self) -> &'p Routine {
        self.routine_ref(self.id)
    }

    fn vclass(&self, ty: TypeId) -> VClass {
        match self.types().get(ty) {
            Type::Real(_) => VClass::Real,
            Type::Int(_)
            | Type::Bool
            | Type::Char
            | Type::Enum { .. }
            | Type::Subrange { .. }
            | Type::Pointer(_)
            | Type::Procedural(_)
            | Type::Nil => VClass::Int,
            _ => VClass::Mem,
        }
    }

    fn is_single(&self, ty: TypeId) -> bool {
        matches!(self.types().get(ty), Type::Real(RealKind::Single))
    }

    fn temp(&mut self, size: u32, align: u32) -> i32 {
        self.temp_top = align_up(self.temp_top + size.max(1), align.clamp(1, 16));
        self.temp_max = self.temp_max.max(self.temp_top);
        -(self.temp_top as i32)
    }

    // ---- small helpers ---------------------------------------------------

    fn push(&mut self, r: Reg) {
        self.a.push(r);
        self.depth += 1;
    }

    fn pop(&mut self, r: Reg) {
        self.a.pop(r);
        self.depth -= 1;
    }

    fn push_xmm0(&mut self) {
        self.a.sub(W64, Rsp, 8);
        self.a.movsd(Mem::base(Rsp, 0), Xmm::Xmm0);
        self.depth += 1;
    }

    fn pop_xmm(&mut self, x: Xmm) {
        self.a.movsd(x, Mem::base(Rsp, 0));
        self.a.add(W64, Rsp, 8);
        self.depth -= 1;
    }

    fn mov_imm(&mut self, r: Reg, v: i64) {
        if v == 0 {
            self.a.xor(W32, r, r);
        } else if (0..=u32::MAX as i64).contains(&v) {
            self.a.mov(W32, r, v);
        } else if fits_i32(v) {
            self.a.mov(W64, r, v as i32);
        } else {
            self.a.movabs(r, v);
        }
    }

    /// `cmp r, v` for any 64-bit constant (uses R11 for wide values).
    fn cmp_imm(&mut self, r: Reg, v: i64) {
        if fits_i32(v) {
            self.a.cmp(W64, r, v as i32);
        } else {
            self.a.movabs(R11, v);
            self.a.cmp(W64, r, R11);
        }
    }

    fn add_imm(&mut self, r: Reg, v: i64) {
        if v == 0 {
            return;
        }
        if fits_i32(v) {
            self.a.add(W64, r, v as i32);
        } else {
            self.a.movabs(R11, v);
            self.a.add(W64, r, R11);
        }
    }

    fn win64(&self) -> bool {
        self.g.os == Os::Windows
    }

    /// Integer argument register `i` (0-based) of the platform C ABI.
    fn arg(&self, i: usize) -> Reg {
        if self.win64() { WIN_INT_ARGS[i] } else { INT_ARGS[i] }
    }

    /// A call with the stack aligned to 16 bytes (and, on Windows, the
    /// callee's shadow space reserved).
    fn call_aligned(&mut self, target: impl Into<odin_asm::x86_64::Target>) {
        let pad = self.depth % 2 == 1;
        let below = if pad { 8 } else { 0 } + if self.win64() { SHADOW } else { 0 };
        if below > 0 {
            self.a.sub(W64, Rsp, below);
        }
        self.a.call(target);
        if below > 0 {
            self.a.add(W64, Rsp, below);
        }
    }

    /// Loads an ordinal or pointer of type `ty` from `m` into `r`,
    /// sign- or zero-extended to 64 bits.
    fn load_int(&mut self, r: Reg, m: Mem, ty: TypeId) {
        let t = self.types();
        if matches!(t.get(ty), Type::Pointer(_) | Type::Procedural(_) | Type::Nil) {
            self.a.mov(W64, r, m);
            return;
        }
        let k = t.int_kind(ty);
        match (k.size, k.signed) {
            (1, true) => self.a.movsx(W64, r, W8, m),
            (1, false) => self.a.movzx(W32, r, W8, m),
            (2, true) => self.a.movsx(W64, r, W16, m),
            (2, false) => self.a.movzx(W32, r, W16, m),
            (4, true) => self.a.movsxd(r, m),
            (4, false) => self.a.mov(W32, r, m),
            _ => self.a.mov(W64, r, m),
        }
    }

    /// Re-extends RAX after it was produced at 64 bits for a narrower type.
    fn extend_rax(&mut self, ty: TypeId) {
        let t = self.types();
        if !t.is_ordinal(ty) {
            return;
        }
        let k = t.int_kind(ty);
        match (k.size, k.signed) {
            (1, true) => self.a.movsx(W64, Rax, W8, Rax),
            (1, false) => self.a.movzx(W32, Rax, W8, Rax),
            (2, true) => self.a.movsx(W64, Rax, W16, Rax),
            (2, false) => self.a.movzx(W32, Rax, W16, Rax),
            (4, true) => self.a.movsxd(Rax, Rax),
            (4, false) => self.a.mov(W32, Rax, Rax),
            _ => {}
        }
    }

    fn store_int(&mut self, m: Mem, ty: TypeId, src: Reg) {
        let w = match self.types().size(ty) {
            1 => W8,
            2 => W16,
            4 => W32,
            _ => W64,
        };
        self.a.mov(w, m, src);
    }

    fn load_real(&mut self, m: Mem, ty: TypeId) {
        if self.is_single(ty) {
            self.a.movss(Xmm::Xmm0, m);
            self.a.cvtss2sd(Xmm::Xmm0, Xmm::Xmm0);
        } else {
            self.a.movsd(Xmm::Xmm0, m);
        }
    }

    fn store_real(&mut self, m: Mem, ty: TypeId) {
        if self.is_single(ty) {
            self.a.cvtsd2ss(Xmm::Xmm1, Xmm::Xmm0);
            self.a.movss(m, Xmm::Xmm1);
        } else {
            self.a.movsd(m, Xmm::Xmm0);
        }
    }

    /// Copies `size` bytes from [RSI] to [RDI].
    fn memcpy(&mut self, size: u64) {
        self.mov_imm(Rcx, size as i64);
        self.a.rep_movs(W8);
    }

    // ---- variables ---------------------------------------------------------

    /// Frame pointer of `routine` (the current one or a lexical ancestor).
    fn frame_base(&mut self, routine: RoutineId) -> Reg {
        if routine == self.id {
            return Rbp;
        }
        self.a.mov(W64, R11, Mem::base(Rbp, -8));
        let mut r = self.me().parent.expect("up-level access needs a parent");
        while r != routine {
            self.a.mov(W64, R11, Mem::base(R11, -8));
            r = self.routine_ref(r).parent.expect("ancestor chain");
        }
        R11
    }

    /// Memory operand of a variable's storage; may use R11.
    fn var_mem(&mut self, v: Var) -> Mem {
        match v {
            Var::Global(g) => Mem::rip(self.p.globals[g.0 as usize].symbol.as_str(), 0),
            Var::Local { routine, index } => {
                let base = self.frame_base(routine);
                match self.g.layouts[routine.0 as usize].slots[index as usize] {
                    Slot::Value(off) => Mem::base(base, off),
                    Slot::Pointer(off) => {
                        self.a.mov(W64, R11, Mem::base(base, off));
                        Mem::base(R11, 0)
                    }
                }
            }
        }
    }

    /// The open-array High local belonging to parameter local `param`.
    fn open_high(&mut self, base: &Expr) -> CResult<Mem> {
        let ExprKind::Var(Var::Local { routine, index }) = base.kind else {
            return err("internal: open array without parameter", base.span);
        };
        let r = self.routine_ref(routine);
        let Some(h) = r.locals.iter().position(|l| l.kind == LocalKind::OpenHigh(index)) else {
            return err("internal: open array without High", base.span);
        };
        Ok(self.var_mem(Var::Local { routine, index: h as u32 }))
    }

    // ---- runtime checks ----------------------------------------------------

    fn range_check(&mut self, lo: i64, hi: i64) {
        let ok = self.a.new_label();
        let bad = self.a.new_label();
        self.cmp_imm(Rax, lo);
        self.a.jcc(XCond::L, bad);
        self.cmp_imm(Rax, hi);
        self.a.jcc(XCond::Le, ok);
        self.a.bind(bad);
        self.call_aligned(rtl::RANGE_ERROR);
        self.a.bind(ok);
    }

    // ---- addresses ---------------------------------------------------------

    /// RAX = address of an lvalue or of a (possibly temporary) structured value.
    fn address(&mut self, e: &Expr) -> CResult<()> {
        let t = self.types();
        match &e.kind {
            ExprKind::Var(v) => {
                let m = self.var_mem(*v);
                self.a.lea(W64, Rax, m);
            }
            ExprKind::Field { base, offset } => {
                self.address(base)?;
                self.add_imm(Rax, *offset as i64);
            }
            ExprKind::Index { base, index, lo, hi, check } => {
                let esize = t.size(e.ty) as i64;
                self.address(base)?;
                self.push(Rax);
                self.int(index)?;
                if *check {
                    self.range_check(*lo, *hi);
                }
                self.add_imm(Rax, lo.wrapping_neg());
                self.pop(Rcx);
                self.scaled_add(esize);
            }
            ExprKind::OpenIndex { base, index, check } => {
                let esize = t.size(e.ty) as i64;
                self.address(base)?;
                self.push(Rax);
                self.int(index)?;
                if *check {
                    let m = self.open_high(base)?;
                    self.a.mov(W64, Rcx, m);
                    let ok = self.a.new_label();
                    let bad = self.a.new_label();
                    self.a.test(W64, Rax, Rax);
                    self.a.jcc(XCond::L, bad);
                    self.a.cmp(W64, Rax, Rcx);
                    self.a.jcc(XCond::Le, ok);
                    self.a.bind(bad);
                    self.call_aligned(rtl::RANGE_ERROR);
                    self.a.bind(ok);
                }
                self.pop(Rcx);
                self.scaled_add(esize);
            }
            ExprKind::Deref(p) => self.int(p)?,
            ExprKind::Str(bytes) => {
                let name = self.g.string_literal(bytes);
                self.a.lea(W64, Rax, Mem::rip(name, 0));
            }
            ExprKind::SetConst(bytes) => {
                let name = self.g.set_literal(bytes);
                self.a.lea(W64, Rax, Mem::rip(name, 0));
            }
            ExprKind::Call { .. } => self.call(e)?,
            ExprKind::Concat(items) => self.concat(items, e.span)?,
            ExprKind::Convert(Conv::CharToStr, x) => {
                self.int(x)?;
                let off = self.temp(2, 1);
                self.a.mov(W8, Mem::base(Rbp, off + 1), Rax);
                self.a.mov(W8, Mem::base(Rbp, off), 1);
                self.a.lea(W64, Rax, Mem::base(Rbp, off));
            }
            ExprKind::Convert(_, x) => self.address(x)?,
            ExprKind::SetBuild(items) => self.set_build(items, e.ty)?,
            ExprKind::Binary(op @ (BinOp::SetUnion | BinOp::SetDiff | BinOp::SetIntersect), l, r) => {
                self.set_binop(*op, l, r, e.ty)?
            }
            _ if self.vclass(e.ty) == VClass::Int => {
                // A scalar value needed in memory (rare): spill to a temp.
                let size = t.size(e.ty) as u32;
                self.int(e)?;
                let off = self.temp(size.max(8), 8);
                self.a.mov(W64, Mem::base(Rbp, off), Rax);
                self.a.lea(W64, Rax, Mem::base(Rbp, off));
            }
            _ if self.vclass(e.ty) == VClass::Real => {
                self.real(e)?;
                let off = self.temp(8, 8);
                self.store_real(Mem::base(Rbp, off), e.ty);
                self.a.lea(W64, Rax, Mem::base(Rbp, off));
            }
            _ => return err(format!("internal: no address for {:?}", e.kind), e.span),
        }
        Ok(())
    }

    /// RAX = RCX + RAX * size.
    fn scaled_add(&mut self, size: i64) {
        match size {
            1 | 2 | 4 | 8 => self.a.lea(W64, Rax, Mem::index(Rcx, Rax, size as u8, 0)),
            _ => {
                if fits_i32(size) {
                    self.a.imul3(W64, Rax, Rax, size);
                } else {
                    self.a.movabs(R11, size);
                    self.a.imul(W64, Rax, R11);
                }
                self.a.add(W64, Rax, Rcx);
            }
        }
    }

    // ---- integer expressions -------------------------------------------------

    /// RAX = value of an ordinal, pointer or procedural expression.
    fn int(&mut self, e: &Expr) -> CResult<()> {
        match &e.kind {
            ExprKind::Int(v) => self.mov_imm(Rax, *v),
            ExprKind::Nil => self.a.xor(W32, Rax, Rax),
            ExprKind::Var(v) => {
                let m = self.var_mem(*v);
                self.load_int(Rax, m, e.ty);
            }
            ExprKind::Field { .. } | ExprKind::Index { .. } | ExprKind::OpenIndex { .. } | ExprKind::Deref(_) => {
                self.address(e)?;
                self.load_int(Rax, Mem::base(Rax, 0), e.ty);
            }
            ExprKind::AddrOf(x) => self.address(x)?,
            ExprKind::RoutineAddr(r) => {
                let sym = self.routine_ref(*r).symbol.clone();
                self.a.lea(W64, Rax, Mem::rip(sym, 0));
            }
            ExprKind::Unary(op, x) => {
                self.int(x)?;
                match op {
                    UnOp::Neg => self.a.neg(W64, Rax),
                    UnOp::Not => self.a.not(W64, Rax),
                    UnOp::BoolNot => self.a.xor(W32, Rax, 1),
                    UnOp::RealNeg => return err("internal: real negation as integer", e.span),
                }
            }
            ExprKind::Binary(op, l, r) => self.int_binary(*op, l, r, e)?,
            ExprKind::Convert(conv, x) => match conv {
                Conv::Resize => {
                    self.int(x)?;
                    self.extend_rax(e.ty);
                }
                Conv::RangeCheck { lo, hi } => {
                    self.int(x)?;
                    self.range_check(*lo, *hi);
                }
                Conv::Bits => match self.vclass(x.ty) {
                    VClass::Int => self.int(x)?,
                    VClass::Real => {
                        self.real(x)?;
                        self.a.movq(Rax, Xmm::Xmm0);
                    }
                    VClass::Mem => self.address(x)?,
                },
                _ => return err(format!("internal: {conv:?} as integer"), e.span),
            },
            ExprKind::Call { .. } => self.call(e)?,
            ExprKind::Intrinsic(op, args) => self.int_intrinsic(*op, args, e)?,
            _ => return err(format!("internal: {:?} as integer", e.kind), e.span),
        }
        Ok(())
    }

    fn int_intrinsic(&mut self, op: Intrinsic, args: &[Expr], e: &Expr) -> CResult<()> {
        match op {
            Intrinsic::Length => {
                self.address(&args[0])?;
                self.a.movzx(W32, Rax, W8, Mem::base(Rax, 0));
            }
            Intrinsic::OpenHigh => {
                let m = self.open_high(&args[0])?;
                self.a.mov(W64, Rax, m);
            }
            Intrinsic::Odd => {
                self.int(&args[0])?;
                self.a.and(W32, Rax, 1);
            }
            Intrinsic::AbsInt => {
                self.int(&args[0])?;
                self.a.mov(W64, Rcx, Rax);
                self.a.neg(W64, Rcx);
                self.a.test(W64, Rax, Rax);
                self.a.cmov(XCond::S, W64, Rax, Rcx);
            }
            Intrinsic::SqrInt => {
                self.int(&args[0])?;
                self.a.imul(W64, Rax, Rax);
            }
            Intrinsic::Trunc => {
                self.real(&args[0])?;
                self.a.cvttsd2si(W64, Rax, Xmm::Xmm0);
            }
            Intrinsic::Round => {
                // The default MXCSR mode rounds half to even, like FPC.
                self.real(&args[0])?;
                self.a.cvtsd2si(W64, Rax, Xmm::Xmm0);
            }
            _ => return err(format!("internal: {op:?} as integer"), e.span),
        }
        Ok(())
    }

    fn int_binary(&mut self, op: BinOp, l: &Expr, r: &Expr, e: &Expr) -> CResult<()> {
        match op {
            BinOp::Add | BinOp::Sub | BinOp::And | BinOp::Or | BinOp::Xor | BinOp::AddChecked | BinOp::SubChecked => {
                self.int(l)?;
                let imm = r.int_value().filter(|v| fits_i32(*v));
                if imm.is_none() {
                    self.push(Rax);
                    self.int(r)?;
                    self.a.mov(W64, Rcx, Rax);
                    self.pop(Rax);
                }
                let src: odin_asm::x86_64::Operand = match imm {
                    Some(v) => (v as i32).into(),
                    None => Rcx.into(),
                };
                match op {
                    BinOp::Add | BinOp::AddChecked => self.a.add(W64, Rax, src),
                    BinOp::Sub | BinOp::SubChecked => self.a.sub(W64, Rax, src),
                    BinOp::And => self.a.and(W64, Rax, src),
                    BinOp::Or => self.a.or(W64, Rax, src),
                    _ => self.a.xor(W64, Rax, src),
                }
                if matches!(op, BinOp::AddChecked | BinOp::SubChecked) {
                    self.overflow_check();
                }
            }
            BinOp::Mul | BinOp::MulChecked => {
                self.int(l)?;
                match r.int_value().filter(|v| fits_i32(*v)) {
                    Some(v) => self.a.imul3(W64, Rax, Rax, v),
                    None => {
                        self.push(Rax);
                        self.int(r)?;
                        self.a.mov(W64, Rcx, Rax);
                        self.pop(Rax);
                        self.a.imul(W64, Rax, Rcx);
                    }
                }
                if op == BinOp::MulChecked {
                    self.overflow_check();
                }
            }
            BinOp::Div | BinOp::Mod => {
                self.int(l)?;
                self.push(Rax);
                self.int(r)?;
                self.a.mov(W64, Rcx, Rax);
                let ok = self.a.new_label();
                self.a.test(W64, Rcx, Rcx);
                self.a.jcc(XCond::Ne, ok);
                self.call_aligned(rtl::DIVZERO_ERROR);
                self.a.bind(ok);
                self.pop(Rax);
                self.a.cqo();
                self.a.idiv(W64, Rcx);
                if op == BinOp::Mod {
                    self.a.mov(W64, Rax, Rdx);
                }
            }
            BinOp::Shl | BinOp::Shr => {
                self.int(l)?;
                self.push(Rax);
                self.int(r)?;
                self.a.mov(W64, Rcx, Rax);
                self.pop(Rax);
                let w = if self.types().size(e.ty) >= 8 { W64 } else { W32 };
                if op == BinOp::Shl {
                    self.a.shl(w, Rax, Rcx);
                } else {
                    self.a.shr(w, Rax, Rcx);
                }
                if w == W32 {
                    self.a.movsxd(Rax, Rax);
                }
            }
            BinOp::Cmp(_) | BinOp::RealCmp(_) | BinOp::StrCmp(_) | BinOp::SetCmp(_) => {
                let cond = self.compare(op, l, r)?;
                self.a.setcc(cond, Rax);
                self.a.movzx(W32, Rax, W8, Rax);
            }
            BinOp::In => self.set_in(l, r)?,
            BinOp::BoolAnd | BinOp::BoolOr | BinOp::BoolXor => {
                self.int(l)?;
                self.push(Rax);
                self.int(r)?;
                self.pop(Rcx);
                match op {
                    BinOp::BoolAnd => self.a.and(W32, Rax, Rcx),
                    BinOp::BoolOr => self.a.or(W32, Rax, Rcx),
                    _ => self.a.xor(W32, Rax, Rcx),
                }
            }
            BinOp::AndThen | BinOp::OrElse => {
                let f = self.a.new_label();
                let end = self.a.new_label();
                self.branch(e, f, false)?;
                self.a.mov(W32, Rax, 1);
                self.a.jmp(end);
                self.a.bind(f);
                self.a.xor(W32, Rax, Rax);
                self.a.bind(end);
            }
            _ => return err(format!("internal: {op:?} as integer"), e.span),
        }
        Ok(())
    }

    fn overflow_check(&mut self) {
        let ok = self.a.new_label();
        self.a.jcc(XCond::No, ok);
        self.call_aligned(rtl::OVERFLOW_ERROR);
        self.a.bind(ok);
    }

    /// Evaluates a comparison and returns the x86 condition that is true
    /// when the comparison holds.
    fn compare(&mut self, op: BinOp, l: &Expr, r: &Expr) -> CResult<XCond> {
        Ok(match op {
            BinOp::Cmp(c) => {
                self.int(l)?;
                match r.int_value().filter(|v| fits_i32(*v)) {
                    Some(v) => self.a.cmp(W64, Rax, v as i32),
                    None => {
                        self.push(Rax);
                        self.int(r)?;
                        self.a.mov(W64, Rcx, Rax);
                        self.pop(Rax);
                        self.a.cmp(W64, Rax, Rcx);
                    }
                }
                signed_cond(c)
            }
            BinOp::RealCmp(c) => {
                self.real(l)?;
                self.push_xmm0();
                self.real(r)?;
                self.a.movapd(Xmm::Xmm1, Xmm::Xmm0);
                self.pop_xmm(Xmm::Xmm0);
                self.a.ucomisd(Xmm::Xmm0, Xmm::Xmm1);
                match c {
                    Cond::Eq => XCond::E,
                    Cond::Ne => XCond::Ne,
                    Cond::Lt => XCond::B,
                    Cond::Le => XCond::Be,
                    Cond::Gt => XCond::A,
                    Cond::Ge => XCond::Ae,
                }
            }
            BinOp::StrCmp(c) => {
                self.address(l)?;
                self.push(Rax);
                self.address(r)?;
                let (a0, a1) = (self.arg(0), self.arg(1));
                self.a.mov(W64, a1, Rax);
                self.pop(a0);
                self.call_aligned(rtl::STR_COMPARE);
                self.a.cmp(W32, Rax, 0);
                signed_cond(c)
            }
            BinOp::SetCmp(c) => {
                let size = self.set_size(l.ty);
                self.address(l)?;
                self.push(Rax);
                self.address(r)?;
                self.a.mov(W64, Rsi, Rax);
                self.pop(Rdx);
                self.a.xor(W32, R8, R8);
                for i in 0..size as i32 {
                    match c {
                        Cond::Le => {
                            self.a.mov(W8, Rax, Mem::base(Rsi, i));
                            self.a.not(W8, Rax);
                            self.a.and(W8, Rax, Mem::base(Rdx, i));
                        }
                        Cond::Ge => {
                            self.a.mov(W8, Rax, Mem::base(Rdx, i));
                            self.a.not(W8, Rax);
                            self.a.and(W8, Rax, Mem::base(Rsi, i));
                        }
                        _ => {
                            self.a.mov(W8, Rax, Mem::base(Rdx, i));
                            self.a.xor(W8, Rax, Mem::base(Rsi, i));
                        }
                    }
                    self.a.or(W8, R8, Rax);
                }
                self.a.test(W8, R8, R8);
                if c == Cond::Ne { XCond::Ne } else { XCond::E }
            }
            _ => unreachable!(),
        })
    }

    /// Jumps to `target` when the Boolean `e` equals `when`.
    fn branch(&mut self, e: &Expr, target: Label, when: bool) -> CResult<()> {
        match &e.kind {
            ExprKind::Int(v) => {
                if (*v != 0) == when {
                    self.a.jmp(target);
                }
            }
            ExprKind::Unary(UnOp::BoolNot, x) => self.branch(x, target, !when)?,
            ExprKind::Binary(BinOp::AndThen, l, r) => {
                if when {
                    let skip = self.a.new_label();
                    self.branch(l, skip, false)?;
                    self.branch(r, target, true)?;
                    self.a.bind(skip);
                } else {
                    self.branch(l, target, false)?;
                    self.branch(r, target, false)?;
                }
            }
            ExprKind::Binary(BinOp::OrElse, l, r) => {
                if when {
                    self.branch(l, target, true)?;
                    self.branch(r, target, true)?;
                } else {
                    let skip = self.a.new_label();
                    self.branch(l, skip, true)?;
                    self.branch(r, target, false)?;
                    self.a.bind(skip);
                }
            }
            ExprKind::Binary(op @ (BinOp::Cmp(_) | BinOp::RealCmp(_) | BinOp::StrCmp(_) | BinOp::SetCmp(_)), l, r) => {
                let cond = self.compare(*op, l, r)?;
                self.a.jcc(if when { cond } else { cond.negate() }, target);
            }
            _ => {
                self.int(e)?;
                self.a.test(W32, Rax, Rax);
                self.a.jcc(if when { XCond::Ne } else { XCond::E }, target);
            }
        }
        Ok(())
    }

    // ---- reals -----------------------------------------------------------

    /// XMM0 = value of a real expression, as a double.
    fn real(&mut self, e: &Expr) -> CResult<()> {
        match &e.kind {
            ExprKind::Real(v) => {
                self.a.movabs(Rax, v.to_bits() as i64);
                self.a.movq(Xmm::Xmm0, Rax);
            }
            ExprKind::Int(v) => {
                let bits = (*v as f64).to_bits() as i64;
                self.a.movabs(Rax, bits);
                self.a.movq(Xmm::Xmm0, Rax);
            }
            ExprKind::Var(v) => {
                let m = self.var_mem(*v);
                self.load_real(m, e.ty);
            }
            ExprKind::Field { .. } | ExprKind::Index { .. } | ExprKind::OpenIndex { .. } | ExprKind::Deref(_) => {
                self.address(e)?;
                self.load_real(Mem::base(Rax, 0), e.ty);
            }
            ExprKind::Unary(UnOp::RealNeg, x) => {
                self.real(x)?;
                self.a.movq(Rax, Xmm::Xmm0);
                self.a.btc(W64, Rax, 63);
                self.a.movq(Xmm::Xmm0, Rax);
            }
            ExprKind::Binary(op, l, r) => {
                self.real(l)?;
                self.push_xmm0();
                self.real(r)?;
                self.a.movapd(Xmm::Xmm1, Xmm::Xmm0);
                self.pop_xmm(Xmm::Xmm0);
                match op {
                    BinOp::RealAdd => self.a.addsd(Xmm::Xmm0, Xmm::Xmm1),
                    BinOp::RealSub => self.a.subsd(Xmm::Xmm0, Xmm::Xmm1),
                    BinOp::RealMul => self.a.mulsd(Xmm::Xmm0, Xmm::Xmm1),
                    BinOp::RealDiv => self.a.divsd(Xmm::Xmm0, Xmm::Xmm1),
                    _ => return err(format!("internal: {op:?} as real"), e.span),
                }
            }
            ExprKind::Convert(Conv::IntToReal, x) => {
                self.int(x)?;
                self.a.cvtsi2sd(Xmm::Xmm0, W64, Rax);
            }
            ExprKind::Convert(_, x) => self.real(x)?,
            ExprKind::Call { .. } => self.call(e)?,
            ExprKind::Intrinsic(op, args) => {
                self.real(&args[0])?;
                match op {
                    Intrinsic::AbsReal => {
                        self.a.movq(Rax, Xmm::Xmm0);
                        self.a.btr(W64, Rax, 63);
                        self.a.movq(Xmm::Xmm0, Rax);
                    }
                    Intrinsic::SqrReal => self.a.mulsd(Xmm::Xmm0, Xmm::Xmm0),
                    Intrinsic::Sqrt => self.a.sqrtsd(Xmm::Xmm0, Xmm::Xmm0),
                    Intrinsic::Int => self.a.roundsd(Xmm::Xmm0, Xmm::Xmm0, 3),
                    Intrinsic::Frac => {
                        self.a.movapd(Xmm::Xmm1, Xmm::Xmm0);
                        self.a.roundsd(Xmm::Xmm1, Xmm::Xmm1, 3);
                        self.a.subsd(Xmm::Xmm0, Xmm::Xmm1);
                    }
                    _ => return err(format!("internal: {op:?} as real"), e.span),
                }
            }
            _ => return err(format!("internal: {:?} as real", e.kind), e.span),
        }
        Ok(())
    }

    // ---- strings and sets ----------------------------------------------------

    fn concat(&mut self, items: &[Expr], span: Span) -> CResult<()> {
        let Some((first, rest)) = items.split_first() else {
            return err("internal: empty concatenation", span);
        };
        let off = self.temp(256, 1);
        let (a0, a1, a2) = (self.arg(0), self.arg(1), self.arg(2));
        self.address(first)?;
        self.a.mov(W64, a2, Rax);
        self.a.lea(W64, a0, Mem::base(Rbp, off));
        self.a.mov(W32, a1, 255);
        self.call_aligned(rtl::STR_ASSIGN);
        for item in rest {
            self.address(item)?;
            self.a.mov(W64, a1, Rax);
            self.a.lea(W64, a0, Mem::base(Rbp, off));
            self.call_aligned(rtl::STR_APPEND);
        }
        self.a.lea(W64, Rax, Mem::base(Rbp, off));
        Ok(())
    }

    fn set_layout(&self, ty: TypeId) -> (u32, u32) {
        match self.types().get(ty) {
            Type::Set { first_byte, size, .. } => (*first_byte, *size),
            _ => (0, 32),
        }
    }

    fn set_size(&self, ty: TypeId) -> u32 {
        self.set_layout(ty).1
    }

    /// Sets the bit for the value in RAX in the set at [RBP+off].
    fn set_include(&mut self, off: i32, first_byte: u32, size: u32) {
        let skip = self.a.new_label();
        self.add_imm(Rax, -(first_byte as i64 * 8));
        self.a.cmp(W64, Rax, (size * 8) as i32);
        self.a.jcc(XCond::Ae, skip);
        self.a.mov(W32, Rcx, Rax);
        self.a.and(W32, Rcx, 7);
        self.a.mov(W32, Rdx, 1);
        self.a.shl(W32, Rdx, Rcx);
        self.a.shr(W64, Rax, 3);
        self.a.or(W8, Mem::index(Rbp, Rax, 1, off), Rdx);
        self.a.bind(skip);
    }

    fn set_build(&mut self, items: &[(Expr, Option<Expr>)], ty: TypeId) -> CResult<()> {
        let (first_byte, size) = self.set_layout(ty);
        let off = self.temp(size, 8);
        let mut i = 0;
        while i < size {
            let (w, n) = match size - i {
                8.. => (W64, 8),
                4.. => (W32, 4),
                2.. => (W16, 2),
                _ => (W8, 1),
            };
            self.a.mov(w, Mem::base(Rbp, off + i as i32), 0);
            i += n;
        }
        for (lo, hi) in items {
            match hi {
                None => {
                    self.int(lo)?;
                    self.set_include(off, first_byte, size);
                }
                Some(hi) => {
                    let cur = self.temp(8, 8);
                    let top = self.temp(8, 8);
                    self.int(lo)?;
                    self.a.mov(W64, Mem::base(Rbp, cur), Rax);
                    self.int(hi)?;
                    self.a.mov(W64, Mem::base(Rbp, top), Rax);
                    let lp = self.a.new_label();
                    let done = self.a.new_label();
                    self.a.bind(lp);
                    self.a.mov(W64, Rax, Mem::base(Rbp, cur));
                    self.a.cmp(W64, Rax, Mem::base(Rbp, top));
                    self.a.jcc(XCond::G, done);
                    self.set_include(off, first_byte, size);
                    self.a.inc(W64, Mem::base(Rbp, cur));
                    self.a.jmp(lp);
                    self.a.bind(done);
                }
            }
        }
        self.a.lea(W64, Rax, Mem::base(Rbp, off));
        Ok(())
    }

    fn set_binop(&mut self, op: BinOp, l: &Expr, r: &Expr, ty: TypeId) -> CResult<()> {
        let size = self.set_size(ty);
        self.address(l)?;
        self.push(Rax);
        self.address(r)?;
        self.a.mov(W64, Rsi, Rax);
        self.pop(Rdx);
        let off = self.temp(size, 8);
        for i in 0..size as i32 {
            self.a.mov(W8, Rax, Mem::base(Rdx, i));
            self.a.mov(W8, Rcx, Mem::base(Rsi, i));
            match op {
                BinOp::SetUnion => self.a.or(W8, Rax, Rcx),
                BinOp::SetIntersect => self.a.and(W8, Rax, Rcx),
                _ => {
                    self.a.not(W8, Rcx);
                    self.a.and(W8, Rax, Rcx);
                }
            }
            self.a.mov(W8, Mem::base(Rbp, off + i), Rax);
        }
        self.a.lea(W64, Rax, Mem::base(Rbp, off));
        Ok(())
    }

    fn set_in(&mut self, l: &Expr, r: &Expr) -> CResult<()> {
        let (first_byte, size) = self.set_layout(r.ty);
        self.int(l)?;
        self.push(Rax);
        self.address(r)?;
        self.a.mov(W64, Rdx, Rax);
        self.pop(Rax);
        let no = self.a.new_label();
        let end = self.a.new_label();
        self.add_imm(Rax, -(first_byte as i64 * 8));
        self.a.cmp(W64, Rax, (size * 8) as i32);
        self.a.jcc(XCond::Ae, no);
        self.a.mov(W32, Rcx, Rax);
        self.a.and(W32, Rcx, 7);
        self.a.shr(W64, Rax, 3);
        self.a.movzx(W32, Rax, W8, Mem::index(Rdx, Rax, 1, 0));
        self.a.shr(W32, Rax, Rcx);
        self.a.and(W32, Rax, 1);
        self.a.jmp(end);
        self.a.bind(no);
        self.a.xor(W32, Rax, Rax);
        self.a.bind(end);
        Ok(())
    }

    // ---- calls -------------------------------------------------------------

    /// Calls `e` (an `ExprKind::Call`). The result ends up in RAX, XMM0
    /// (as double) or, for structured results, RAX = address of a temp.
    fn call(&mut self, e: &Expr) -> CResult<()> {
        let ExprKind::Call { callee, args } = &e.kind else { unreachable!() };
        let t = self.types();
        let sig: &Signature = match callee {
            Callee::Routine(id) | Callee::Virtual { routine: id, .. } => &self.routine_ref(*id).sig,
            Callee::Indirect(x) => match t.get(x.ty) {
                Type::Procedural(s) => s,
                _ => return err("internal: indirect call of a non-procedural value", e.span),
            },
        };
        let depth0 = self.depth;
        let mut classes = Vec::new();
        if let Callee::Indirect(x) = callee {
            self.int(x)?;
            self.push(Rax);
            classes.push(ArgClass::Callee);
        }
        let mut result_temp = None;
        if let Some(rt) = sig.result
            && result_by_ref(t, rt)
        {
            let off = self.temp(t.size(rt) as u32, t.align(rt));
            self.a.lea(W64, Rax, Mem::base(Rbp, off));
            self.push(Rax);
            classes.push(ArgClass::Int);
            result_temp = Some(off);
        }
        for (p, a) in sig.params.iter().zip(args) {
            match passing(t, p.mode, p.ty) {
                Passing::Value if self.vclass(p.ty) == VClass::Real => {
                    self.real(a)?;
                    if self.is_single(p.ty) {
                        self.a.cvtsd2ss(Xmm::Xmm0, Xmm::Xmm0);
                    }
                    self.push_xmm0();
                    classes.push(ArgClass::Float);
                }
                Passing::Value => {
                    self.int(a)?;
                    self.push(Rax);
                    classes.push(ArgClass::Int);
                }
                Passing::Ref | Passing::RefCopy => {
                    self.address(a)?;
                    self.push(Rax);
                    classes.push(ArgClass::Int);
                }
                Passing::OpenArray => {
                    self.address(a)?;
                    self.push(Rax);
                    classes.push(ArgClass::Int);
                    match t.get(a.ty) {
                        Type::Array { lo, hi, .. } => self.mov_imm(Rax, hi - lo),
                        Type::ShortString(max) => self.mov_imm(Rax, *max as i64),
                        _ => {
                            let m = self.open_high(a)?;
                            self.a.mov(W64, Rax, m);
                        }
                    }
                    self.push(Rax);
                    classes.push(ArgClass::Int);
                }
            }
        }
        // Distribute the pushed values over registers and stack slots.
        let n = classes.len() as i32;
        let slot = |i: usize, extra: i32| Mem::base(Rsp, 8 * (n - 1 - i as i32) + 8 * extra);
        let (mut ni, mut nf) = (0, 0);
        let win64 = self.win64();
        let mut position = 0;
        let mut int_regs = Vec::new();
        let mut float_regs = Vec::new();
        let mut stack = Vec::new();
        for (i, c) in classes.iter().enumerate() {
            match c {
                ArgClass::Callee => {}
                _ if win64 => {
                    match c {
                        _ if position >= 4 => stack.push(i),
                        ArgClass::Float => float_regs.push((FLOAT_ARGS[position], i)),
                        _ => int_regs.push((WIN_INT_ARGS[position], i)),
                    }
                    position += 1;
                }
                ArgClass::Int if ni < 6 => {
                    int_regs.push((INT_ARGS[ni], i));
                    ni += 1;
                }
                ArgClass::Float if nf < 8 => {
                    float_regs.push((FLOAT_ARGS[nf], i));
                    nf += 1;
                }
                _ => stack.push(i),
            }
        }
        let k = stack.len() as u32;
        let pad = (self.depth + k) % 2 == 1;
        let mut extra = 0;
        if pad {
            self.a.sub(W64, Rsp, 8);
            extra += 1;
        }
        for &i in stack.iter().rev() {
            self.a.push(slot(i, extra));
            extra += 1;
        }
        if win64 {
            self.a.sub(W64, Rsp, SHADOW);
            extra += SHADOW / 8;
        }
        for (r, i) in &int_regs {
            self.a.mov(W64, *r, slot(*i, extra));
        }
        for (x, i) in &float_regs {
            self.a.movsd(*x, slot(*i, extra));
        }
        match callee {
            Callee::Routine(id) => {
                let r = self.routine_ref(*id);
                if let Some(parent) = r.parent {
                    let base = self.frame_base(parent);
                    self.a.mov(W64, R10, base);
                }
                match &r.body {
                    RoutineBody::External { symbol, library } if library == RTL_ASM_LIBRARY => {
                        self.a.call(symbol.as_str());
                    }
                    RoutineBody::External { symbol, library } => {
                        let Some(lib) = import_library(self.g.os, library) else {
                            return err(format!("pustaka '{library}' tidak didukung; gunakan 'c'"), r.span);
                        };
                        let name = self.g.import(symbol, lib);
                        if !win64 {
                            // Variadic C functions read the vector-register count from AL.
                            self.a.mov(W32, Rax, nf as i32);
                        }
                        self.a.call(Mem::got(name));
                    }
                    RoutineBody::Code(_) => self.a.call(r.symbol.as_str()),
                }
            }
            Callee::Indirect(_) => {
                self.a.mov(W64, R11, slot(0, extra));
                self.a.call(R11);
            }
            Callee::Virtual { vmt_offset, slot: index, check, .. } => {
                // Self is the first argument after a hidden result pointer;
                // it is already in its register.
                let self_index = result_temp.is_some() as usize;
                let Some(&(this, _)) = int_regs.iter().find(|(_, i)| *i == self_index) else {
                    return err("internal: Self of a virtual call is not in a register", e.span);
                };
                self.a.mov(W64, R11, Mem::base(this, *vmt_offset as i32));
                if *check {
                    let fail = self.a.new_label();
                    let ok = self.a.new_label();
                    self.a.test(W64, R11, R11);
                    self.a.jcc(XCond::E, fail);
                    self.a.mov(W64, Rax, Mem::base(R11, 0));
                    self.a.add(W64, Rax, Mem::base(R11, 8));
                    self.a.jcc(XCond::E, ok);
                    self.a.bind(fail);
                    self.a.call(rtl::OBJECT_ERROR);
                    self.a.bind(ok);
                }
                let at = VMT_HEADER as i32 + 8 * *index as i32;
                self.a.mov(W64, R11, Mem::base(R11, at));
                self.a.call(R11);
            }
        }
        let total = n + k as i32 + pad as i32 + if win64 { SHADOW / 8 } else { 0 };
        if total > 0 {
            self.a.add(W64, Rsp, 8 * total);
        }
        self.depth = depth0;
        match (sig.result, result_temp) {
            (_, Some(off)) => self.a.lea(W64, Rax, Mem::base(Rbp, off)),
            (Some(rt), None) if self.vclass(rt) == VClass::Real => {
                if self.is_single(rt) {
                    self.a.cvtss2sd(Xmm::Xmm0, Xmm::Xmm0);
                }
            }
            (Some(rt), None) => self.extend_rax(rt),
            (None, None) => {}
        }
        Ok(())
    }

    // ---- statements --------------------------------------------------------

    fn stmts(&mut self, list: &[Stmt]) -> CResult<()> {
        for s in list {
            self.stmt(s)?;
        }
        Ok(())
    }

    fn stmt(&mut self, s: &Stmt) -> CResult<()> {
        self.temp_top = self.g.layouts[self.id.0 as usize].size;
        let mark = self.a.here();
        self.marks.push((mark, s.span));
        // A while loop checks in at its condition, once per iteration.
        let mut point = None;
        if self.instrument && !matches!(s.kind, StmtKind::Label(_) | StmtKind::While { .. }) {
            point = Some(self.debug_point(s.span));
        }
        match &s.kind {
            StmtKind::Assign { target, value } => self.assign(target, value)?,
            StmtKind::Call(e) => self.call(e)?,
            StmtKind::If { cond, then, otherwise } => {
                let other = self.a.new_label();
                let end = self.a.new_label();
                self.branch(cond, other, false)?;
                self.stmts(then)?;
                if otherwise.is_empty() {
                    self.a.bind(other);
                } else {
                    self.a.jmp(end);
                    self.a.bind(other);
                    self.stmts(otherwise)?;
                }
                self.a.bind(end);
            }
            StmtKind::While { cond, body } => {
                let top = self.a.new_label();
                let end = self.a.new_label();
                self.a.bind(top);
                if self.instrument {
                    self.debug_point(s.span);
                }
                self.temp_top = self.g.layouts[self.id.0 as usize].size;
                self.branch(cond, end, false)?;
                self.loops.push((top, end));
                self.stmts(body)?;
                self.loops.pop();
                self.a.jmp(top);
                self.a.bind(end);
            }
            StmtKind::Repeat { body, cond } => {
                let top = self.a.new_label();
                let test = self.a.new_label();
                let end = self.a.new_label();
                self.a.bind(top);
                self.loops.push((test, end));
                self.stmts(body)?;
                self.loops.pop();
                self.a.bind(test);
                if self.instrument {
                    self.debug_point(cond.span);
                }
                self.temp_top = self.g.layouts[self.id.0 as usize].size;
                self.branch(cond, top, false)?;
                self.a.bind(end);
            }
            StmtKind::For { var, from, to, limit, down, body } => {
                self.for_loop(var, from, to, *limit, *down, body, point)?
            }
            StmtKind::Case { selector, arms, otherwise } => {
                self.int(selector)?;
                let end = self.a.new_label();
                let other = self.a.new_label();
                let labels: Vec<Label> = arms.iter().map(|_| self.a.new_label()).collect();
                for (arm, label) in arms.iter().zip(&labels) {
                    for &(lo, hi) in &arm.ranges {
                        if lo == hi {
                            self.cmp_imm(Rax, lo);
                            self.a.jcc(XCond::E, *label);
                        } else {
                            let next = self.a.new_label();
                            self.cmp_imm(Rax, lo);
                            self.a.jcc(XCond::L, next);
                            self.cmp_imm(Rax, hi);
                            self.a.jcc(XCond::Le, *label);
                            self.a.bind(next);
                        }
                    }
                }
                self.a.jmp(other);
                for (arm, label) in arms.iter().zip(&labels) {
                    self.a.bind(*label);
                    self.stmts(&arm.body)?;
                    self.a.jmp(end);
                }
                self.a.bind(other);
                self.stmts(otherwise)?;
                self.a.bind(end);
            }
            StmtKind::Goto(l) => {
                let label = self.label(*l);
                self.a.jmp(label);
            }
            StmtKind::Label(l) => {
                let label = self.label(*l);
                self.a.bind(label);
            }
            StmtKind::Break | StmtKind::Continue => {
                let Some(&(cont, brk)) = self.loops.last() else {
                    return err("internal: Break di luar loop", s.span);
                };
                self.a.jmp(if matches!(s.kind, StmtKind::Break) { brk } else { cont });
            }
            StmtKind::Exit => {
                let exit = self.exit;
                self.a.jmp(exit);
            }
            StmtKind::Block(list) => {
                // The pieces of one lowered statement (Write, Inc, ...) share
                // its debugger stop.
                let instrument = std::mem::replace(&mut self.instrument, false);
                let result = self.stmts(list);
                self.instrument = instrument;
                result?
            }
        }
        Ok(())
    }

    // ---- debugger hooks (debug builds) -------------------------------------

    /// Records the statement as the current line and calls the hook when the
    /// debugger is attached and stepping, pausing or has a breakpoint here.
    /// Step-counting builds count the statement instead. Returns its id.
    fn debug_point(&mut self, span: Span) -> i32 {
        let id = self.g.debug_points.len() as i32;
        self.g.debug_points.push(span);
        if self.g.count_steps {
            self.count_step(id);
            return id;
        }
        let skip = self.a.new_label();
        let hook = self.a.new_label();
        self.a.mov(W32, Mem::rip(rtl::DBG_LINE, 0), id);
        self.a.mov(W64, Rax, Mem::rip(rtl::DBG_SHARED, 0));
        self.a.test(W64, Rax, Rax);
        self.a.jcc(XCond::E, skip);
        self.a.cmp(W16, Mem::base(Rax, 0), 0);
        self.a.jcc(XCond::Ne, hook);
        self.a.cmp(W8, Mem::base(Rax, 16 + id), 0);
        self.a.jcc(XCond::E, skip);
        self.a.bind(hook);
        let a0 = self.arg(0);
        self.a.mov(W32, a0, id);
        self.call_aligned(rtl::DBG_HOOK);
        self.a.bind(skip);
        id
    }

    /// One step of statement `id`: its counter and the step budget, which
    /// ends the program with runtime error 240 when it runs out. Touches no
    /// register: it runs between statements and before `for` loop bodies.
    fn count_step(&mut self, id: i32) {
        let skip = self.a.new_label();
        self.a.add(W64, Mem::rip(STEP_COUNTS, i64::from(id) * 8), 1);
        self.a.sub(W64, Mem::rip(rtl::STEP_BUDGET, 0), 1);
        self.a.jcc(XCond::Ns, skip);
        self.call_aligned(rtl::STEP_LIMIT);
        self.a.bind(skip);
    }

    /// Step-counting routine entry: one level deeper, its maximum, and the
    /// depth limit (runtime error 202).
    fn stat_enter(&mut self) {
        let below_max = self.a.new_label();
        let below_limit = self.a.new_label();
        self.a.mov(W32, Rax, Mem::rip(rtl::STAT_DEPTH, 0));
        self.a.add(W32, Rax, 1);
        self.a.mov(W32, Mem::rip(rtl::STAT_DEPTH, 0), Rax);
        self.a.cmp(W32, Rax, Mem::rip(rtl::STAT_MAXDEPTH, 0));
        self.a.jcc(XCond::Le, below_max);
        self.a.mov(W32, Mem::rip(rtl::STAT_MAXDEPTH, 0), Rax);
        self.a.bind(below_max);
        self.a.cmp(W32, Rax, Mem::rip(rtl::STAT_DEPTHLIMIT, 0));
        self.a.jcc(XCond::Le, below_limit);
        self.call_aligned(rtl::DEPTH_LIMIT);
        self.a.bind(below_limit);
    }

    fn stat_leave(&mut self) {
        self.a.sub(W32, Mem::rip(rtl::STAT_DEPTH, 0), 1);
    }

    /// Bytes copied by one instruction count one step per 64 in
    /// step-counting builds, so that copying a large array is not one step.
    fn weigh(&mut self, bytes: u64) {
        let steps = bytes / 64;
        if !(self.instrument && self.g.count_steps) || steps == 0 {
            return;
        }
        let skip = self.a.new_label();
        self.a.add(W64, Mem::rip(rtl::STEP_WEIGHT, 0), steps as i32);
        self.a.sub(W64, Mem::rip(rtl::STEP_BUDGET, 0), steps as i32);
        self.a.jcc(XCond::Ns, skip);
        self.call_aligned(rtl::STEP_LIMIT);
        self.a.bind(skip);
    }

    /// Step-counting builds start every variable and function result at
    /// zero: what an uninitialized local holds otherwise depends on the OS
    /// and on what ran before, and a judge must see the same run everywhere.
    /// Runs after the parameters are stored, so it may use RAX, RCX and RDI.
    fn zero_locals(&mut self) {
        let r = self.me();
        let t = self.types();
        let slots = self.g.layouts[self.id.0 as usize].slots.clone();
        for (i, local) in r.locals.iter().enumerate() {
            if !matches!(local.kind, LocalKind::Var | LocalKind::Result) {
                continue;
            }
            let Slot::Value(off) = slots[i] else { continue };
            let size = t.size(local.ty);
            if size > 64 {
                self.a.lea(W64, Rdi, Mem::base(Rbp, off));
                self.a.xor(W32, Rax, Rax);
                self.mov_imm(Rcx, size as i64);
                self.a.rep_stos(W8);
                continue;
            }
            let mut done = 0u64;
            for (w, n) in [(W64, 8u64), (W32, 4), (W16, 2), (W8, 1)] {
                while done + n <= size {
                    self.a.mov(w, Mem::base(Rbp, off + done as i32), 0);
                    done += n;
                }
            }
        }
    }

    /// Routine entry: one level deeper; the shadow stack records the
    /// caller's line, this routine and its frame.
    fn debug_enter(&mut self) {
        let skip = self.a.new_label();
        self.a.mov(W32, Rax, Mem::rip(rtl::DBG_DEPTH, 0));
        self.a.add(W32, Rax, 1);
        self.a.mov(W32, Mem::rip(rtl::DBG_DEPTH, 0), Rax);
        self.a.cmp(W32, Rax, rtl::DBG_STACK_SIZE);
        self.a.jcc(XCond::Ae, skip);
        self.a.shl(W64, Rax, 4);
        self.a.lea(W64, Rcx, Mem::rip(rtl::DBG_STACK, 0));
        self.a.add(W64, Rcx, Rax);
        self.a.mov(W32, Rdx, Mem::rip(rtl::DBG_LINE, 0));
        self.a.mov(W32, Mem::base(Rcx, 0), Rdx);
        self.a.mov(W32, Mem::base(Rcx, 4), self.id.0 as i32);
        self.a.mov(W64, Mem::base(Rcx, 8), Rbp);
        self.a.bind(skip);
    }

    /// Routine exit: back to the caller's depth and current line.
    fn debug_leave(&mut self) {
        let skip = self.a.new_label();
        self.a.mov(W32, Rax, Mem::rip(rtl::DBG_DEPTH, 0));
        self.a.cmp(W32, Rax, rtl::DBG_STACK_SIZE);
        self.a.jcc(XCond::Ae, skip);
        self.a.shl(W64, Rax, 4);
        self.a.lea(W64, Rcx, Mem::rip(rtl::DBG_STACK, 0));
        self.a.mov(W32, Rdx, Mem::index(Rcx, Rax, 1, 0));
        self.a.mov(W32, Mem::rip(rtl::DBG_LINE, 0), Rdx);
        self.a.bind(skip);
        self.a.sub(W32, Mem::rip(rtl::DBG_DEPTH, 0), 1);
    }

    fn label(&mut self, l: LabelId) -> Label {
        if let Some(x) = self.labels.get(&l) {
            return *x;
        }
        let x = self.a.new_label();
        self.labels.insert(l, x);
        x
    }

    fn assign(&mut self, target: &Expr, value: &Expr) -> CResult<()> {
        let t = self.types();
        match self.vclass(target.ty) {
            VClass::Int => {
                self.int(value)?;
                if let ExprKind::Var(v) = target.kind {
                    let m = self.var_mem(v);
                    self.store_int(m, target.ty, Rax);
                } else {
                    self.push(Rax);
                    self.address(target)?;
                    self.a.mov(W64, Rcx, Rax);
                    self.pop(Rax);
                    self.store_int(Mem::base(Rcx, 0), target.ty, Rax);
                }
            }
            VClass::Real => {
                self.real(value)?;
                if let ExprKind::Var(v) = target.kind {
                    let m = self.var_mem(v);
                    self.store_real(m, target.ty);
                } else {
                    self.push_xmm0();
                    self.address(target)?;
                    self.pop_xmm(Xmm::Xmm0);
                    self.store_real(Mem::base(Rax, 0), target.ty);
                }
            }
            VClass::Mem => {
                self.address(value)?;
                self.push(Rax);
                self.address(target)?;
                let (a0, a1, a2) = (self.arg(0), self.arg(1), self.arg(2));
                if let Type::ShortString(max) = t.get(target.ty) {
                    self.a.mov(W64, a0, Rax);
                    self.a.mov(W32, a1, *max as i32);
                    self.pop(a2);
                    self.call_aligned(rtl::STR_ASSIGN);
                } else if let Type::OpenString = t.get(target.ty) {
                    // Capacity of an open string parameter: its hidden High.
                    self.a.mov(W64, a0, Rax);
                    self.push(a0);
                    let m = self.open_high(target)?;
                    self.a.mov(W64, a1, m);
                    self.pop(a0);
                    self.pop(a2);
                    self.call_aligned(rtl::STR_ASSIGN);
                } else {
                    self.a.mov(W64, Rdi, Rax);
                    self.pop(Rsi);
                    self.memcpy(t.size(target.ty));
                    self.weigh(t.size(target.ty));
                }
            }
        }
        Ok(())
    }

    /// `point`: the loop's statement id in instrumented routines; step-counting
    /// builds count it once more per iteration, as a while loop counts its
    /// condition.
    #[allow(clippy::too_many_arguments)]
    fn for_loop(
        &mut self,
        var: &Expr,
        from: &Expr,
        to: &Expr,
        limit: Var,
        down: bool,
        body: &[Stmt],
        point: Option<i32>,
    ) -> CResult<()> {
        let ty = var.ty;
        let ExprKind::Var(v) = var.kind else {
            return err("internal: for variable is not a variable", var.span);
        };
        self.int(from)?;
        self.push(Rax);
        self.int(to)?;
        let m = self.var_mem(limit);
        self.store_int(m, ty, Rax);
        self.pop(Rax);
        let m = self.var_mem(v);
        self.store_int(m, ty, Rax);
        let top = self.a.new_label();
        let step = self.a.new_label();
        let end = self.a.new_label();
        // Skip the loop when the range is empty.
        let m = self.var_mem(v);
        self.load_int(Rax, m, ty);
        let m = self.var_mem(limit);
        self.load_int(Rcx, m, ty);
        self.a.cmp(W64, Rax, Rcx);
        self.a.jcc(if down { XCond::L } else { XCond::G }, end);
        self.a.bind(top);
        if let Some(id) = point
            && self.g.count_steps
        {
            self.count_step(id);
        }
        self.loops.push((step, end));
        self.stmts(body)?;
        self.loops.pop();
        self.a.bind(step);
        let m = self.var_mem(v);
        self.load_int(Rax, m, ty);
        let m = self.var_mem(limit);
        self.load_int(Rcx, m, ty);
        self.a.cmp(W64, Rax, Rcx);
        self.a.jcc(XCond::E, end);
        if down {
            self.a.sub(W64, Rax, 1);
        } else {
            self.a.add(W64, Rax, 1);
        }
        let m = self.var_mem(v);
        self.store_int(m, ty, Rax);
        self.a.jmp(top);
        self.a.bind(end);
        Ok(())
    }

    // ---- prologue and epilogue -----------------------------------------------

    fn routine(mut self, body: &[Stmt]) -> CResult<Atom> {
        let r = self.me();
        let t = self.types();
        let win64 = self.win64();
        self.a.push(Rbp);
        self.a.mov(W64, Rbp, Rsp);
        let after_frame;
        if win64 {
            // ODIN_CHKSTK touches every page of the frame (RAX bytes) and
            // keeps all registers but RAX and R11, arguments included.
            self.a.mov(W32, Rax, FRAME_PLACEHOLDER);
            after_frame = self.a.here();
            self.a.call(CHKSTK);
            self.a.sub(W64, Rsp, Rax);
            self.a.mov(W64, Mem::base(Rbp, WIN_SAVE_RSI), Rsi);
            self.a.mov(W64, Mem::base(Rbp, WIN_SAVE_RDI), Rdi);
        } else {
            self.a.sub(W64, Rsp, FRAME_PLACEHOLDER);
            after_frame = self.a.here();
        }
        if r.parent.is_some() {
            self.a.mov(W64, Mem::base(Rbp, -8), R10);
        }
        // Incoming arguments: registers first, then the caller's stack.
        let mut inc = Incoming { ni: 0, nf: 0, position: 0, win64, stack_off: if win64 { 16 + SHADOW } else { 16 } };
        let layout_slots: Vec<Slot> = self.g.layouts[self.id.0 as usize].slots.clone();
        let scratch: Vec<Option<i32>> = self.g.layouts[self.id.0 as usize].scratch.clone();
        if let Some(rt) = r.sig.result
            && result_by_ref(t, rt)
        {
            let idx = r.result_local().expect("function has a result local") as usize;
            let reg = inc.int(&mut self.a);
            if let Slot::Pointer(off) = layout_slots[idx] {
                self.a.mov(W64, Mem::base(Rbp, off), reg);
            }
        }
        let mut copies = Vec::new();
        for (i, p) in r.sig.params.iter().enumerate() {
            match passing(t, p.mode, p.ty) {
                Passing::Value if matches!(t.get(p.ty), Type::Real(_)) => {
                    let Slot::Value(off) = layout_slots[i] else { unreachable!() };
                    let single = matches!(t.get(p.ty), Type::Real(RealKind::Single));
                    if let Some(x) = inc.float() {
                        if single {
                            self.a.movss(Mem::base(Rbp, off), x);
                        } else {
                            self.a.movsd(Mem::base(Rbp, off), x);
                        }
                    } else {
                        self.a.mov(W64, Rax, Mem::base(Rbp, inc.stack_off));
                        inc.stack_off += 8;
                        self.a.mov(if single { W32 } else { W64 }, Mem::base(Rbp, off), Rax);
                    }
                }
                Passing::Value => {
                    let Slot::Value(off) = layout_slots[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.store_int(Mem::base(Rbp, off), p.ty, reg);
                }
                Passing::Ref => {
                    let Slot::Pointer(off) = layout_slots[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.mov(W64, Mem::base(Rbp, off), reg);
                }
                Passing::OpenArray => {
                    let Slot::Pointer(off) = layout_slots[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.mov(W64, Mem::base(Rbp, off), reg);
                    let h = r.locals.iter().position(|l| l.kind == LocalKind::OpenHigh(i as u32)).expect("High local");
                    let Slot::Value(hoff) = layout_slots[h] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.mov(W64, Mem::base(Rbp, hoff), reg);
                }
                Passing::RefCopy => {
                    let Some(sp) = scratch[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.mov(W64, Mem::base(Rbp, sp), reg);
                    copies.push(i);
                }
            }
        }
        // Value parameters of structured types are copied on entry.
        for i in copies {
            let p = &r.sig.params[i];
            let Slot::Value(off) = layout_slots[i] else { unreachable!() };
            let sp = scratch[i].unwrap();
            if let Type::ShortString(max) = t.get(p.ty) {
                let (a0, a1, a2) = (self.arg(0), self.arg(1), self.arg(2));
                self.a.lea(W64, a0, Mem::base(Rbp, off));
                self.a.mov(W32, a1, *max as i32);
                self.a.mov(W64, a2, Mem::base(Rbp, sp));
                self.call_aligned(rtl::STR_ASSIGN);
            } else {
                self.a.mov(W64, Rsi, Mem::base(Rbp, sp));
                self.a.lea(W64, Rdi, Mem::base(Rbp, off));
                self.memcpy(t.size(p.ty));
                self.weigh(t.size(p.ty));
            }
        }
        if self.instrument && self.g.count_steps {
            self.zero_locals();
            self.stat_enter();
        } else if self.instrument {
            self.debug_enter();
        }
        self.stmts(body)?;
        let exit = self.exit;
        self.a.bind(exit);
        if self.instrument && self.g.count_steps {
            self.stat_leave();
        } else if self.instrument {
            self.debug_leave();
        }
        if let Some(rt) = r.sig.result {
            let idx = r.result_local().expect("result local") as usize;
            match layout_slots[idx] {
                Slot::Pointer(off) => self.a.mov(W64, Rax, Mem::base(Rbp, off)),
                Slot::Value(off) => match self.vclass(rt) {
                    VClass::Real if self.is_single(rt) => self.a.movss(Xmm::Xmm0, Mem::base(Rbp, off)),
                    VClass::Real => self.a.movsd(Xmm::Xmm0, Mem::base(Rbp, off)),
                    _ => self.load_int(Rax, Mem::base(Rbp, off), rt),
                },
            }
        }
        if win64 {
            self.a.mov(W64, Rsi, Mem::base(Rbp, WIN_SAVE_RSI));
            self.a.mov(W64, Rdi, Mem::base(Rbp, WIN_SAVE_RDI));
        }
        self.a.leave();
        self.a.ret();
        if self.depth != 0 {
            return err("internal: stack depth mismatch", r.span);
        }
        let frame = align_up(self.temp_max, 16);
        let code = self.a.finish().map_err(|e| CodegenError { message: format!("internal: {e}"), span: r.span })?;
        let mut code = code;
        let patch = code.label_offset(after_frame).expect("frame label") as usize - 4;
        code.bytes[patch..patch + 4].copy_from_slice(&(frame as i32).to_le_bytes());
        for (label, span) in &self.marks {
            if let Some(offset) = code.label_offset(*label) {
                self.g.lines.push(LineEntry { symbol: r.symbol.clone(), offset, span: *span });
            }
        }
        Ok(code.into_atom(r.symbol.as_str(), 16))
    }
}

/// Cursor over a routine's incoming arguments.
struct Incoming {
    ni: usize,
    nf: usize,
    /// Win64: arguments take registers by position, whatever their class.
    position: usize,
    win64: bool,
    stack_off: i32,
}

impl Incoming {
    /// The register holding the next integer-class argument; arguments
    /// passed on the stack are loaded into RAX first.
    fn int(&mut self, a: &mut Assembler) -> Reg {
        let reg = if self.win64 {
            self.position += 1;
            WIN_INT_ARGS.get(self.position - 1).copied()
        } else {
            self.ni += 1;
            INT_ARGS.get(self.ni - 1).copied()
        };
        reg.unwrap_or_else(|| {
            a.mov(W64, Rax, Mem::base(Rbp, self.stack_off));
            self.stack_off += 8;
            Rax
        })
    }

    /// The register holding the next real argument, or `None` when it was
    /// passed on the stack (at `stack_off`, which the caller then advances).
    fn float(&mut self) -> Option<Xmm> {
        if self.win64 {
            self.position += 1;
            (self.position <= 4).then(|| FLOAT_ARGS[self.position - 1])
        } else {
            self.nf += 1;
            FLOAT_ARGS.get(self.nf - 1).copied()
        }
    }
}

fn signed_cond(c: Cond) -> XCond {
    match c {
        Cond::Eq => XCond::E,
        Cond::Ne => XCond::Ne,
        Cond::Lt => XCond::L,
        Cond::Le => XCond::Le,
        Cond::Gt => XCond::G,
        Cond::Ge => XCond::Ge,
    }
}
