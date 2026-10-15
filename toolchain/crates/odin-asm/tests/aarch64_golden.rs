// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Compares odin_asm AArch64 encodings with goldens produced by clang (see
//! `gen_golden_aarch64.py`): every instruction of `aarch64_golden.txt` on its
//! own through the text assembler, every block of `aarch64_blocks.s` as a
//! whole, and a selection of instructions built through the Rust API.
//! Relocations must match in offset, kind and addend. Instruction fields
//! under relocations are zero on both sides; only `.quad` data fields are
//! masked, since Mach-O keeps their addend in the data and odin_asm does not.

use std::collections::HashMap;

use odin_asm::aarch64::{Assembler, Cond, Extend, IndexExt, LogicOp, Mem, Op2, Reg, Round, SysReg, VReg, regs::*};
use odin_asm::text::{Arch, assemble_for};
use odin_asm::{Reloc, RelocKind};

struct Expected {
    bytes: Vec<u8>,
    relocs: Vec<(u32, RelocKind, i64)>,
}

fn parse_words(col: &str) -> Vec<u8> {
    let mut bytes = Vec::new();
    for item in col.split_whitespace() {
        let (word, count) = match item.split_once('*') {
            Some((w, n)) => (w, n.parse().unwrap()),
            None => (item, 1),
        };
        let w = u32::from_str_radix(word, 16).unwrap();
        for _ in 0..count {
            bytes.extend_from_slice(&w.to_le_bytes());
        }
    }
    bytes
}

fn parse_kind(kind: &str) -> RelocKind {
    match kind {
        "branch26" => RelocKind::Arm64Branch26,
        "page21" => RelocKind::Arm64Page21,
        "gotpage21" => RelocKind::Arm64GotPage21,
        "gotpageoff12" => RelocKind::Arm64GotPageOff12,
        "abs64" => RelocKind::Abs64,
        k => match k.strip_prefix("pageoff12/") {
            Some(s) => RelocKind::Arm64PageOff12 { scale: s.parse().unwrap() },
            None => panic!("unknown reloc kind {k}"),
        },
    }
}

fn parse_line(line: &str) -> Option<(String, Expected)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let cols: Vec<&str> = line.split('|').map(str::trim).collect();
    assert!(cols.len() >= 2, "golden line without words (rerun gen_golden_aarch64.py): {line}");
    let relocs = match cols.get(2) {
        None => Vec::new(),
        Some(r) => r
            .split(',')
            .map(|item| {
                let f: Vec<&str> = item.split(':').collect();
                (f[0].parse().unwrap(), parse_kind(f[1]), f[2].parse().unwrap())
            })
            .collect(),
    };
    Some((cols[0].to_string(), Expected { bytes: parse_words(cols[1]), relocs }))
}

fn words(bytes: &[u8]) -> String {
    let w: Vec<String> =
        bytes.chunks(4).map(|c| format!("{:08x}", u32::from_le_bytes(c.try_into().unwrap_or([0; 4])))).collect();
    if w.len() > 40 { format!("{} ... ({} words)", w[..40].join(" "), w.len()) } else { w.join(" ") }
}

/// Compares code with its golden; returns a description of any mismatch.
fn compare(bytes: &[u8], relocs: &[Reloc], want: &Expected) -> Option<String> {
    let got: Vec<(u32, RelocKind, i64)> = relocs.iter().map(|r| (r.offset, r.kind, r.addend)).collect();
    if got != want.relocs {
        return Some(format!("relocations {got:?}, expected {:?}", want.relocs));
    }
    let mut ours = bytes.to_vec();
    let mut theirs = want.bytes.clone();
    for &(offset, kind, _) in &want.relocs {
        if kind == RelocKind::Abs64 {
            for b in [&mut ours, &mut theirs] {
                let end = (offset as usize + 8).min(b.len());
                b[(offset as usize).min(end)..end].fill(0);
            }
        }
    }
    if ours == theirs {
        return None;
    }
    let first = ours.iter().zip(&theirs).position(|(a, b)| a != b).unwrap_or(ours.len().min(theirs.len()));
    Some(format!("words {}, expected {} (first difference at byte {first})", words(bytes), words(&want.bytes)))
}

