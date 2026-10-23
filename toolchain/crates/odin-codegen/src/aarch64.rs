// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! AArch64 code generation (AAPCS64, Apple and Linux) by walking the HIR.
//!
//! The same design as [`crate::x86_64`]: every variable lives in memory at a
//! fixed offset from the frame pointer X29, expressions are evaluated into X0
//! (ordinals, pointers), D0 (reals, always as double) or, for strings,
//! records, arrays and sets, as an address in X0, and intermediate values go
//! on the machine stack, 16 bytes per value so SP stays aligned. Calls
//! follow the C ABI (X0-X7, D0-D7), plus a static link in X15 for nested
//! routines.
//!
//! Registers: X0 accumulator, X1-X4 operands of binary operations and
//! runtime calls, X9-X11 short-lived temporaries (X9 also walks the static
//! chain), X15 the static link. X16/X17 belong to the encoder's helpers and
//! X18 is never touched (Apple's platform register).
//!
//! AArch64 has no floating-point traps: after a real operation that can
//! fail, the code reads the cumulative FPSR flags and calls ODIN_FPERROR, so
//! a program stops with runtime error 207, 200 or 205 where x86-64 traps.
//! On Apple systems, the variadic arguments of the few C functions the RTL
//! calls that way (`open`, `fcntl`, `ioctl`) also go on the stack, where the
//! Apple ABI expects them.

use std::collections::{BTreeMap, HashMap};

use odin_asm::aarch64::regs::*;
use odin_asm::aarch64::{Assembler, Cond as ACond, Label, Mem, Reg, SysReg, VReg};
use odin_asm::{Atom, Import, Object, RelocKind, SectionKind};
use odin_base::Span;
use odin_ir::*;

use crate::{
    CResult, CodegenError, LineEntry, LocalSlot, Options, Os, Output, RTL_ASM_LIBRARY, STEP_COUNTS, import_library,
};

const INT_ARGS: [Reg; 8] = [X0, X1, X2, X3, X4, X5, X6, X7];
const FLOAT_ARGS: [VReg; 8] = [D0, D1, D2, D3, D4, D5, D6, D7];
/// Static link of nested routines.
const SLINK: Reg = X15;
/// FPSR cumulative flags that end the program: invalid operation, division
/// by zero, overflow (as the unmasked MXCSR exceptions on x86-64).
const FP_ERROR_FLAGS: i64 = 0b111;

/// Where a local lives, relative to X29.
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

fn align_up(v: u32, a: u32) -> u32 {
    v.div_ceil(a.max(1)) * a.max(1)
}

/// Number of fixed parameters of the variadic C functions the RTL calls;
/// on Apple systems the rest are passed on the stack.
fn variadic_fixed(symbol: &str) -> Option<usize> {
    match symbol {
        "open" | "fcntl" | "ioctl" => Some(2),
        "openat" => Some(3),
        _ => None,
    }
}

