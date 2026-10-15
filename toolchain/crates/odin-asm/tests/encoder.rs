// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Tests of the x86-64 encoder API: branch relaxation, label offsets,
//! relocations, alignment and error handling. Instruction encodings
//! themselves are checked against clang in `golden.rs`.

use odin_asm::x86_64::{Assembler, Code, Cond, Label, Mem, Reg::*, Width::*, Xmm::*, round};
use odin_asm::{RelocKind, SectionKind};

fn finish(a: Assembler) -> Code {
    a.finish().unwrap_or_else(|e| panic!("{e}"))
}

/// Decodes the jump at `at` and returns (length, target offset).
fn decode_jump(bytes: &[u8], at: usize) -> (usize, i64) {
    let b = &bytes[at..];
    let rel32 = |i: usize| i32::from_le_bytes(b[i..i + 4].try_into().unwrap()) as i64;
    let (len, disp) = match b[0] {
        0xEB | 0x70..=0x7F => (2, b[1] as i8 as i64),
        0xE9 => (5, rel32(1)),
        0x0F if (0x80..=0x8F).contains(&b[1]) => (6, rel32(2)),
        op => panic!("no jump at {at:#x}: {op:#04x}"),
    };
    (len, at as i64 + len as i64 + disp)
}

#[test]
fn short_jumps_and_label_offsets() {
    let mut a = Assembler::new();
    let top = a.here();
    let done = a.new_label();
    a.inc(W32, Rax);
    a.cmp(W32, Rax, 10);
    a.jcc(Cond::L, top);
    a.jcc(Cond::E, done);
    a.jmp(top);
    a.bind(done);
    a.ret();
    let code = finish(a);
    // Same bytes clang produces for this loop (see `_short_jumps` in the
    // blocks golden, minus its leading `xor eax, eax`).
    assert_eq!(code.bytes, [0xff, 0xc0, 0x83, 0xf8, 0x0a, 0x7c, 0xf9, 0x74, 0x02, 0xeb, 0xf5, 0xc3]);
    assert_eq!(code.label_offset(top), Some(0));
    assert_eq!(code.label_offset(done), Some(11));
    assert!(code.relocs.is_empty());
}

#[test]
fn near_jumps_when_rel8_does_not_fit() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.jcc(Cond::Ne, far);
    a.jmp(far);
    a.bytes(&[0x90; 200]);
    a.bind(far);
    a.ret();
    let code = finish(a);
    assert_eq!(&code.bytes[..11], &[0x0f, 0x85, 0xcd, 0, 0, 0, 0xe9, 0xc8, 0, 0, 0]);
    assert_eq!(code.label_offset(far), Some(211));
}

#[test]
fn rel8_boundaries() {
    // Forward +127 is short, +128 is near; backward -128 is short, -129 near.
    let mut a = Assembler::new();
    let (f127, f128) = (a.new_label(), a.new_label());
    a.jmp(f127);
    a.bytes(&[0; 127]);
    a.bind(f127);
    a.jmp(f128);
    a.bytes(&[0; 128]);
    a.bind(f128);
    let b128 = a.here();
    a.bytes(&[0; 126]);
    a.jmp(b128);
    let b129 = a.here();
    a.bytes(&[0; 127]);
    a.jmp(b129);
    let code = finish(a);
    let f127_at = code.label_offset(f127).unwrap() as usize;
    let f128_at = code.label_offset(f128).unwrap() as usize;
    assert_eq!(decode_jump(&code.bytes, 0), (2, f127_at as i64));
    assert_eq!(decode_jump(&code.bytes, f127_at), (5, f128_at as i64));
    let back1 = f128_at + 126;
    assert_eq!(decode_jump(&code.bytes, back1), (2, f128_at as i64));
    let b129_at = code.label_offset(b129).unwrap() as usize;
    assert_eq!(decode_jump(&code.bytes, b129_at + 127), (5, b129_at as i64));
}

#[test]
fn growth_cascades_over_several_passes() {
    // J3 is out of range; that pushes J2 out of range; both push J1 out.
    let mut a = Assembler::new();
    let (t1, t2, t3) = (a.new_label(), a.new_label(), a.new_label());
    a.jmp(t1);
    a.jmp(t2);
    a.jmp(t3);
    a.bytes(&[0; 122]);
    a.bind(t1);
    a.bytes(&[0; 2]);
    a.bind(t2);
    a.bytes(&[0; 6]);
    a.bind(t3);
    a.ret();
    let code = finish(a);
    assert_eq!(&code.bytes[..15], &[0xe9, 0x84, 0, 0, 0, 0xe9, 0x81, 0, 0, 0, 0xe9, 0x82, 0, 0, 0]);
    assert_eq!(code.label_offset(t1), Some(15 + 122));
    assert_eq!(code.label_offset(t3), Some(15 + 130));
}

