// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Windows executables (PE32+) built from programs hand-assembled with the
//! Win64 ABI: arguments in rcx, rdx, r8, r9 (the fifth at [rsp+32]), 32
//! bytes of shadow space, rsp 16-byte aligned at every call (so 8 mod 16 at
//! entry, as after any call). They are linked everywhere, checked with
//! LLVM's `objdump` when it is installed, and run on Windows.

use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use odin_asm::object::RelocKind::*;
use odin_asm::object::{Atom, Import, Object, SectionKind};
use odin_asm::x86_64::{Assembler, Cond, Mem, Reg::*, Width::*, Xmm};
use odin_link::{LinkOptions, LinkedImage, Target, link};

const KERNEL32: &str = "kernel32.dll";
const UCRT: &str = "ucrtbase.dll";
const STD_OUTPUT_HANDLE: i32 = -11;

fn imports(library: &str, names: &[&str]) -> Vec<Import> {
    names.iter().map(|name| Import { name: name.to_string(), library: library.to_string() }).collect()
}

fn windows(objects: &[Object], name: &str) -> LinkedImage {
    link(objects, &LinkOptions::new(Target::X86_64Windows, "main", name)).unwrap()
}

/// Writes `image` as `name.exe` in the test tmp dir.
fn write_executable(name: &str, image: &LinkedImage) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("odin-link-windows");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(format!("{name}.exe"));
    let _ = std::fs::remove_file(&path);
    std::fs::write(&path, &image.bytes).unwrap();
    path
}

/// Runs an external tool, or returns `None` (and says so) when it is not
/// installed.
fn tool(program: &str, args: &[&str]) -> Option<Output> {
    match Command::new(program).args(args).output() {
        Ok(output) => Some(output),
        Err(error) if error.kind() == ErrorKind::NotFound => {
            eprintln!("skipping the {program} check: not installed");
            None
        }
        Err(error) => panic!("cannot run {program}: {error}"),
    }
}

fn text(output: &Output) -> String {
    format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr))
}

/// `objdump` with `args` on `path`, when the installed `objdump` is LLVM's
/// (the one on macOS is; GNU objdump formats PE headers differently, so it
/// is skipped rather than half-understood).
fn llvm_objdump(path: &Path, args: &[&str]) -> Option<String> {
    let version = tool("objdump", &["--version"])?;
    if !text(&version).contains("LLVM") {
        eprintln!("skipping the objdump check: not LLVM's objdump");
        return None;
    }
    let mut all = args.to_vec();
    all.push(path.to_str().unwrap());
    let output = tool("objdump", &all)?;
    let dump = text(&output);
    assert!(output.status.success(), "objdump rejected {}:\n{dump}", path.display());
    assert!(!dump.contains("warning:") && !dump.contains("error:"), "objdump complained:\n{dump}");
    Some(dump)
}

/// The value after `key` in the header listing of `objdump -p`.
fn field<'d>(dump: &'d str, key: &str) -> &'d str {
    dump.lines()
        .find_map(|line| {
            let mut words = line.split_whitespace();
            if words.next() == Some(key) { words.next() } else { None }
        })
        .unwrap_or_else(|| panic!("no {key}:\n{dump}"))
}

/// (RVA, size) of data directory `index` in `objdump -p`.
fn directory(dump: &str, index: usize) -> (u64, u64) {
    let key = format!("{index:x}");
    let line = dump
        .lines()
        .find(|line| line.split_whitespace().take(2).eq(["Entry", key.as_str()]))
        .unwrap_or_else(|| panic!("no directory {index}:\n{dump}"));
    let words: Vec<&str> = line.split_whitespace().collect();
    (u64::from_str_radix(words[2], 16).unwrap(), u64::from_str_radix(words[3], 16).unwrap())
}

