// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Tests of the AArch64 encoder API: branch relaxation, label offsets,
//! relocations, alignment, the helpers that expand into several
//! instructions (checked by running them on a tiny emulator), and error
//! handling. Single-instruction encodings are checked against clang in
//! `aarch64_golden.rs`.

use odin_asm::aarch64::{
    Assembler, Code, Cond, IndexExt, Label, LogicOp, Mem, Reg, SysReg, logical_imm, offset_is_direct, regs::*,
};
use odin_asm::{RelocKind, SectionKind};

fn finish(a: Assembler) -> Code {
    a.finish().unwrap_or_else(|e| panic!("{e}"))
}

fn words(code: &Code) -> Vec<u32> {
    code.bytes.chunks(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).collect()
}

fn sext(v: u32, bits: u32) -> i64 {
    ((v as i64) << (64 - bits)) >> (64 - bits)
}

/// Decodes the branch at byte offset `at`: returns (length in bytes,
/// target offset), following a relaxed pair (inverted branch over `b`).
fn decode_branch(code: &Code, at: usize) -> (usize, i64) {
    let w = |i: usize| u32::from_le_bytes(code.bytes[i..i + 4].try_into().unwrap());
    let word = w(at);
    let here = at as i64;
    let (disp, conditional) = match word {
        _ if word & 0x7C00_0000 == 0x1400_0000 => (sext(word & 0x03ff_ffff, 26) * 4, false),
        _ if word & 0xFF00_0010 == 0x5400_0000 => (sext((word >> 5) & 0x7_ffff, 19) * 4, true),
        _ if word & 0x7E00_0000 == 0x3400_0000 => (sext((word >> 5) & 0x7_ffff, 19) * 4, true),
        _ if word & 0x7E00_0000 == 0x3600_0000 => (sext((word >> 5) & 0x3fff, 14) * 4, true),
        _ => panic!("no branch at {at:#x}: {word:#010x}"),
    };
    // A conditional branch skipping exactly one `b` is a relaxed pair.
    if conditional && disp == 8 && w(at + 4) & 0xFC00_0000 == 0x1400_0000 {
        let b = w(at + 4);
        return (8, here + 4 + sext(b & 0x03ff_ffff, 26) * 4);
    }
    (4, here + disp)
}

#[test]
fn short_branches_and_label_offsets() {
    let mut a = Assembler::new();
    let top = a.here();
    let done = a.new_label();
    a.add(W0, W0, 1);
    a.cmp(W0, 10);
    a.b_cond(Cond::Lt, top);
    a.cbz(X1, done);
    a.tbnz(X3, 63, done);
    a.b(top);
    a.bind(done);
    a.ret();
    let code = finish(a);
    // The same words clang produces for `_short_branches` (minus a few).
    assert_eq!(words(&code), [0x11000400, 0x7100281f, 0x54ffffcb, 0xb4000061, 0xb7f80043, 0x17fffffb, 0xd65f03c0]);
    assert_eq!(code.label_offset(top), Some(0));
    assert_eq!(code.label_offset(done), Some(24));
    assert!(code.relocs.is_empty());
    assert_eq!(code.align, 4);
}

#[test]
fn conditional_branch_range_boundaries() {
    // b.cond: +1 MiB - 4 fits, +1 MiB does not; -1 MiB fits, -1 MiB - 4
    // does not. Same for cbz. tbz: +32764 / -32768.
    for (bits, max) in [(19u8, (1i64 << 20) - 4), (14, (1 << 15) - 4)] {
        for (fill, relaxed) in [(max - 4, false), (max, true)] {
            let mut a = Assembler::new();
            let l = a.new_label();
            if bits == 19 {
                a.b_cond(Cond::Eq, l);
            } else {
                a.tbz(W0, 5, l);
            }
            a.bytes(&vec![0; fill as usize]);
            a.bind(l);
            let code = finish(a);
            let target = code.label_offset(l).unwrap() as i64;
            assert_eq!(decode_branch(&code, 0), (if relaxed { 8 } else { 4 }, target), "bits {bits} fill {fill}");
        }
        for (fill, relaxed) in [(max + 4, false), (max + 8, true)] {
            let mut a = Assembler::new();
            let l = a.here();
            a.bytes(&vec![0; fill as usize]);
            if bits == 19 {
                a.cbnz(X0, l);
            } else {
                a.tbnz(X0, 33, l);
            }
            let code = finish(a);
            assert_eq!(
                decode_branch(&code, fill as usize),
                (if relaxed { 8 } else { 4 }, 0),
                "bits {bits} back {fill}"
            );
        }
    }
}

