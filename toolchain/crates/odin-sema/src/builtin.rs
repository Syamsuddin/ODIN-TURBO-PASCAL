// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Compiler-magic routines. Function-like builtins become HIR expressions
//! (folded when their arguments are constant); procedure-like builtins
//! become RTL calls and assignments.

use odin_base::{Span, code};
use odin_ir::*;
use odin_syntax::{Switches, ast};

use crate::expr::{Class, Resolved};
use crate::scope::Builtin;
use crate::{Analyzer, SResult};

#[derive(Clone, Copy, PartialEq, Eq)]
enum FileKind {
    Text,
    Typed(TypeId),
    Untyped,
}

fn stmt(kind: StmtKind, span: Span) -> Stmt {
    Stmt { kind, span }
}

impl Analyzer<'_> {
    fn arg_count(&self, args: &[ast::Arg], min: usize, max: usize, span: Span) -> SResult<()> {
        if args.len() < min || args.len() > max {
            return self.error_with(code::WRONG_ARG_COUNT, span, format!(": diberikan {}", args.len()));
        }
        for a in args {
            if a.width.is_some() {
                return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
            }
        }
        Ok(())
    }

    fn ordinal_arg(&mut self, a: &ast::Arg) -> SResult<Expr> {
        let v = self.expr(&a.value)?;
        if !self.types.is_ordinal(v.ty) {
            return self.error(code::ORDINAL_EXPR_EXPECTED, a.value.span);
        }
        Ok(v)
    }

    fn numeric_arg(&mut self, a: &ast::Arg) -> SResult<Expr> {
        let v = self.expr(&a.value)?;
        if !matches!(self.class(v.ty), Class::Int | Class::Real) {
            return self.error(code::INT_OR_REAL_EXPR_EXPECTED, a.value.span);
        }
        Ok(v)
    }

    fn int_const(&self, v: i64, ty: TypeId, span: Span) -> Expr {
        Expr::new(ExprKind::Int(v), ty, span)
    }

    /// Builtins used as values.
    pub(crate) fn builtin_expr(&mut self, b: Builtin, args: &[ast::Arg], span: Span) -> SResult<Expr> {
        let bt = self.types.builtin;
        match b {
            Builtin::Ord => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.ordinal_arg(&args[0])?;
                let ty = if self.types.size(v.ty) <= 4 { bt.longint } else { bt.int64 };
                if let ExprKind::Int(n) = v.kind {
                    return Ok(self.int_const(n, ty, span));
                }
                Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(v)), ty, span))
            }
            Builtin::Chr => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                if self.class(v.ty) != Class::Int {
                    return self.error(code::INTEGER_EXPR_EXPECTED, args[0].value.span);
                }
                if let ExprKind::Int(n) = v.kind {
                    return Ok(self.int_const(n as u8 as i64, bt.char, span));
                }
                Ok(Expr::new(ExprKind::Convert(Conv::Resize, Box::new(v)), bt.char, span))
            }
            Builtin::Succ | Builtin::Pred => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.ordinal_arg(&args[0])?;
                let ty = v.ty;
                let delta = if b == Builtin::Succ { 1 } else { -1 };
                let (lo, hi) = self.types.bounds(ty);
                if let ExprKind::Int(n) = v.kind {
                    let r = n.wrapping_add(delta);
                    if r < lo || r > hi {
                        return self.error(code::CONST_OUT_OF_RANGE, span);
                    }
                    return Ok(self.int_const(r, ty, span));
                }
                let one = self.int_const(delta, bt.longint, span);
                let sum = Expr::new(ExprKind::Binary(BinOp::Add, Box::new(v), Box::new(one)), bt.int64, span);
                let conv = if self.sw.get(Switches::RANGE) { Conv::RangeCheck { lo, hi } } else { Conv::Resize };
                Ok(Expr::new(ExprKind::Convert(conv, Box::new(sum)), ty, span))
            }
            Builtin::Odd => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                if self.class(v.ty) != Class::Int {
                    return self.error(code::INTEGER_EXPR_EXPECTED, args[0].value.span);
                }
                if let ExprKind::Int(n) = v.kind {
                    return Ok(self.int_const(n & 1, bt.boolean, span));
                }
                Ok(Expr::new(ExprKind::Intrinsic(Intrinsic::Odd, vec![v]), bt.boolean, span))
            }
            Builtin::Abs | Builtin::Sqr => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.numeric_arg(&args[0])?;
                let is_int = self.class(v.ty) == Class::Int;
                match (&v.kind, b) {
                    (ExprKind::Int(n), Builtin::Abs) => return Ok(self.int_const(n.wrapping_abs(), bt.int64, span)),
                    (ExprKind::Int(n), _) => return Ok(self.int_const(n.wrapping_mul(*n), bt.int64, span)),
                    (ExprKind::Real(r), Builtin::Abs) => {
                        return Ok(Expr::new(ExprKind::Real(r.abs()), bt.double, span));
                    }
                    (ExprKind::Real(r), _) => return Ok(Expr::new(ExprKind::Real(r * r), bt.double, span)),
                    _ => {}
                }
                let (op, ty) = match (b, is_int) {
                    (Builtin::Abs, true) => (Intrinsic::AbsInt, bt.int64),
                    (Builtin::Abs, false) => (Intrinsic::AbsReal, bt.double),
                    (_, true) => (Intrinsic::SqrInt, bt.int64),
                    (_, false) => (Intrinsic::SqrReal, bt.double),
                };
                Ok(Expr::new(ExprKind::Intrinsic(op, vec![v]), ty, span))
            }
            Builtin::Sqrt | Builtin::Int | Builtin::Frac | Builtin::Trunc | Builtin::Round => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.numeric_arg(&args[0])?;
                let v = self.to_real(v);
                if let ExprKind::Real(r) = v.kind {
                    return Ok(match b {
                        Builtin::Sqrt => Expr::new(ExprKind::Real(r.sqrt()), bt.double, span),
                        Builtin::Int => Expr::new(ExprKind::Real(r.trunc()), bt.double, span),
                        Builtin::Frac => Expr::new(ExprKind::Real(r - r.trunc()), bt.double, span),
                        Builtin::Trunc => self.int_const(r.trunc() as i64, bt.int64, span),
                        _ => self.int_const(r.round_ties_even() as i64, bt.int64, span),
                    });
                }
                let (op, ty) = match b {
                    Builtin::Sqrt => (Intrinsic::Sqrt, bt.double),
                    Builtin::Int => (Intrinsic::Int, bt.double),
                    Builtin::Frac => (Intrinsic::Frac, bt.double),
                    Builtin::Trunc => (Intrinsic::Trunc, bt.int64),
                    _ => (Intrinsic::Round, bt.int64),
                };
                Ok(Expr::new(ExprKind::Intrinsic(op, vec![v]), ty, span))
            }
            Builtin::Length => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                match (self.class(v.ty), &v.kind) {
                    (Class::Str, ExprKind::Str(s)) => Ok(self.int_const(s.len() as i64, bt.longint, span)),
                    (Class::Char, _) => Ok(self.int_const(1, bt.longint, span)),
                    (Class::Str, _) => Ok(Expr::new(ExprKind::Intrinsic(Intrinsic::Length, vec![v]), bt.longint, span)),
                    _ => self.error(code::STRING_EXPR_EXPECTED, args[0].value.span),
                }
            }
            Builtin::SizeOf => {
                self.arg_count(args, 1, 1, span)?;
                let ty = match self.resolve(&args[0].value)? {
                    Resolved::Type(t, _) => t,
                    // An object with a VMT: the size of its actual type, read
                    // from the VMT (as FPC does).
                    Resolved::Value(v)
                        if v.is_lvalue() && self.types.object(v.ty).is_some_and(|o| o.vmt_offset.is_some()) =>
                    {
                        let vmt = self.vmt_of_instance(v, span)?;
                        let int64_ptr = self.pointer_to(bt.int64);
                        let p = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(vmt)), int64_ptr, span);
                        return Ok(Expr::new(ExprKind::Deref(Box::new(p)), bt.int64, span));
                    }
                    Resolved::Value(v) => v.ty,
                    _ => return self.error(code::ERROR_IN_EXPR, args[0].value.span),
                };
                if let Type::OpenString = self.types.get(ty) {
                    let Resolved::Value(v) = self.resolve(&args[0].value)? else { unreachable!() };
                    // An open string occupies High + 1 bytes.
                    let high = Expr::new(ExprKind::Intrinsic(Intrinsic::OpenHigh, vec![v]), bt.int64, span);
                    let one = self.int_const(1, bt.longint, span);
                    return Ok(Expr::new(ExprKind::Binary(BinOp::Add, Box::new(high), Box::new(one)), bt.int64, span));
                }
                if matches!(self.types.get(ty), Type::OpenArray { .. } | Type::Untyped) {
                    return self.error_with(code::NOT_SUPPORTED, span, ": SizeOf parameter open array");
                }
                let size = self.types.size(ty) as i64;
                Ok(self.int_const(size, bt.longint, span))
            }
            Builtin::High | Builtin::Low => {
                self.arg_count(args, 1, 1, span)?;
                let high = b == Builtin::High;
                let ty = match self.resolve(&args[0].value)? {
                    Resolved::Type(t, _) => t,
                    Resolved::Value(v) => {
                        if let Type::OpenArray { .. } | Type::OpenString = self.types.get(v.ty) {
                            if !high {
                                return Ok(self.int_const(0, bt.longint, span));
                            }
                            return Ok(Expr::new(ExprKind::Intrinsic(Intrinsic::OpenHigh, vec![v]), bt.int64, span));
                        }
                        v.ty
                    }
                    _ => return self.error(code::ERROR_IN_EXPR, args[0].value.span),
                };
                match self.types.get(ty).clone() {
                    Type::Array { index, lo, hi, .. } => Ok(self.int_const(if high { hi } else { lo }, index, span)),
                    Type::ShortString(max) => Ok(self.int_const(if high { max as i64 } else { 0 }, bt.longint, span)),
                    _ if self.types.is_ordinal(ty) => {
                        let (lo, hi) = self.types.bounds(ty);
                        Ok(self.int_const(if high { hi } else { lo }, ty, span))
                    }
                    _ => self.error(code::ORDINAL_TYPE_EXPECTED, args[0].value.span),
                }
            }
            Builtin::Assigned => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                if !matches!(self.class(v.ty), Class::Ptr | Class::Proc) {
                    return self.error(code::POINTER_OR_PROC_VAR_EXPECTED, args[0].value.span);
                }
                let nil = Expr::new(ExprKind::Nil, v.ty, span);
                Ok(Expr::new(ExprKind::Binary(BinOp::Cmp(Cond::Ne), Box::new(v), Box::new(nil)), bt.boolean, span))
            }
            Builtin::Lo | Builtin::Hi => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                if self.class(v.ty) != Class::Int {
                    return self.error(code::INTEGER_EXPR_EXPECTED, args[0].value.span);
                }
                let size = self.types.size(v.ty);
                // FPC: nibbles of a Byte, bytes of a Word, words of a LongInt.
                let (bits, ty) = match size {
                    1 => (4, bt.byte),
                    2 => (8, bt.byte),
                    4 => (16, bt.word),
                    _ => (32, bt.longword),
                };
                let mask = (1i64 << bits) - 1;
                let shifted = if b == Builtin::Hi {
                    let amount = self.int_const(bits, bt.longint, span);
                    Expr::new(ExprKind::Binary(BinOp::Shr, Box::new(v), Box::new(amount)), bt.int64, span)
                } else {
                    v
                };
                let m = self.int_const(mask, bt.int64, span);
                if let ExprKind::Int(n) = shifted.kind {
                    return Ok(self.int_const(n & mask, ty, span));
                }
                let masked = Expr::new(ExprKind::Binary(BinOp::And, Box::new(shifted), Box::new(m)), bt.int64, span);
                Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(masked)), ty, span))
            }
            Builtin::Concat => {
                if args.is_empty() {
                    return self.error(code::WRONG_ARG_COUNT, span);
                }
                let mut parts = Vec::new();
                for a in args {
                    let v = self.expr(&a.value)?;
                    if !matches!(self.class(v.ty), Class::Str | Class::Char) {
                        return self.error(code::STRING_EXPR_EXPECTED, a.value.span);
                    }
                    parts.push(v);
                }
                Ok(self.concat(parts, span))
            }
            // Ofs(X): the address of X as a pointer-sized integer (TP's
            // offset part; there are no segments). Ofs(P^) is P itself.
            Builtin::Ofs => {
                self.arg_count(args, 1, 1, span)?;
                let address = match &args[0].value.kind {
                    ast::ExprKind::Deref(inner) => {
                        let p = self.expr(inner)?;
                        if self.class(p.ty) != Class::Ptr {
                            return self.error(code::POINTER_EXPR_EXPECTED, inner.span);
                        }
                        p
                    }
                    _ => {
                        let v = self.expr(&args[0].value)?;
                        if !v.is_lvalue() {
                            return self.error(code::BAD_AT_ARGUMENT, args[0].value.span);
                        }
                        Expr::new(ExprKind::AddrOf(Box::new(v)), bt.pointer, span)
                    }
                };
                Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(address)), bt.qword, span))
            }
            // Seg(X): always 0 in a flat address space.
            Builtin::Seg => {
                self.arg_count(args, 1, 1, span)?;
                self.expr(&args[0].value)?;
                Ok(self.int_const(0, bt.word, span))
            }
            Builtin::Addr => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                if !v.is_lvalue() {
                    return self.error(code::BAD_AT_ARGUMENT, args[0].value.span);
                }
                Ok(Expr::new(ExprKind::AddrOf(Box::new(v)), bt.pointer, span))
            }
            Builtin::Eof
            | Builtin::Eoln
            | Builtin::SeekEof
            | Builtin::SeekEoln
            | Builtin::FilePos
            | Builtin::FileSize => self.file_function(b, args, span),
            Builtin::Random => {
                self.arg_count(args, 0, 1, span)?;
                match args.first() {
                    None => self.rtl_call("ODIN_RANDOM_REAL", Vec::new(), span),
                    Some(a) => {
                        let n = self.expr(&a.value)?;
                        if self.class(n.ty) != Class::Int {
                            return self.error(code::INTEGER_EXPR_EXPECTED, a.value.span);
                        }
                        let ty = if self.types.size(n.ty) <= 4 { bt.longint } else { bt.int64 };
                        let r = self.rtl_call("ODIN_RANDOM_INT", vec![n], span)?;
                        Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(r)), ty, span))
                    }
                }
            }
            Builtin::Swap => {
                self.arg_count(args, 1, 1, span)?;
                let v = self.expr(&args[0].value)?;
                if self.class(v.ty) != Class::Int {
                    return self.error(code::INTEGER_EXPR_EXPECTED, args[0].value.span);
                }
                let ty = self.types.base(v.ty);
                let bits = match self.types.size(ty) {
                    1 => return Ok(Expr { span, ..v }),
                    2 => 8,
                    4 => 16,
                    _ => 32,
                };
                let mask = (1i64 << bits) - 1;
                if let ExprKind::Int(n) = v.kind {
                    let k = self.types.int_kind(ty);
                    let swapped = ((n >> bits) & mask) | ((n & mask) << bits);
                    return Ok(self.int_const(crate::expr::wrap(swapped, k), ty, span));
                }
                // (x shr bits) and mask  or  (x and mask) shl bits, in the operand's width.
                let shift = self.int_const(bits, bt.longint, span);
                let m = self.int_const(mask, bt.int64, span);
                let low =
                    Expr::new(ExprKind::Binary(BinOp::And, Box::new(v.clone()), Box::new(m.clone())), bt.int64, span);
                let high =
                    Expr::new(ExprKind::Binary(BinOp::Shl, Box::new(low), Box::new(shift.clone())), bt.int64, span);
                let down = Expr::new(ExprKind::Binary(BinOp::Shr, Box::new(v), Box::new(shift)), bt.int64, span);
                let down = Expr::new(ExprKind::Binary(BinOp::And, Box::new(down), Box::new(m)), bt.int64, span);
                let both = Expr::new(ExprKind::Binary(BinOp::Or, Box::new(high), Box::new(down)), bt.int64, span);
                Ok(Expr::new(ExprKind::Convert(Conv::Resize, Box::new(both)), ty, span))
            }
            Builtin::TypeOf => {
                self.arg_count(args, 1, 1, span)?;
                match self.resolve(&args[0].value)? {
                    Resolved::Type(t, s) => self.vmt_address(t, s),
                    Resolved::Value(v) if v.is_lvalue() => self.vmt_of_instance(v, span),
                    _ => self.error(code::OBJECT_TYPE_EXPECTED, args[0].value.span),
                }
            }
            // Function form with a constructor: P := New(PNode, Init(...)).
            Builtin::New if args.len() == 2 => {
                let Resolved::Type(t, _) = self.resolve(&args[0].value)? else {
                    return self.error(code::POINTER_TYPE_IDENT_EXPECTED, args[0].value.span);
                };
                self.new_object(t, &args[1].value, span)
            }
            Builtin::New if args.len() == 1 => {
                // Function form: P := New(PNode).
                let Resolved::Type(t, _) = self.resolve(&args[0].value)? else {
                    return self.error(code::NO_VALUE, span);
                };
                let Type::Pointer(Some(target)) = self.types.get(t).clone() else {
                    return self.error(code::POINTER_TYPE_IDENT_EXPECTED, args[0].value.span);
                };
                let size = self.types.size(target) as i64;
                let n = self.int_const(size, bt.int64, span);
                let mem = self.rtl_call("ODIN_GETMEM", vec![n], span)?;
                Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(mem)), t, span))
            }
            _ => self.error(code::NO_VALUE, span),
        }
    }

    /// Builtins used as statements.
    pub(crate) fn builtin_stmt(&mut self, b: Builtin, args: &[ast::Arg], span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        match b {
            Builtin::Write | Builtin::WriteLn => self.write(args, b == Builtin::WriteLn, span),
            Builtin::Read | Builtin::ReadLn => self.read(args, b == Builtin::ReadLn, span),
            Builtin::Inc | Builtin::Dec => self.inc_dec(args, b == Builtin::Inc, span),
            Builtin::Halt => {
                self.arg_count(args, 0, 1, span)?;
                let code_value = match args.first() {
                    Some(a) => {
                        let v = self.expr(&a.value)?;
                        if self.class(v.ty) != Class::Int {
                            return self.error(code::INTEGER_EXPR_EXPECTED, a.value.span);
                        }
                        v
                    }
                    None => self.int_const(0, bt.longint, span),
                };
                let call = self.rtl_call("ODIN_HALT", vec![code_value], span)?;
                Ok(vec![stmt(StmtKind::Call(call), span)])
            }
            Builtin::Exit => {
                if !args.is_empty() {
                    return self.error_with(code::NOT_SUPPORTED, span, ": Exit dengan nilai (bukan Turbo Pascal)");
                }
                Ok(vec![stmt(StmtKind::Exit, span)])
            }
            Builtin::Break | Builtin::Continue => {
                self.arg_count(args, 0, 0, span)?;
                if self.frames.last().is_none_or(|f| f.loops == 0) {
                    return self.error(code::NO_ENCLOSING_LOOP, span);
                }
                Ok(vec![stmt(if b == Builtin::Break { StmtKind::Break } else { StmtKind::Continue }, span)])
            }
            Builtin::New | Builtin::Dispose if args.len() == 2 => {
                let p = self.expr(&args[0].value)?;
                if !p.is_lvalue() && b == Builtin::New {
                    return self.error(code::VAR_IDENT_EXPECTED, args[0].value.span);
                }
                if b == Builtin::Dispose {
                    let stmts = self.dispose_object(p, &args[1].value, span)?;
                    return Ok(vec![stmt(StmtKind::Block(stmts), span)]);
                }
                let value = self.new_object(p.ty, &args[1].value, span)?;
                Ok(vec![stmt(StmtKind::Assign { target: p, value }, span)])
            }
            Builtin::New | Builtin::Dispose => {
                self.arg_count(args, 1, 1, span)?;
                let p = self.expr(&args[0].value)?;
                // Dispose also takes a variable typecast: Dispose(PRec(Item)).
                let typecast = matches!(&p.kind, ExprKind::Convert(Conv::Bits, inner) if inner.is_lvalue());
                if !p.is_lvalue() && !(b == Builtin::Dispose && typecast) {
                    return self.error(code::VAR_IDENT_EXPECTED, args[0].value.span);
                }
                let Type::Pointer(Some(target)) = self.types.get(p.ty).clone() else {
                    return self.error(code::POINTER_VAR_EXPECTED, args[0].value.span);
                };
                let size = self.int_const(self.types.size(target) as i64, bt.int64, span);
                if b == Builtin::New {
                    let mem = self.rtl_call("ODIN_GETMEM", vec![size], span)?;
                    let value = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(mem)), p.ty, span);
                    Ok(vec![stmt(StmtKind::Assign { target: p, value }, span)])
                } else {
                    let ptr = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), bt.pointer, span);
                    let call = self.rtl_call("ODIN_FREEMEM", vec![ptr, size], span)?;
                    Ok(vec![stmt(StmtKind::Call(call), span)])
                }
            }
            Builtin::Include | Builtin::Exclude => {
                self.arg_count(args, 2, 2, span)?;
                let s = self.expr(&args[0].value)?;
                if !s.is_lvalue() || self.class(s.ty) != Class::Set {
                    return self.error(code::VAR_IDENT_EXPECTED, args[0].value.span);
                }
                let e = self.ordinal_arg(&args[1])?;
                let Type::Set { base, .. } = self.types.get(s.ty).clone() else { unreachable!() };
                if !self.ordinals_compatible(e.ty, base) {
                    return self.error(code::TYPE_MISMATCH, args[1].value.span);
                }
                let mut stmts = Vec::new();
                let target = self.stable_lvalue(s, &mut stmts, span);
                let single = Expr::new(ExprKind::SetBuild(vec![(e, None)]), target.ty, span);
                let op = if b == Builtin::Include { BinOp::SetUnion } else { BinOp::SetDiff };
                let value =
                    Expr::new(ExprKind::Binary(op, Box::new(target.clone()), Box::new(single)), target.ty, span);
                stmts.push(stmt(StmtKind::Assign { target, value }, span));
                Ok(vec![stmt(StmtKind::Block(stmts), span)])
            }
            Builtin::Str => self.str_proc(args, span),
            Builtin::Val => self.val_proc(args, span),
            Builtin::Assign
            | Builtin::Rename
            | Builtin::Reset
            | Builtin::Rewrite
            | Builtin::Append
            | Builtin::Flush
            | Builtin::Close
            | Builtin::Erase
            | Builtin::Truncate
            | Builtin::Seek
            | Builtin::BlockRead
            | Builtin::BlockWrite => self.file_stmt(b, args, span),
            Builtin::FillChar => {
                self.arg_count(args, 3, 3, span)?;
                let x = self.expr(&args[0].value)?;
                if !x.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, args[0].value.span);
                }
                let count = self.value_arg(&args[1], bt.int64)?;
                let v = self.ordinal_arg(&args[2])?;
                let v = Expr::new(ExprKind::Convert(Conv::Resize, Box::new(v)), bt.byte, span);
                let call = self.rtl_call("ODIN_FILLCHAR", vec![x, count, v], span)?;
                Ok(vec![stmt(StmtKind::Call(call), span)])
            }
            Builtin::GetMem => {
                self.arg_count(args, 2, 2, span)?;
                let p = self.expr(&args[0].value)?;
                if !p.is_lvalue() || !matches!(self.types.get(p.ty), Type::Pointer(_)) {
                    return self.error(code::POINTER_VAR_EXPECTED, args[0].value.span);
                }
                let size = self.value_arg(&args[1], bt.int64)?;
                let mem = self.rtl_call("ODIN_GETMEM", vec![size], span)?;
                let value = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(mem)), p.ty, span);
                Ok(vec![stmt(StmtKind::Assign { target: p, value }, span)])
            }
            Builtin::FreeMem => {
                self.arg_count(args, 1, 2, span)?;
                let p = self.expr(&args[0].value)?;
                if !matches!(self.types.get(p.ty), Type::Pointer(_)) {
                    return self.error(code::POINTER_VAR_EXPECTED, args[0].value.span);
                }
                let size = match args.get(1) {
                    Some(a) => self.value_arg(a, bt.int64)?,
                    None => self.int_const(0, bt.int64, span),
                };
                let ptr = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), bt.pointer, span);
                let call = self.rtl_call("ODIN_FREEMEM", vec![ptr, size], span)?;
                Ok(vec![stmt(StmtKind::Call(call), span)])
            }
            Builtin::RunError => {
                self.arg_count(args, 0, 1, span)?;
                let code_value = match args.first() {
                    Some(a) => self.value_arg(a, bt.longint)?,
                    None => self.int_const(0, bt.longint, span),
                };
                let call = self.rtl_call("ODIN_RUNERROR", vec![code_value], span)?;
                Ok(vec![stmt(StmtKind::Call(call), span)])
            }
            _ => {
                self.error_with(code::ERROR_IN_STATEMENT, span, ": fungsi bawaan tidak bisa dipakai sebagai statement")
            }
        }
    }

    fn file_kind(&self, ty: TypeId) -> Option<FileKind> {
        if Some(ty) == self.text_type {
            return Some(FileKind::Text);
        }
        match self.types.get(ty) {
            Type::File { elem: Some(e), .. } => Some(FileKind::Typed(*e)),
            Type::File { elem: None, .. } => Some(FileKind::Untyped),
            _ => None,
        }
    }

    /// A file variable argument.
    fn file_arg(&mut self, a: &ast::Arg) -> SResult<(Expr, FileKind)> {
        if a.width.is_some() {
            return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
        }
        let f = self.expr(&a.value)?;
        match self.file_kind(f.ty) {
            Some(k) if f.is_lvalue() => Ok((f, k)),
            _ => self.error(code::FILE_VAR_EXPECTED, a.value.span),
        }
    }

    fn value_arg(&mut self, a: &ast::Arg, ty: TypeId) -> SResult<Expr> {
        if a.width.is_some() {
            return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
        }
        let v = self.expr_expect(&a.value, Some(ty))?;
        self.coerce(v, ty, a.value.span)
    }

    /// One RTL call followed by an I/O check under `{$I+}`, as a block.
    fn io_call(&self, name: &str, args: Vec<Expr>, span: Span) -> SResult<Vec<Stmt>> {
        let mut stmts = vec![stmt(StmtKind::Call(self.rtl_call(name, args, span)?), span)];
        self.io_check(&mut stmts, span)?;
        Ok(vec![stmt(StmtKind::Block(stmts), span)])
    }

    fn file_stmt(&mut self, b: Builtin, args: &[ast::Arg], span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        match b {
            Builtin::Assign | Builtin::Rename => {
                self.arg_count(args, 2, 2, span)?;
                let (f, k) = self.file_arg(&args[0])?;
                let n = self.value_arg(&args[1], bt.string)?;
                let name = match (b, k) {
                    (Builtin::Assign, FileKind::Text) => "ODIN_TEXT_ASSIGN",
                    (Builtin::Assign, _) => "ODIN_FILE_ASSIGN",
                    (_, FileKind::Text) => "ODIN_TEXT_RENAME",
                    _ => "ODIN_FILE_RENAME",
                };
                self.io_call(name, vec![f, n], span)
            }
            Builtin::Reset | Builtin::Rewrite => {
                self.arg_count(args, 1, 2, span)?;
                let (f, k) = self.file_arg(&args[0])?;
                let reset = b == Builtin::Reset;
                match k {
                    FileKind::Text => {
                        if args.len() == 2 {
                            return self.error(code::WRONG_ARG_COUNT, span);
                        }
                        self.io_call(if reset { "ODIN_TEXT_RESET" } else { "ODIN_TEXT_REWRITE" }, vec![f], span)
                    }
                    FileKind::Typed(elem) => {
                        if args.len() == 2 {
                            return self.error(code::WRONG_ARG_COUNT, span);
                        }
                        let size = self.int_const(self.types.size(elem) as i64, bt.longint, span);
                        self.io_call(if reset { "ODIN_FILE_RESET" } else { "ODIN_FILE_REWRITE" }, vec![f, size], span)
                    }
                    FileKind::Untyped => {
                        let size = match args.get(1) {
                            Some(a) => self.value_arg(a, bt.longint)?,
                            None => self.int_const(128, bt.longint, span),
                        };
                        self.io_call(if reset { "ODIN_FILE_RESET" } else { "ODIN_FILE_REWRITE" }, vec![f, size], span)
                    }
                }
            }
            Builtin::Append | Builtin::Flush => {
                self.arg_count(args, 1, 1, span)?;
                let (f, k) = self.file_arg(&args[0])?;
                if k != FileKind::Text {
                    return self.error(code::BAD_FILE_TYPE, args[0].value.span);
                }
                self.io_call(if b == Builtin::Append { "ODIN_TEXT_APPEND" } else { "ODIN_TEXT_FLUSH" }, vec![f], span)
            }
            Builtin::Close | Builtin::Erase | Builtin::Truncate => {
                self.arg_count(args, 1, 1, span)?;
                let (f, k) = self.file_arg(&args[0])?;
                let name = match (b, k) {
                    (Builtin::Close, FileKind::Text) => "ODIN_TEXT_CLOSE",
                    (Builtin::Close, _) => "ODIN_FILE_CLOSE",
                    (Builtin::Erase, FileKind::Text) => "ODIN_TEXT_ERASE",
                    (Builtin::Erase, _) => "ODIN_FILE_ERASE",
                    (_, FileKind::Text) => return self.error(code::BAD_FILE_TYPE, args[0].value.span),
                    _ => "ODIN_FILE_TRUNCATE",
                };
                self.io_call(name, vec![f], span)
            }
            Builtin::Seek => {
                self.arg_count(args, 2, 2, span)?;
                let (f, k) = self.file_arg(&args[0])?;
                if k == FileKind::Text {
                    return self.error(code::BAD_FILE_TYPE, args[0].value.span);
                }
                let n = self.value_arg(&args[1], bt.int64)?;
                self.io_call("ODIN_FILE_SEEK", vec![f, n], span)
            }
            Builtin::BlockRead | Builtin::BlockWrite => {
                self.arg_count(args, 3, 4, span)?;
                let (f, k) = self.file_arg(&args[0])?;
                if k != FileKind::Untyped {
                    return self.error(code::BAD_FILE_TYPE, args[0].value.span);
                }
                let buf = self.expr(&args[1].value)?;
                if !buf.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, args[1].value.span);
                }
                let count = self.value_arg(&args[2], bt.int64)?;
                // -1 tells the RTL that no result variable was given.
                let temp = self.add_temp(bt.longint);
                let temp_expr = self.var_expr(temp, bt.longint, span);
                let mut stmts = vec![stmt(
                    StmtKind::Assign {
                        target: temp_expr.clone(),
                        value: self.int_const(if args.len() == 4 { 0 } else { -1 }, bt.longint, span),
                    },
                    span,
                )];
                let name = if b == Builtin::BlockRead { "ODIN_FILE_BLOCKREAD" } else { "ODIN_FILE_BLOCKWRITE" };
                stmts.push(stmt(
                    StmtKind::Call(self.rtl_call(name, vec![f, buf, count, temp_expr.clone()], span)?),
                    span,
                ));
                if let Some(a) = args.get(3) {
                    let target = self.expr(&a.value)?;
                    if !target.is_lvalue() || self.class(target.ty) != Class::Int {
                        return self.error(code::INTEGER_VAR_EXPECTED, a.value.span);
                    }
                    stmts.push(stmt(StmtKind::Assign { target, value: temp_expr }, span));
                }
                self.io_check(&mut stmts, span)?;
                Ok(vec![stmt(StmtKind::Block(stmts), span)])
            }
            _ => unreachable!(),
        }
    }

    fn file_function(&mut self, b: Builtin, args: &[ast::Arg], span: Span) -> SResult<Expr> {
        self.arg_count(args, 0, 1, span)?;
        let (f, k) = match args.first() {
            Some(a) => self.file_arg(a)?,
            None if matches!(b, Builtin::FilePos | Builtin::FileSize) => {
                return self.error(code::WRONG_ARG_COUNT, span);
            }
            None => (self.rtl_var("INPUT", span)?, FileKind::Text),
        };
        let name = match (b, k) {
            (Builtin::Eof, FileKind::Text) => "ODIN_TEXT_EOF",
            (Builtin::Eof, _) => "ODIN_FILE_EOF",
            (Builtin::Eoln, FileKind::Text) => "ODIN_TEXT_EOLN",
            (Builtin::SeekEof, FileKind::Text) => "ODIN_TEXT_SEEKEOF",
            (Builtin::SeekEoln, FileKind::Text) => "ODIN_TEXT_SEEKEOLN",
            (Builtin::FilePos, FileKind::Typed(_) | FileKind::Untyped) => "ODIN_FILE_POS",
            (Builtin::FileSize, FileKind::Typed(_) | FileKind::Untyped) => "ODIN_FILE_SIZE",
            _ => return self.error(code::BAD_FILE_TYPE, span),
        };
        self.rtl_call(name, vec![f], span)
    }

    /// Makes an lvalue safe to evaluate twice: anything but a plain
    /// variable is replaced by a dereferenced temporary pointer.
    pub(crate) fn stable_lvalue(&mut self, lv: Expr, stmts: &mut Vec<Stmt>, span: Span) -> Expr {
        if matches!(lv.kind, ExprKind::Var(_)) {
            return lv;
        }
        let ty = lv.ty;
        let pty = self.pointer_to(ty);
        let temp = self.add_temp(pty);
        let addr = Expr::new(ExprKind::AddrOf(Box::new(lv)), pty, span);
        stmts.push(stmt(StmtKind::Assign { target: self.var_expr(temp, pty, span), value: addr }, span));
        Expr::new(ExprKind::Deref(Box::new(self.var_expr(temp, pty, span))), ty, span)
    }

    fn io_check(&self, stmts: &mut Vec<Stmt>, span: Span) -> SResult<()> {
        if self.sw.get(Switches::IO) {
            let call = self.rtl_call("ODIN_IOCHECK", Vec::new(), span)?;
            stmts.push(stmt(StmtKind::Call(call), span));
        }
        Ok(())
    }

    /// Splits off a leading file argument; without one the file is the
    /// System variable `default` (Input or Output).
    #[allow(clippy::type_complexity)]
    fn text_file<'a>(
        &mut self,
        args: &'a [ast::Arg],
        default: &str,
        span: Span,
    ) -> SResult<(Expr, FileKind, Vec<(Expr, &'a ast::Arg)>)> {
        let mut values = Vec::new();
        for a in args {
            values.push((self.expr(&a.value)?, a));
        }
        if let Some((first, a)) = values.first()
            && a.width.is_none()
            && first.is_lvalue()
            && let Some(kind) = self.file_kind(first.ty)
        {
            let (f, _) = values.remove(0);
            return Ok((f, kind, values));
        }
        Ok((self.rtl_var(default, span)?, FileKind::Text, values))
    }

    /// Write/Read of a typed file: one record per value.
    fn typed_transfer(
        &mut self,
        file: Expr,
        elem: TypeId,
        values: Vec<(Expr, &ast::Arg)>,
        write: bool,
        span: Span,
    ) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        let size = self.types.size(elem) as i64;
        let mut stmts = Vec::new();
        for (v, a) in values {
            if a.width.is_some() {
                return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
            }
            let s = a.value.span;
            let v = if write {
                let v = self.coerce(v, elem, s)?;
                if v.is_lvalue() && v.ty == elem {
                    v
                } else {
                    // A value that is not a variable goes through a temporary.
                    let temp = self.add_temp(elem);
                    let t = self.var_expr(temp, elem, s);
                    stmts.push(stmt(StmtKind::Assign { target: t.clone(), value: v }, s));
                    t
                }
            } else {
                if !v.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, s);
                }
                let compatible = v.ty == elem
                    || (self.types.is_ordinal(v.ty)
                        && self.types.base(v.ty) == self.types.base(elem)
                        && self.types.size(v.ty) == self.types.size(elem));
                if !compatible {
                    return self.error(code::TYPE_MISMATCH, s);
                }
                v
            };
            let n = self.int_const(size, bt.longint, s);
            let name = if write { "ODIN_FILE_WRITE" } else { "ODIN_FILE_READ" };
            stmts.push(stmt(StmtKind::Call(self.rtl_call(name, vec![file.clone(), v, n], s)?), s));
            self.io_check(&mut stmts, span)?;
        }
        Ok(vec![stmt(StmtKind::Block(stmts), span)])
    }

    fn write(&mut self, args: &[ast::Arg], newline: bool, span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        let (file, kind, values) = self.text_file(args, "OUTPUT", span)?;
        match kind {
            FileKind::Text => {}
            FileKind::Typed(elem) if !newline => return self.typed_transfer(file, elem, values, true, span),
            _ => return self.error(code::BAD_FILE_TYPE, args[0].value.span),
        }
        let mut stmts = Vec::new();
        for (v, a) in values {
            let width = match &a.width {
                Some(w) => {
                    let w = self.expr(w)?;
                    if self.class(w.ty) != Class::Int {
                        return self.error(code::INTEGER_EXPR_EXPECTED, w.span);
                    }
                    w
                }
                None => self.int_const(if self.class(v.ty) == Class::Real { -1 } else { 0 }, bt.longint, span),
            };
            let class = self.class(v.ty);
            if a.decimals.is_some() && class != Class::Real {
                return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
            }
            let call = match class {
                Class::Int => self.rtl_call("ODIN_WRITE_INT", vec![file.clone(), v, width], a.value.span)?,
                Class::Char => self.rtl_call("ODIN_WRITE_CHAR", vec![file.clone(), v, width], a.value.span)?,
                Class::Bool => self.rtl_call("ODIN_WRITE_BOOL", vec![file.clone(), v, width], a.value.span)?,
                Class::Str => self.rtl_call("ODIN_WRITE_STR", vec![file.clone(), v, width], a.value.span)?,
                Class::Ptr if self.is_pchar(v.ty) => {
                    self.rtl_call("ODIN_WRITE_PCHAR", vec![file.clone(), v, width], a.value.span)?
                }
                _ if matches!(self.types.get(v.ty), Type::Array { elem, .. } if *elem == bt.char) && v.is_lvalue() => {
                    let Type::Array { lo, hi, .. } = *self.types.get(v.ty) else { unreachable!() };
                    let len = self.int_const(hi - lo + 1, bt.longint, span);
                    let zero = self.int_const((lo == 0) as i64, bt.boolean, span);
                    self.rtl_call("ODIN_WRITE_CHARS", vec![file.clone(), v, len, zero, width], a.value.span)?
                }
                Class::Real => {
                    let decimals = match &a.decimals {
                        Some(d) => {
                            let d = self.expr(d)?;
                            if self.class(d.ty) != Class::Int {
                                return self.error(code::INTEGER_EXPR_EXPECTED, d.span);
                            }
                            d
                        }
                        None => self.int_const(-1, bt.longint, span),
                    };
                    self.rtl_call("ODIN_WRITE_REAL", vec![file.clone(), v, width, decimals], a.value.span)?
                }
                _ => return self.error(code::CANNOT_READ_WRITE, a.value.span),
            };
            stmts.push(stmt(StmtKind::Call(call), a.value.span));
            self.io_check(&mut stmts, span)?;
        }
        if newline {
            let call = self.rtl_call("ODIN_WRITELN", vec![file], span)?;
            stmts.push(stmt(StmtKind::Call(call), span));
            self.io_check(&mut stmts, span)?;
        } else {
            let call = self.rtl_call("ODIN_WRITE_END", vec![file], span)?;
            stmts.push(stmt(StmtKind::Call(call), span));
        }
        Ok(vec![stmt(StmtKind::Block(stmts), span)])
    }

    fn read(&mut self, args: &[ast::Arg], newline: bool, span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        let (file, kind, values) = self.text_file(args, "INPUT", span)?;
        match kind {
            FileKind::Text => {}
            FileKind::Typed(elem) if !newline => return self.typed_transfer(file, elem, values, false, span),
            _ => return self.error(code::BAD_FILE_TYPE, args[0].value.span),
        }
        let mut stmts = Vec::new();
        for (target, a) in values {
            if a.width.is_some() {
                return self.error(code::BAD_FORMAT_SPECIFIER, a.value.span);
            }
            if !target.is_lvalue() {
                return self.error(code::VAR_IDENT_EXPECTED, a.value.span);
            }
            let s = a.value.span;
            match self.class(target.ty) {
                Class::Int | Class::Char | Class::Real => {
                    let name = match self.class(target.ty) {
                        Class::Int => "ODIN_READ_INT",
                        Class::Char => "ODIN_READ_CHAR",
                        _ => "ODIN_READ_REAL",
                    };
                    let value = self.rtl_call(name, vec![file.clone()], s)?;
                    let value = self.coerce(value, target.ty, s)?;
                    stmts.push(stmt(StmtKind::Assign { target, value }, s));
                }
                Class::Str => {
                    let Type::ShortString(max) = self.types.get(target.ty).clone() else { unreachable!() };
                    let max = self.int_const(max as i64, bt.longint, s);
                    let call = self.rtl_call("ODIN_READ_STR", vec![file.clone(), target, max], s)?;
                    stmts.push(stmt(StmtKind::Call(call), s));
                }
                _ => return self.error(code::CANNOT_READ_WRITE, s),
            }
            self.io_check(&mut stmts, span)?;
        }
        if newline {
            let call = self.rtl_call("ODIN_READLN", vec![file], span)?;
            stmts.push(stmt(StmtKind::Call(call), span));
            self.io_check(&mut stmts, span)?;
        }
        Ok(vec![stmt(StmtKind::Block(stmts), span)])
    }

    fn inc_dec(&mut self, args: &[ast::Arg], inc: bool, span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        self.arg_count(args, 1, 2, span)?;
        let x = self.expr(&args[0].value)?;
        if !x.is_lvalue() {
            return self.error(code::VAR_IDENT_EXPECTED, args[0].value.span);
        }
        let amount = match args.get(1) {
            Some(a) => {
                let n = self.expr(&a.value)?;
                if self.class(n.ty) != Class::Int {
                    return self.error(code::INTEGER_EXPR_EXPECTED, a.value.span);
                }
                n
            }
            None => self.int_const(1, bt.longint, span),
        };
        let mut stmts = Vec::new();
        let checked = self.sw.get(Switches::OVERFLOW);
        let op = match (inc, checked) {
            (true, false) => BinOp::Add,
            (false, false) => BinOp::Sub,
            (true, true) => BinOp::AddChecked,
            (false, true) => BinOp::SubChecked,
        };
        match self.types.get(x.ty).clone() {
            Type::Pointer(Some(target)) => {
                let size = self.types.size(target) as i64;
                let target_lv = self.stable_lvalue(x, &mut stmts, span);
                let step = self.int_const(size, bt.int64, span);
                let scaled = Expr::new(ExprKind::Binary(BinOp::Mul, Box::new(amount), Box::new(step)), bt.int64, span);
                let as_int = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(target_lv.clone())), bt.int64, span);
                let sum = Expr::new(ExprKind::Binary(op, Box::new(as_int), Box::new(scaled)), bt.int64, span);
                let value = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(sum)), target_lv.ty, span);
                stmts.push(stmt(StmtKind::Assign { target: target_lv, value }, span));
            }
            _ if self.types.is_ordinal(x.ty) => {
                let ty = x.ty;
                let target_lv = self.stable_lvalue(x, &mut stmts, span);
                let sum =
                    Expr::new(ExprKind::Binary(op, Box::new(target_lv.clone()), Box::new(amount)), bt.int64, span);
                let value = if self.sw.get(Switches::RANGE) {
                    let (lo, hi) = self.types.bounds(ty);
                    Expr::new(ExprKind::Convert(Conv::RangeCheck { lo, hi }, Box::new(sum)), ty, span)
                } else {
                    sum
                };
                stmts.push(stmt(StmtKind::Assign { target: target_lv, value }, span));
            }
            _ => return self.error(code::ORDINAL_VAR_EXPECTED, args[0].value.span),
        }
        Ok(vec![stmt(StmtKind::Block(stmts), span)])
    }

    fn str_proc(&mut self, args: &[ast::Arg], span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        if args.len() != 2 {
            return self.error(code::WRONG_ARG_COUNT, span);
        }
        let v = self.numeric_arg(&args[0])?;
        let mut target = self.expr(&args[1].value)?;
        if !target.is_lvalue() {
            return self.error(code::STRING_VAR_EXPECTED, args[1].value.span);
        }
        // An array of Char receives the digits through a string temporary,
        // without a terminating #0.
        let mut chars = None;
        if let Type::Array { lo, hi, elem, .. } = *self.types.get(target.ty)
            && elem == bt.char
        {
            let temp = self.add_temp(bt.string);
            chars = Some((target, hi - lo + 1));
            target = self.var_expr(temp, bt.string, span);
        }
        let Type::ShortString(max) = self.types.get(target.ty).clone() else {
            return self.error(code::STRING_VAR_EXPECTED, args[1].value.span);
        };
        let width = match &args[0].width {
            Some(w) => self.expr(w)?,
            None => self.int_const(if self.class(v.ty) == Class::Real { -1 } else { 0 }, bt.longint, span),
        };
        let max = self.int_const(max as i64, bt.longint, span);
        let call = if self.class(v.ty) == Class::Int {
            if args[0].decimals.is_some() {
                return self.error(code::BAD_FORMAT_SPECIFIER, args[0].value.span);
            }
            self.rtl_call("ODIN_STR_INT", vec![v, width, target.clone(), max], span)?
        } else {
            let decimals = match &args[0].decimals {
                Some(d) => self.expr(d)?,
                None => self.int_const(-1, bt.longint, span),
            };
            self.rtl_call("ODIN_STR_REAL", vec![v, width, decimals, target.clone(), max], span)?
        };
        let mut stmts = vec![stmt(StmtKind::Call(call), span)];
        if let Some((array, len)) = chars {
            let len = self.int_const(len, bt.longint, span);
            let copy = self.rtl_call("ODIN_STR_TO_CHARS", vec![target, array, len], span)?;
            stmts.push(stmt(StmtKind::Call(copy), span));
        }
        Ok(stmts)
    }

    fn val_proc(&mut self, args: &[ast::Arg], span: Span) -> SResult<Vec<Stmt>> {
        let bt = self.types.builtin;
        self.arg_count(args, 3, 3, span)?;
        let s = self.expr(&args[0].value)?;
        let s = self.coerce(s, bt.string, args[0].value.span)?;
        let target = self.expr(&args[1].value)?;
        let code_var = self.expr(&args[2].value)?;
        if !target.is_lvalue() || !code_var.is_lvalue() || self.class(code_var.ty) != Class::Int {
            return self.error(code::VAR_IDENT_EXPECTED, args[1].value.span);
        }
        let temp = self.add_temp(bt.longint);
        let temp_expr = self.var_expr(temp, bt.longint, span);
        let name = match self.class(target.ty) {
            Class::Int => "ODIN_VAL_INT",
            Class::Real => "ODIN_VAL_REAL",
            _ => return self.error(code::INT_OR_REAL_VAR_EXPECTED, args[1].value.span),
        };
        let value = self.rtl_call(name, vec![s, temp_expr.clone()], span)?;
        // Out-of-range results set the error code instead of failing.
        let value = match self.class(target.ty) {
            Class::Int => Expr::new(ExprKind::Convert(Conv::Resize, Box::new(value)), target.ty, span),
            _ => value,
        };
        let mut stmts = vec![stmt(StmtKind::Assign { target, value }, span)];
        stmts.push(stmt(StmtKind::Assign { target: code_var, value: temp_expr }, span));
        Ok(vec![stmt(StmtKind::Block(stmts), span)])
    }
}
