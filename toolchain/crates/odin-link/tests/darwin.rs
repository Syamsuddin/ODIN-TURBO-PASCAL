// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Spikes S1 and S2 of Tahap 0: hand-encoded programs linked into real Mach-O
//! executables, run where the hardware allows, and checked with Apple's own
//! tools (`codesign`, `otool`, `dyld_info`) when they are installed.

use std::io::ErrorKind;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use odin_asm::object::RelocKind::*;
use odin_asm::object::{Atom, Import, Object, SectionKind};
use odin_link::{LinkOptions, LinkedImage, Target, link};

const LIBSYSTEM: &str = "/usr/lib/libSystem.B.dylib";

fn libsystem(names: &[&str]) -> Vec<Import> {
    names.iter().map(|name| Import { name: name.to_string(), library: LIBSYSTEM.to_string() }).collect()
}

/// Writes `image` as an executable file named `name` in the test tmp dir.
fn write_executable(name: &str, image: &LinkedImage) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("odin-link");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    // A fresh inode each time: the kernel caches code signatures per vnode,
    // so rewriting a signed binary in place can get it killed.
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

/// `codesign -v` accepts the ad-hoc signature, and `otool -l` and
/// `dyld_info` parse the load commands and fixups.
fn check_with_apple_tools(path: &Path, imports: &[&str]) {
    let file = path.to_str().unwrap();
    if let Some(output) = tool("codesign", &["-v", "--verbose=4", file]) {
        assert!(output.status.success(), "codesign -v rejected {file}:\n{}", text(&output));
        eprintln!("{}", text(&output).trim());
    }
    if let Some(output) = tool("codesign", &["-d", "--verbose=4", file]) {
        let details = text(&output);
        assert!(output.status.success(), "codesign -d failed:\n{details}");
        assert!(details.contains("flags=0x20002(adhoc,linker-signed)"), "{details}");
        assert!(details.contains("Hash type=sha256"), "{details}");
    }
    if let Some(output) = tool("otool", &["-l", file]) {
        let commands = text(&output);
        assert!(output.status.success(), "otool -l failed:\n{commands}");
        for cmd in [
            "LC_DYLD_INFO_ONLY",
            "LC_SYMTAB",
            "LC_DYSYMTAB",
            "LC_LOAD_DYLINKER",
            "LC_UUID",
            "LC_BUILD_VERSION",
            "LC_MAIN",
            "LC_LOAD_DYLIB",
            "LC_CODE_SIGNATURE",
        ] {
            assert!(commands.contains(cmd), "{cmd} missing:\n{commands}");
        }
    }
    // dyld's own malformed-file checks; problems are indented lines after
    // the file name, and the exit status stays 0.
    if let Some(output) = tool("dyld_info", &["-validate_only", file]) {
        let report = text(&output);
        assert!(output.status.success(), "dyld_info -validate_only failed:\n{report}");
        assert!(report.lines().skip(1).all(|l| l.trim().is_empty()), "dyld_info found problems:\n{report}");
    }
    if let Some(output) = tool("dyld_info", &["-fixups", "-exports", file]) {
        let fixups = text(&output);
        assert!(output.status.success(), "dyld_info failed:\n{fixups}");
        for import in imports {
            assert!(fixups.contains(&format!("bind  libSystem/{import}")), "no bind for {import}:\n{fixups}");
        }
        assert!(fixups.contains("__mh_execute_header") && fixups.contains("_main"), "exports:\n{fixups}");
    }
}

/// S1: `write(1, "hello\n", 6); exit(3);` through the GOT.
fn hello_x86_64() -> Vec<Object> {
    #[rustfmt::skip]
    let code = vec![
        0x55,                               // push rbp
        0x48, 0x89, 0xe5,                   // mov  rbp, rsp
        0xbf, 0x01, 0x00, 0x00, 0x00,       // mov  edi, 1
        0x48, 0x8d, 0x35, 0, 0, 0, 0,       // lea  rsi, [rip + _msg]
        0xba, 0x06, 0x00, 0x00, 0x00,       // mov  edx, 6
        0xff, 0x15, 0, 0, 0, 0,             // call [rip + _write@GOT]
        0xbf, 0x03, 0x00, 0x00, 0x00,       // mov  edi, 3
        0xff, 0x15, 0, 0, 0, 0,             // call [rip + _exit@GOT]
    ];
    let main = Atom::new("_main", SectionKind::Text, 16, code)
        .reloc(12, X86Pc32, "_msg", -4)
        .reloc(23, X86GotPc32, "_write", -4)
        .reloc(34, X86GotPc32, "_exit", -4);
    let msg = Atom::new("_msg", SectionKind::ReadOnly, 1, b"hello\n".to_vec());
    vec![Object { name: "hello".to_string(), atoms: vec![main, msg], imports: libsystem(&["_write", "_exit"]) }]
}