#[test]
fn relaxed_forms_invert_the_condition() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.b_cond(Cond::Hs, far);
    a.cbz(W2, far);
    a.cbnz(X3, far);
    a.tbz(X4, 40, far);
    a.tbnz(W5, 3, far);
    a.b_cond(Cond::Al, far);
    a.bytes(&vec![0; 1 << 21]);
    a.bind(far);
    let code = finish(a);
    let w = words(&code);
    // inverted condition, skip +8 (imm = 2), register / bit kept.
    assert_eq!(w[0], 0x5400_0043); // b.lo +8
    assert_eq!(w[2], 0x3500_0042); // cbnz w2, +8
    assert_eq!(w[4], 0xb400_0043); // cbz x3, +8
    assert_eq!(w[6], 0xb740_0044); // tbnz x4, #40, +8
    assert_eq!(w[8], 0x3618_0045); // tbz w5, #3, +8
    // b.al becomes a single `b`.
    assert_eq!(w[10] & 0xFC00_0000, 0x1400_0000);
    let target = code.label_offset(far).unwrap() as i64;
    for at in [0, 8, 16, 24, 32, 40] {
        assert_eq!(decode_branch(&code, at).1, target);
    }
    assert_eq!(target, 44 + (1 << 21));
}

#[test]
fn growth_cascades_over_several_passes() {
    // The second tbz is out of range; relaxing it pushes the first out.
    let mut a = Assembler::new();
    let (la, lb) = (a.new_label(), a.new_label());
    a.tbz(W0, 0, la);
    a.tbz(W0, 1, lb);
    a.bytes(&vec![0; 32756]);
    a.bind(la);
    a.bytes(&[0; 8]);
    a.bind(lb);
    let code = finish(a);
    assert_eq!(decode_branch(&code, 0), (8, code.label_offset(la).unwrap() as i64));
    assert_eq!(decode_branch(&code, 8), (8, code.label_offset(lb).unwrap() as i64));
    assert_eq!(code.label_offset(la), Some(16 + 32756));
}

#[test]
fn many_branches_resolve_to_their_labels() {
    // A deterministic jumble of forward and backward branches of all
    // kinds, checked by decoding every one in the final code.
    let mut a = Assembler::new();
    let targets: Vec<Label> = (0..80).map(|_| a.new_label()).collect();
    let mut branches = Vec::new();
    let mut seed = 12345u32;
    let mut next = |n: u32| {
        seed = seed.wrapping_mul(1103515245).wrapping_add(12345);
        (seed >> 16) % n
    };
    for (i, &t) in targets.iter().enumerate() {
        a.bind(t);
        for _ in 0..4 {
            let near = (i as i64 + next(5) as i64 - 2).clamp(0, targets.len() as i64 - 1) as usize;
            let target = if next(4) == 0 { targets[next(targets.len() as u32) as usize] } else { targets[near] };
            let at = a.here();
            match next(5) {
                0 => a.b(target),
                1 => a.b_cond(Cond::ALL[next(14) as usize], target),
                2 => a.cbz(X7, target),
                3 => a.cbnz(W9, target),
                _ => a.tbz(X1, next(64) as u8, target),
            }
            branches.push((at, target));
            let filler = next(if i % 9 == 0 { 9000 } else { 300 }) as usize * 4;
            a.bytes(&vec![0; filler]);
        }
    }
    let code = finish(a);
    let (mut short, mut long) = (0, 0);
    for (at, target) in branches {
        let (len, dest) = decode_branch(&code, code.label_offset(at).unwrap() as usize);
        assert_eq!(dest, code.label_offset(target).unwrap() as i64);
        if len == 4 { short += 1 } else { long += 1 }
    }
    assert!(short > 50 && long > 20, "{short} short, {long} long");
}

#[test]
fn label_fixups_adr_literal_and_diff32() {
    let mut a = Assembler::new();
    let (data, table, case1) = (a.new_label(), a.new_label(), a.new_label());
    a.adr(X0, data, 0); // 0
    a.adr(X1, data, 4); // 4
    a.ldr(D0, Mem::label(data)); // 8
    a.ldrsw(X2, Mem::label_plus(data, 4)); // 12
    a.bl(case1); // 16
    a.bind(case1);
    a.ret(); // 20
    a.bind(table);
    a.diff32(case1, table); // 24
    a.bind(data);
    a.bytes(&[1, 2, 3, 4, 5, 6, 7, 8]); // 28
    let code = finish(a);
    let w = words(&code);
    let adr = |w: u32| sext((w >> 5 & 0x7ffff) << 2 | (w >> 29 & 3), 21);
    assert_eq!(adr(w[0]), 28);
    assert_eq!(adr(w[1]), 32 - 4);
    assert_eq!(sext(w[2] >> 5 & 0x7ffff, 19) * 4, 20);
    assert_eq!(w[2] & 0xff00_001f, 0x5c00_0000);
    assert_eq!(sext(w[3] >> 5 & 0x7ffff, 19) * 4, 32 - 12);
    assert_eq!(w[4], 0x9400_0001);
    assert_eq!(w[6] as i32, 20 - 24);
}