#[test]
fn many_jumps_resolve_to_their_labels() {
    // A deterministic jumble of forward and backward jumps of all lengths,
    // checked by decoding every jump in the final code.
    let mut a = Assembler::new();
    let targets: Vec<Label> = (0..60).map(|_| a.new_label()).collect();
    let mut jumps = Vec::new();
    let mut seed = 12345u32;
    let mut next = |n: u32| {
        seed = seed.wrapping_mul(1103515245).wrapping_add(12345);
        (seed >> 16) % n
    };
    for (i, &t) in targets.iter().enumerate() {
        a.bind(t);
        for _ in 0..4 {
            // Mostly nearby labels (either direction), sometimes anywhere.
            let near = (i as i64 + next(5) as i64 - 2).clamp(0, targets.len() as i64 - 1) as usize;
            let target = if next(4) == 0 { targets[next(targets.len() as u32) as usize] } else { targets[near] };
            let at = a.here();
            if next(2) == 0 {
                a.jmp(target);
            } else {
                a.jcc(Cond::ALL[next(16) as usize], target);
            }
            jumps.push((at, target));
            let filler = next(if i % 7 == 0 { 120 } else { 30 }) as usize;
            a.bytes(&vec![0x90; filler]);
        }
    }
    let code = finish(a);
    let (mut short, mut near) = (0, 0);
    for (at, target) in jumps {
        let (len, dest) = decode_jump(&code.bytes, code.label_offset(at).unwrap() as usize);
        assert_eq!(dest, code.label_offset(target).unwrap() as i64);
        if len == 2 { short += 1 } else { near += 1 }
    }
    assert!(short > 20 && near > 20, "{short} short, {near} near");
}

#[test]
fn symbol_relocations_and_addends() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.jmp(far); // grows to 5 bytes, moving everything after it
    a.call("_f"); // 5..10, field at 6
    a.cmp(W8, Mem::rip("_x", 0), 1); // 80 3d rel32 ib: field at 12, -4 - 1
    a.mov(W64, Mem::rip("_x", 8), 5); // 48 c7 05 rel32 id: field at 20, 8 - 4 - 4
    a.call(Mem::got("_write")); // ff 15 rel32: field at 30
    a.roundsd(Xmm0, Mem::rip("_k", -16), round::TRUNCATE); // 66 0f 3a 0b 05 rel32 ib: field at 39
    a.abs64("_table", 24); // field at 44
    a.jmp("_tail"); // e9 rel32: field at 53
    a.bytes(&[0; 130]);
    a.bind(far);
    let code = finish(a);
    let relocs: Vec<(u32, RelocKind, &str, i64)> =
        code.relocs.iter().map(|r| (r.offset, r.kind, r.target.as_str(), r.addend)).collect();
    assert_eq!(
        relocs,
        [
            (6, RelocKind::X86Pc32, "_f", -4),
            (12, RelocKind::X86Pc32, "_x", -5),
            (20, RelocKind::X86Pc32, "_x", 0),
            (30, RelocKind::X86GotPc32, "_write", -4),
            (39, RelocKind::X86Pc32, "_k", -21),
            (44, RelocKind::Abs64, "_table", 24),
            (53, RelocKind::X86Pc32, "_tail", -4),
        ]
    );
    assert_eq!(code.bytes[0], 0xe9);
    assert_eq!(&code.bytes[34..39], &[0x66, 0x0f, 0x3a, 0x0b, 0x05]);
    assert_eq!(code.bytes[43], round::TRUNCATE);
}

#[test]
fn rip_label_and_call_label_fixups() {
    let mut a = Assembler::new();
    let data = a.new_label();
    let sub = a.new_label();
    a.lea(W64, Rax, Mem::label(data)); // 0..7
    a.cmp(W8, Mem::label_plus(data, 2), 7); // 7..14, imm8 after the field
    a.call(sub); // 14..19
    a.ret(); // 19
    a.bind(sub);
    a.ret(); // 20
    a.bind(data);
    a.bytes(&[1, 2, 3, 4]); // 21
    let code = finish(a);
    let rel = |at: usize| i32::from_le_bytes(code.bytes[at..at + 4].try_into().unwrap());
    assert_eq!(&code.bytes[..3], &[0x48, 0x8d, 0x05]);
    assert_eq!(rel(3), 21 - 7);
    assert_eq!(&code.bytes[7..9], &[0x80, 0x3d]);
    assert_eq!(rel(9), 21 + 2 - 14);
    assert_eq!(code.bytes[13], 7);
    assert_eq!(code.bytes[14], 0xe8);
    assert_eq!(rel(15), 20 - 19);
    assert!(code.relocs.is_empty());
}

