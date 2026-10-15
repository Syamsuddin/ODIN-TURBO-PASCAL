// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Tests of the `.s` assembler: atoms, sections, local labels, directives and
//! error reporting.

use odin_asm::text::{AsmError, assemble};
use odin_asm::{Atom, Import, Object, Reloc, RelocKind, SectionKind};

fn asm(src: &str) -> Object {
    assemble(src, "test.s").unwrap_or_else(|e| panic!("{e}"))
}

fn err(src: &str) -> AsmError {
    assemble(src, "test.s").expect_err("expected an error")
}

fn atom<'a>(obj: &'a Object, name: &str) -> &'a Atom {
    obj.atoms.iter().find(|a| a.name == name).unwrap_or_else(|| panic!("no atom {name}"))
}

#[test]
fn shim_example_from_the_docs() {
    let obj = asm(r#"
.intel_syntax noprefix
.text
.keep _odin_start
_odin_start:                      # a new atom
    push rbp
    mov rbp, rsp
    mov qword ptr [rip + _odin_argc], rdi
    call qword ptr [rip + _exit@GOTPCREL]
.Lloop:                           # local to _odin_start
    jmp .Lloop

.import _exit, "/usr/lib/libSystem.B.dylib"

.bss
.align 8
_odin_argc:
    .zero 8
"#);
    assert_eq!(obj.name, "test.s");
    assert_eq!(obj.atoms.len(), 2);
    let start = &obj.atoms[0];
    assert_eq!(
        (start.name.as_str(), start.section, start.align, start.keep),
        ("_odin_start", SectionKind::Text, 16, true)
    );
    assert_eq!(start.bytes, [0x55, 0x48, 0x89, 0xe5, 0x48, 0x89, 0x3d, 0, 0, 0, 0, 0xff, 0x15, 0, 0, 0, 0, 0xeb, 0xfe]);
    assert_eq!(
        start.relocs,
        [
            Reloc { offset: 7, kind: RelocKind::X86Pc32, target: "_odin_argc".into(), addend: -4 },
            Reloc { offset: 13, kind: RelocKind::X86GotPc32, target: "_exit".into(), addend: -4 },
        ]
    );
    assert_eq!(obj.atoms[1], Atom::bss("_odin_argc", 8, 8));
    assert_eq!(obj.imports, [Import { name: "_exit".into(), library: "/usr/lib/libSystem.B.dylib".into() }]);
}

#[test]
fn sections_and_atom_continuation() {
    let obj = asm(r#"
.text
_f:
    mov eax, 1
.data
_counter:
    .long 7
.rodata
_msg:
    .asciz "hi"
.text
    ret             # continues _f
.data
    .long 8         # continues _counter
"#);
    let names: Vec<(&str, SectionKind)> = obj.atoms.iter().map(|a| (a.name.as_str(), a.section)).collect();
    assert_eq!(names, [("_f", SectionKind::Text), ("_counter", SectionKind::Data), ("_msg", SectionKind::ReadOnly)]);
    assert_eq!(atom(&obj, "_f").bytes, [0xb8, 1, 0, 0, 0, 0xc3]);
    assert_eq!(atom(&obj, "_counter").bytes, [7, 0, 0, 0, 8, 0, 0, 0]);
    assert_eq!(atom(&obj, "_msg").bytes, b"hi\0");
    assert_eq!(atom(&obj, "_msg").align, 1);
}

#[test]
fn local_labels_are_per_atom() {
    let obj = asm(r#"
_a:
.Lx:
    jmp .Lx
_b:
    nop
.Lx:
    jmp .Lx
    jmp _a
"#);
    assert_eq!(atom(&obj, "_a").bytes, [0xeb, 0xfe]);
    assert_eq!(atom(&obj, "_b").bytes, [0x90, 0xeb, 0xfe, 0xe9, 0, 0, 0, 0]);
    assert_eq!(atom(&obj, "_b").relocs[0].target, "_a");

    let e = err("_a:\n    jmp .Ly\n_b:\n.Ly:\n    ret\n");
    assert_eq!(e.line, 2);
    assert_eq!(e.message, "undefined label `.Ly` (`.L` labels are local to their atom, `_a`)");
}

#[test]
fn local_labels_in_data_become_self_relocations() {
    let obj = asm(r#"
.rodata
.align 8
_table:
    .quad .Lone, .Ltwo + 1, _other - 8
.Lone:
    .byte 1
.Ltwo:
    .byte 2
"#);
    let t = atom(&obj, "_table");
    assert_eq!((t.align, t.size), (8, 26));
    assert_eq!(
        t.relocs,
        [
            Reloc { offset: 0, kind: RelocKind::Abs64, target: "_table".into(), addend: 24 },
            Reloc { offset: 8, kind: RelocKind::Abs64, target: "_table".into(), addend: 26 },
            Reloc { offset: 16, kind: RelocKind::Abs64, target: "_other".into(), addend: -8 },
        ]
    );
}

#[test]
fn rip_relative_local_label_in_code() {
    let obj = asm(r#"
_f:
    lea rax, [rip + .Lmsg]
    ret
.Lmsg:
    .ascii "ok"
"#);
    assert_eq!(atom(&obj, "_f").bytes, [0x48, 0x8d, 0x05, 1, 0, 0, 0, 0xc3, b'o', b'k']);
    assert!(atom(&obj, "_f").relocs.is_empty());
}

#[test]
fn keep_import_and_globl() {
    let obj = asm(r#"
.globl _main
.keep _main
.import _write, "/usr/lib/libSystem.B.dylib"
.import _write, "/usr/lib/libSystem.B.dylib"
.import _exit, "/usr/lib/libSystem.B.dylib"
_main:
    ret
_helper:
    ret
"#);
    assert!(atom(&obj, "_main").keep);
    assert!(!atom(&obj, "_helper").keep);
    let imports: Vec<&str> = obj.imports.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(imports, ["_write", "_exit"]);
}

#[test]
fn align_directives() {
    let obj = asm(r#"
.text
.align 4
_f:
    nop
    .align 8
.Lhere:
    ret
.p2align 5
_g:
    ret
.data
.balign 4
_d:
    .byte 1
    .align 4
    .byte 2
.bss
_z:
    .zero 3
    .align 8
    .zero 1
"#);
    let f = atom(&obj, "_f");
    assert_eq!(f.align, 8);
    assert_eq!(f.bytes, [0x90, 0x0f, 0x1f, 0x80, 0, 0, 0, 0, 0xc3]);
    assert_eq!(atom(&obj, "_g").align, 32);
    let d = atom(&obj, "_d");
    assert_eq!((d.align, d.bytes.clone()), (4, vec![1, 0, 0, 0, 2]));
    let z = atom(&obj, "_z");
    assert_eq!((z.align, z.size), (8, 9));
}

#[test]
fn data_directives() {
    let obj = asm(r#"
SIX = 6
.set SEVEN, SIX + 1
.equ MASK, 1 << 4
.data
_d:
    .byte 1, -1, 0xff, 'A', SEVEN
    .short -2, 0xffff
    .word 3
    .long 0x12345678, -1, MASK
    .quad -1, 0x8000000000000000
    .ascii "a#b;c", "\n\t\0\\\"\x41\101"
    .asciz ""
    .string "z"
    .space 2, 0x55
    .zero 1
"#);
    let mut want = vec![1, 0xff, 0xff, b'A', 7, 0xfe, 0xff, 0xff, 0xff, 3, 0, 0x78, 0x56, 0x34, 0x12];
    want.extend([0xff; 4]);
    want.extend([16, 0, 0, 0]);
    want.extend([0xff; 8]);
    want.extend([0, 0, 0, 0, 0, 0, 0, 0x80]);
    want.extend(b"a#b;c\n\t\0\\\"AA");
    want.extend(b"\0z\0");
    want.extend([0x55, 0x55, 0]);
    assert_eq!(atom(&obj, "_d").bytes, want);
}

#[test]
fn constants_in_operands_and_data_in_code() {
    let obj = asm(r#"
FRAME = 32
_f:
    sub rsp, FRAME
    mov qword ptr [rbp - FRAME / 4], 0
    .byte 0xcc
    .quad _target + 8
"#);
    let f = atom(&obj, "_f");
    assert_eq!(&f.bytes[..12], &[0x48, 0x83, 0xec, 0x20, 0x48, 0xc7, 0x45, 0xf8, 0, 0, 0, 0]);
    assert_eq!(&f.bytes[12..], &[0xcc, 0, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(f.relocs, [Reloc { offset: 13, kind: RelocKind::Abs64, target: "_target".into(), addend: 8 }]);
}

#[test]
fn comments_case_and_line_endings() {
    let obj = asm("_f: ; comment\r\n    MOV EAX, 'A' # trailing\r\n    Rep StosB\r\n    ret ; done\r\n");
    assert_eq!(atom(&obj, "_f").bytes, [0xb8, 0x41, 0, 0, 0, 0xf3, 0xaa, 0xc3]);
}

#[test]
fn label_and_instruction_on_one_line() {
    let obj = asm("_f: _g: ret\n");
    assert_eq!(atom(&obj, "_f").size, 0);
    assert_eq!(atom(&obj, "_g").bytes, [0xc3]);
}

#[test]
fn error_messages_carry_file_and_line() {
    let cases: &[(&str, u32, &str)] = &[
        ("_f:\n    frob rax\n", 2, "unknown instruction `frob`"),
        ("_f:\n\n    mov qword ptr [rax], qword ptr [rbx]\n", 3, "mov: invalid operands (memory, memory)"),
        ("_f:\n    mov [rax], 1\n", 2, "operand size is ambiguous; add byte/word/dword/qword ptr"),
        ("_f:\n    mov eax, rbx\n", 2, "operand size mismatch"),
        ("_f:\n    add rax, 0x80000000\n", 2, "add: immediate 2147483648 does not fit in a sign-extended 32-bit field"),
        ("_f:\n    mov al, ah\n", 2, "high-byte register `ah` is not supported"),
        ("_f:\n    mov eax, dword ptr [eax]\n", 2, "`eax` cannot address memory; use a 64-bit register"),
        ("_f:\n    lea rax, [_sym]\n", 2, "an absolute address is not position-independent; write `[rip + _sym]`"),
        ("_f:\n    mov rax, _sym\n", 2, "symbol `_sym` cannot be used here (as an address: `[rip + _sym]`)"),
        ("_f:\n    ret 1, 2\n", 2, "`ret` takes no operand or a 16-bit immediate"),
        ("_f:\n    nop rax\n", 2, "`nop` takes no operands"),
        ("_f:\n    movzx eax, [rbx]\n", 2, "source size is ambiguous; add byte ptr or word ptr"),
        ("_f:\n    movsd xmm0, dword ptr [rax]\n", 2, "memory operand must be 8 bytes"),
        ("_f:\n    rep ret\n", 2, "prefix `rep` is not supported with `ret`"),
        ("    ret\n", 1, "content before the first label of the section; start an atom with a label"),
        (".data\n_d:\n    ret\n", 3, "instruction `ret` outside `.text`"),
        (".data\n_d:\n    .byte 256\n", 3, "value 256 does not fit in 1 bytes"),
        (".data\n_d:\n    .long _sym\n", 3, "only `.quad` can hold the address of `_sym`"),
        (".bss\n_b:\n    .byte 1\n", 3, "`.bss` can only hold zeros (use `.zero`)"),
        ("_f:\n    ret\n_f:\n", 3, "symbol `_f` is already defined at line 1"),
        ("_f:\n.La:\n.La:\n", 3, "label `.La` is already defined at line 2"),
        (".frob 1\n", 1, "unknown directive `.frob`"),
        (".align 3\n", 1, "alignment 3 is not a power of two up to 4096"),
        (".att_syntax\n", 1, "AT&T syntax is not supported; use Intel syntax"),
        (".keep _nothing\n_f:\n    ret\n", 1, "`.keep _nothing`: no atom of that name in this file"),
        (".import _f, \"/usr/lib/libSystem.B.dylib\"\n_f:\n", 1, "`_f` is both imported and defined (at line 2)"),
        (".import _w, \"a\"\n.import _w, \"b\"\n", 2, "`_w` is already imported from \"a\" at line 1"),
        (".ascii \"abc\n", 1, "unterminated string"),
        ("_f:\n    mov eax, 010\n", 2, "number `010` has a leading zero (write it in decimal, or with 0o for octal)"),
        (
            "_f:\n    jmp .Lnowhere\n    ret\n",
            2,
            "undefined label `.Lnowhere` (`.L` labels are local to their atom, `_f`)",
        ),
        ("_f:\n    call [rip + _x@GOTPCREL + 8]\n", 2, "`@GOTPCREL` is only allowed as `[rip + sym@GOTPCREL]`"),
        ("_f:\n    shl eax, ebx\n", 2, "the shift count must be an immediate or `cl`"),
        ("_f:\n    push eax\n", 2, "`push` needs a 64-bit register or qword memory operand"),
        ("_f:\n    je rax\n", 2, "a conditional jump needs a label or symbol"),
    ];
    for &(src, line, message) in cases {
        let e = err(src);
        assert_eq!((e.line, e.message.as_str()), (line, message), "source: {src:?}");
        assert_eq!(e.file, "test.s");
    }
    assert_eq!(err("_f:\n    frob\n").to_string(), "test.s:2: unknown instruction `frob`");
}

#[test]
fn mxcsr_load_and_store() {
    let obj = asm(
        ".intel_syntax noprefix\n.text\nf:\n    stmxcsr dword ptr [rsp - 4]\n    ldmxcsr dword ptr [rdi]\n    ret\n",
    );
    // 0f ae /3 with [rsp - 4] (SIB, disp8), then 0f ae /2 with [rdi].
    assert_eq!(atom(&obj, "f").bytes, [0x0F, 0xAE, 0x5C, 0x24, 0xFC, 0x0F, 0xAE, 0x17, 0xC3]);
    assert!(err(".intel_syntax noprefix\n.text\nf:\n    ldmxcsr eax\n").to_string().contains("memory operand"));
}