#[test]
fn symbol_relocations() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.cbz(X0, far); // relaxed to 8 bytes, moving everything after it
    a.bl("_f"); // 8
    a.b("_tail"); // 12
    a.load_address(X1, "_msg", 16); // 16, 20
    a.ldr(W2, Mem::page_off(X1, "_var", 4)); // 24
    a.strh(W2, Mem::page_off(X1, "_var", 2)); // 28
    a.load_got(X3, "_errno"); // 32, 36
    a.call_got("_write"); // 40, 44, 48
    a.abs64("_vmt", 24); // 52
    a.bytes(&vec![0; 1 << 20]);
    a.bind(far);
    let code = finish(a);
    let relocs: Vec<(u32, RelocKind, &str, i64)> =
        code.relocs.iter().map(|r| (r.offset, r.kind, r.target.as_str(), r.addend)).collect();
    use RelocKind::*;
    assert_eq!(
        relocs,
        [
            (8, Arm64Branch26, "_f", 0),
            (12, Arm64Branch26, "_tail", 0),
            (16, Arm64Page21, "_msg", 16),
            (20, Arm64PageOff12 { scale: 0 }, "_msg", 16),
            (24, Arm64PageOff12 { scale: 2 }, "_var", 4),
            (28, Arm64PageOff12 { scale: 1 }, "_var", 2),
            (32, Arm64GotPage21, "_errno", 0),
            (36, Arm64GotPageOff12, "_errno", 0),
            (40, Arm64GotPage21, "_write", 0),
            (44, Arm64GotPageOff12, "_write", 0),
            (52, Abs64, "_vmt", 24),
        ]
    );
    let w = words(&code);
    assert_eq!(
        &w[4..13],
        &[
            0x9000_0001, // adrp x1
            0x9100_0021, // add x1, x1
            0xb940_0022, // ldr w2, [x1]
            0x7900_0022, // strh w2, [x1]
            0x9000_0003, // adrp x3
            0xf940_0063, // ldr x3, [x3]
            0x9000_0010, // adrp x16
            0xf940_0210, // ldr x16, [x16]
            0xd63f_0200, // blr x16
        ]
    );
    // The relocated fields are left zero.
    assert_eq!(w[2], 0x9400_0000);
}

#[test]
fn symbol_memory_operand_goes_through_x16() {
    let mut a = Assembler::new();
    a.ldr(X0, Mem::sym("_v", 8));
    a.str(D1, Mem::sym("_w", 0));
    a.str(X16, Mem::sym("_w", 0)); // storing x16 itself: x17 holds the page
    let code = finish(a);
    assert_eq!(words(&code), [0x9000_0010, 0xf940_0200, 0x9000_0010, 0xfd00_0201, 0x9000_0011, 0xf900_0230]);
    let kinds: Vec<_> = code.relocs.iter().map(|r| (r.offset, r.kind, r.addend)).collect();
    assert_eq!(kinds[..2], [(0, RelocKind::Arm64Page21, 8), (4, RelocKind::Arm64PageOff12 { scale: 3 }, 8)]);
    assert_eq!(kinds[3], (12, RelocKind::Arm64PageOff12 { scale: 3 }, 0));
}

#[test]
fn alignment_padding_and_exports() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.cbz(X0, far); // 4 or 8 bytes: padding is settled after relaxation
    a.align(16);
    let top = a.here();
    a.export("_entry", top);
    a.ret();
    a.bytes(&[0xAA]);
    a.align(16);
    a.ret();
    a.bytes(&vec![0; 1 << 20]);
    a.bind(far);
    let code = finish(a);
    assert_eq!(code.align, 16);
    let w = words(&code);
    assert_eq!(&w[2..5], &[0xd503_201f, 0xd503_201f, 0xd65f_03c0]);
    assert_eq!(code.exports, [("_entry".to_string(), 16)]);
    // One byte of data at 20, then 3 zero bytes and two nops up to 32.
    assert_eq!(&code.bytes[20..24], &[0xAA, 0, 0, 0]);
    assert_eq!(&w[6..9], &[0xd503_201f, 0xd503_201f, 0xd65f_03c0]);
    let atom = code.into_atom("_f", 4);
    assert_eq!((atom.section, atom.align, atom.labels.clone()), (SectionKind::Text, 16, vec![("_entry".into(), 16)]));
}