#[test]
fn jump_table_with_diff32() {
    let mut a = Assembler::new();
    let table = a.new_label();
    let cases: Vec<Label> = (0..3).map(|_| a.new_label()).collect();
    a.lea(W64, Rcx, Mem::label(table));
    a.movsxd(Rax, Mem::index(Rcx, Rdi, 4, 0));
    a.add(W64, Rax, Rcx);
    a.jmp(Rax);
    a.align(4);
    a.bind(table);
    for &c in &cases {
        a.diff32(c, table);
    }
    for (i, &c) in cases.iter().enumerate() {
        a.bind(c);
        a.mov(W32, Rax, i as i32);
        a.ret();
    }
    let code = finish(a);
    let t = code.label_offset(table).unwrap() as usize;
    assert_eq!(t % 4, 0);
    for (i, &c) in cases.iter().enumerate() {
        let entry = i32::from_le_bytes(code.bytes[t + 4 * i..t + 4 * i + 4].try_into().unwrap());
        assert_eq!(t as i64 + entry as i64, code.label_offset(c).unwrap() as i64);
    }
}

#[test]
fn align_pads_with_nops_after_relaxation() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.jmp(far); // becomes near: 5 bytes
    a.align(16); // 11 bytes of padding: a 10-byte and a 1-byte NOP
    let head = a.here();
    a.bytes(&[0xcc; 200]);
    a.bind(far);
    a.ret();
    let code = finish(a);
    assert_eq!(code.label_offset(head), Some(16));
    assert_eq!(&code.bytes[5..16], &[0x66, 0x2e, 0x0f, 0x1f, 0x84, 0, 0, 0, 0, 0, 0x90]);
    assert_eq!(code.align, 16);
    let atom = code.into_atom("_f", 4);
    assert_eq!((atom.section, atom.align, atom.size), (SectionKind::Text, 16, 217));
}

#[test]
fn nops_of_every_length() {
    for n in 0..=25 {
        let mut a = Assembler::new();
        a.nops(n);
        assert_eq!(finish(a).bytes.len(), n as usize);
    }
}

#[test]
fn exports_become_atom_labels() {
    let mut a = Assembler::new();
    let far = a.new_label();
    a.jmp(far);
    a.bytes(&[0; 200]);
    a.bind(far);
    a.export("_f_exit", far);
    a.ret();
    let atom = finish(a).into_atom("_f", 16);
    assert_eq!(atom.labels, [("_f_exit".to_string(), 205)]);
    assert!(!atom.keep);
}

