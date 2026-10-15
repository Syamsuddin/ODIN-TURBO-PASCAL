// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Tests of the `.s` assembler for AArch64: the example from the module
//! docs, atoms and local labels, directives in code, comments, and error
//! reporting. Instruction encodings are checked in `aarch64_golden.rs`.

use odin_asm::text::{Arch, AsmError, assemble_for};
use odin_asm::{Atom, Import, Object, Reloc, RelocKind, SectionKind};

fn asm(src: &str) -> Object {
    assemble_for(Arch::Aarch64, src, "test.s").unwrap_or_else(|e| panic!("{e}"))
}

fn err(src: &str) -> AsmError {
    assemble_for(Arch::Aarch64, src, "test.s").expect_err("expected an error")
}

fn atom<'a>(obj: &'a Object, name: &str) -> &'a Atom {
    obj.atoms.iter().find(|a| a.name == name).unwrap_or_else(|| panic!("no atom {name}"))
}

fn words(a: &Atom) -> Vec<u32> {
    a.bytes.chunks(4).map(|c| u32::from_le_bytes(c.try_into().unwrap())).collect()
}

#[test]
fn shim_example_from_the_docs() {
    let obj = asm(r#"
# SPDX-License-Identifier: GPL-3.0-or-later
.text
.keep _odin_start
_odin_start:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x8, _odin_argc@PAGE          // Darwin; ELF: adrp x8, odin_argc
    str x0, [x8, _odin_argc@PAGEOFF]  // ELF: [x8, :lo12:odin_argc]
    adrp x16, _exit@GOTPAGE           // ELF: adrp x16, :got:exit
    ldr x16, [x16, _exit@GOTPAGEOFF]  // ELF: [x16, :got_lo12:exit]
    blr x16
.Lloop:
    b .Lloop

.import _exit, "/usr/lib/libSystem.B.dylib"

.bss
.p2align 3
_odin_argc:
    .zero 8
"#);
    assert_eq!(obj.atoms.len(), 2);
    let start = &obj.atoms[0];
    assert_eq!(
        (start.name.as_str(), start.section, start.align, start.keep),
        ("_odin_start", SectionKind::Text, 16, true)
    );
    assert_eq!(
        words(start),
        [0xa9bf7bfd, 0x910003fd, 0x90000008, 0xf9000100, 0x90000010, 0xf9400210, 0xd63f0200, 0x14000000]
    );
    let r = |offset, kind, target: &str| Reloc { offset, kind, target: target.into(), addend: 0 };
    assert_eq!(
        start.relocs,
        [
            r(8, RelocKind::Arm64Page21, "_odin_argc"),
            r(12, RelocKind::Arm64PageOff12 { scale: 3 }, "_odin_argc"),
            r(16, RelocKind::Arm64GotPage21, "_exit"),
            r(20, RelocKind::Arm64GotPageOff12, "_exit"),
        ]
    );
    assert_eq!(obj.atoms[1], Atom::bss("_odin_argc", 8, 8));
    assert_eq!(obj.imports, [Import { name: "_exit".into(), library: "/usr/lib/libSystem.B.dylib".into() }]);
}

#[test]
fn elf_operators_and_case() {
    let obj = asm("
odin_start:
    ADRP X1, msg + 8
    ADD x1, x1, #:lo12:msg + 8
    ldrb w2, [x1, :LO12:msg]
    adrp x16, :got:exit
    ldr x16, [x16, :got_lo12:exit]
    BL helper
");
    let relocs: Vec<(u32, RelocKind, &str, i64)> =
        obj.atoms[0].relocs.iter().map(|r| (r.offset, r.kind, r.target.as_str(), r.addend)).collect();
    use RelocKind::*;
    assert_eq!(
        relocs,
        [
            (0, Arm64Page21, "msg", 8),
            (4, Arm64PageOff12 { scale: 0 }, "msg", 8),
            (8, Arm64PageOff12 { scale: 0 }, "msg", 0),
            (12, Arm64GotPage21, "exit", 0),
            (16, Arm64GotPageOff12, "exit", 0),
            (20, Arm64Branch26, "helper", 0),
        ]
    );
}

#[test]
fn local_labels_relaxation_and_data_in_code() {
    let obj = asm("
.set COUNT, 3
_f:
    mov w0, #COUNT * 2
.Lagain:
    subs w0, w0, #1
    b.ne .Lagain
    cbz x1, .Lout
    ldr d0, .Lconst
    adr x2, .Ltable
    b .Lskip
.p2align 3
.Lconst:
    .quad 0x3ff0000000000000
.Ltable:
    .quad _g + 16
    .long 7
.Lskip:
    .zero 1048576
.Lout:
    ret
_g:
.Lagain:
    b .Lagain
");
    let f = atom(&obj, "_f");
    let w = words(f);
    assert_eq!(w[0], 0x528000c0); // mov w0, #6
    assert_eq!(w[2], 0x54ffffe1); // b.ne .Lagain
    // cbz relaxed: cbnz x1, +8; b .Lout. The padding before .Lconst
    // shrinks from 4 bytes to none.
    assert_eq!(w[3], 0xb5000041);
    let out = 52 + 1048576;
    assert_eq!(w[4], 0x1400_0000 | ((out - 16) / 4) as u32);
    assert_eq!(&w[5..8], &[0x5c000060, 0x10000082, 0x14000006]); // ldr d0, +12; adr x2, +16; b +24
    assert_eq!(&w[8..10], &[0, 0x3ff00000]);
    assert_eq!(f.relocs, [Reloc { offset: 40, kind: RelocKind::Abs64, target: "_g".into(), addend: 16 }]);
    assert_eq!(f.bytes.len(), out + 4);
    // `.Lagain` is local to each atom.
    assert_eq!(words(atom(&obj, "_g")), [0x14000000]);
}

#[test]
fn alignment_and_sections() {
    let obj = asm("
.p2align 1
_tiny:
    ret
.align 32
_big:
    nop
.p2align 4
    ret
.rodata
_k:
    .quad 0x4000000000000000
.text
    ret             // continues _big
");
    assert_eq!(atom(&obj, "_tiny").align, 4, "code atoms are aligned to at least 4");
    assert_eq!(atom(&obj, "_big").align, 32);
    assert_eq!(words(atom(&obj, "_big")), [0xd503201f, 0xd503201f, 0xd503201f, 0xd503201f, 0xd65f03c0, 0xd65f03c0]);
    assert_eq!(atom(&obj, "_k").section, SectionKind::ReadOnly);
    assert_eq!(atom(&obj, "_k").bytes, 0x4000000000000000u64.to_le_bytes());
}

#[test]
fn comments() {
    let obj = asm("
# a hash comment at the start of a line
    # also when indented
_f: // after a label
    add x0, x1, #2 // the # here is an immediate
    ret
");
    assert_eq!(words(&obj.atoms[0]), [0x91000820, 0xd65f03c0]);
}

#[test]
fn errors_have_line_numbers() {
    let cases = [
        ("_f:\n    add x0, x1, #1 ; comment\n", 2, "statement separator"),
        ("_f:\n    ldr x0, [x1, #32768]\n", 2, "offset 32768 is out of range"),
        ("_f:\n    ldp x0, x1, [sp, #512]\n", 2, "offset 512 is out of range"),
        ("_f:\n    b.eq _g\n", 2, "can only reach `.L` labels"),
        ("_f:\n    cbz x0, _g\n", 2, "can only reach `.L` labels"),
        ("_f:\n    adr x0, _g\n", 2, "can only reach `.L` labels"),
        ("_f:\n    adrp x0, .Lx\n.Lx:\n", 2, "use `adr`"),
        ("_f:\n    bl _g + 4\n", 2, "cannot have an offset"),
        ("_f:\n    add x0, x1, #4097\n", 2, "not 0 to 4095"),
        ("_f:\n    and x0, x1, #5\n", 2, "not a valid bitmask"),
        ("_f:\n    mov x0, #0x12345\n", 2, "needs 2 instructions"),
        ("_f:\n    ldr x0, [x1, _g]\n", 2, "needs `@PAGEOFF`"),
        ("_f:\n    ldr w0, [x1, _g@GOTPAGEOFF]\n", 2, "GOT slot"),
        ("_f:\n    add x0, x1, _g@PAGE\n", 2, "only allowed as `add xd, xn, sym@PAGEOFF`"),
        ("_f:\n    adrp x0, _g@TLVPPAGE\n", 2, "unsupported relocation operator"),
        ("_f:\n    ldr x0, [x1], #8, #9\n", 2, "takes 2 or 3 operand(s)"),
        ("_f:\n    frobnicate x0\n", 2, "unknown instruction"),
        ("_f:\n    csel x0, x1, x2, sometimes\n", 2, "unknown condition"),
        ("_f:\n    mrs x0, sctlr_el1\n", 2, "expected `nzcv`"),
        ("_f:\n    dmb sy\n", 2, "only `dmb ish`"),
        ("_f:\n    fcmp d0, #0\n", 2, "only immediate `fcmp` takes is #0.0"),
        ("_f:\n    ldr x0, [x1, x2, lsl #2]\n", 2, "must be #0 or #3"),
        ("_f:\n    b .Lnowhere\n", 2, "undefined label `.Lnowhere`"),
        (".intel_syntax noprefix\n", 1, "only for x86-64"),
        ("    ret\n", 1, "content before the first label"),
        (".data\n_d:\n    nop\n", 3, "outside `.text`"),
    ];
    for (src, line, want) in cases {
        let e = err(src);
        assert_eq!(e.line, line, "{src}: {e}");
        assert!(e.message.contains(want), "{src}: expected `{want}` in `{}`", e.message);
        assert_eq!(e.file, "test.s");
    }
}

#[test]
fn x86_default_is_unchanged() {
    // `assemble` stays the x86-64 entry point, and the same source means
    // something else (or nothing) for AArch64.
    let x86 = odin_asm::text::assemble("_f:\n    ret # comment\n", "x.s").unwrap();
    assert_eq!(x86.atoms[0].bytes, [0xc3]);
    let same = assemble_for(Arch::X86_64, "_f:\n    ret # comment\n", "x.s").unwrap();
    assert_eq!(same, x86);
    assert!(assemble_for(Arch::Aarch64, "_f:\n    ret # comment\n", "x.s").is_err());
}