// ----- an emulator for the expansion helpers ------------------------------

/// The general registers (x31 = sp) and NZCV of a tiny AArch64 subset:
/// move wide, logical immediate, add/sub (immediate, shifted and extended
/// register) and register-offset address computation.
struct Cpu {
    x: [u64; 32],
    nzcv: u8,
}

fn decode_logical(field: u32, bits: u32) -> u64 {
    // Brute force: the encoder is checked exhaustively in its unit tests;
    // here the field just has to round-trip through `logical_imm`.
    let mask = if bits == 64 { u64::MAX } else { 0xffff_ffff };
    for size in [2u32, 4, 8, 16, 32, 64] {
        if size > bits {
            break;
        }
        for ones in 1..size {
            for rot in 0..size {
                let emask = if size == 64 { u64::MAX } else { (1u64 << size) - 1 };
                let run = (1u64 << ones) - 1;
                let elem = if rot == 0 { run } else { ((run >> rot) | (run << (size - rot))) & emask };
                let v = (0..bits / size).fold(0, |acc, k| acc | elem << (k * size)) & mask;
                if logical_imm(v, bits) == Some(field) {
                    return v;
                }
            }
        }
    }
    panic!("bad logical immediate field {field:#x}")
}

impl Cpu {
    fn new() -> Cpu {
        let mut x = [0u64; 32];
        for (i, r) in x.iter_mut().enumerate() {
            *r = 0x1111_1111_1111_1111u64.wrapping_mul(i as u64 + 1);
        }
        Cpu { x, nzcv: 0 }
    }

    fn get(&self, n: u32, sp: bool) -> u64 {
        if n == 31 && !sp { 0 } else { self.x[n as usize] }
    }

    fn set(&mut self, n: u32, sp: bool, v: u64) {
        if n != 31 || sp {
            self.x[n as usize] = v;
        }
    }

    fn addsub(&mut self, a: u64, b: u64, sub: bool, flags: bool, sf: bool) -> u64 {
        let mask = if sf { u64::MAX } else { 0xffff_ffff };
        let bits = if sf { 64 } else { 32 };
        let (a, b) = (a & mask, if sub { !b & mask } else { b & mask });
        let wide = a as u128 + b as u128 + sub as u128;
        let r = (wide as u64) & mask;
        if flags {
            let n = r >> (bits - 1) & 1;
            let z = (r == 0) as u64;
            let c = (wide >> bits) as u64 & 1;
            let sa = a >> (bits - 1) & 1;
            let sb = b >> (bits - 1) & 1;
            let v = (sa == sb && n != sa) as u64;
            self.nzcv = (n << 3 | z << 2 | c << 1 | v) as u8;
        }
        r
    }

    fn run(&mut self, code: &Code) {
        for w in words(code) {
            let sf = w >> 31 == 1;
            let mask = if sf { u64::MAX } else { 0xffff_ffff };
            let (rd, rn, rm) = (w & 31, w >> 5 & 31, w >> 16 & 31);
            if w & 0x1f80_0000 == 0x1280_0000 {
                let (opc, hw, imm) = (w >> 29 & 3, w >> 21 & 3, (w >> 5 & 0xffff) as u64);
                let v = match opc {
                    0 => !(imm << (16 * hw)),
                    2 => imm << (16 * hw),
                    3 => (self.get(rd, false) & !(0xffffu64 << (16 * hw))) | imm << (16 * hw),
                    _ => panic!("bad move wide {w:#x}"),
                };
                self.set(rd, false, v & mask);
            } else if w & 0x1f80_0000 == 0x1200_0000 {
                let v = decode_logical(w >> 10 & 0x1fff, if sf { 64 } else { 32 });
                let a = self.get(rn, false);
                let (r, sp) = match w >> 29 & 3 {
                    0 => (a & v, true),
                    1 => (a | v, true),
                    2 => (a ^ v, true),
                    _ => panic!("ands not emulated"),
                };
                self.set(rd, sp, r & mask);
            } else if w & 0x1f00_0000 == 0x1100_0000 {
                let imm = ((w >> 10 & 0xfff) as u64) << (12 * (w >> 22 & 1));
                let (sub, flags) = (w >> 30 & 1 == 1, w >> 29 & 1 == 1);
                let r = self.addsub(self.get(rn, true), imm, sub, flags, sf);
                self.set(rd, !flags, r);
            } else if w & 0x1f20_0000 == 0x0b00_0000 {
                assert_eq!(w >> 10 & 0x3f, 0, "shifted operands not emulated");
                let (sub, flags) = (w >> 30 & 1 == 1, w >> 29 & 1 == 1);
                let r = self.addsub(self.get(rn, false), self.get(rm, false), sub, flags, sf);
                self.set(rd, false, r);
            } else if w & 0x1f20_0000 == 0x0b20_0000 {
                assert!(matches!(w >> 13 & 7, 2 | 3) && w >> 10 & 7 == 0, "only uxtw/uxtx #0 emulated");
                let (sub, flags) = (w >> 30 & 1 == 1, w >> 29 & 1 == 1);
                let r = self.addsub(self.get(rn, true), self.get(rm, false), sub, flags, sf);
                self.set(rd, !flags, r);
            } else {
                panic!("instruction {w:#010x} is not emulated");
            }
        }
    }
}