/// S1, second program: data, bss, a pointer table that dyld must rebase, a
/// call between atoms, labels, and atoms smart linking must drop. Prints
/// "linked\nok\n" and exits with 30 + 10 + 2 = 42.
fn data_and_calls_x86_64() -> Vec<Object> {
    #[rustfmt::skip]
    let main = vec![
        0x55,                               // 00 push rbp
        0x48, 0x89, 0xe5,                   // 01 mov  rbp, rsp
        0x53,                               // 04 push rbx
        0x48, 0x83, 0xec, 0x08,             // 05 sub  rsp, 8
        0x48, 0x8d, 0x1d, 0, 0, 0, 0,       // 09 lea  rbx, [rip + _table]
        0x48, 0x8b, 0x7b, 0x08,             // 10 mov  rdi, [rbx + 8]        _buf
        0x48, 0x8b, 0x33,                   // 14 mov  rsi, [rbx]            _msg
        0xba, 0x07, 0x00, 0x00, 0x00,       // 17 mov  edx, 7
        0xe8, 0, 0, 0, 0,                   // 1c call _copy
        0x48, 0x8b, 0x7b, 0x08,             // 21 mov  rdi, [rbx + 8]
        0x48, 0x83, 0xc7, 0x07,             // 25 add  rdi, 7
        0x48, 0x8b, 0x73, 0x10,             // 29 mov  rsi, [rbx + 16]       _msg_ok
        0xba, 0x03, 0x00, 0x00, 0x00,       // 2d mov  edx, 3
        0xe8, 0, 0, 0, 0,                   // 32 call _copy
        0xbf, 0x01, 0x00, 0x00, 0x00,       // 37 mov  edi, 1
        0x48, 0x8b, 0x73, 0x08,             // 3c mov  rsi, [rbx + 8]
        0xba, 0x0a, 0x00, 0x00, 0x00,       // 40 mov  edx, 10
        0xff, 0x15, 0, 0, 0, 0,             // 45 call [rip + _write@GOT]
        0x48, 0x83, 0x05, 0, 0, 0, 0, 0x0a, // 4b add  qword [rip + _base], 10
        0x48, 0xff, 0x05, 0, 0, 0, 0,       // 53 inc  qword [rip + _counter]
        0x48, 0xff, 0x05, 0, 0, 0, 0,       // 5a inc  qword [rip + _counter]
        0x48, 0x8b, 0x3d, 0, 0, 0, 0,       // 61 mov  rdi, [rip + _base]
        0x48, 0x03, 0x3d, 0, 0, 0, 0,       // 68 add  rdi, [rip + _counter]
        0xff, 0x15, 0, 0, 0, 0,             // 6f call [rip + _exit@GOT]
    ];
    let main = Atom::new("_main", SectionKind::Text, 16, main)
        .reloc(0x0c, X86Pc32, "_table", -4)
        .reloc(0x1d, X86Pc32, "_copy", -4)
        .reloc(0x33, X86Pc32, "_copy", -4)
        .reloc(0x47, X86GotPc32, "_write", -4)
        .reloc(0x4e, X86Pc32, "_base", -5) // an imm8 follows the displacement
        .reloc(0x56, X86Pc32, "_counter", -4)
        .reloc(0x5d, X86Pc32, "_counter", -4)
        .reloc(0x64, X86Pc32, "_base", -4)
        .reloc(0x6b, X86Pc32, "_counter", -4)
        .reloc(0x71, X86GotPc32, "_exit", -4);
    // Pointers, rebased by dyld: msg (via the label and a negative addend),
    // the bss buffer, and the label itself.
    let table = Atom::new("_table", SectionKind::Data, 8, vec![0; 24])
        .reloc(0, Abs64, "_msg_ok", -7)
        .reloc(8, Abs64, "_buf", 0)
        .reloc(16, Abs64, "_msg_ok", 0);
    let base = Atom::new("_base", SectionKind::Data, 8, 30u64.to_le_bytes().to_vec());
    let counter = Atom::bss("_counter", 8, 8);
    let program = Object {
        name: "program".to_string(),
        atoms: vec![main, table, base, counter],
        imports: libsystem(&["_write", "_exit", "_puts"]),
    };

    #[rustfmt::skip]
    let copy = vec![
        0x48, 0x85, 0xd2,                   // test rdx, rdx
        0x74, 0x0f,                         // jz   done
        0x8a, 0x06,                         // loop: mov al, [rsi]
        0x88, 0x07,                         // mov  [rdi], al
        0x48, 0xff, 0xc6,                   // inc  rsi
        0x48, 0xff, 0xc7,                   // inc  rdi
        0x48, 0xff, 0xca,                   // dec  rdx
        0x75, 0xf1,                         // jnz  loop
        0xc3,                               // done: ret
    ];
    let copy = Atom::new("_copy", SectionKind::Text, 16, copy);
    let msg = Atom {
        labels: vec![("_msg_ok".to_string(), 7)],
        ..Atom::new("_msg", SectionKind::ReadOnly, 1, b"linked\nok\n".to_vec())
    };
    let buf = Atom::bss("_buf", 64, 16);
    // Nothing references `_unused`; its undefined target must not matter.
    let unused = Atom::new("_unused", SectionKind::Text, 1, vec![0xe9, 0, 0, 0, 0]).reloc(1, X86Pc32, "_missing", -4);
    let kept = Atom::new("_kept", SectionKind::Text, 1, vec![0xc3]).keep();
    let util =
        Object { name: "util".to_string(), atoms: vec![copy, msg, buf, unused, kept], imports: libsystem(&["_write"]) };
    vec![program, util]
}