fn golden() -> Vec<(String, Expected)> {
    include_str!("aarch64_golden.txt").lines().filter_map(parse_line).collect()
}

#[test]
fn instructions_match_clang() {
    let mut failures = Vec::new();
    let mut count = 0;
    for (insn, want) in golden() {
        count += 1;
        match assemble_for(Arch::Aarch64, &format!("_t:\n    {insn}\n"), "golden.s") {
            Err(e) => failures.push(format!("{insn}: {e}")),
            Ok(obj) => {
                let atom = &obj.atoms[0];
                if let Some(msg) = compare(&atom.bytes, &atom.relocs, &want) {
                    failures.push(format!("{insn}: {msg}"));
                }
            }
        }
    }
    assert!(count > 550, "only {count} golden instructions");
    assert!(
        failures.is_empty(),
        "{} of {count} instructions differ from clang:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn blocks_match_clang() {
    let obj = assemble_for(Arch::Aarch64, include_str!("aarch64_blocks.s"), "aarch64_blocks.s").unwrap();
    let mut failures = Vec::new();
    let mut count = 0;
    for line in include_str!("aarch64_blocks.golden").lines() {
        let Some((name, want)) = parse_line(line) else { continue };
        count += 1;
        let atom = obj.atoms.iter().find(|a| a.name == name).unwrap_or_else(|| panic!("no atom {name}"));
        assert_eq!(atom.align % 4, 0, "{name}: code atoms are aligned to at least 4");
        if let Some(msg) = compare(&atom.bytes, &atom.relocs, &want) {
            failures.push(format!("{name}: {msg}"));
        }
    }
    assert_eq!(count, obj.atoms.len(), "every block has a golden");
    assert!(failures.is_empty(), "blocks differ from clang:\n{}", failures.join("\n"));
}

type Build = fn(&mut Assembler);

/// Instructions built through the Rust API, keyed by their golden text.
const API_CASES: &[(&str, Build)] = &[
    ("add x0, x1, #4095", |a| a.add(X0, X1, 4095)),
    ("add x0, x1, #4096", |a| a.add(X0, X1, 4096)),
    ("add x0, x1, #-8", |a| a.add(X0, X1, -8)),
    ("add sp, sp, #16", |a| a.add(SP, SP, 16)),
    ("sub sp, sp, #32", |a| a.sub(SP, SP, 32)),
    ("cmp x0, #-1", |a| a.cmp(X0, -1)),
    ("cmp sp, #16", |a| a.cmp(SP, 16)),
    ("mov x0, sp", |a| a.mov(X0, SP)),
    ("mov sp, x0", |a| a.mov(SP, X0)),
    ("mov x29, x30", |a| a.mov(X29, X30)),
    ("mov w30, wzr", |a| a.mov(W30, WZR)),
    ("add x0, x1, x2, lsl #63", |a| a.add(X0, X1, X2.lsl(63))),
    ("sub x0, xzr, x2", |a| a.sub(X0, XZR, X2)),
    ("neg w0, w1, lsl #2", |a| a.neg(W0, W1.lsl(2))),
    ("add x0, sp, x1", |a| a.add(X0, SP, X1)),
    ("add sp, sp, x1, lsl #3", |a| a.add(SP, SP, X1.lsl(3))),
    ("add x0, x1, w2, sxtw", |a| a.add(X0, X1, W2.sxtw(0))),
    ("add x0, x1, w2, uxth #1", |a| a.add(X0, X1, W2.ext(Extend::Uxth, 1))),
    ("cmp sp, x1", |a| a.cmp(SP, X1)),
    ("adds x0, sp, x1", |a| a.adds(X0, SP, X1)),
    ("orr x0, x1, x2, ror #8", |a| a.orr(X0, X1, X2.ror(8))),
    ("bic x0, x1, x2", |a| a.bic(X0, X1, X2)),
    ("tst w0, w1, lsl #2", |a| a.tst(W0, W1.lsl(2))),
    ("mvn w0, w1, ror #3", |a| a.mvn(W0, W1.ror(3))),
    ("and x0, x1, #0x00ff00ff00ff00ff", |a| a.and(X0, X1, 0x00ff_00ff_00ff_00ffu64)),
    ("and sp, x0, #0xfffffffffffffff0", |a| a.and(SP, X0, -16)),
    ("orr w0, w1, #0xaaaaaaaa", |a| a.orr(W0, W1, 0xaaaa_aaaau32)),
    ("bics w0, w1, #1", |a| a.logical(LogicOp::Bics, W0, W1, 1)),
    ("tst x1, #0xc000000000000001", |a| a.tst(X1, 0xc000_0000_0000_0001u64)),
    ("movz x0, #0xffff, lsl #48", |a| a.movz(X0, 0xffff, 48)),
    ("movn w0, #0x1234, lsl #16", |a| a.movn(W0, 0x1234, 16)),
    ("movk x0, #0xdead, lsl #32", |a| a.movk(X0, 0xdead, 32)),
    ("mov w0, #-1", |a| a.mov(W0, -1)),
    ("mov x0, #0xffffffff", |a| a.mov(X0, 0xffff_ffffi64)),
    ("mov w0, #0x7fffffff", |a| a.mov_imm(W0, 0x7fff_ffff)),
    ("mov x0, #0xffff0000ffff0000", |a| a.mov_imm(X0, 0xffff_0000_ffff_0000u64 as i64)),
    ("madd x0, x1, x2, x3", |a| a.madd(X0, X1, X2, X3)),
    ("smulh x0, x1, x2", |a| a.smulh(X0, X1, X2)),
    ("umull x0, w1, w2", |a| a.umull(X0, W1, W2)),
    ("sdiv w0, w1, w2", |a| a.sdiv(W0, W1, W2)),
    ("lsl x0, x1, #63", |a| a.lsl(X0, X1, 63)),
    ("lsr w0, w1, #31", |a| a.lsr(W0, W1, 31)),
    ("asr x0, x1, #32", |a| a.asr(X0, X1, 32)),
    ("ror w0, w1, #31", |a| a.ror(W0, W1, 31)),
    ("lsl x0, x1, x2", |a| a.lsl(X0, X1, X2)),
    ("sxtw x0, w1", |a| a.sxtw(X0, W1)),
    ("sxtb x0, w1", |a| a.sxtb(X0, W1)),
    ("uxth w0, w1", |a| a.uxth(W0, W1)),
    ("ubfx x0, x1, #4, #8", |a| a.ubfx(X0, X1, 4, 8)),
    ("sbfiz x0, x1, #2, #32", |a| a.sbfiz(X0, X1, 2, 32)),
    ("bfi x0, x1, #8, #16", |a| a.bfi(X0, X1, 8, 16)),
    ("csel w0, w1, wzr, ne", |a| a.csel(W0, W1, WZR, Cond::Ne)),
    ("cset x0, hi", |a| a.cset(X0, Cond::Hi)),
    ("csetm x0, lt", |a| a.csetm(X0, Cond::Lt)),
    ("cinc w0, w1, ge", |a| a.cinc(W0, W1, Cond::Ge)),
    ("cneg x0, x1, gt", |a| a.cneg(X0, X1, Cond::Gt)),
    ("ccmp x0, #31, #15, eq", |a| a.ccmp(X0, 31, 15, Cond::Eq)),
    ("ccmn w0, w1, #8, vs", |a| a.ccmn(W0, W1, 8, Cond::Vs)),
    ("clz w0, w1", |a| a.clz(W0, W1)),
    ("rev x0, x1", |a| a.rev(X0, X1)),
    ("ldr x0, [x1, #32760]", |a| a.ldr(X0, Mem::base(X1, 32760))),
    ("ldr x0, [x1, #4]", |a| a.ldr(X0, Mem::base(X1, 4))),
    ("ldr x0, [x1, #-256]", |a| a.ldr(X0, Mem::base(X1, -256))),
    ("ldrsw x0, [sp, #16380]", |a| a.ldrsw(X0, Mem::base(SP, 16380))),
    ("ldrsb w0, [x1, #2]", |a| a.ldrsb(W0, Mem::base(X1, 2))),
    ("ldrh w0, [x1, #1]", |a| a.ldrh(W0, Mem::base(X1, 1))),
    ("str xzr, [sp]", |a| a.str(XZR, Mem::base(SP, 0))),
    ("str d31, [x30, #32760]", |a| a.str(D31, Mem::base(X30, 32760))),
    ("ldr s0, [sp, #-4]", |a| a.ldr(S0, Mem::base(SP, -4))),
    ("ldursh x0, [x1, #-5]", |a| a.ldursh(X0, X1, -5)),
    ("stur s0, [x0, #3]", |a| a.stur(S0, X0, 3)),
    ("str x0, [sp, #-16]!", |a| a.str(X0, Mem::pre(SP, -16))),
    ("ldr x0, [x1], #-256", |a| a.ldr(X0, Mem::post(X1, -256))),
    ("ldr d0, [sp], #8", |a| a.ldr(D0, Mem::post(SP, 8))),
    ("ldr x0, [x1, x2, lsl #3]", |a| a.ldr(X0, Mem::index_scaled(X1, X2))),
    ("ldr x0, [x1, w2, sxtw #3]", |a| a.ldr(X0, Mem::index_ext(X1, W2, IndexExt::Sxtw, true))),
    ("ldrb w0, [x1, x2]", |a| a.ldrb(W0, Mem::index(X1, X2))),
    ("ldrb w0, [x1, x2, lsl #0]", |a| a.ldrb(W0, Mem::index_scaled(X1, X2))),
    ("str s0, [x1, w2, sxtw #2]", |a| a.str(S0, Mem::index_ext(X1, W2, IndexExt::Sxtw, true))),
    ("stp x29, x30, [sp, #-16]!", |a| a.stp(X29, X30, Mem::pre(SP, -16))),
    ("ldp x29, x30, [sp], #504", |a| a.ldp(X29, X30, Mem::post(SP, 504))),
    ("stp x0, x1, [sp, #-512]", |a| a.stp(X0, X1, Mem::base(SP, -512))),
    ("ldp w0, w1, [x2, #252]", |a| a.ldp(W0, W1, Mem::base(X2, 252))),
    ("stp d8, d9, [sp, #-16]!", |a| a.stp(D8, D9, Mem::pre(SP, -16))),
    ("ldp s2, s3, [x0, #-256]", |a| a.ldp(S2, S3, Mem::base(X0, -256))),
    ("adrp x0, _x@PAGE+16", |a| a.adrp(X0, "_x", 16)),
    ("add x0, x1, _x@PAGEOFF+16", |a| a.add_pageoff(X0, X1, "_x", 16)),
    ("ldr w0, [x1, _x@PAGEOFF+4]", |a| a.ldr(W0, Mem::page_off(X1, "_x", 4))),
    ("ldrh w0, [x1, _x@PAGEOFF]", |a| a.ldrh(W0, Mem::page_off(X1, "_x", 0))),
    ("str d0, [x1, _x@PAGEOFF+8]", |a| a.str(D0, Mem::page_off(X1, "_x", 8))),
    ("adrp x16, _write@GOTPAGE", |a| a.adrp_got(X16, "_write")),
    ("ldr x16, [x16, _write@GOTPAGEOFF]", |a| a.ldr(X16, Mem::got_page_off(X16, "_write"))),
    ("bl _f", |a| a.bl("_f")),
    ("b _f", |a| a.b("_f")),
    ("blr x8", |a| a.blr(X8)),
    ("ret", |a| a.ret()),
    ("ret x1", |a| a.ret_to(X1)),
    ("fmov d0, x1", |a| a.fmov(D0, X1)),
    ("fmov w0, s1", |a| a.fmov(W0, S1)),
    ("fmov s0, s1", |a| a.fmov(S0, S1)),
    ("fmov d0, #-2.0", |a| a.fmov_imm(D0, -2.0)),
    ("fmov s0, #1.9375", |a| a.fmov_imm(S0, 1.9375)),
    ("fmov d0, #0.0", |a| a.fmov_imm(D0, 0.0)),
    ("fadd d0, d1, d2", |a| a.fadd(D0, D1, D2)),
    ("fdiv s0, s1, s2", |a| a.fdiv(S0, S1, S2)),
    ("fnmul d0, d1, d2", |a| a.fnmul(D0, D1, D2)),
    ("fsqrt s0, s1", |a| a.fsqrt(S0, S1)),
    ("fabs s31, s30", |a| a.fabs(S31, S30)),
    ("fcmp d0, #0.0", |a| a.fcmp_zero(D0)),
    ("fcmpe d0, d1", |a| a.fcmpe(D0, D1)),
    ("fcsel s0, s1, s2, lt", |a| a.fcsel(S0, S1, S2, Cond::Lt)),
    ("fcvt d0, s1", |a| a.fcvt(D0, S1)),
    ("scvtf s0, x1", |a| a.scvtf(S0, X1)),
    ("ucvtf d0, w1", |a| a.ucvtf(D0, W1)),
    ("fcvtzs w0, d1", |a| a.fcvtzs(W0, D1)),
    ("fcvtms x0, d0", |a| a.fcvtms(X0, D0)),
    ("fcvtns w0, d0", |a| a.fcvtns(W0, D0)),
    ("fcvtau w0, d0", |a| a.fcvt_int(Round::Away, false, W0, D0)),
    ("frintm s0, s1", |a| a.frintm(S0, S1)),
    ("frinta d0, d1", |a| a.frinta(D0, D1)),
    ("brk #0xf000", |a| a.brk(0xf000)),
    ("udf #65535", |a| a.udf(65535)),
    ("svc #0x80", |a| a.svc(0x80)),
    ("dmb ish", |a| a.dmb_ish()),
    ("mrs x1, fpcr", |a| a.mrs(X1, SysReg::Fpcr)),
    ("msr fpsr, xzr", |a| a.msr(SysReg::Fpsr, XZR)),
];

#[test]
fn api_matches_clang() {
    let golden: HashMap<String, Expected> = golden().into_iter().collect();
    let mut failures = Vec::new();
    for (insn, build) in API_CASES {
        let want = golden.get(*insn).unwrap_or_else(|| panic!("`{insn}` is not in aarch64_golden.txt"));
        let mut a = Assembler::new();
        build(&mut a);
        match a.finish() {
            Err(e) => failures.push(format!("{insn}: {e}")),
            Ok(code) => {
                if let Some(msg) = compare(&code.bytes, &code.relocs, want) {
                    failures.push(format!("{insn}: {msg}"));
                }
            }
        }
    }
    assert!(failures.is_empty(), "API encodings differ from clang:\n{}", failures.join("\n"));
}

/// Every register number reaches every register field: add (shifted) with
/// rotating registers, compared with the bits clang uses.
#[test]
fn register_numbers() {
    let golden: HashMap<String, Expected> = golden().into_iter().collect();
    let base = u32::from_le_bytes(golden["add x0, x1, x2"].bytes[..4].try_into().unwrap()) & !0x001f_03ff;
    for n in 0..31u8 {
        let (d, s, m) = (Reg::x(n), Reg::x((n + 7) % 31), Reg::x((n + 19) % 31));
        let mut a = Assembler::new();
        a.add(d, s, Op2::Reg(m));
        let word = u32::from_le_bytes(a.finish().unwrap().bytes[..4].try_into().unwrap());
        assert_eq!(word, base | (m.index() as u32) << 16 | (s.index() as u32) << 5 | d.index() as u32);
        let mut a = Assembler::new();
        a.fadd(VReg::d(n), VReg::d(31 - n), VReg::d(n / 2));
        let word = u32::from_le_bytes(a.finish().unwrap().bytes[..4].try_into().unwrap());
        assert_eq!(word, 0x1e60_2800 | (n as u32 / 2) << 16 | (31 - n as u32) << 5 | n as u32);
    }
}