fn values() -> Vec<i64> {
    let mut v = vec![
        0,
        1,
        -1,
        4095,
        4096,
        -4096,
        4097,
        0xfff000,
        -0xfff000,
        0x1000000,
        0xffffff,
        -0xffffff,
        0x12345,
        i64::MAX,
        i64::MIN,
        0x7fff_ffff,
        -0x8000_0000,
        0xffff_ffff,
        0x5555_5555_5555_5555,
        0x1234_5678_9abc_def0,
    ];
    let mut seed = 0x2545_f491_4f6c_dd1du64;
    for _ in 0..300 {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        v.push(seed as i64 >> (seed % 60));
    }
    v
}

#[test]
fn mov_imm_builds_every_value() {
    for v in values() {
        for rd in [X0, W0, X16, W17] {
            if !rd.is_64() && !(i32::MIN as i64..=u32::MAX as i64).contains(&v) {
                continue;
            }
            let mut a = Assembler::new();
            a.mov_imm(rd, v);
            let code = finish(a);
            let mut cpu = Cpu::new();
            cpu.run(&code);
            let want = if rd.is_64() { v as u64 } else { v as u64 & 0xffff_ffff };
            assert_eq!(cpu.x[rd.index() as usize], want, "mov_imm {rd}, {v:#x}");
            assert!(code.bytes.len() <= if rd.is_64() { 16 } else { 8 });
        }
    }
}

#[test]
fn add_const_and_cmp_const_compute_the_right_thing() {
    for v in values() {
        for (rd, rn) in [(X0, X1), (SP, SP), (X2, SP), (SP, X3), (X16, X16), (W4, W5)] {
            if !rd.is_64() && !(i32::MIN as i64..=u32::MAX as i64).contains(&v) {
                continue;
            }
            let mut a = Assembler::new();
            a.add_const(rd, rn, v);
            let code = finish(a);
            let mut cpu = Cpu::new();
            let before = cpu.x;
            cpu.run(&code);
            let want = before[rn.index() as usize].wrapping_add(v as u64);
            let want = if rd.is_64() { want } else { want & 0xffff_ffff };
            assert_eq!(cpu.x[rd.index() as usize], want, "add_const {rd}, {rn}, {v:#x}");
            // Only rd and the scratch register may change.
            let scratch = if rn.same(X16) { 17 } else { 16 };
            for (i, (now, was)) in cpu.x.iter().zip(before).enumerate() {
                if i != rd.index() as usize && i != scratch {
                    assert_eq!(*now, was, "add_const {rd}, {rn}, {v:#x} changed x{i}");
                }
            }
            let small = v.unsigned_abs() < 1 << 24;
            assert!(code.bytes.len() <= if small { 8 } else { 20 }, "{v:#x}: {} bytes", code.bytes.len());
        }
        for rn in [X1, W1, SP] {
            if !rn.is_64() && !(i32::MIN as i64..=u32::MAX as i64).contains(&v) {
                continue;
            }
            let mut a = Assembler::new();
            a.cmp_const(rn, v);
            let code = finish(a);
            let mut cpu = Cpu::new();
            let x = cpu.x[rn.index() as usize];
            cpu.run(&code);
            let mut reference = Cpu::new();
            reference.addsub(x, v as u64, true, true, rn.is_64());
            assert_eq!(cpu.nzcv, reference.nzcv, "cmp_const {rn}, {v:#x}");
        }
    }
}