/// S2: the same hello for arm64, with a `bl` to a helper atom.
fn hello_arm64() -> Vec<Object> {
    let words: [u32; 14] = [
        0xa9bf_7bfd, // stp  x29, x30, [sp, #-16]!
        0x9100_03fd, // mov  x29, sp
        0x5280_0020, // mov  w0, #1
        0x9000_0001, // adrp x1, _msg@PAGE
        0x9100_0021, // add  x1, x1, _msg@PAGEOFF
        0x5280_00c2, // mov  w2, #6
        0x9400_0000, // bl   _nothing
        0x9000_0010, // adrp x16, _write@GOTPAGE
        0xf940_0210, // ldr  x16, [x16, _write@GOTPAGEOFF]
        0xd63f_0200, // blr  x16
        0x5280_0060, // mov  w0, #3
        0x9000_0010, // adrp x16, _exit@GOTPAGE
        0xf940_0210, // ldr  x16, [x16, _exit@GOTPAGEOFF]
        0xd63f_0200, // blr  x16
    ];
    let code = words.iter().flat_map(|w| w.to_le_bytes()).collect();
    let main = Atom::new("_main", SectionKind::Text, 4, code)
        .reloc(0x0c, Arm64Page21, "_msg", 0)
        .reloc(0x10, Arm64PageOff12 { scale: 0 }, "_msg", 0)
        .reloc(0x18, Arm64Branch26, "_nothing", 0)
        .reloc(0x1c, Arm64GotPage21, "_write", 0)
        .reloc(0x20, Arm64GotPageOff12, "_write", 0)
        .reloc(0x2c, Arm64GotPage21, "_exit", 0)
        .reloc(0x30, Arm64GotPageOff12, "_exit", 0);
    let nothing = Atom::new("_nothing", SectionKind::Text, 4, 0xd65f_03c0u32.to_le_bytes().to_vec()); // ret
    let msg = Atom::new("_msg", SectionKind::ReadOnly, 1, b"hello\n".to_vec());
    vec![Object {
        name: "hello".to_string(),
        atoms: vec![main, nothing, msg],
        imports: libsystem(&["_write", "_exit"]),
    }]
}

fn run(path: &Path) -> Output {
    let output = Command::new(path).output().unwrap_or_else(|e| panic!("cannot start {}: {e}", path.display()));
    eprintln!("{}: status {:?}, stdout {:?}", path.display(), output.status, String::from_utf8_lossy(&output.stdout));
    output
}

