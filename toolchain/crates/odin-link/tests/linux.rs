// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Small hand-assembled programs linked into Linux ELF executables for both
//! architectures, checked with `objdump` and `readelf` when installed, and
//! run where Linux is at hand:
//!
//! * natively, on Linux of the program's architecture;
//! * through a command prefix in `ODIN_LINUX_RUN` (x86_64 programs) or
//!   `ODIN_LINUX_RUN_AARCH64` (aarch64 programs), split on whitespace, e.g.
//!   `ODIN_LINUX_RUN="limactl shell odin-linux --"` and
//!   `ODIN_LINUX_RUN_AARCH64="limactl shell odin-linux -- qemu-aarch64-static -L /usr/aarch64-linux-gnu"`.
//!   The executable's absolute path is appended, so it must be visible at
//!   the same path where the command runs it.
//!
//! Otherwise execution is skipped and only the structure is checked. Every
//! program starts like a glibc one: `_start` hands `main` to
//! `__libc_start_main`, reached through the GOT like every import.

use std::io::ErrorKind;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use odin_asm::object::RelocKind::*;
use odin_asm::object::{Atom, Import, Object, SectionKind};
use odin_asm::x86_64::{Assembler, Cond, Mem, Reg::*, Width::*, Xmm};
use odin_link::{LinkOptions, LinkedImage, Target, link};

const GLIBC: [&str; 2] = ["libc.so.6", "libm.so.6"];

fn libc(names: &[&str]) -> Vec<Import> {
    names.iter().map(|name| Import { name: name.to_string(), library: "libc".to_string() }).collect()
}

fn options(target: Target) -> LinkOptions {
    LinkOptions::new(target, "_start", "test")
}

/// Writes `image` as an executable file named `name` in the test tmp dir.
fn write_executable(name: &str, image: &LinkedImage) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("odin-link-linux");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    let _ = std::fs::remove_file(&path);
    std::fs::write(&path, &image.bytes).unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
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

/// Whether this machine runs Linux on `target`'s architecture.
fn native(target: Target) -> bool {
    match target {
        Target::X86_64Linux => cfg!(all(target_os = "linux", target_arch = "x86_64")),
        Target::Aarch64Linux => cfg!(all(target_os = "linux", target_arch = "aarch64")),
        _ => unreachable!("Linux targets only"),
    }
}

/// The command prefix that runs a program for `target`, or `None` when
/// nothing here can.
fn runner(target: Target) -> Option<Vec<String>> {
    let variable = if target == Target::X86_64Linux { "ODIN_LINUX_RUN" } else { "ODIN_LINUX_RUN_AARCH64" };
    match std::env::var(variable) {
        Ok(prefix) if !prefix.trim().is_empty() => Some(prefix.split_whitespace().map(String::from).collect()),
        _ if native(target) => Some(Vec::new()),
        _ => {
            eprintln!("not running the {0} program: this is not {0} and {variable} is not set", target.triple());
            None
        }
    }
}