#[test]
fn logical_const_and_scratch_use() {
    for v in values() {
        let mut a = Assembler::new();
        a.logical_const(LogicOp::Eor, X0, X1, v);
        let code = finish(a);
        let mut cpu = Cpu::new();
        let x1 = cpu.x[1];
        if logical_imm(v as u64, 64).is_some() {
            assert_eq!(code.bytes.len(), 4);
            cpu.run(&code);
            assert_eq!(cpu.x[0], x1 ^ v as u64);
        } else {
            // mov_imm into x16, then `eor x0, x1, x16`.
            let w = words(&code);
            assert_eq!(*w.last().unwrap(), 0xca10_0020);
        }
    }
}

#[test]
fn out_of_range_offsets_expand_through_scratch() {
    let mut a = Assembler::new();
    a.ldr(X0, Mem::base(X1, 32768)); // scaled limit is 32760
    a.str(W2, Mem::base(X16, -257)); // base x16: scratch x17
    a.ldrb(W3, Mem::base(SP, 4096));
    a.ldp(X4, X5, Mem::base(X29, 1024)); // pair limit is 504
    a.stp(X16, X6, Mem::base(SP, -520)); // storing x16: scratch x17
    let code = finish(a);
    let w = words(&code);
    assert_eq!(
        w,
        [
            0xd290_0010, // mov x16, #32768
            0xf870_6820, // ldr x0, [x1, x16]
            0x9280_2011, // mov x17, #-257
            0xb831_6a02, // str w2, [x16, x17]
            0xd282_0010, // mov x16, #4096
            0x3870_6be3, // ldrb w3, [sp, x16]
            0x9110_03b0, // add x16, x29, #1024
            0xa940_1604, // ldp x4, x5, [x16]
            0xd108_23f1, // sub x17, sp, #520
            0xa900_1a30, // stp x16, x6, [x17]
        ]
    );
}

// ----- errors ---------------------------------------------------------------