/// Checks the header fields every program shares, the entry point, the
/// absence of `.pdata`, and the DLLs (names as written, in order) and
/// functions it imports.
fn check_headers(dump: &str, image: &LinkedImage, dlls: &[(&str, &[&str])]) {
    let expected = [
        ("Characteristics", "0x22"),
        ("Magic", "020b"),
        ("ImageBase", "0000000140000000"),
        ("SectionAlignment", "00001000"),
        ("FileAlignment", "00000200"),
        ("MajorOSystemVersion", "6"),
        ("MinorOSystemVersion", "0"),
        ("MajorSubsystemVersion", "6"),
        ("MinorSubsystemVersion", "0"),
        ("Subsystem", "00000003"),
        ("DllCharacteristics", "00008160"),
        ("SizeOfStackReserve", "0000000000800000"),
        ("SizeOfStackCommit", "0000000000001000"),
        ("SizeOfHeapReserve", "0000000000100000"),
        ("SizeOfHeapCommit", "0000000000001000"),
        ("NumberOfRvaAndSizes", "00000010"),
    ];
    for (key, value) in expected {
        assert_eq!(field(dump, key), value, "{key}:\n{dump}");
    }
    let entry = image.symbols["main"] - image.image_base;
    assert_eq!(field(dump, "AddressOfEntryPoint"), format!("{entry:016x}"), "{dump}");
    assert_eq!(directory(dump, 3), (0, 0), "no .pdata:\n{dump}");
    let names: Vec<&str> = dump.lines().filter_map(|l| l.trim().strip_prefix("DLL Name: ")).collect();
    let expected: Vec<&str> = dlls.iter().map(|(dll, _)| *dll).collect();
    assert_eq!(names, expected, "import tables:\n{dump}");
    let imported: Vec<&str> = dlls.iter().flat_map(|(_, functions)| functions.iter().copied()).collect();
    let listed: Vec<&str> = dump
        .lines()
        .filter_map(|line| match line.split_whitespace().collect::<Vec<_>>()[..] {
            ["0", name] => Some(name),
            _ => None,
        })
        .collect();
    assert_eq!(listed, imported, "hint 0 and the name of each import, by DLL:\n{dump}");
}

/// Section names from `objdump -h`, in order.
fn section_names(dump: &str) -> Vec<String> {
    dump.lines()
        .filter_map(|line| {
            let mut words = line.split_whitespace();
            match (words.next(), words.next()) {
                (Some(index), Some(name)) if index.parse::<u32>().is_ok() && name.starts_with('.') => {
                    Some(name.to_string())
                }
                _ => None,
            }
        })
        .collect()
}

/// In `objdump -d`, `count` instructions `call [rip + slot]` exist, and
/// each reads an 8-byte slot inside the IAT.
fn check_iat_calls(disassembly: &str, headers: &str, count: usize) {
    let (iat, size) = directory(headers, 12);
    let iat = 0x1_4000_0000 + iat..0x1_4000_0000 + iat + size;
    let slots: Vec<u64> = disassembly
        .lines()
        .filter(|line| line.contains("callq\t*") && line.contains("(%rip)"))
        .map(|line| {
            let target = line.rsplit("# 0x").next().unwrap().trim();
            u64::from_str_radix(target, 16).unwrap_or_else(|_| panic!("no target in `{line}`"))
        })
        .collect();
    assert_eq!(slots.len(), count, "{disassembly}");
    for slot in slots {
        assert!(iat.contains(&slot) && slot % 8 == 0, "slot {slot:#x} outside the IAT {iat:x?}");
    }
}

/// `GetStdHandle(STD_OUTPUT_HANDLE)`, then `WriteFile(handle, buffer,
/// length, &written, NULL)` with the buffer address and length already in
/// rdx and r8. Needs 48 bytes at rsp: shadow space, the fifth argument and
/// the `written` count.
fn write_stdout(a: &mut Assembler) {
    a.mov(W64, Rsi, Rdx);
    a.mov(W64, Rdi, R8);
    a.mov(W32, Rcx, STD_OUTPUT_HANDLE);
    a.call(Mem::got("GetStdHandle"));
    a.mov(W64, Rcx, Rax);
    a.mov(W64, Rdx, Rsi);
    a.mov(W64, R8, Rdi);
    a.lea(W64, R9, Mem::base(Rsp, 40));
    a.mov(W64, Mem::base(Rsp, 32), 0);
    a.call(Mem::got("WriteFile"));
}