/// Runs the program at `path` if this machine can.
fn run(target: Target, path: &Path) -> Option<Output> {
    let prefix = runner(target)?;
    let mut command = match prefix.split_first() {
        Some((program, args)) => {
            let mut command = Command::new(program);
            command.args(args).arg(path);
            command
        }
        None => Command::new(path),
    };
    let output = command.output().unwrap_or_else(|e| panic!("cannot start {}: {e}", path.display()));
    eprintln!(
        "{}: status {:?}, stdout {:?}, stderr {:?}",
        path.display(),
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    Some(output)
}

/// Runs the program where possible and checks its output and exit status.
fn expect_run(target: Target, path: &Path, stdout: &str, status: i32) {
    if let Some(output) = run(target, path) {
        assert_eq!(String::from_utf8_lossy(&output.stdout), stdout, "stdout of {}", path.display());
        assert_eq!(output.status.code(), Some(status), "{}:\n{}", path.display(), text(&output));
    }
}

/// Checks the file with `objdump` (LLVM's reads both architectures, GNU's
/// only its own) and GNU `readelf` (any architecture), when installed.
fn check_with_tools(path: &Path, target: Target, imports: &[&str], needed: &[&str]) {
    let file = path.to_str().unwrap();
    let objdump = |flag: &str| {
        let output = tool("objdump", &[flag, file])?;
        let listing = text(&output);
        assert!(output.status.success(), "objdump {flag} failed:\n{listing}");
        Some(listing)
    };
    let readable = tool("objdump", &["--version"]).is_some_and(|v| text(&v).contains("LLVM")) || native(target);
    if readable && let Some(headers) = objdump("-p") {
        for kind in ["PHDR", "INTERP", "LOAD", "DYNAMIC", "RELRO", "STACK", "r-x", "rw-"] {
            assert!(headers.contains(kind), "no {kind} in the program headers:\n{headers}");
        }
        assert!(!headers.contains("rwx"), "a segment is writable and executable:\n{headers}");
        let dynamic: Vec<&str> = headers.lines().filter(|l| l.contains("NEEDED")).map(str::trim_end).collect();
        assert_eq!(dynamic.len(), needed.len(), "{headers}");
        for (line, soname) in dynamic.iter().zip(needed) {
            assert!(line.ends_with(soname), "{line} is not {soname}");
        }
        for tag in ["HASH", "STRTAB", "SYMTAB", "DEBUG", "FLAGS_1"] {
            assert!(headers.lines().any(|l| l.trim_start().starts_with(tag)), "no {tag}:\n{headers}");
        }
    }
    if readable && let Some(sections) = objdump("-h") {
        for name in [".interp", ".hash", ".dynsym", ".dynstr", ".text", ".dynamic"] {
            assert!(sections.contains(name), "no {name} section:\n{sections}");
        }
    }
    if readable && let Some(symbols) = objdump("-T") {
        for import in imports {
            let undefined = symbols.lines().any(|l| l.contains("*UND*") && l.split_whitespace().any(|w| w == *import));
            assert!(undefined, "{import} is not an undefined dynamic symbol:\n{symbols}");
        }
    }
    if readable && let Some(relocations) = objdump("-R") {
        for import in imports {
            assert!(
                relocations.lines().any(|l| l.contains("GLOB_DAT") && l.contains(import)),
                "no GLOB_DAT for {import}:\n{relocations}"
            );
        }
    }
    // The symbol table names the code.
    if readable && let Some(listing) = objdump("-d") {
        assert!(listing.contains("<_start>:"), "{listing}");
        assert!(listing.contains("<main>:") || !imports.contains(&"__libc_start_main"), "{listing}");
        assert!(!listing.contains("(bad)"), "{listing}");
    }
    if let Some(output) = tool("readelf", &["-W", "-a", file]) {
        let report = text(&output);
        assert!(output.status.success(), "readelf failed:\n{report}");
        assert!(output.stderr.is_empty(), "readelf complains:\n{report}");
        assert!(report.contains("DYN (Position-Independent Executable file)"), "{report}");
    }
}

/// Links `objects` for `target`, writes the result as `name` and checks it.
fn build(name: &str, target: Target, objects: &[Object], imports: &[&str], needed: &[&str]) -> (LinkedImage, PathBuf) {
    let image = link(objects, &options(target)).unwrap_or_else(|e| panic!("{name}: {e}"));
    let path = write_executable(name, &image);
    check_with_tools(&path, target, imports, needed);
    (image, path)
}

fn arm64_code(name: &str, words: &[u32]) -> Atom {
    Atom::new(name, SectionKind::Text, 4, words.iter().flat_map(|w| w.to_le_bytes()).collect())
}

fn program(start: Atom, atoms: Vec<Atom>, imports: &[&str]) -> Vec<Object> {
    vec![
        Object { name: "start".to_string(), atoms: vec![start], imports: libc(&["__libc_start_main"]) },
        Object { name: "program".to_string(), atoms, imports: libc(imports) },
    ]
}

// ----- x86_64 ---------------------------------------------------------

/// glibc's `_start`: `__libc_start_main(main, argc, argv, init, fini,
/// rtld_fini, stack_end)`, with ld.so's `rtld_fini` in rdx.
fn start_x86_64() -> Atom {
    let mut a = Assembler::new();
    a.xor(W32, Rbp, Rbp); // the outermost frame
    a.mov(W64, R9, Rdx); // rtld_fini
    a.pop(Rsi); // argc
    a.mov(W64, Rdx, Rsp); // argv
    a.and(W64, Rsp, -16);
    a.push(Rax); // keeps the stack 16-byte aligned
    a.push(Rsp); // stack_end
    a.xor(W32, R8, R8); // fini
    a.xor(W32, Rcx, Rcx); // init
    a.lea(W64, Rdi, Mem::rip("main", 0));
    a.call(Mem::got("__libc_start_main"));
    a.ud2(); // never returns
    a.finish().unwrap().into_atom("_start", 16)
}

fn finish(a: Assembler, name: &str) -> Atom {
    a.finish().unwrap().into_atom(name, 16)
}

/// `write(1, "hello\n", 6); return 0;`
fn hello_x86_64() -> Vec<Object> {
    let mut a = Assembler::new();
    a.push(Rbp);
    a.mov(W64, Rbp, Rsp);
    a.mov(W32, Rdi, 1);
    a.lea(W64, Rsi, Mem::rip("msg", 0));
    a.mov(W32, Rdx, 6);
    a.call(Mem::got("write"));
    a.xor(W32, Rax, Rax);
    a.pop(Rbp);
    a.ret();
    let msg = Atom::new("msg", SectionKind::ReadOnly, 1, b"hello\n".to_vec());
    program(start_x86_64(), vec![finish(a, "main"), msg], &["write"])
}

/// Data, bss, a read-only pointer table ld.so must relocate (local targets,
/// a label with a negative addend, an import and `__ehdr_start`), a call
/// between atoms, a GOT slot holding a local address, and atoms smart
/// linking must drop. Prints "linked\nok\nELF" and exits with
/// 30 + 10 + 2 = 42.
fn data_and_calls_x86_64() -> Vec<Object> {
    let mut a = Assembler::new();
    let fail = a.new_label();
    a.push(Rbp);
    a.mov(W64, Rbp, Rsp);
    a.push(Rbx);
    a.sub(W64, Rsp, 8);
    a.lea(W64, Rbx, Mem::rip("table", 0));
    a.mov(W64, Rdi, Mem::base(Rbx, 8)); // buf
    a.mov(W64, Rsi, Mem::base(Rbx, 0)); // msg
    a.mov(W32, Rdx, 7);
    a.call("copy");
    a.mov(W64, Rdi, Mem::base(Rbx, 8));
    a.add(W64, Rdi, 7);
    a.mov(W64, Rsi, Mem::base(Rbx, 16)); // msg_ok
    a.mov(W32, Rdx, 3);
    a.call("copy");
    a.mov(W32, Rdi, 1);
    a.mov(W64, Rsi, Mem::base(Rbx, 8));
    a.mov(W32, Rdx, 10);
    a.call(Mem::base(Rbx, 24)); // write, through an absolute pointer
    // The table's pointer to the header agrees with the PC-relative
    // address, and the header starts with "\x7fELF".
    a.lea(W64, Rsi, Mem::rip("__ehdr_start", 0));
    a.cmp(W64, Rsi, Mem::base(Rbx, 32));
    a.jcc(Cond::Ne, fail);
    a.add(W64, Rsi, 1);
    a.mov(W32, Rdi, 1);
    a.mov(W32, Rdx, 3);
    a.call(Mem::got("write"));
    a.mov(W64, Rax, Mem::got("base")); // a local GOT slot
    a.add(W64, Mem::base(Rax, 0), 10);
    a.inc(W64, Mem::rip("counter", 0));
    a.inc(W64, Mem::rip("counter", 0));
    a.mov(W64, Rdi, Mem::rip("base", 0));
    a.add(W64, Rdi, Mem::rip("counter", 0));
    a.call(Mem::got("exit"));
    a.bind(fail);
    a.mov(W32, Rdi, 99);
    a.call(Mem::got("exit"));
    a.ud2();
    let table = Atom::new("table", SectionKind::ReadOnly, 8, vec![0; 40])
        .reloc(0, Abs64, "msg_ok", -7)
        .reloc(8, Abs64, "buf", 0)
        .reloc(16, Abs64, "msg_ok", 0)
        .reloc(24, Abs64, "write", 0)
        .reloc(32, Abs64, "__ehdr_start", 0);
    let base = Atom::new("base", SectionKind::Data, 8, 30u64.to_le_bytes().to_vec());
    let counter = Atom::bss("counter", 8, 8);

    let mut c = Assembler::new();
    let (copy_loop, done) = (c.new_label(), c.new_label());
    c.test(W64, Rdx, Rdx);
    c.jcc(Cond::E, done);
    c.bind(copy_loop);
    c.mov(W8, Rax, Mem::base(Rsi, 0));
    c.mov(W8, Mem::base(Rdi, 0), Rax);
    c.inc(W64, Rsi);
    c.inc(W64, Rdi);
    c.dec(W64, Rdx);
    c.jcc(Cond::Ne, copy_loop);
    c.bind(done);
    c.ret();
    let msg = Atom {
        labels: vec![("msg_ok".to_string(), 7)],
        ..Atom::new("msg", SectionKind::ReadOnly, 1, b"linked\nok\n".to_vec())
    };
    let buf = Atom::bss("buf", 64, 16);
    // Nothing references `unused`; its undefined target must not matter.
    let unused = Atom::new("unused", SectionKind::Text, 1, vec![0xe9, 0, 0, 0, 0]).reloc(1, X86Pc32, "missing", -4);
    let kept = Atom::new("kept", SectionKind::Text, 1, vec![0xc3]).keep();
    let atoms = vec![finish(a, "main"), table, base, counter, finish(c, "copy"), msg, buf, unused, kept];
    program(start_x86_64(), atoms, &["write", "exit", "puts"])
}

/// `return (int)cos(0.0) + 41;` libm must be loaded for `cos` to bind.
fn cos_x86_64() -> Vec<Object> {
    let mut a = Assembler::new();
    a.push(Rbp);
    a.mov(W64, Rbp, Rsp);
    a.xorpd(Xmm::Xmm0, Xmm::Xmm0);
    a.call(Mem::got("cos"));
    a.cvttsd2si(W32, Rax, Xmm::Xmm0);
    a.add(W32, Rax, 41);
    a.pop(Rbp);
    a.ret();
    program(start_x86_64(), vec![finish(a, "main")], &["cos"])
}

/// `main(argc, argv, envp)` checks that the data import `environ`, read
/// through its GOT slot, is the `envp` glibc passed, and says so.
fn environ_x86_64() -> Vec<Object> {
    let mut a = Assembler::new();
    let fail = a.new_label();
    a.push(Rbp);
    a.mov(W64, Rbp, Rsp);
    a.mov(W64, Rax, Mem::got("environ")); // &environ
    a.mov(W64, Rax, Mem::base(Rax, 0));
    a.cmp(W64, Rax, Rdx);
    a.jcc(Cond::Ne, fail);
    a.mov(W32, Rdi, 1);
    a.lea(W64, Rsi, Mem::rip("ok", 0));
    a.mov(W32, Rdx, 11);
    a.call(Mem::got("write"));
    a.xor(W32, Rax, Rax);
    a.pop(Rbp);
    a.ret();
    a.bind(fail);
    a.mov(W32, Rax, 1);
    a.pop(Rbp);
    a.ret();
    let ok = Atom::new("ok", SectionKind::ReadOnly, 1, b"environ ok\n".to_vec());
    program(start_x86_64(), vec![finish(a, "main"), ok], &["write", "environ"])
}

/// Prints "before\n", then stores into a pointer table that ld.so made
/// read-only after relocating it (PT_GNU_RELRO, with the GOT); the store
/// must fault before "after\n" is printed.
fn relro_x86_64() -> Vec<Object> {
    let mut a = Assembler::new();
    a.push(Rbp);
    a.mov(W64, Rbp, Rsp);
    for (message, length) in [("before", 7), ("after", 6)] {
        a.mov(W32, Rdi, 1);
        a.lea(W64, Rsi, Mem::rip(message, 0));
        a.mov(W32, Rdx, length);
        a.call(Mem::got("write"));
        if message == "before" {
            a.lea(W64, Rax, Mem::rip("table", 0));
            a.mov(W64, Mem::base(Rax, 0), 0);
        }
    }
    a.xor(W32, Rax, Rax);
    a.pop(Rbp);
    a.ret();
    let atoms = vec![
        finish(a, "main"),
        Atom::new("table", SectionKind::ReadOnly, 8, vec![0; 8]).reloc(0, Abs64, "main", 0),
        Atom::new("before", SectionKind::ReadOnly, 1, b"before\n".to_vec()),
        Atom::new("after", SectionKind::ReadOnly, 1, b"after\n".to_vec()),
    ];
    program(start_x86_64(), atoms, &["write"])
}

/// No libraries at all: `_start` exits with 7 through a system call. ld.so
/// still loads and relocates the program.
fn no_imports_x86_64() -> Vec<Object> {
    let mut a = Assembler::new();
    a.mov(W32, Rdi, 7);
    a.mov(W32, Rax, 60); // exit
    a.syscall();
    vec![Object { name: "bare".to_string(), atoms: vec![finish(a, "_start")], imports: vec![] }]
}

// ----- aarch64 --------------------------------------------------------

/// glibc's `_start` for aarch64; ld.so passes `rtld_fini` in x0.
fn start_arm64() -> Atom {
    #[rustfmt::skip]
    let words = [
        0xd280_001d, // 00 mov  x29, #0
        0xd280_001e, // 04 mov  x30, #0
        0xaa00_03e5, // 08 mov  x5, x0                 rtld_fini
        0xf940_03e1, // 0c ldr  x1, [sp]               argc
        0x9100_23e2, // 10 add  x2, sp, #8             argv
        0x9100_03e6, // 14 mov  x6, sp                 stack_end
        0x9000_0000, // 18 adrp x0, main
        0x9100_0000, // 1c add  x0, x0, :lo12:main
        0xd280_0003, // 20 mov  x3, #0                 init
        0xd280_0004, // 24 mov  x4, #0                 fini
        0x9000_0010, // 28 adrp x16, :got:__libc_start_main
        0xf940_0210, // 2c ldr  x16, [x16, :got_lo12:__libc_start_main]
        0xd63f_0200, // 30 blr  x16
        0x0000_0000, // 34 udf  #0                     never returns
    ];
    arm64_code("_start", &words)
        .reloc(0x18, Arm64Page21, "main", 0)
        .reloc(0x1c, Arm64PageOff12 { scale: 0 }, "main", 0)
        .reloc(0x28, Arm64GotPage21, "__libc_start_main", 0)
        .reloc(0x2c, Arm64GotPageOff12, "__libc_start_main", 0)
}

/// `write(1, "hello\n", 6); return 0;`
fn hello_arm64() -> Vec<Object> {
    #[rustfmt::skip]
    let words = [
        0xa9bf_7bfd, // 00 stp  x29, x30, [sp, #-16]!
        0x9100_03fd, // 04 mov  x29, sp
        0x5280_0020, // 08 mov  w0, #1
        0x9000_0001, // 0c adrp x1, msg
        0x9100_0021, // 10 add  x1, x1, :lo12:msg
        0x5280_00c2, // 14 mov  w2, #6
        0x9000_0010, // 18 adrp x16, :got:write
        0xf940_0210, // 1c ldr  x16, [x16, :got_lo12:write]
        0xd63f_0200, // 20 blr  x16
        0x5280_0000, // 24 mov  w0, #0
        0xa8c1_7bfd, // 28 ldp  x29, x30, [sp], #16
        0xd65f_03c0, // 2c ret
    ];
    let main = arm64_code("main", &words)
        .reloc(0x0c, Arm64Page21, "msg", 0)
        .reloc(0x10, Arm64PageOff12 { scale: 0 }, "msg", 0)
        .reloc(0x18, Arm64GotPage21, "write", 0)
        .reloc(0x1c, Arm64GotPageOff12, "write", 0);
    let msg = Atom::new("msg", SectionKind::ReadOnly, 1, b"hello\n".to_vec());
    program(start_arm64(), vec![main, msg], &["write"])
}

/// The aarch64 counterpart of [`data_and_calls_x86_64`].
fn data_and_calls_arm64() -> Vec<Object> {
    #[rustfmt::skip]
    let words = [
        0xa9be_7bfd, // 00 stp  x29, x30, [sp, #-32]!
        0x9100_03fd, // 04 mov  x29, sp
        0xf900_0bf3, // 08 str  x19, [sp, #16]
        0x9000_0013, // 0c adrp x19, table
        0x9100_0273, // 10 add  x19, x19, :lo12:table
        0xf940_0660, // 14 ldr  x0, [x19, #8]           buf
        0xf940_0261, // 18 ldr  x1, [x19]               msg
        0xd280_0142, // 1c mov  x2, #10
        0x9400_0000, // 20 bl   copy
        0x5280_0020, // 24 mov  w0, #1
        0xf940_0661, // 28 ldr  x1, [x19, #8]
        0xd280_0142, // 2c mov  x2, #10
        0xf940_0a70, // 30 ldr  x16, [x19, #16]         write, through an absolute pointer
        0xd63f_0200, // 34 blr  x16
        0x9000_0001, // 38 adrp x1, __ehdr_start
        0x9100_0021, // 3c add  x1, x1, :lo12:__ehdr_start
        0xf940_0e70, // 40 ldr  x16, [x19, #24]
        0xeb10_003f, // 44 cmp  x1, x16
        0x5400_02c1, // 48 b.ne fail
        0x9100_0421, // 4c add  x1, x1, #1              "ELF"
        0x5280_0020, // 50 mov  w0, #1
        0xd280_0062, // 54 mov  x2, #3
        0x9000_0010, // 58 adrp x16, :got:write
        0xf940_0210, // 5c ldr  x16, [x16, :got_lo12:write]
        0xd63f_0200, // 60 blr  x16
        0x9000_0010, // 64 adrp x16, :got:base           a local GOT slot
        0xf940_0210, // 68 ldr  x16, [x16, :got_lo12:base]
        0xf940_0200, // 6c ldr  x0, [x16]
        0x9100_2800, // 70 add  x0, x0, #10
        0xf900_0200, // 74 str  x0, [x16]
        0x9000_0011, // 78 adrp x17, counter
        0x9100_0231, // 7c add  x17, x17, :lo12:counter
        0xf940_0221, // 80 ldr  x1, [x17]
        0x9100_0821, // 84 add  x1, x1, #2
        0xf900_0221, // 88 str  x1, [x17]
        0xf940_0221, // 8c ldr  x1, [x17]
        0x8b01_0000, // 90 add  x0, x0, x1
        0xf940_0bf3, // 94 ldr  x19, [sp, #16]
        0xa8c2_7bfd, // 98 ldp  x29, x30, [sp], #32
        0xd65f_03c0, // 9c ret
        0x5280_0c60, // a0 fail: mov w0, #99
        0xf940_0bf3, // a4 ldr  x19, [sp, #16]
        0xa8c2_7bfd, // a8 ldp  x29, x30, [sp], #32
        0xd65f_03c0, // ac ret
    ];
    let main = arm64_code("main", &words)
        .reloc(0x0c, Arm64Page21, "table", 0)
        .reloc(0x10, Arm64PageOff12 { scale: 0 }, "table", 0)
        .reloc(0x20, Arm64Branch26, "copy", 0)
        .reloc(0x38, Arm64Page21, "__ehdr_start", 0)
        .reloc(0x3c, Arm64PageOff12 { scale: 0 }, "__ehdr_start", 0)
        .reloc(0x58, Arm64GotPage21, "write", 0)
        .reloc(0x5c, Arm64GotPageOff12, "write", 0)
        .reloc(0x64, Arm64GotPage21, "base", 0)
        .reloc(0x68, Arm64GotPageOff12, "base", 0)
        .reloc(0x78, Arm64Page21, "counter", 0)
        .reloc(0x7c, Arm64PageOff12 { scale: 0 }, "counter", 0);
    #[rustfmt::skip]
    let copy = [
        0xb400_00a2, // 00 cbz  x2, done
        0x3840_1423, // 04 loop: ldrb w3, [x1], #1
        0x3800_1403, // 08 strb w3, [x0], #1
        0xd100_0442, // 0c sub  x2, x2, #1
        0xb5ff_ffa2, // 10 cbnz x2, loop
        0xd65f_03c0, // 14 done: ret
    ];
    let table = Atom::new("table", SectionKind::ReadOnly, 8, vec![0; 32])
        .reloc(0, Abs64, "msg_ok", -7)
        .reloc(8, Abs64, "buf", 0)
        .reloc(16, Abs64, "write", 0)
        .reloc(24, Abs64, "__ehdr_start", 0);
    let msg = Atom {
        labels: vec![("msg_ok".to_string(), 7)],
        ..Atom::new("msg", SectionKind::ReadOnly, 1, b"linked\nok\n".to_vec())
    };
    let atoms = vec![
        main,
        arm64_code("copy", &copy),
        table,
        msg,
        Atom::new("base", SectionKind::Data, 8, 30u64.to_le_bytes().to_vec()),
        Atom::bss("counter", 8, 8),
        Atom::bss("buf", 64, 16),
        arm64_code("unused", &[0x1400_0000]).reloc(0, Arm64Branch26, "missing", 0),
        arm64_code("kept", &[0xd65f_03c0]).keep(),
    ];
    program(start_arm64(), atoms, &["write", "puts"])
}

/// `return (int)cos(0.0) + 41;`
fn cos_arm64() -> Vec<Object> {
    #[rustfmt::skip]
    let words = [
        0xa9bf_7bfd, // 00 stp  x29, x30, [sp, #-16]!
        0x9100_03fd, // 04 mov  x29, sp
        0x9e67_03e0, // 08 fmov d0, xzr
        0x9000_0010, // 0c adrp x16, :got:cos
        0xf940_0210, // 10 ldr  x16, [x16, :got_lo12:cos]
        0xd63f_0200, // 14 blr  x16
        0x1e78_0000, // 18 fcvtzs w0, d0
        0x1100_a400, // 1c add  w0, w0, #41
        0xa8c1_7bfd, // 20 ldp  x29, x30, [sp], #16
        0xd65f_03c0, // 24 ret
    ];
    let main =
        arm64_code("main", &words).reloc(0x0c, Arm64GotPage21, "cos", 0).reloc(0x10, Arm64GotPageOff12, "cos", 0);
    program(start_arm64(), vec![main], &["cos"])
}

/// The aarch64 counterpart of [`environ_x86_64`]; `envp` arrives in x2.
fn environ_arm64() -> Vec<Object> {
    #[rustfmt::skip]
    let words = [
        0xa9bf_7bfd, // 00 stp  x29, x30, [sp, #-16]!
        0x9100_03fd, // 04 mov  x29, sp
        0x9000_0010, // 08 adrp x16, :got:environ
        0xf940_0210, // 0c ldr  x16, [x16, :got_lo12:environ]
        0xf940_0210, // 10 ldr  x16, [x16]
        0xeb02_021f, // 14 cmp  x16, x2
        0x5400_0161, // 18 b.ne fail
        0x5280_0020, // 1c mov  w0, #1
        0x9000_0001, // 20 adrp x1, ok
        0x9100_0021, // 24 add  x1, x1, :lo12:ok
        0xd280_0162, // 28 mov  x2, #11
        0x9000_0010, // 2c adrp x16, :got:write
        0xf940_0210, // 30 ldr  x16, [x16, :got_lo12:write]
        0xd63f_0200, // 34 blr  x16
        0x5280_0000, // 38 mov  w0, #0
        0xa8c1_7bfd, // 3c ldp  x29, x30, [sp], #16
        0xd65f_03c0, // 40 ret
        0x5280_0020, // 44 fail: mov w0, #1
        0xa8c1_7bfd, // 48 ldp  x29, x30, [sp], #16
        0xd65f_03c0, // 4c ret
    ];
    let main = arm64_code("main", &words)
        .reloc(0x08, Arm64GotPage21, "environ", 0)
        .reloc(0x0c, Arm64GotPageOff12, "environ", 0)
        .reloc(0x20, Arm64Page21, "ok", 0)
        .reloc(0x24, Arm64PageOff12 { scale: 0 }, "ok", 0)
        .reloc(0x2c, Arm64GotPage21, "write", 0)
        .reloc(0x30, Arm64GotPageOff12, "write", 0);
    let ok = Atom::new("ok", SectionKind::ReadOnly, 1, b"environ ok\n".to_vec());
    program(start_arm64(), vec![main, ok], &["write", "environ"])
}

/// No libraries: `_start` exits with 7 through a system call.
fn no_imports_arm64() -> Vec<Object> {
    #[rustfmt::skip]
    let words = [
        0xd280_00e0, // mov x0, #7
        0xd280_0ba8, // mov x8, #93                    exit
        0xd400_0001, // svc #0
    ];
    vec![Object { name: "bare".to_string(), atoms: vec![arm64_code("_start", &words)], imports: vec![] }]
}

// ----- tests ----------------------------------------------------------

const X86: Target = Target::X86_64Linux;
const ARM: Target = Target::Aarch64Linux;

#[test]
fn hello_x86_64_runs() {
    let (_, path) = build("hello-x86_64", X86, &hello_x86_64(), &["__libc_start_main", "write"], &GLIBC);
    expect_run(X86, &path, "hello\n", 0);
}

#[test]
fn hello_arm64_runs() {
    let (_, path) = build("hello-arm64", ARM, &hello_arm64(), &["__libc_start_main", "write"], &GLIBC);
    expect_run(ARM, &path, "hello\n", 0);
}

fn check_data_and_calls(image: &LinkedImage) {
    for name in ["main", "copy", "msg", "msg_ok", "table", "base", "counter", "buf", "kept", "_start"] {
        assert!(image.symbols.contains_key(name), "{name} placed");
    }
    assert!(!image.symbols.contains_key("unused"), "smart linking drops unused");
    assert_eq!(image.symbols["msg_ok"], image.symbols["msg"] + 7);
    assert_eq!(image.image_base, 0);
    assert!(!image.bytes.windows(5).any(|w| w == b"puts\0"), "unused import dropped");
}

#[test]
fn data_and_calls_x86_64_runs() {
    let imports = ["__libc_start_main", "write", "exit"];
    let (image, path) = build("data-x86_64", X86, &data_and_calls_x86_64(), &imports, &GLIBC);
    check_data_and_calls(&image);
    // Twice: each run gets a different load base, and the pointer table
    // only works if ld.so relocated it.
    for _ in 0..2 {
        expect_run(X86, &path, "linked\nok\nELF", 42);
    }
}

#[test]
fn data_and_calls_arm64_runs() {
    let (image, path) = build("data-arm64", ARM, &data_and_calls_arm64(), &["__libc_start_main", "write"], &GLIBC);
    check_data_and_calls(&image);
    for _ in 0..2 {
        expect_run(ARM, &path, "linked\nok\nELF", 42);
    }
}

#[test]
fn libm_import_x86_64_runs() {
    let (_, path) = build("cos-x86_64", X86, &cos_x86_64(), &["__libc_start_main", "cos"], &GLIBC);
    expect_run(X86, &path, "", 42);
}

#[test]
fn libm_import_arm64_runs() {
    let (_, path) = build("cos-arm64", ARM, &cos_arm64(), &["__libc_start_main", "cos"], &GLIBC);
    expect_run(ARM, &path, "", 42);
}

#[test]
fn data_import_x86_64_runs() {
    let imports = ["__libc_start_main", "write", "environ"];
    let (_, path) = build("environ-x86_64", X86, &environ_x86_64(), &imports, &GLIBC);
    expect_run(X86, &path, "environ ok\n", 0);
}

#[test]
fn data_import_arm64_runs() {
    let imports = ["__libc_start_main", "write", "environ"];
    let (_, path) = build("environ-arm64", ARM, &environ_arm64(), &imports, &GLIBC);
    expect_run(ARM, &path, "environ ok\n", 0);
}

/// Only on x86_64, whose pages are always 4 KiB: under 64 KiB pages the
/// 4 KiB-aligned RELRO end protects nothing, as with GNU ld's output.
#[test]
fn relro_x86_64_faults() {
    let (_, path) = build("relro-x86_64", X86, &relro_x86_64(), &["__libc_start_main", "write"], &GLIBC);
    if let Some(output) = run(X86, &path) {
        assert_eq!(String::from_utf8_lossy(&output.stdout), "before\n");
        assert!(!output.status.success(), "the store into RELRO data succeeded");
    }
}

#[test]
fn no_imports_x86_64_runs() {
    let (_, path) = build("bare-x86_64", X86, &no_imports_x86_64(), &[], &[]);
    expect_run(X86, &path, "", 7);
}

#[test]
fn no_imports_arm64_runs() {
    let (_, path) = build("bare-arm64", ARM, &no_imports_arm64(), &[], &[]);
    expect_run(ARM, &path, "", 7);
}