#[test]
fn s1_hello_x86_64_links() {
    let image = link(&hello_x86_64(), &LinkOptions::new(Target::X86_64Darwin, "_main", "hello")).unwrap();
    let path = write_executable("hello-x86_64", &image);
    if cfg!(target_os = "macos") {
        check_with_apple_tools(&path, &["_write", "_exit"]);
    }
}

#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
#[test]
fn s1_hello_x86_64_runs() {
    let image = link(&hello_x86_64(), &LinkOptions::new(Target::X86_64Darwin, "_main", "hello-run")).unwrap();
    let path = write_executable("hello-run-x86_64", &image);
    let output = run(&path);
    assert_eq!(String::from_utf8_lossy(&output.stdout), "hello\n");
    assert_eq!(output.status.code(), Some(3));
}

#[test]
fn s1_data_and_calls_x86_64_links() {
    let image = link(&data_and_calls_x86_64(), &LinkOptions::new(Target::X86_64Darwin, "_main", "data")).unwrap();
    for name in ["_main", "_copy", "_msg", "_msg_ok", "_table", "_base", "_counter", "_buf", "_kept"] {
        assert!(image.symbols.contains_key(name), "{name} placed");
    }
    assert!(!image.symbols.contains_key("_unused"), "smart linking drops _unused");
    assert_eq!(image.symbols["_msg_ok"], image.symbols["_msg"] + 7);
    assert!(!image.bytes.windows(6).any(|w| w == b"_puts\0"), "unused import dropped");
    let path = write_executable("data-x86_64", &image);
    if cfg!(target_os = "macos") {
        check_with_apple_tools(&path, &["_write", "_exit"]);
    }
}

#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
#[test]
fn s1_data_and_calls_x86_64_runs() {
    let image = link(&data_and_calls_x86_64(), &LinkOptions::new(Target::X86_64Darwin, "_main", "data-run")).unwrap();
    let path = write_executable("data-run-x86_64", &image);
    // Twice: each run gets a different ASLR slide, and the pointer table
    // only works if dyld rebased it.
    for _ in 0..2 {
        let output = run(&path);
        assert_eq!(String::from_utf8_lossy(&output.stdout), "linked\nok\n");
        assert_eq!(output.status.code(), Some(42));
    }
}

#[test]
fn s2_hello_arm64_links_and_verifies() {
    let image = link(&hello_arm64(), &LinkOptions::new(Target::Aarch64Darwin, "_main", "hello")).unwrap();
    let path = write_executable("hello-arm64", &image);
    if !cfg!(target_os = "macos") {
        return;
    }
    check_with_apple_tools(&path, &["_write", "_exit"]);
    // An independent disassembler sees the patched instructions, and finds
    // the GOT slots through the indirect symbol table.
    if let Some(output) = tool("otool", &["-tv", path.to_str().unwrap()]) {
        let listing = text(&output);
        assert!(output.status.success(), "otool -tv failed:\n{listing}");
        let line = |at: u64| {
            listing
                .lines()
                .find(|l| l.starts_with(&format!("{at:016x}\t")))
                .unwrap_or_else(|| panic!("no {at:x}:\n{listing}"))
        };
        let (main, msg) = (image.symbols["_main"], image.symbols["_msg"]);
        assert!(line(main + 0x0c).ends_with(&format!("; 0x{:x}", msg & !0xfff)), "adrp x1:\n{listing}");
        assert!(line(main + 0x10).ends_with(&format!("add\tx1, x1, #0x{:x}", msg & 0xfff)), "add x1:\n{listing}");
        assert!(line(main + 0x18).ends_with("bl\t_nothing"), "bl:\n{listing}");
        assert!(line(main + 0x20).ends_with("literal pool symbol address: _write"), "ldr _write:\n{listing}");
        assert!(line(main + 0x30).ends_with("literal pool symbol address: _exit"), "ldr _exit:\n{listing}");
    }
    #[cfg(target_arch = "aarch64")]
    {
        let output = run(&path);
        assert_eq!(String::from_utf8_lossy(&output.stdout), "hello\n");
        assert_eq!(output.status.code(), Some(3));
    }
}