/// (a) "hello\n" through kernel32.dll, then `ExitProcess(0)`.
fn hello() -> Vec<Object> {
    let mut a = Assembler::new();
    a.push(Rsi); // rsi and rdi are callee-saved in the Win64 ABI
    a.push(Rdi);
    a.sub(W64, Rsp, 56); // 8 + 16 + 56: aligned
    a.lea(W64, Rdx, Mem::rip("hello_msg", 0));
    a.mov(W32, R8, 6);
    write_stdout(&mut a);
    a.xor(W32, Rcx, Rcx);
    a.call(Mem::got("ExitProcess"));
    a.int3();
    let main = a.finish().unwrap().into_atom("main", 16);
    let msg = Atom::new("hello_msg", SectionKind::ReadOnly, 1, b"hello\n".to_vec());
    vec![Object {
        name: "hello".to_string(),
        atoms: vec![main, msg],
        imports: imports(KERNEL32, &["GetStdHandle", "WriteFile", "ExitProcess"]),
    }]
}

/// (b) Data, bss, pointer tables the loader must relocate (in `.data` and
/// in `.rdata`), calls between atoms (direct, and through a relocated
/// pointer), labels, `__ImageBase`, and atoms and imports smart linking must
/// drop. Prints "linked\nok\n" and exits with 30 + 10 + 2 = 42; a missed
/// relocation adds 100, 200 or 50 to that, or crashes.
fn data_and_calls() -> Vec<Object> {
    let mut a = Assembler::new();
    let (same_base, is_mz, rodata_ok) = (a.new_label(), a.new_label(), a.new_label());
    a.push(Rbx);
    a.push(Rsi);
    a.push(Rdi);
    a.sub(W64, Rsp, 48); // 8 + 24 + 48: aligned
    a.lea(W64, Rbx, Mem::rip("table", 0));
    // copy(buf, msg, 7); copy(buf + 7, msg_ok, 3)
    a.mov(W64, Rcx, Mem::base(Rbx, 8));
    a.mov(W64, Rdx, Mem::base(Rbx, 0));
    a.mov(W32, R8, 7);
    a.call("copy");
    a.mov(W64, Rcx, Mem::base(Rbx, 8));
    a.add(W64, Rcx, 7);
    a.mov(W64, Rdx, Mem::base(Rbx, 16));
    a.mov(W32, R8, 3);
    a.call("copy");
    a.mov(W64, Rdx, Mem::base(Rbx, 8));
    a.mov(W32, R8, 10);
    write_stdout(&mut a);
    // base += 10; bump() twice, through the pointer in table[4]
    a.add(W64, Mem::rip("base", 0), 10);
    a.call(Mem::base(Rbx, 32));
    a.call(Mem::base(Rbx, 32));
    a.mov(W64, Rcx, Mem::rip("base", 0));
    a.add(W64, Rcx, Mem::rip("counter", 0));
    // The relocated pointer to __ImageBase equals its RIP-relative address,
    // which is the DOS header.
    a.lea(W64, Rax, Mem::rip("__ImageBase", 0));
    a.cmp(W64, Rax, Mem::base(Rbx, 24));
    a.jcc(Cond::E, same_base);
    a.add(W32, Rcx, 100);
    a.bind(same_base);
    a.cmp(W16, Mem::base(Rax, 0), 0x5a4d);
    a.jcc(Cond::E, is_mz);
    a.add(W32, Rcx, 200);
    a.bind(is_mz);
    // A pointer in read-only data is relocated too.
    a.mov(W64, Rax, Mem::rip("rotable", 0));
    a.lea(W64, Rdx, Mem::rip("msg", 0));
    a.cmp(W64, Rax, Rdx);
    a.jcc(Cond::E, rodata_ok);
    a.add(W32, Rcx, 50);
    a.bind(rodata_ok);
    a.call(Mem::got("ExitProcess"));
    a.int3();
    let main = a.finish().unwrap().into_atom("main", 16);

    // Pointers the loader slides: msg (through the label and a negative
    // addend), the bss buffer, the label itself, the image base, a function.
    let table = Atom::new("table", SectionKind::Data, 8, vec![0; 40])
        .reloc(0, Abs64, "msg_ok", -7)
        .reloc(8, Abs64, "buf", 0)
        .reloc(16, Abs64, "msg_ok", 0)
        .reloc(24, Abs64, "__ImageBase", 0)
        .reloc(32, Abs64, "bump", 0);
    let rotable = Atom::new("rotable", SectionKind::ReadOnly, 8, vec![0; 8]).reloc(0, Abs64, "msg", 0);
    let base = Atom::new("base", SectionKind::Data, 8, 30u64.to_le_bytes().to_vec());
    let counter = Atom::bss("counter", 8, 8);
    let mut program_imports = imports(KERNEL32, &["GetStdHandle", "WriteFile", "ExitProcess"]);
    program_imports.extend(imports("user32.dll", &["MessageBoxA"]));
    let program = Object {
        name: "program".to_string(),
        atoms: vec![main, table, rotable, base, counter],
        imports: program_imports,
    };

    // copy(dst = rcx, src = rdx, count = r8)
    let mut a = Assembler::new();
    let (copy_loop, done) = (a.new_label(), a.new_label());
    a.test(W64, R8, R8);
    a.jcc(Cond::E, done);
    a.bind(copy_loop);
    a.mov(W8, Rax, Mem::base(Rdx, 0));
    a.mov(W8, Mem::base(Rcx, 0), Rax);
    a.inc(W64, Rdx);
    a.inc(W64, Rcx);
    a.dec(W64, R8);
    a.jcc(Cond::Ne, copy_loop);
    a.bind(done);
    a.ret();
    let copy = a.finish().unwrap().into_atom("copy", 16);
    let mut a = Assembler::new();
    a.inc(W64, Mem::rip("counter", 0));
    a.ret();
    let bump = a.finish().unwrap().into_atom("bump", 16);
    let msg = Atom {
        labels: vec![("msg_ok".to_string(), 7)],
        ..Atom::new("msg", SectionKind::ReadOnly, 1, b"linked\nok\n".to_vec())
    };
    let buf = Atom::bss("buf", 64, 16);
    // Nothing references `unused`; neither its undefined target nor the
    // user32.dll import it would need may matter.
    let mut a = Assembler::new();
    a.call("missing");
    a.call(Mem::got("MessageBoxA"));
    let unused = a.finish().unwrap().into_atom("unused", 1);
    let kept = Atom::new("kept", SectionKind::Text, 1, vec![0xc3]).keep();
    let util = Object {
        name: "util".to_string(),
        atoms: vec![copy, bump, msg, buf, unused, kept],
        imports: imports(KERNEL32, &["WriteFile"]),
    };
    vec![program, util]
}