/// An expected error message fragment and the code that should produce it.
type Case = (&'static str, Box<dyn FnOnce(&mut Assembler)>);

fn error_of(f: impl FnOnce(&mut Assembler)) -> String {
    let mut a = Assembler::new();
    f(&mut a);
    a.finish().expect_err("expected an encoding error").message
}

#[test]
fn unencodable_operands_are_errors() {
    let cases: Vec<Case> = vec![
        ("not a valid bitmask", Box::new(|a| a.and(X0, X1, 5))),
        ("not a valid bitmask", Box::new(|a| a.orr(W0, W1, 0))),
        ("not a valid bitmask", Box::new(|a| a.eor(X0, X1, -1))),
        ("does not fit in 32 bits", Box::new(|a| a.and(W0, W1, 0x1_0000_0000i64))),
        ("not 0 to 4095", Box::new(|a| a.add(X0, X1, 4097))),
        ("not 0 to 4095", Box::new(|a| a.cmp(X0, 0x100_0000))),
        ("needs 2 instructions", Box::new(|a| a.mov(X0, 0x12345))),
        ("shift amount 32", Box::new(|a| a.add(W0, W1, W2.lsl(32)))),
        ("`ror` is not allowed", Box::new(|a| a.add(X0, X1, X2.ror(1)))),
        ("extend amount 5", Box::new(|a| a.add(X0, X1, W2.sxtw(5)))),
        ("must be a W register", Box::new(|a| a.add(X0, X1, X2.sxtw(0)))),
        ("all be W or all be X", Box::new(|a| a.add(X0, W1, X2))),
        ("all be S or all be D", Box::new(|a| a.fadd(D0, S1, D2))),
        ("differ in size", Box::new(|a| a.fmov(D0, W1))),
        ("cannot be encoded as an 8-bit", Box::new(|a| a.fmov_imm(D0, 0.1))),
        ("shift amount 64", Box::new(|a| a.lsl(X0, X1, 64))),
        ("does not fit in 32 bits", Box::new(|a| a.ubfx(W0, W1, 30, 4))),
        (
            "bit 32 is out of range",
            Box::new(|a| {
                let l = a.new_label();
                a.tbz(W0, 32, l)
            }),
        ),
        ("condition `al` is not allowed", Box::new(|a| a.cset(X0, Cond::Al))),
        ("flags #16", Box::new(|a| a.ccmp(X0, 1, 16, Cond::Eq))),
        ("immediate 32 is out of range", Box::new(|a| a.ccmp(X0, 32, 0, Cond::Eq))),
        ("offset 256 is out of range", Box::new(|a| a.ldr(X0, Mem::pre(X1, 256)))),
        ("offset 256 is out of range", Box::new(|a| a.ldur(X0, X1, 256))),
        ("offset 4 is out of range", Box::new(|a| a.ldp(X0, X1, Mem::pre(SP, 4)))),
        ("offset 512 is out of range", Box::new(|a| a.stp(X0, X1, Mem::post(SP, 512)))),
        ("loading `x0` twice", Box::new(|a| a.ldp(X0, X0, Mem::base(SP, 0)))),
        ("both the transfer register and the written-back base", Box::new(|a| a.ldr(X1, Mem::post(X1, 8)))),
        ("written-back base", Box::new(|a| a.stp(X29, X30, Mem::pre(X29, -16)))),
        ("must be a 32-bit (W)", Box::new(|a| a.ldrb(X0, Mem::base(X1, 0)))),
        ("must be a 64-bit (X)", Box::new(|a| a.ldrsw(W0, Mem::base(X1, 0)))),
        ("address base `w1`", Box::new(|a| a.ldr(X0, Mem::base(W1, 0)))),
        ("index `x2` must be a W register", Box::new(|a| a.ldr(X0, Mem::index_ext(X1, X2, IndexExt::Sxtw, false)))),
        ("GOT slot", Box::new(|a| a.ldr(W0, Mem::got_page_off(X1, "_x")))),
        (
            "cannot store to a literal",
            Box::new(|a| {
                let l = a.here();
                a.str(X0, Mem::label(l))
            }),
        ),
        (
            "only `ldr`",
            Box::new(|a| {
                let l = a.here();
                a.ldrb(W0, Mem::label(l))
            }),
        ),
        ("must be a 64-bit (X)", Box::new(|a| a.br(W0))),
        ("must be a 64-bit (X)", Box::new(|a| a.mrs(W0, SysReg::Nzcv))),
        ("same", Box::new(|a| a.fcvt(D0, D1))),
        ("use mov", Box::new(|a| a.fmov(X0, X1))),
    ];
    for (want, f) in cases {
        let msg = error_of(f);
        assert!(msg.contains(want), "expected `{want}` in `{msg}`");
    }
}

#[test]
fn sp_and_zero_register_are_never_confused() {
    // Fields where 31 means the zero register reject sp, and vice versa.
    let cases: Vec<Case> = vec![
        ("register 31 means the zero register", Box::new(|a| a.add(X0, X1, SP))),
        ("register 31 means the zero register", Box::new(|a| a.adds(SP, X0, X1))),
        ("register 31 means the zero register", Box::new(|a| a.subs(SP, X0, 1))),
        ("register 31 means the zero register", Box::new(|a| a.mul(X0, SP, X1))),
        ("register 31 means the zero register", Box::new(|a| a.and(X0, SP, X1))),
        ("register 31 means the zero register", Box::new(|a| a.orr(X0, SP, 1))),
        ("register 31 means the zero register", Box::new(|a| a.ands(SP, X0, 1))),
        (
            "register 31 means the zero register",
            Box::new(|a| {
                let l = a.here();
                a.cbz(SP, l)
            }),
        ),
        ("register 31 means the zero register", Box::new(|a| a.ldr(SP, Mem::base(X0, 0)))),
        ("register 31 means the zero register", Box::new(|a| a.br(SP))),
        ("register 31 means the zero register", Box::new(|a| a.lsl(SP, X0, 1))),
        ("register 31 means the zero register", Box::new(|a| a.mov_imm(SP, 0x12345))),
        ("register 31 means the stack pointer", Box::new(|a| a.add(XZR, X0, 1))),
        ("register 31 means the stack pointer", Box::new(|a| a.add(X0, XZR, 1))),
        ("register 31 means the stack pointer", Box::new(|a| a.ldr(X0, Mem::base(XZR, 8)))),
        ("register 31 means the stack pointer", Box::new(|a| a.add(X0, XZR, W1.sxtw(0)))),
        ("register 31 means the stack pointer", Box::new(|a| a.and(XZR, X0, 0xff))),
        ("register 31 means the stack pointer", Box::new(|a| a.mov(XZR, SP))),
    ];
    for (want, f) in cases {
        let msg = error_of(f);
        assert!(msg.contains(want), "expected `{want}` in `{msg}`");
    }
    // ... while each legitimate use picks the right form.
    let mut a = Assembler::new();
    a.mov(X0, SP); // add x0, sp, #0
    a.mov(X0, XZR); // orr x0, xzr, xzr
    a.add(X0, SP, X1); // extended form
    a.add(X0, XZR, X1); // shifted form
    a.str(XZR, Mem::base(SP, 0));
    a.cmp(SP, X1);
    a.cmp(XZR, X1);
    assert_eq!(
        words(&finish(a)),
        [0x9100_03e0, 0xaa1f_03e0, 0x8b21_63e0, 0x8b01_03e0, 0xf900_03ff, 0xeb21_63ff, 0xeb01_03ff,]
    );
}

#[test]
fn errors_keep_the_first_and_roll_back() {
    let mut a = Assembler::new();
    a.nop();
    a.add_const(X0, X1, 0x1234_5678); // fine: 3 instructions
    a.ldp(X0, X1, Mem::base(XZR, 0x10000)); // fails after nothing was emitted
    a.and(X0, X1, 5); // second error, ignored
    a.ret();
    let e = a.error().cloned().unwrap();
    assert!(e.message.starts_with("ldp: "), "{e}");
    assert_eq!(e.offset, 4 * 4);
    let e = a.finish().unwrap_err();
    assert!(e.to_string().contains("near code offset 0x10"), "{e}");

    // take_error lets encoding go on; the failed instruction left nothing.
    let mut a = Assembler::new();
    a.str(X0, Mem::base(X1, 1 << 40)); // fine through x16
    let len = a.clone().finish().unwrap().bytes.len();
    a.ldr(X0, Mem::post(X0, 8));
    assert!(a.take_error().is_some());
    a.ret();
    let code = a.finish().unwrap();
    assert_eq!(code.bytes.len(), len + 4);
}

#[test]
fn label_errors() {
    let mut a = Assembler::new();
    let l = a.new_label();
    a.b(l);
    assert!(a.finish().unwrap_err().message.contains("used but never bound"));

    let mut a = Assembler::new();
    let l = a.here();
    a.bind(l);
    assert!(a.finish().unwrap_err().message.contains("bound twice"));

    let mut other = Assembler::new();
    other.new_label();
    let foreign = other.new_label();
    let mut a = Assembler::new();
    a.cbz(X0, foreign);
    assert!(a.finish().unwrap_err().message.contains("does not belong"));

    let mut a = Assembler::new();
    let l = a.new_label();
    a.export("_x", l);
    assert!(a.finish().unwrap_err().message.contains("exported but never bound"));

    // adr and literal loads are not relaxed.
    let mut a = Assembler::new();
    let l = a.new_label();
    a.adr(X0, l, 0);
    a.bytes(&vec![0; 1 << 20]);
    a.bind(l);
    assert!(a.finish().unwrap_err().message.contains("out of range"));

    // A branch to a misaligned label.
    let mut a = Assembler::new();
    let l = a.new_label();
    a.b(l);
    a.bytes(&[0]);
    a.bind(l);
    assert!(a.finish().unwrap_err().message.contains("not 4-byte aligned"));
}

#[test]
fn register_helpers() {
    assert_eq!(Reg::parse("X29"), Some(X29));
    assert_eq!(Reg::parse("lr"), Some(X30));
    assert_eq!(Reg::parse("wsp"), Some(WSP));
    assert_eq!(Reg::parse("x31"), None);
    assert_eq!(Reg::parse("x01"), None);
    assert_eq!(X5.to_w(), W5);
    assert_eq!(WZR.to_x(), XZR);
    assert_eq!(SP.index(), 31);
    assert_eq!(XZR.index(), 31);
    assert_ne!(SP, XZR);
    assert!(SP.is_sp() && !SP.is_zr() && XZR.is_zr());
    assert_eq!(format!("{SP} {WSP} {XZR} {W7} {D3} {S31}"), "sp wsp xzr w7 d3 s31");
    assert_eq!(Cond::Eq.invert(), Cond::Ne);
    assert_eq!(Cond::Hs.invert(), Cond::Lo);
    assert_eq!(Cond::Gt.invert(), Cond::Le);
    for c in Cond::ALL {
        assert_eq!(c.invert().invert(), c);
        assert_eq!(Cond::parse(c.suffix()), Some(c));
    }
    assert_eq!(Cond::parse("cs"), Some(Cond::CS));
    assert_eq!(IP0, X16);
    assert_eq!(FP, X29);
    // Which [base, #offset] accesses are one instruction.
    for (size, offset, direct) in [
        (3, 32760, true),
        (3, 32768, false),
        (3, 4, true),
        (3, -256, true),
        (3, -257, false),
        (0, 4095, true),
        (0, 4096, false),
        (2, 16380, true),
        (2, 16382, false),
    ] {
        assert_eq!(offset_is_direct(size, offset), direct, "size {size} offset {offset}");
    }
}