#[test]
fn invalid_instructions_are_reported_and_emit_nothing() {
    let mut a = Assembler::new();
    a.mov(W64, Rax, Rbx);
    a.mov(W64, Mem::base(Rax, 0), Mem::base(Rbx, 0));
    a.ret();
    assert_eq!(a.error().unwrap().message, "mov: invalid operands (memory, memory)");
    let e = a.finish().unwrap_err();
    assert_eq!(e.offset, 3);

    type Case = (Box<dyn Fn(&mut Assembler)>, &'static str);
    let cases: Vec<Case> = vec![
        (
            Box::new(|a| a.add(W64, Rax, 0x8000_0000i64)),
            "add: immediate 2147483648 does not fit in a sign-extended 32-bit field",
        ),
        (Box::new(|a| a.add(W8, Rax, 256)), "add: immediate 256 does not fit in 8 bits"),
        (
            Box::new(|a| a.mov(W64, Mem::base(Rax, 0), 0x1_0000_0000i64)),
            "mov: immediate 4294967296 does not fit in a sign-extended 32-bit field",
        ),
        (Box::new(|a| a.lea(W8, Rax, Mem::base(Rbx, 0))), "lea: 8-bit operands are not allowed"),
        (Box::new(|a| a.lea(W64, Rax, Rbx)), "lea: invalid operands (register, register)"),
        (Box::new(|a| a.mov(W64, Rax, Mem::index(Rbx, Rsp, 1, 0))), "mov: rsp cannot be an index register"),
        (Box::new(|a| a.mov(W64, Rax, Mem::index(Rbx, Rcx, 3, 0))), "mov: scale 3 is not 1, 2, 4 or 8"),
        (Box::new(|a| a.shl(W64, Rax, Rbx)), "shl: the shift count must be an immediate or cl"),
        (Box::new(|a| a.movzx(W32, Rax, W32, Rbx)), "movzx: cannot extend 32 bits to 32 bits"),
        (Box::new(|a| a.cvtsi2sd(Xmm0, W8, Rax)), "cvtsi2sd: the integer operand must be 32 or 64 bits"),
        (Box::new(|a| a.addsd(Xmm0, Rax)), "addsd: invalid operands (xmm, register)"),
        (Box::new(|a| a.jcc(Cond::E, Rax)), "jcc: conditional jumps cannot be indirect"),
        (Box::new(|a| a.align(3)), "align: alignment 3 is not a power of two"),
    ];
    for (emit, message) in cases {
        let mut a = Assembler::new();
        emit(&mut a);
        let e = a.take_error().expect(message);
        assert_eq!(e.message, message);
        assert!(finish(a).bytes.is_empty(), "{message}: bytes left behind");
    }
}

#[test]
fn label_errors() {
    let mut a = Assembler::new();
    let l = a.new_label();
    a.jmp(l);
    assert_eq!(a.finish().unwrap_err().message, "label L0 is used but never bound");

    let mut a = Assembler::new();
    let l = a.here();
    a.bind(l);
    assert_eq!(a.finish().unwrap_err().message, "bind: label L0 is bound twice");

    let mut other = Assembler::new();
    let foreign = other.new_label();
    let foreign = [foreign, other.new_label()][1];
    let mut a = Assembler::new();
    a.jmp(foreign);
    assert_eq!(a.finish().unwrap_err().message, "jmp: label L1 does not belong to this assembler");

    let mut a = Assembler::new();
    let l = a.new_label();
    a.export("_x", l);
    assert_eq!(a.finish().unwrap_err().message, "label L0 is exported but never bound");

    // Unused, unbound labels are fine and have no offset.
    let mut a = Assembler::new();
    let l = a.new_label();
    a.ret();
    assert_eq!(finish(a).label_offset(l), None);
}

#[test]
fn take_error_lets_encoding_continue() {
    let mut a = Assembler::new();
    let never = a.new_label();
    a.add(W64, Mem::base(Rax, 0), Mem::base(Rax, 0));
    assert!(a.take_error().is_some());
    // A failed instruction does not count as a use of its labels: here
    // `never` is marked before the foreign base label fails.
    let mut other = Assembler::new();
    let foreign = (0..5).map(|_| other.new_label()).last().unwrap();
    a.diff32(never, foreign);
    assert_eq!(a.take_error().unwrap().message, "diff32: label L4 does not belong to this assembler");
    a.ret();
    assert_eq!(finish(a).bytes, [0xc3]);
}

#[test]
fn api_operand_conversions() {
    let slot = Mem::base(Rbp, -8);
    let mut a = Assembler::new();
    a.mov(W64, Rax, &slot);
    a.add(W64, Rax, 1);
    a.mov(W64, &slot, Rax);
    a.mov(W64, Rcx, 0x1234_5678_9abc_def0i64);
    a.mov(W32, Rdx, 0xffff_ffffu32);
    a.mov(W64, Rax, slot.clone().offset(-8));
    a.movsd(Xmm1, Mem::base(Rsp, 0));
    let code = finish(a);
    assert_eq!(
        code.bytes,
        [
            0x48, 0x8b, 0x45, 0xf8, // mov rax, [rbp - 8]
            0x48, 0x83, 0xc0, 0x01, // add rax, 1
            0x48, 0x89, 0x45, 0xf8, // mov [rbp - 8], rax
            0x48, 0xb9, 0xf0, 0xde, 0xbc, 0x9a, 0x78, 0x56, 0x34, 0x12, // movabs rcx, ...
            0xba, 0xff, 0xff, 0xff, 0xff, // mov edx, 0xffffffff
            0x48, 0x8b, 0x45, 0xf0, // mov rax, [rbp - 16]
            0xf2, 0x0f, 0x10, 0x0c, 0x24, // movsd xmm1, [rsp]
        ]
    );
}

#[test]
fn register_and_condition_names() {
    use odin_asm::x86_64::{Reg, Width, Xmm};
    assert_eq!(R8.name(W32), "r8d");
    assert_eq!(Rsi.name(W8), "sil");
    assert_eq!(Reg::parse("R15W"), Some((R15, Width::W16)));
    assert_eq!(Reg::parse("ah"), None);
    assert_eq!(Xmm::parse("xmm15"), Some(Xmm15));
    assert_eq!(Xmm::parse("xmm16"), None);
    assert_eq!(Cond::parse("nae"), Some(Cond::B));
    assert_eq!(Cond::Z, Cond::E);
    assert_eq!(Cond::L.negate(), Cond::Ge);
    assert_eq!(Cond::P.negate(), Cond::Np);
    assert_eq!(Mem::index(Rax, Rcx, 8, -16).to_string(), "[rax + rcx*8 - 16]");
    assert_eq!(Mem::got("_write").to_string(), "[rip + _write@GOTPCREL]");
}