/// (c) A second DLL: `strlen` and `cos` from ucrtbase.dll. Prints the
/// message and exits with strlen + cos(0) = 13 + 1 = 14. The kernel32.dll
/// imports are spelled three ways, and still share one import descriptor.
fn ucrt() -> Vec<Object> {
    let mut a = Assembler::new();
    a.push(Rbx);
    a.push(Rsi);
    a.push(Rdi);
    a.sub(W64, Rsp, 48);
    a.lea(W64, Rcx, Mem::rip("text", 0));
    a.call(Mem::got("strlen"));
    a.mov(W64, Rbx, Rax);
    a.lea(W64, Rdx, Mem::rip("text", 0));
    a.mov(W64, R8, Rbx);
    write_stdout(&mut a);
    a.xorpd(Xmm::Xmm0, Xmm::Xmm0);
    a.call(Mem::got("cos"));
    a.cvttsd2si(W32, Rcx, Xmm::Xmm0);
    a.add(W32, Rcx, Rbx);
    a.call(Mem::got("ExitProcess"));
    a.int3();
    let main = a.finish().unwrap().into_atom("main", 16);
    let message = Atom::new("text", SectionKind::ReadOnly, 1, b"ucrt says hi\n\0".to_vec());
    let mut first = imports(UCRT, &["strlen"]);
    first.extend(imports("KERNEL32.DLL", &["GetStdHandle"]));
    first.extend(imports("Kernel32.dll", &["ExitProcess"]));
    let mut second = imports(KERNEL32, &["WriteFile"]);
    second.extend(imports("UCRTBASE.DLL", &["cos"]));
    vec![
        Object { name: "main".to_string(), atoms: vec![main, message], imports: first },
        Object { name: "decls".to_string(), atoms: vec![], imports: second },
    ]
}

#[test]
fn hello_links() {
    let image = windows(&hello(), "hello");
    assert_eq!(image.image_base, 0x1_4000_0000);
    assert_eq!(image.symbols["__ImageBase"], image.image_base);
    let path = write_executable("hello", &image);
    if let Some(dump) = llvm_objdump(&path, &["-p", "-h"]) {
        eprintln!("{dump}");
        check_headers(&dump, &image, &[(KERNEL32, &["GetStdHandle", "WriteFile", "ExitProcess"])]);
        assert_eq!(section_names(&dump), [".text", ".rdata"], "nothing to relocate, no data:\n{dump}");
        assert_eq!(field(&dump, "SizeOfHeaders"), "00000200", "two section headers fit 512 bytes");
        assert_eq!(directory(&dump, 5), (0, 0), "no base relocations:\n{dump}");
        assert_eq!(directory(&dump, 12), (0x2000, 32), "the IAT starts .rdata: three slots and a null:\n{dump}");
        if let Some(disassembly) = llvm_objdump(&path, &["-d"]) {
            check_iat_calls(&disassembly, &dump, 3);
        }
    }
}