/// Generates the whole program as one object.
pub fn generate(p: &Program, options: &Options) -> CResult<Output> {
    if options.os == Os::Windows {
        return err("internal: AArch64 Windows is not a target", Span::default());
    }
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
        // [x29-8] is the static link.
        let mut off: u32 = 8;
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

    /// `_main` / `main`: startup, debugger connection (debug builds), unit
    /// initializations, program, halt.
    fn main_stub(&mut self, debug: bool) -> String {
        let mut a = Assembler::new();
        a.stp(X29, X30, Mem::pre(SP, -16));
        a.mov(X29, SP);
        // The FPSR flags are sticky: start clean, so a flag means this program's error.
        a.msr(SysReg::Fpsr, XZR);
        // argc and argv are still in x0/x1.
        a.bl(rtl::STARTUP);
        if debug && self.count_steps {
            let points = self.debug_points.len();
            self.atoms.push(Atom::bss(STEP_COUNTS, (points.max(1) * 8) as u64, 8));
            a.mov_imm(X0, points as i64);
            a.load_address(X1, STEP_COUNTS, 0);
            a.bl(rtl::STEPS_INIT);
        } else if debug {
            a.mov_imm(X0, self.debug_points.len() as i64);
            a.bl(rtl::DBG_INIT);
        }
        for id in &self.p.init_order {
            a.bl(self.p.routines[id.0 as usize].symbol.as_str());
        }
        a.bl(self.p.routines[self.p.main.0 as usize].symbol.as_str());
        a.mov_imm(X0, 0);
        a.bl(rtl::HALT);
        a.udf(0);
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
    /// 16-byte values pushed on the machine stack and not yet popped.
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
            | Type::Nil
            | Type::Class(_)
            | Type::ClassRef(_) => VClass::Int,
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
        self.a.str(r, Mem::pre(SP, -16));
        self.depth += 1;
    }

    fn pop(&mut self, r: Reg) {
        self.a.ldr(r, Mem::post(SP, 16));
        self.depth -= 1;
    }

    fn push_d0(&mut self) {
        self.a.str(D0, Mem::pre(SP, -16));
        self.depth += 1;
    }

    fn pop_d(&mut self, d: VReg) {
        self.a.ldr(d, Mem::post(SP, 16));
        self.depth -= 1;
    }

    /// X0 += v (any 64-bit constant).
    fn add_imm(&mut self, r: Reg, v: i64) {
        if v == 0 {
            return;
        }
        if v == i64::MIN {
            self.a.mov_imm(X10, v);
            self.a.add(r, r, X10);
        } else {
            self.a.add_const(r, r, v);
        }
    }

    /// A call of a runtime routine (SP is always 16-byte aligned).
    fn call_rtl(&mut self, sym: &str) {
        self.a.bl(sym);
    }

    /// Ends the program with runtime error 207/200/205 when the last real
    /// operations raised invalid, division by zero or overflow.
    fn fp_check(&mut self) {
        let ok = self.a.new_label();
        self.a.mrs(X9, SysReg::Fpsr);
        self.a.tst(X9, FP_ERROR_FLAGS);
        self.a.b_cond(ACond::Eq, ok);
        self.a.mov(X0, X9);
        self.call_rtl(rtl::FP_ERROR);
        self.a.bind(ok);
    }

    /// Loads an ordinal or pointer of type `ty` from `m` into `r` (an X
    /// register), sign- or zero-extended to 64 bits.
    fn load_int(&mut self, r: Reg, m: Mem, ty: TypeId) {
        let t = self.types();
        if matches!(t.get(ty), Type::Pointer(_) | Type::Procedural(_) | Type::Nil | Type::Class(_) | Type::ClassRef(_))
        {
            self.a.ldr(r, m);
            return;
        }
        let k = t.int_kind(ty);
        match (k.size, k.signed) {
            (1, true) => self.a.ldrsb(r, m),
            (1, false) => self.a.ldrb(r.to_w(), m),
            (2, true) => self.a.ldrsh(r, m),
            (2, false) => self.a.ldrh(r.to_w(), m),
            (4, true) => self.a.ldrsw(r, m),
            (4, false) => self.a.ldr(r.to_w(), m),
            _ => self.a.ldr(r, m),
        }
    }

    /// Re-extends X0 after it was produced at 64 bits for a narrower type.
    fn extend_x0(&mut self, ty: TypeId) {
        let t = self.types();
        if !t.is_ordinal(ty) {
            return;
        }
        let k = t.int_kind(ty);
        match (k.size, k.signed) {
            (1, true) => self.a.sxtb(X0, W0),
            (1, false) => self.a.uxtb(W0, W0),
            (2, true) => self.a.sxth(X0, W0),
            (2, false) => self.a.uxth(W0, W0),
            (4, true) => self.a.sxtw(X0, W0),
            (4, false) => self.a.ubfx(X0, X0, 0, 32),
            _ => {}
        }
    }

    fn store_int(&mut self, m: Mem, ty: TypeId, src: Reg) {
        match self.types().size(ty) {
            1 => self.a.strb(src.to_w(), m),
            2 => self.a.strh(src.to_w(), m),
            4 => self.a.str(src.to_w(), m),
            _ => self.a.str(src, m),
        }
    }

    fn load_real(&mut self, m: Mem, ty: TypeId) {
        if self.is_single(ty) {
            self.a.ldr(S0, m);
            self.a.fcvt(D0, S0);
        } else {
            self.a.ldr(D0, m);
        }
    }

    fn store_real(&mut self, m: Mem, ty: TypeId) {
        if self.is_single(ty) {
            self.a.fcvt(S1, D0);
            self.fp_check();
            self.a.str(S1, m);
        } else {
            self.a.str(D0, m);
        }
    }

    /// Copies `size` bytes from [X3] to [X4]; uses X2 and X9.
    fn memcpy(&mut self, size: u64) {
        let mut done = 0u64;
        if size > 128 {
            let lp = self.a.new_label();
            self.a.mov_imm(X2, (size / 8) as i64);
            self.a.bind(lp);
            self.a.ldr(X9, Mem::post(X3, 8));
            self.a.str(X9, Mem::post(X4, 8));
            self.a.subs(X2, X2, 1);
            self.a.b_cond(ACond::Ne, lp);
            let rest = size % 8;
            for i in 0..rest as i64 {
                self.a.ldrb(W9, Mem::base(X3, i));
                self.a.strb(W9, Mem::base(X4, i));
            }
            return;
        }
        while size - done >= 8 {
            self.a.ldr(X9, Mem::base(X3, done as i64));
            self.a.str(X9, Mem::base(X4, done as i64));
            done += 8;
        }
        if size - done >= 4 {
            self.a.ldr(W9, Mem::base(X3, done as i64));
            self.a.str(W9, Mem::base(X4, done as i64));
            done += 4;
        }
        if size - done >= 2 {
            self.a.ldrh(W9, Mem::base(X3, done as i64));
            self.a.strh(W9, Mem::base(X4, done as i64));
            done += 2;
        }
        if size - done >= 1 {
            self.a.ldrb(W9, Mem::base(X3, done as i64));
            self.a.strb(W9, Mem::base(X4, done as i64));
        }
    }

    // ---- variables ---------------------------------------------------------

    /// Frame pointer of `routine` (the current one or a lexical ancestor).
    fn frame_base(&mut self, routine: RoutineId) -> Reg {
        if routine == self.id {
            return X29;
        }
        self.a.ldr(X9, Mem::base(X29, -8));
        let mut r = self.me().parent.expect("up-level access needs a parent");
        while r != routine {
            self.a.ldr(X9, Mem::base(X9, -8));
            r = self.routine_ref(r).parent.expect("ancestor chain");
        }
        X9
    }

    /// Memory operand of a variable's storage; may use X9.
    fn var_mem(&mut self, v: Var) -> Mem {
        match v {
            Var::Global(g) => Mem::sym(self.p.globals[g.0 as usize].symbol.as_str(), 0),
            Var::Local { routine, index } => {
                let base = self.frame_base(routine);
                match self.g.layouts[routine.0 as usize].slots[index as usize] {
                    Slot::Value(off) => Mem::base(base, off as i64),
                    Slot::Pointer(off) => {
                        self.a.ldr(X9, Mem::base(base, off as i64));
                        Mem::base(X9, 0)
                    }
                }
            }
        }
    }

    /// `rd` = address of a variable's storage.
    fn var_address(&mut self, rd: Reg, v: Var) {
        match v {
            Var::Global(g) => {
                let sym = self.p.globals[g.0 as usize].symbol.clone();
                self.a.load_address(rd, &sym, 0);
            }
            Var::Local { routine, index } => {
                let base = self.frame_base(routine);
                match self.g.layouts[routine.0 as usize].slots[index as usize] {
                    Slot::Value(off) => self.a.add_const(rd, base, off as i64),
                    Slot::Pointer(off) => self.a.ldr(rd, Mem::base(base, off as i64)),
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
        self.a.cmp_const(X0, lo);
        self.a.b_cond(ACond::Lt, bad);
        self.a.cmp_const(X0, hi);
        self.a.b_cond(ACond::Le, ok);
        self.a.bind(bad);
        self.call_rtl(rtl::RANGE_ERROR);
        self.a.bind(ok);
    }

    // ---- addresses ---------------------------------------------------------

    /// X0 = address of an lvalue or of a (possibly temporary) structured value.
    fn address(&mut self, e: &Expr) -> CResult<()> {
        let t = self.types();
        match &e.kind {
            ExprKind::Var(v) => self.var_address(X0, *v),
            ExprKind::Field { base, offset } => {
                self.address(base)?;
                self.add_imm(X0, *offset as i64);
            }
            ExprKind::Index { base, index, lo, hi, check } => {
                let esize = t.size(e.ty) as i64;
                self.address(base)?;
                self.push(X0);
                self.int(index)?;
                if *check {
                    self.range_check(*lo, *hi);
                }
                self.add_imm(X0, lo.wrapping_neg());
                self.pop(X1);
                self.scaled_add(esize);
            }
            ExprKind::OpenIndex { base, index, check } => {
                let esize = t.size(e.ty) as i64;
                self.address(base)?;
                self.push(X0);
                self.int(index)?;
                if *check {
                    let m = self.open_high(base)?;
                    self.a.ldr(X2, m);
                    let ok = self.a.new_label();
                    let bad = self.a.new_label();
                    self.a.cmp(X0, 0);
                    self.a.b_cond(ACond::Lt, bad);
                    self.a.cmp(X0, X2);
                    self.a.b_cond(ACond::Le, ok);
                    self.a.bind(bad);
                    self.call_rtl(rtl::RANGE_ERROR);
                    self.a.bind(ok);
                }
                self.pop(X1);
                self.scaled_add(esize);
            }
            ExprKind::Deref(p) => self.int(p)?,
            ExprKind::Str(bytes) => {
                let name = self.g.string_literal(bytes);
                self.a.load_address(X0, &name, 0);
            }
            ExprKind::SetConst(bytes) => {
                let name = self.g.set_literal(bytes);
                self.a.load_address(X0, &name, 0);
            }
            ExprKind::Call { .. } => self.call(e)?,
            ExprKind::Concat(items) => self.concat(items, e.span)?,
            ExprKind::Convert(Conv::CharToStr, x) => {
                self.int(x)?;
                let off = self.temp(2, 1) as i64;
                self.a.strb(W0, Mem::base(X29, off + 1));
                self.a.mov_imm(X9, 1);
                self.a.strb(W9, Mem::base(X29, off));
                self.a.add_const(X0, X29, off);
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
                let off = self.temp(size.max(8), 8) as i64;
                self.a.str(X0, Mem::base(X29, off));
                self.a.add_const(X0, X29, off);
            }
            _ if self.vclass(e.ty) == VClass::Real => {
                self.real(e)?;
                let off = self.temp(8, 8) as i64;
                self.store_real(Mem::base(X29, off), e.ty);
                self.a.add_const(X0, X29, off);
            }
            _ => return err(format!("internal: no address for {:?}", e.kind), e.span),
        }
        Ok(())
    }

    /// X0 = X1 + X0 * size.
    fn scaled_add(&mut self, size: i64) {
        if size > 0 && (size as u64).is_power_of_two() {
            self.a.add(X0, X1, X0.lsl(size.trailing_zeros() as u8));
        } else {
            self.a.mov_imm(X9, size);
            self.a.madd(X0, X0, X9, X1);
        }
    }

    // ---- integer expressions -------------------------------------------------

    /// X0 = value of an ordinal, pointer or procedural expression.
    fn int(&mut self, e: &Expr) -> CResult<()> {
        match &e.kind {
            ExprKind::Int(v) => self.a.mov_imm(X0, *v),
            ExprKind::Nil => self.a.mov_imm(X0, 0),
            ExprKind::Var(v) => {
                let m = self.var_mem(*v);
                self.load_int(X0, m, e.ty);
            }
            ExprKind::Field { .. } | ExprKind::Index { .. } | ExprKind::OpenIndex { .. } | ExprKind::Deref(_) => {
                self.address(e)?;
                self.load_int(X0, Mem::base(X0, 0), e.ty);
            }
            ExprKind::AddrOf(x) => self.address(x)?,
            ExprKind::RoutineAddr(r) => {
                let sym = self.routine_ref(*r).symbol.clone();
                self.a.load_address(X0, &sym, 0);
            }
            ExprKind::Unary(op, x) => {
                self.int(x)?;
                match op {
                    UnOp::Neg => self.a.neg(X0, X0),
                    UnOp::Not => self.a.mvn(X0, X0),
                    UnOp::BoolNot => self.a.eor(W0, W0, 1),
                    UnOp::RealNeg => return err("internal: real negation as integer", e.span),
                }
            }
            ExprKind::Binary(op, l, r) => self.int_binary(*op, l, r, e)?,
            ExprKind::Convert(conv, x) => match conv {
                Conv::Resize => {
                    self.int(x)?;
                    self.extend_x0(e.ty);
                }
                Conv::RangeCheck { lo, hi } => {
                    self.int(x)?;
                    self.range_check(*lo, *hi);
                }
                Conv::Bits => match self.vclass(x.ty) {
                    VClass::Int => self.int(x)?,
                    VClass::Real => {
                        self.real(x)?;
                        self.a.fmov(X0, D0);
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
                self.a.ldrb(W0, Mem::base(X0, 0));
            }
            Intrinsic::OpenHigh => {
                let m = self.open_high(&args[0])?;
                self.a.ldr(X0, m);
            }
            Intrinsic::Odd => {
                self.int(&args[0])?;
                self.a.and(X0, X0, 1);
            }
            Intrinsic::AbsInt => {
                self.int(&args[0])?;
                self.a.cmp(X0, 0);
                self.a.cneg(X0, X0, ACond::Lt);
            }
            Intrinsic::SqrInt => {
                self.int(&args[0])?;
                self.a.mul(X0, X0, X0);
            }
            Intrinsic::Trunc => {
                self.real(&args[0])?;
                self.a.fcvtzs(X0, D0);
                self.fp_check();
            }
            Intrinsic::Round => {
                // Half to even, like FPC and the default MXCSR mode on x86-64.
                self.real(&args[0])?;
                self.a.fcvtns(X0, D0);
                self.fp_check();
            }
            _ => return err(format!("internal: {op:?} as integer"), e.span),
        }
        Ok(())
    }

    /// X0 = left operand, X1 = right operand.
    fn operands(&mut self, l: &Expr, r: &Expr) -> CResult<()> {
        self.int(l)?;
        match r.int_value() {
            Some(v) => self.a.mov_imm(X1, v),
            None => {
                self.push(X0);
                self.int(r)?;
                self.a.mov(X1, X0);
                self.pop(X0);
            }
        }
        Ok(())
    }

    fn int_binary(&mut self, op: BinOp, l: &Expr, r: &Expr, e: &Expr) -> CResult<()> {
        match op {
            BinOp::Add | BinOp::Sub | BinOp::And | BinOp::Or | BinOp::Xor => {
                self.int(l)?;
                if let Some(v) = r.int_value() {
                    match op {
                        BinOp::Add => self.add_imm(X0, v),
                        BinOp::Sub => {
                            if v == i64::MIN {
                                self.a.mov_imm(X1, v);
                                self.a.sub(X0, X0, X1);
                            } else {
                                self.add_imm(X0, -v);
                            }
                        }
                        BinOp::And => self.a.logical_const(odin_asm::aarch64::LogicOp::And, X0, X0, v),
                        BinOp::Or => self.a.logical_const(odin_asm::aarch64::LogicOp::Orr, X0, X0, v),
                        _ => self.a.logical_const(odin_asm::aarch64::LogicOp::Eor, X0, X0, v),
                    }
                    return Ok(());
                }
                self.push(X0);
                self.int(r)?;
                self.a.mov(X1, X0);
                self.pop(X0);
                match op {
                    BinOp::Add => self.a.add(X0, X0, X1),
                    BinOp::Sub => self.a.sub(X0, X0, X1),
                    BinOp::And => self.a.and(X0, X0, X1),
                    BinOp::Or => self.a.orr(X0, X0, X1),
                    _ => self.a.eor(X0, X0, X1),
                }
            }
            BinOp::AddChecked | BinOp::SubChecked => {
                self.operands(l, r)?;
                if op == BinOp::AddChecked {
                    self.a.adds(X0, X0, X1);
                } else {
                    self.a.subs(X0, X0, X1);
                }
                self.overflow_check(ACond::Vc);
            }
            BinOp::Mul | BinOp::MulChecked => {
                self.operands(l, r)?;
                if op == BinOp::MulChecked {
                    // Overflow when the high half is not the sign of the low half.
                    self.a.smulh(X9, X0, X1);
                    self.a.mul(X0, X0, X1);
                    self.a.cmp(X9, X0.asr(63));
                    self.overflow_check(ACond::Eq);
                } else {
                    self.a.mul(X0, X0, X1);
                }
            }
            BinOp::Div | BinOp::Mod => {
                self.int(l)?;
                self.push(X0);
                self.int(r)?;
                self.a.mov(X1, X0);
                let ok = self.a.new_label();
                self.a.cbnz(X1, ok);
                self.call_rtl(rtl::DIVZERO_ERROR);
                self.a.bind(ok);
                self.pop(X0);
                self.a.sdiv(X2, X0, X1);
                if op == BinOp::Mod {
                    self.a.msub(X0, X2, X1, X0);
                } else {
                    self.a.mov(X0, X2);
                }
            }
            BinOp::Shl | BinOp::Shr => {
                self.operands(l, r)?;
                if self.types().size(e.ty) >= 8 {
                    if op == BinOp::Shl {
                        self.a.lsl(X0, X0, X1);
                    } else {
                        self.a.lsr(X0, X0, X1);
                    }
                } else {
                    if op == BinOp::Shl {
                        self.a.lsl(W0, W0, W1);
                    } else {
                        self.a.lsr(W0, W0, W1);
                    }
                    self.a.sxtw(X0, W0);
                }
            }
            BinOp::Cmp(_) | BinOp::RealCmp(_) | BinOp::StrCmp(_) | BinOp::SetCmp(_) => {
                let cond = self.compare(op, l, r)?;
                self.a.cset(X0, cond);
            }
            BinOp::In => self.set_in(l, r)?,
            BinOp::BoolAnd | BinOp::BoolOr | BinOp::BoolXor => {
                self.int(l)?;
                self.push(X0);
                self.int(r)?;
                self.pop(X1);
                match op {
                    BinOp::BoolAnd => self.a.and(W0, W0, W1),
                    BinOp::BoolOr => self.a.orr(W0, W0, W1),
                    _ => self.a.eor(W0, W0, W1),
                }
            }
            BinOp::AndThen | BinOp::OrElse => {
                let f = self.a.new_label();
                let end = self.a.new_label();
                self.branch(e, f, false)?;
                self.a.mov_imm(X0, 1);
                self.a.b(end);
                self.a.bind(f);
                self.a.mov_imm(X0, 0);
                self.a.bind(end);
            }
            _ => return err(format!("internal: {op:?} as integer"), e.span),
        }
        Ok(())
    }

    /// Runtime error 215 unless `ok` holds.
    fn overflow_check(&mut self, ok: ACond) {
        let fine = self.a.new_label();
        self.a.b_cond(ok, fine);
        self.call_rtl(rtl::OVERFLOW_ERROR);
        self.a.bind(fine);
    }

    /// Evaluates a comparison and returns the condition that is true when
    /// the comparison holds.
    fn compare(&mut self, op: BinOp, l: &Expr, r: &Expr) -> CResult<ACond> {
        Ok(match op {
            BinOp::Cmp(c) => {
                self.int(l)?;
                match r.int_value() {
                    Some(v) => self.a.cmp_const(X0, v),
                    None => {
                        self.push(X0);
                        self.int(r)?;
                        self.a.mov(X1, X0);
                        self.pop(X0);
                        self.a.cmp(X0, X1);
                    }
                }
                signed_cond(c)
            }
            BinOp::RealCmp(c) => {
                self.real(l)?;
                self.push_d0();
                self.real(r)?;
                self.a.fmov(D1, D0);
                self.pop_d(D0);
                self.a.fcmp(D0, D1);
                // False for unordered operands, like the x86 conditions after ucomisd.
                match c {
                    Cond::Eq => ACond::Eq,
                    Cond::Ne => ACond::Ne,
                    Cond::Lt => ACond::Mi,
                    Cond::Le => ACond::Ls,
                    Cond::Gt => ACond::Gt,
                    Cond::Ge => ACond::Ge,
                }
            }
            BinOp::StrCmp(c) => {
                self.address(l)?;
                self.push(X0);
                self.address(r)?;
                self.a.mov(X1, X0);
                self.pop(X0);
                self.call_rtl(rtl::STR_COMPARE);
                self.a.cmp(W0, 0);
                signed_cond(c)
            }
            BinOp::SetCmp(c) => {
                let size = self.set_size(l.ty);
                self.address(l)?;
                self.push(X0);
                self.address(r)?;
                self.a.mov(X3, X0);
                self.pop(X2);
                self.a.mov_imm(X11, 0);
                for i in 0..size as i64 {
                    match c {
                        Cond::Le => {
                            self.a.ldrb(W0, Mem::base(X3, i));
                            self.a.ldrb(W9, Mem::base(X2, i));
                            self.a.bic(W0, W9, W0);
                        }
                        Cond::Ge => {
                            self.a.ldrb(W0, Mem::base(X2, i));
                            self.a.ldrb(W9, Mem::base(X3, i));
                            self.a.bic(W0, W9, W0);
                        }
                        _ => {
                            self.a.ldrb(W0, Mem::base(X2, i));
                            self.a.ldrb(W9, Mem::base(X3, i));
                            self.a.eor(W0, W0, W9);
                        }
                    }
                    self.a.orr(W11, W11, W0);
                }
                self.a.tst(W11, 0xff);
                if c == Cond::Ne { ACond::Ne } else { ACond::Eq }
            }
            _ => unreachable!(),
        })
    }

    /// Jumps to `target` when the Boolean `e` equals `when`.
    fn branch(&mut self, e: &Expr, target: Label, when: bool) -> CResult<()> {
        match &e.kind {
            ExprKind::Int(v) => {
                if (*v != 0) == when {
                    self.a.b(target);
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
                self.a.b_cond(if when { cond } else { cond.invert() }, target);
            }
            _ => {
                self.int(e)?;
                if when {
                    self.a.cbnz(W0, target);
                } else {
                    self.a.cbz(W0, target);
                }
            }
        }
        Ok(())
    }

    // ---- reals -----------------------------------------------------------

    /// D0 = value of a real expression, as a double.
    fn real(&mut self, e: &Expr) -> CResult<()> {
        match &e.kind {
            ExprKind::Real(v) => {
                self.a.mov_imm(X0, v.to_bits() as i64);
                self.a.fmov(D0, X0);
            }
            ExprKind::Int(v) => {
                self.a.mov_imm(X0, (*v as f64).to_bits() as i64);
                self.a.fmov(D0, X0);
            }
            ExprKind::Var(v) => {
                let m = self.var_mem(*v);
                self.load_real(m, e.ty);
            }
            ExprKind::Field { .. } | ExprKind::Index { .. } | ExprKind::OpenIndex { .. } | ExprKind::Deref(_) => {
                self.address(e)?;
                self.load_real(Mem::base(X0, 0), e.ty);
            }
            ExprKind::Unary(UnOp::RealNeg, x) => {
                self.real(x)?;
                self.a.fneg(D0, D0);
            }
            ExprKind::Binary(op, l, r) => {
                self.real(l)?;
                self.push_d0();
                self.real(r)?;
                self.a.fmov(D1, D0);
                self.pop_d(D0);
                match op {
                    BinOp::RealAdd => self.a.fadd(D0, D0, D1),
                    BinOp::RealSub => self.a.fsub(D0, D0, D1),
                    BinOp::RealMul => self.a.fmul(D0, D0, D1),
                    BinOp::RealDiv => self.a.fdiv(D0, D0, D1),
                    _ => return err(format!("internal: {op:?} as real"), e.span),
                }
                self.fp_check();
            }
            ExprKind::Convert(Conv::IntToReal, x) => {
                self.int(x)?;
                self.a.scvtf(D0, X0);
            }
            ExprKind::Convert(_, x) => self.real(x)?,
            ExprKind::Call { .. } => self.call(e)?,
            ExprKind::Intrinsic(op, args) => {
                self.real(&args[0])?;
                match op {
                    Intrinsic::AbsReal => self.a.fabs(D0, D0),
                    Intrinsic::SqrReal => {
                        self.a.fmul(D0, D0, D0);
                        self.fp_check();
                    }
                    Intrinsic::Sqrt => {
                        self.a.fsqrt(D0, D0);
                        self.fp_check();
                    }
                    Intrinsic::Int => self.a.frintz(D0, D0),
                    Intrinsic::Frac => {
                        self.a.frintz(D1, D0);
                        self.a.fsub(D0, D0, D1);
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
        let off = self.temp(256, 1) as i64;
        self.address(first)?;
        self.a.mov(X2, X0);
        self.a.add_const(X0, X29, off);
        self.a.mov_imm(X1, 255);
        self.call_rtl(rtl::STR_ASSIGN);
        for item in rest {
            self.address(item)?;
            self.a.mov(X1, X0);
            self.a.add_const(X0, X29, off);
            self.call_rtl(rtl::STR_APPEND);
        }
        self.a.add_const(X0, X29, off);
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

    /// Sets the bit for the value in X0 in the set at [X29+off]; uses X0-X2,
    /// X9, X10.
    fn set_include(&mut self, off: i32, first_byte: u32, size: u32) {
        let skip = self.a.new_label();
        self.add_imm(X0, -(first_byte as i64 * 8));
        self.a.cmp_const(X0, (size * 8) as i64);
        self.a.b_cond(ACond::Hs, skip);
        self.a.and(X1, X0, 7);
        self.a.mov_imm(X2, 1);
        self.a.lsl(W2, W2, W1);
        self.a.lsr(X0, X0, 3);
        self.a.add_const(X9, X29, off as i64);
        self.a.ldrb(W10, Mem::index(X9, X0));
        self.a.orr(W10, W10, W2);
        self.a.strb(W10, Mem::index(X9, X0));
        self.a.bind(skip);
    }

    fn set_build(&mut self, items: &[(Expr, Option<Expr>)], ty: TypeId) -> CResult<()> {
        let (first_byte, size) = self.set_layout(ty);
        let off = self.temp(size, 8);
        let mut i = 0;
        while i < size {
            let at = Mem::base(X29, off as i64 + i as i64);
            i += match size - i {
                8.. => {
                    self.a.str(XZR, at);
                    8
                }
                4.. => {
                    self.a.str(WZR, at);
                    4
                }
                2.. => {
                    self.a.strh(WZR, at);
                    2
                }
                _ => {
                    self.a.strb(WZR, at);
                    1
                }
            };
        }
        for (lo, hi) in items {
            match hi {
                None => {
                    self.int(lo)?;
                    self.set_include(off, first_byte, size);
                }
                Some(hi) => {
                    let cur = self.temp(8, 8) as i64;
                    let top = self.temp(8, 8) as i64;
                    self.int(lo)?;
                    self.a.str(X0, Mem::base(X29, cur));
                    self.int(hi)?;
                    self.a.str(X0, Mem::base(X29, top));
                    let lp = self.a.new_label();
                    let done = self.a.new_label();
                    self.a.bind(lp);
                    self.a.ldr(X0, Mem::base(X29, cur));
                    self.a.ldr(X11, Mem::base(X29, top));
                    self.a.cmp(X0, X11);
                    self.a.b_cond(ACond::Gt, done);
                    self.set_include(off, first_byte, size);
                    self.a.ldr(X11, Mem::base(X29, cur));
                    self.a.add(X11, X11, 1);
                    self.a.str(X11, Mem::base(X29, cur));
                    self.a.b(lp);
                    self.a.bind(done);
                }
            }
        }
        self.a.add_const(X0, X29, off as i64);
        Ok(())
    }

    fn set_binop(&mut self, op: BinOp, l: &Expr, r: &Expr, ty: TypeId) -> CResult<()> {
        let size = self.set_size(ty);
        self.address(l)?;
        self.push(X0);
        self.address(r)?;
        self.a.mov(X3, X0);
        self.pop(X2);
        let off = self.temp(size, 8) as i64;
        for i in 0..size as i64 {
            self.a.ldrb(W0, Mem::base(X2, i));
            self.a.ldrb(W1, Mem::base(X3, i));
            match op {
                BinOp::SetUnion => self.a.orr(W0, W0, W1),
                BinOp::SetIntersect => self.a.and(W0, W0, W1),
                _ => self.a.bic(W0, W0, W1),
            }
            self.a.strb(W0, Mem::base(X29, off + i));
        }
        self.a.add_const(X0, X29, off);
        Ok(())
    }

    fn set_in(&mut self, l: &Expr, r: &Expr) -> CResult<()> {
        let (first_byte, size) = self.set_layout(r.ty);
        self.int(l)?;
        self.push(X0);
        self.address(r)?;
        self.a.mov(X2, X0);
        self.pop(X0);
        let no = self.a.new_label();
        let end = self.a.new_label();
        self.add_imm(X0, -(first_byte as i64 * 8));
        self.a.cmp_const(X0, (size * 8) as i64);
        self.a.b_cond(ACond::Hs, no);
        self.a.and(X1, X0, 7);
        self.a.lsr(X0, X0, 3);
        self.a.ldrb(W0, Mem::index(X2, X0));
        self.a.lsr(W0, W0, W1);
        self.a.and(W0, W0, 1);
        self.a.b(end);
        self.a.bind(no);
        self.a.mov_imm(X0, 0);
        self.a.bind(end);
        Ok(())
    }

    // ---- calls -------------------------------------------------------------

    /// Calls `e` (an `ExprKind::Call`). The result ends up in X0, D0 (as
    /// double) or, for structured results, X0 = address of a temp.
    fn call(&mut self, e: &Expr) -> CResult<()> {
        let ExprKind::Call { callee, args } = &e.kind else { unreachable!() };
        let t = self.types();
        let sig: &Signature = match callee {
            Callee::Routine(id) | Callee::Virtual { routine: id, .. } | Callee::VirtualClass { routine: id, .. } => {
                &self.routine_ref(*id).sig
            }
            Callee::Indirect(x) => match t.get(x.ty) {
                Type::Procedural(s) => s,
                _ => return err("internal: indirect call of a non-procedural value", e.span),
            },
        };
        let depth0 = self.depth;
        let mut classes = Vec::new();
        if let Callee::Indirect(x) = callee {
            self.int(x)?;
            self.push(X0);
            classes.push(ArgClass::Callee);
        }
        let mut result_temp = None;
        if let Some(rt) = sig.result
            && result_by_ref(t, rt)
        {
            let off = self.temp(t.size(rt) as u32, t.align(rt));
            self.a.add_const(X0, X29, off as i64);
            self.push(X0);
            classes.push(ArgClass::Int);
            result_temp = Some(off);
        }
        for (p, a) in sig.params.iter().zip(args) {
            match passing(t, p.mode, p.ty) {
                Passing::Value if self.vclass(p.ty) == VClass::Real => {
                    self.real(a)?;
                    if self.is_single(p.ty) {
                        // The single sits in the low half of the slot, where `ldr s` finds it.
                        self.a.fcvt(S0, D0);
                        self.fp_check();
                    }
                    self.push_d0();
                    classes.push(ArgClass::Float);
                }
                Passing::Value => {
                    self.int(a)?;
                    self.push(X0);
                    classes.push(ArgClass::Int);
                }
                Passing::Ref | Passing::RefCopy => {
                    self.address(a)?;
                    self.push(X0);
                    classes.push(ArgClass::Int);
                }
                Passing::OpenArray => {
                    self.address(a)?;
                    self.push(X0);
                    classes.push(ArgClass::Int);
                    match t.get(a.ty) {
                        Type::Array { lo, hi, .. } => self.a.mov_imm(X0, hi - lo),
                        Type::ShortString(max) => self.a.mov_imm(X0, *max as i64),
                        _ => {
                            let m = self.open_high(a)?;
                            self.a.ldr(X0, m);
                        }
                    }
                    self.push(X0);
                    classes.push(ArgClass::Int);
                }
            }
        }
        // Apple passes the variadic arguments of a C function on the stack.
        let external_c = match callee {
            Callee::Routine(id) => match &self.routine_ref(*id).body {
                RoutineBody::External { symbol, library } if library != RTL_ASM_LIBRARY => Some(symbol.as_str()),
                _ => None,
            },
            _ => None,
        };
        let variadic_from = match (self.g.os, external_c) {
            (Os::Darwin, Some(symbol)) => variadic_fixed(symbol),
            _ => None,
        };
        // Distribute the pushed values over registers and stack slots.
        let n = classes.len() as i64;
        let (mut ni, mut nf) = (0, 0);
        let mut int_regs = Vec::new();
        let mut float_regs = Vec::new();
        let mut stack = Vec::new();
        for (i, c) in classes.iter().enumerate() {
            match c {
                ArgClass::Callee => {}
                ArgClass::Int if ni < 8 => {
                    int_regs.push((INT_ARGS[ni], i));
                    ni += 1;
                }
                ArgClass::Float if nf < 8 => {
                    float_regs.push((FLOAT_ARGS[nf], i));
                    nf += 1;
                }
                _ => stack.push(i),
            }
            if variadic_from.is_some_and(|from| i >= from) && !stack.contains(&i) {
                stack.push(i);
            }
        }
        let area = (8 * stack.len() as i64 + 15) & !15;
        let slot = |i: usize| Mem::base(SP, 16 * (n - 1 - i as i64) + area);
        if area > 0 {
            self.a.add_const(SP, SP, -area);
            for (j, &i) in stack.iter().enumerate() {
                self.a.ldr(X9, slot(i));
                self.a.str(X9, Mem::base(SP, 8 * j as i64));
            }
        }
        for &(r, i) in &int_regs {
            self.a.ldr(r, slot(i));
        }
        for &(d, i) in &float_regs {
            self.a.ldr(d, slot(i));
        }
        match callee {
            Callee::Routine(id) => {
                let r = self.routine_ref(*id);
                if let Some(parent) = r.parent {
                    let base = self.frame_base(parent);
                    self.a.mov(SLINK, base);
                }
                match &r.body {
                    RoutineBody::External { symbol, library } if library == RTL_ASM_LIBRARY => {
                        self.a.bl(symbol.as_str());
                    }
                    RoutineBody::External { symbol, library } => {
                        let Some(lib) = import_library(self.g.os, library) else {
                            return err(format!("pustaka '{library}' tidak didukung; gunakan 'c'"), r.span);
                        };
                        let name = self.g.import(symbol, lib);
                        self.a.call_got(&name);
                    }
                    RoutineBody::Code(_) => self.a.bl(r.symbol.as_str()),
                }
            }
            Callee::Indirect(_) => {
                self.a.ldr(X9, slot(0));
                self.a.blr(X9);
            }
            Callee::Virtual { vmt_offset, slot: index, check, .. } => {
                // Self is the first argument after a hidden result pointer;
                // it is already in its register.
                let self_index = result_temp.is_some() as usize;
                let Some(&(this, _)) = int_regs.iter().find(|(_, i)| *i == self_index) else {
                    return err("internal: Self of a virtual call is not in a register", e.span);
                };
                self.a.ldr(X9, Mem::base(this, *vmt_offset as i64));
                if *check {
                    let fail = self.a.new_label();
                    let ok = self.a.new_label();
                    self.a.cbz(X9, fail);
                    self.a.ldr(X10, Mem::base(X9, 0));
                    self.a.ldr(X11, Mem::base(X9, 8));
                    self.a.add(X10, X10, X11);
                    self.a.cbz(X10, ok);
                    self.a.bind(fail);
                    self.call_rtl(rtl::OBJECT_ERROR);
                    self.a.bind(ok);
                }
                let at = VMT_HEADER as i64 + 8 * *index as i64;
                self.a.ldr(X9, Mem::base(X9, at));
                self.a.blr(X9);
            }
            Callee::VirtualClass { arg, slot: index, .. } => {
                // The argument is the VMT itself, already in its register.
                let at_index = result_temp.is_some() as usize + *arg as usize;
                let Some(&(vmt, _)) = int_regs.iter().find(|(_, i)| *i == at_index) else {
                    return err("internal: VMT of a virtual call is not in a register", e.span);
                };
                let at = VMT_HEADER as i64 + 8 * *index as i64;
                self.a.ldr(X9, Mem::base(vmt, at));
                self.a.blr(X9);
            }
        }
        let total = area + 16 * n;
        if total > 0 {
            self.a.add_const(SP, SP, total);
        }
        self.depth = depth0;
        match (sig.result, result_temp) {
            (_, Some(off)) => self.a.add_const(X0, X29, off as i64),
            (Some(rt), None) if self.vclass(rt) == VClass::Real => {
                if self.is_single(rt) {
                    self.a.fcvt(D0, S0);
                }
                if external_c.is_some() {
                    // A C math function: its errors stop the program like ours.
                    self.fp_check();
                }
            }
            (Some(rt), None) => self.extend_x0(rt),
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
                    self.a.b(end);
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
                self.a.b(top);
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
                            self.a.cmp_const(X0, lo);
                            self.a.b_cond(ACond::Eq, *label);
                        } else {
                            let next = self.a.new_label();
                            self.a.cmp_const(X0, lo);
                            self.a.b_cond(ACond::Lt, next);
                            self.a.cmp_const(X0, hi);
                            self.a.b_cond(ACond::Le, *label);
                            self.a.bind(next);
                        }
                    }
                }
                self.a.b(other);
                for (arm, label) in arms.iter().zip(&labels) {
                    self.a.bind(*label);
                    self.stmts(&arm.body)?;
                    self.a.b(end);
                }
                self.a.bind(other);
                self.stmts(otherwise)?;
                self.a.bind(end);
            }
            StmtKind::Goto(l) => {
                let label = self.label(*l);
                self.a.b(label);
            }
            StmtKind::Label(l) => {
                let label = self.label(*l);
                self.a.bind(label);
            }
            StmtKind::Break | StmtKind::Continue => {
                let Some(&(cont, brk)) = self.loops.last() else {
                    return err("internal: Break di luar loop", s.span);
                };
                self.a.b(if matches!(s.kind, StmtKind::Break) { brk } else { cont });
            }
            StmtKind::Exit => {
                let exit = self.exit;
                self.a.b(exit);
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
    fn debug_point(&mut self, span: Span) -> i64 {
        let id = self.g.debug_points.len() as i64;
        self.g.debug_points.push(span);
        if self.g.count_steps {
            self.count_step(id);
            return id;
        }
        let skip = self.a.new_label();
        let hook = self.a.new_label();
        self.a.mov_imm(X9, id);
        self.a.str(W9, Mem::sym(rtl::DBG_LINE, 0));
        self.a.ldr(X9, Mem::sym(rtl::DBG_SHARED, 0));
        self.a.cbz(X9, skip);
        self.a.ldrh(W10, Mem::base(X9, 0));
        self.a.cbnz(W10, hook);
        self.a.ldrb(W10, Mem::base(X9, 16 + id));
        self.a.cbz(W10, skip);
        self.a.bind(hook);
        self.a.mov_imm(X0, id);
        self.call_rtl(rtl::DBG_HOOK);
        self.a.bind(skip);
        id
    }

    /// One step of statement `id`: its counter and the step budget, which
    /// ends the program with runtime error 240 when it runs out. Uses only
    /// x9-x11 (free between statements and before `for` loop bodies).
    fn count_step(&mut self, id: i64) {
        let skip = self.a.new_label();
        self.a.load_address(X11, STEP_COUNTS, id * 8);
        self.a.ldr(X9, Mem::base(X11, 0));
        self.a.add(X9, X9, 1);
        self.a.str(X9, Mem::base(X11, 0));
        self.a.ldr(X10, Mem::sym(rtl::STEP_BUDGET, 0));
        self.a.sub(X10, X10, 1);
        self.a.str(X10, Mem::sym(rtl::STEP_BUDGET, 0));
        self.a.tbz(X10, 63, skip);
        self.call_rtl(rtl::STEP_LIMIT);
        self.a.bind(skip);
    }

    /// Step-counting routine entry: one level deeper, its maximum, and the
    /// depth limit (runtime error 202).
    fn stat_enter(&mut self) {
        let below_max = self.a.new_label();
        let below_limit = self.a.new_label();
        self.a.ldr(W10, Mem::sym(rtl::STAT_DEPTH, 0));
        self.a.add(W10, W10, 1);
        self.a.str(W10, Mem::sym(rtl::STAT_DEPTH, 0));
        self.a.ldr(W9, Mem::sym(rtl::STAT_MAXDEPTH, 0));
        self.a.cmp(W10, W9);
        self.a.b_cond(ACond::Le, below_max);
        self.a.str(W10, Mem::sym(rtl::STAT_MAXDEPTH, 0));
        self.a.bind(below_max);
        self.a.ldr(W9, Mem::sym(rtl::STAT_DEPTHLIMIT, 0));
        self.a.cmp(W10, W9);
        self.a.b_cond(ACond::Le, below_limit);
        self.call_rtl(rtl::DEPTH_LIMIT);
        self.a.bind(below_limit);
    }

    fn stat_leave(&mut self) {
        self.a.ldr(W10, Mem::sym(rtl::STAT_DEPTH, 0));
        self.a.sub(W10, W10, 1);
        self.a.str(W10, Mem::sym(rtl::STAT_DEPTH, 0));
    }

    /// Bytes copied by one statement count one step per 64 in step-counting
    /// builds, so that copying a large array is not one step. Uses only x9,
    /// which the copy itself clobbers.
    fn weigh(&mut self, bytes: u64) {
        let steps = bytes / 64;
        if !(self.instrument && self.g.count_steps) || steps == 0 {
            return;
        }
        let skip = self.a.new_label();
        self.a.ldr(X9, Mem::sym(rtl::STEP_WEIGHT, 0));
        self.a.add_const(X9, X9, steps as i64);
        self.a.str(X9, Mem::sym(rtl::STEP_WEIGHT, 0));
        self.a.ldr(X9, Mem::sym(rtl::STEP_BUDGET, 0));
        self.a.add_const(X9, X9, -(steps as i64));
        self.a.str(X9, Mem::sym(rtl::STEP_BUDGET, 0));
        self.a.tbz(X9, 63, skip);
        self.call_rtl(rtl::STEP_LIMIT);
        self.a.bind(skip);
    }

    /// Step-counting builds start every variable and function result at
    /// zero: what an uninitialized local holds otherwise depends on the OS
    /// and on what ran before, and a judge must see the same run everywhere.
    /// Runs after the parameters are stored, so it may use x9 and x10.
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
            let mut done = 0u64;
            if size > 64 {
                let lp = self.a.new_label();
                self.a.add_const(X9, X29, off as i64);
                self.a.mov_imm(X10, (size / 8) as i64);
                self.a.bind(lp);
                self.a.str(XZR, Mem::post(X9, 8));
                self.a.subs(X10, X10, 1);
                self.a.b_cond(ACond::Ne, lp);
                done = size / 8 * 8;
            }
            let off = off as i64;
            while done + 8 <= size {
                self.a.str(XZR, Mem::base(X29, off + done as i64));
                done += 8;
            }
            while done + 4 <= size {
                self.a.str(WZR, Mem::base(X29, off + done as i64));
                done += 4;
            }
            while done + 2 <= size {
                self.a.strh(WZR, Mem::base(X29, off + done as i64));
                done += 2;
            }
            while done < size {
                self.a.strb(WZR, Mem::base(X29, off + done as i64));
                done += 1;
            }
        }
    }

    /// Routine entry: one level deeper; the shadow stack records the
    /// caller's line, this routine and its frame.
    fn debug_enter(&mut self) {
        let skip = self.a.new_label();
        self.a.ldr(W10, Mem::sym(rtl::DBG_DEPTH, 0));
        self.a.add(W10, W10, 1);
        self.a.str(W10, Mem::sym(rtl::DBG_DEPTH, 0));
        self.a.cmp_const(X10, rtl::DBG_STACK_SIZE as i64);
        self.a.b_cond(ACond::Hs, skip);
        self.a.load_address(X11, rtl::DBG_STACK, 0);
        self.a.add(X11, X11, X10.lsl(4));
        self.a.ldr(W9, Mem::sym(rtl::DBG_LINE, 0));
        self.a.str(W9, Mem::base(X11, 0));
        self.a.mov_imm(X9, self.id.0 as i64);
        self.a.str(W9, Mem::base(X11, 4));
        self.a.str(X29, Mem::base(X11, 8));
        self.a.bind(skip);
    }

    /// Routine exit: back to the caller's depth and current line.
    fn debug_leave(&mut self) {
        let skip = self.a.new_label();
        self.a.ldr(W10, Mem::sym(rtl::DBG_DEPTH, 0));
        self.a.cmp_const(X10, rtl::DBG_STACK_SIZE as i64);
        self.a.b_cond(ACond::Hs, skip);
        self.a.load_address(X11, rtl::DBG_STACK, 0);
        self.a.add(X11, X11, X10.lsl(4));
        self.a.ldr(W9, Mem::base(X11, 0));
        self.a.str(W9, Mem::sym(rtl::DBG_LINE, 0));
        self.a.bind(skip);
        self.a.ldr(W10, Mem::sym(rtl::DBG_DEPTH, 0));
        self.a.sub(W10, W10, 1);
        self.a.str(W10, Mem::sym(rtl::DBG_DEPTH, 0));
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
                    self.store_int(m, target.ty, X0);
                } else {
                    self.push(X0);
                    self.address(target)?;
                    self.a.mov(X1, X0);
                    self.pop(X0);
                    self.store_int(Mem::base(X1, 0), target.ty, X0);
                }
            }
            VClass::Real => {
                self.real(value)?;
                if let ExprKind::Var(v) = target.kind {
                    let m = self.var_mem(v);
                    self.store_real(m, target.ty);
                } else {
                    self.push_d0();
                    self.address(target)?;
                    self.pop_d(D0);
                    self.store_real(Mem::base(X0, 0), target.ty);
                }
            }
            VClass::Mem => {
                self.address(value)?;
                self.push(X0);
                self.address(target)?;
                if let Type::ShortString(max) = t.get(target.ty) {
                    self.a.mov_imm(X1, *max as i64);
                    self.pop(X2);
                    self.call_rtl(rtl::STR_ASSIGN);
                } else if let Type::OpenString = t.get(target.ty) {
                    // Capacity of an open string parameter: its hidden High.
                    self.push(X0);
                    let m = self.open_high(target)?;
                    self.a.ldr(X1, m);
                    self.pop(X0);
                    self.pop(X2);
                    self.call_rtl(rtl::STR_ASSIGN);
                } else {
                    self.a.mov(X4, X0);
                    self.pop(X3);
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
        point: Option<i64>,
    ) -> CResult<()> {
        let ty = var.ty;
        let ExprKind::Var(v) = var.kind else {
            return err("internal: for variable is not a variable", var.span);
        };
        self.int(from)?;
        self.push(X0);
        self.int(to)?;
        let m = self.var_mem(limit);
        self.store_int(m, ty, X0);
        self.pop(X0);
        let m = self.var_mem(v);
        self.store_int(m, ty, X0);
        let top = self.a.new_label();
        let step = self.a.new_label();
        let end = self.a.new_label();
        // Skip the loop when the range is empty.
        let m = self.var_mem(v);
        self.load_int(X0, m, ty);
        let m = self.var_mem(limit);
        self.load_int(X1, m, ty);
        self.a.cmp(X0, X1);
        self.a.b_cond(if down { ACond::Lt } else { ACond::Gt }, end);
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
        self.load_int(X0, m, ty);
        let m = self.var_mem(limit);
        self.load_int(X1, m, ty);
        self.a.cmp(X0, X1);
        self.a.b_cond(ACond::Eq, end);
        if down {
            self.a.sub(X0, X0, 1);
        } else {
            self.a.add(X0, X0, 1);
        }
        let m = self.var_mem(v);
        self.store_int(m, ty, X0);
        self.a.b(top);
        self.a.bind(end);
        Ok(())
    }

    // ---- prologue and epilogue -----------------------------------------------

    fn routine(mut self, body: &[Stmt]) -> CResult<Atom> {
        let r = self.me();
        let t = self.types();
        self.a.stp(X29, X30, Mem::pre(SP, -16));
        self.a.mov(X29, SP);
        // The frame size is known only at the end: movz/movk with zero
        // immediates, patched below.
        let frame_at = self.a.here();
        self.a.movz(X9, 0, 0);
        self.a.movk(X9, 0, 16);
        self.a.sub(SP, SP, X9);
        if r.parent.is_some() {
            self.a.str(SLINK, Mem::base(X29, -8));
        }
        // Incoming arguments: registers first, then the caller's stack.
        let mut inc = Incoming { ni: 0, nf: 0, stack_off: 16 };
        let layout_slots: Vec<Slot> = self.g.layouts[self.id.0 as usize].slots.clone();
        let scratch: Vec<Option<i32>> = self.g.layouts[self.id.0 as usize].scratch.clone();
        if let Some(rt) = r.sig.result
            && result_by_ref(t, rt)
        {
            let idx = r.result_local().expect("function has a result local") as usize;
            let reg = inc.int(&mut self.a);
            if let Slot::Pointer(off) = layout_slots[idx] {
                self.a.str(reg, Mem::base(X29, off as i64));
            }
        }
        let mut copies = Vec::new();
        for (i, p) in r.sig.params.iter().enumerate() {
            match passing(t, p.mode, p.ty) {
                Passing::Value if matches!(t.get(p.ty), Type::Real(_)) => {
                    let Slot::Value(off) = layout_slots[i] else { unreachable!() };
                    let single = matches!(t.get(p.ty), Type::Real(RealKind::Single));
                    if inc.nf < 8 {
                        let d = FLOAT_ARGS[inc.nf];
                        inc.nf += 1;
                        if single {
                            self.a.str(d.to_s(), Mem::base(X29, off as i64));
                        } else {
                            self.a.str(d, Mem::base(X29, off as i64));
                        }
                    } else {
                        self.a.ldr(X9, Mem::base(X29, inc.stack_off as i64));
                        inc.stack_off += 8;
                        if single {
                            self.a.str(W9, Mem::base(X29, off as i64));
                        } else {
                            self.a.str(X9, Mem::base(X29, off as i64));
                        }
                    }
                }
                Passing::Value => {
                    let Slot::Value(off) = layout_slots[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.store_int(Mem::base(X29, off as i64), p.ty, reg);
                }
                Passing::Ref => {
                    let Slot::Pointer(off) = layout_slots[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.str(reg, Mem::base(X29, off as i64));
                }
                Passing::OpenArray => {
                    let Slot::Pointer(off) = layout_slots[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.str(reg, Mem::base(X29, off as i64));
                    let h = r.locals.iter().position(|l| l.kind == LocalKind::OpenHigh(i as u32)).expect("High local");
                    let Slot::Value(hoff) = layout_slots[h] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.str(reg, Mem::base(X29, hoff as i64));
                }
                Passing::RefCopy => {
                    let Some(sp) = scratch[i] else { unreachable!() };
                    let reg = inc.int(&mut self.a);
                    self.a.str(reg, Mem::base(X29, sp as i64));
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
                self.a.add_const(X0, X29, off as i64);
                self.a.mov_imm(X1, *max as i64);
                self.a.ldr(X2, Mem::base(X29, sp as i64));
                self.call_rtl(rtl::STR_ASSIGN);
            } else {
                self.a.ldr(X3, Mem::base(X29, sp as i64));
                self.a.add_const(X4, X29, off as i64);
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
                Slot::Pointer(off) => self.a.ldr(X0, Mem::base(X29, off as i64)),
                Slot::Value(off) => match self.vclass(rt) {
                    VClass::Real if self.is_single(rt) => self.a.ldr(S0, Mem::base(X29, off as i64)),
                    VClass::Real => self.a.ldr(D0, Mem::base(X29, off as i64)),
                    _ => self.load_int(X0, Mem::base(X29, off as i64), rt),
                },
            }
        }
        self.a.mov(SP, X29);
        self.a.ldp(X29, X30, Mem::post(SP, 16));
        self.a.ret();
        if self.depth != 0 {
            return err("internal: stack depth mismatch", r.span);
        }
        let frame = align_up(self.temp_max, 16);
        let code = self.a.finish().map_err(|e| CodegenError { message: format!("internal: {e}"), span: r.span })?;
        let mut code = code;
        // Patch the 16-bit immediates of the movz/movk pair (bits 5..20).
        let at = code.label_offset(frame_at).expect("frame label") as usize;
        for (k, half) in [(0usize, frame & 0xffff), (4, frame >> 16)] {
            let w = u32::from_le_bytes(code.bytes[at + k..at + k + 4].try_into().unwrap());
            let w = (w & !(0xffff << 5)) | (half << 5);
            code.bytes[at + k..at + k + 4].copy_from_slice(&w.to_le_bytes());
        }
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
    stack_off: i32,
}

impl Incoming {
    /// The register holding the next integer-class argument; arguments
    /// passed on the stack are loaded into X9 first.
    fn int(&mut self, a: &mut Assembler) -> Reg {
        if self.ni < 8 {
            self.ni += 1;
            INT_ARGS[self.ni - 1]
        } else {
            a.ldr(X9, Mem::base(X29, self.stack_off as i64));
            self.stack_off += 8;
            X9
        }
    }
}

fn signed_cond(c: Cond) -> ACond {
    match c {
        Cond::Eq => ACond::Eq,
        Cond::Ne => ACond::Ne,
        Cond::Lt => ACond::Lt,
        Cond::Le => ACond::Le,
        Cond::Gt => ACond::Gt,
        Cond::Ge => ACond::Ge,
    }
}