#[test]
fn data_and_calls_links() {
    let image = windows(&data_and_calls(), "data");
    for name in ["main", "copy", "bump", "msg", "msg_ok", "table", "rotable", "base", "counter", "buf", "kept"] {
        assert!(image.symbols.contains_key(name), "{name} placed");
    }
    assert!(!image.symbols.contains_key("unused"), "smart linking drops unused");
    assert_eq!(image.symbols["msg_ok"], image.symbols["msg"] + 7);
    assert!(!image.bytes.windows(10).any(|w| w.eq_ignore_ascii_case(b"user32.dll")), "unused DLL dropped");
    let path = write_executable("data", &image);
    if let Some(dump) = llvm_objdump(&path, &["-p", "-h"]) {
        check_headers(&dump, &image, &[(KERNEL32, &["GetStdHandle", "WriteFile", "ExitProcess"])]);
        assert_eq!(section_names(&dump), [".text", ".rdata", ".data", ".reloc"], "{dump}");
        assert_eq!(field(&dump, "SizeOfHeaders"), "00000400", "four section headers need 552 bytes");
        // One pointer in .rdata, five in .data: blocks of 8 + 2 + 2 (padding)
        // and 8 + 5 * 2 + 2 (padding) bytes.
        assert_eq!(directory(&dump, 5), (0x4000, 12 + 20), "base relocations:\n{dump}");
        if let Some(disassembly) = llvm_objdump(&path, &["-d"]) {
            check_iat_calls(&disassembly, &dump, 3);
            let lea_image_base = |line: &&str| {
                line.contains("leaq") && line.contains("(%rip), %rax") && line.trim_end().ends_with("# 0x140000000")
            };
            assert!(disassembly.lines().any(|l| lea_image_base(&l)), "lea __ImageBase:\n{disassembly}");
        }
    }
}

#[test]
fn ucrt_links() {
    let image = windows(&ucrt(), "ucrt");
    let path = write_executable("ucrt", &image);
    if let Some(dump) = llvm_objdump(&path, &["-p", "-h"]) {
        check_headers(
            &dump,
            &image,
            &[(UCRT, &["strlen", "cos"]), ("KERNEL32.DLL", &["GetStdHandle", "WriteFile", "ExitProcess"])],
        );
        // Two IAT blocks, each ending in a null slot.
        assert_eq!(directory(&dump, 12), (0x2000, 8 * (3 + 4)), "{dump}");
        if let Some(disassembly) = llvm_objdump(&path, &["-d"]) {
            check_iat_calls(&disassembly, &dump, 5);
        }
    }
}

#[cfg(windows)]
fn run(path: &Path) -> Output {
    let output = Command::new(path).output().unwrap_or_else(|e| panic!("cannot start {}: {e}", path.display()));
    eprintln!(
        "{}: status {:?}, stdout {:?}, stderr {:?}",
        path.display(),
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

#[cfg(windows)]
#[test]
fn hello_runs() {
    let path = write_executable("hello-run", &windows(&hello(), "hello-run"));
    let output = run(&path);
    assert_eq!(String::from_utf8_lossy(&output.stdout), "hello\n");
    assert_eq!(output.status.code(), Some(0));
}

#[cfg(windows)]
#[test]
fn data_and_calls_runs() {
    let path = write_executable("data-run", &windows(&data_and_calls(), "data-run"));
    let output = run(&path);
    assert_eq!(String::from_utf8_lossy(&output.stdout), "linked\nok\n");
    assert_eq!(output.status.code(), Some(42));
}

#[cfg(windows)]
#[test]
fn ucrt_runs() {
    let path = write_executable("ucrt-run", &windows(&ucrt(), "ucrt-run"));
    let output = run(&path);
    assert_eq!(String::from_utf8_lossy(&output.stdout), "ucrt says hi\n");
    assert_eq!(output.status.code(), Some(14));
}
