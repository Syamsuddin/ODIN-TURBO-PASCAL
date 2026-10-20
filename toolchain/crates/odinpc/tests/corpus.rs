// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Differential corpus: every `tests/pascal/<dir>/NAME.PAS` that has a
//! `NAME.out` is compiled with `odinpc`, run with `NAME.in` and `NAME.args`,
//! and its standard output and exit status compared with the stored
//! expectations (`NAME.out`, `NAME.code`). Up to 2.3.0 they were made with
//! Free Pascal 3.2.2 (`fpc -Mtp`) as reference, apart from the cases in
//! `tests/pascal/DEVIATIONS.md`; new programs get theirs from
//! `scripts/bless_corpus.py`, reviewed before they are committed.
//!
//! Every program runs three times: built normally, built with `--debug` (with
//! debugger hooks, but no debugger attached) and built with `--count-steps`
//! (step counters, zeroed locals, no report requested). All must match the stored expectations.
//!
//! `ODIN_CORPUS=crt` limits the run to programs whose path relative to
//! `tests/pascal` contains `crt` (case-insensitive).
//!
//! The programs are built for the host by default. `ODIN_CORPUS_TARGET`
//! picks another target (`x86_64-linux`, ...), and `ODIN_CORPUS_RUNNER` runs
//! its executables elsewhere: a command prefix in which `{cwd}` stands for the
//! program's working directory, e.g. for the Lima VM
//! `limactl shell odin-linux -- env -C {cwd}` or, for aarch64 under qemu,
//! `limactl shell odin-linux -- env -C {cwd} qemu-aarch64-static -L /usr/aarch64-linux-gnu`.
//! With a runner, `ODIN_CORPUS_TMP` should name a directory both sides can
//! write (Lima shares `/tmp/lima`). A target `odinpc` does not generate yet
//! is skipped with a message rather than failed.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

fn cases(dir: &Path, out: &mut Vec<PathBuf>) {
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).collect();
    entries.sort();
    for p in entries {
        if p.is_dir() {
            if !matches!(p.file_name().and_then(|n| n.to_str()), Some("syntax" | "errors" | "semantic" | "crt" | "vision")) {
                cases(&p, out);
            }
        } else if p.extension().is_some_and(|e| e == "PAS") && p.with_extension("out").exists() {
            out.push(p);
        }
    }
}

/// `x86_64-darwin`, `aarch64-linux`, ... as `odinpc` names the host.
fn host_target() -> String {
    let os = if cfg!(target_os = "macos") { "darwin" } else { std::env::consts::OS };
    format!("{}-{}", std::env::consts::ARCH, os)
}

#[test]
fn pascal_corpus_matches_expectations() {
    let root = repo();
    let odinpc = env!("CARGO_BIN_EXE_odinpc");
    let target = std::env::var("ODIN_CORPUS_TARGET").unwrap_or_else(|_| host_target());
    let runner: Vec<String> =
        std::env::var("ODIN_CORPUS_RUNNER").map(|r| r.split_whitespace().map(String::from).collect()).unwrap_or_default();
    if runner.is_empty() && target != host_target() {
        eprintln!("corpus: no ODIN_CORPUS_RUNNER to run {target} programs on {}; skipped", host_target());
        return;
    }
    let tmp = match std::env::var("ODIN_CORPUS_TMP") {
        Ok(dir) => PathBuf::from(dir),
        Err(_) => PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("corpus"),
    }
    .join(&target);
    std::fs::create_dir_all(&tmp).unwrap();
    let mut list = Vec::new();
    cases(&root.join("tests/pascal"), &mut list);
    if let Ok(filter) = std::env::var("ODIN_CORPUS") {
        let filter = filter.to_ascii_lowercase();
        list.retain(|p| {
            p.strip_prefix(root.join("tests/pascal")).unwrap().to_string_lossy().to_ascii_lowercase().contains(&filter)
        });
    }
    assert!(!list.is_empty(), "no corpus programs found");
    let mut failures = Vec::new();
    for (src, mode) in list.iter().flat_map(|s| [(s, ""), (s, "--debug"), (s, "--count-steps")]) {
        let mut name = src.strip_prefix(root.join("tests/pascal")).unwrap().display().to_string();
        if !mode.is_empty() {
            name.push_str(&format!(" ({mode})"));
        }
        // Each build gets its own file: replacing a file another machine just
        // ran (the VM, through a shared folder) may still run the old one.
        let stem = src.file_stem().unwrap().to_string_lossy();
        let mut exe = tmp.join(match mode {
            "--debug" => format!("{stem}-debug"),
            "--count-steps" => format!("{stem}-count"),
            _ => stem.to_string(),
        });
        if target.ends_with("windows") {
            exe.set_extension("exe");
        }
        let mut command = Command::new(odinpc);
        command.arg("build").arg(src).arg("--out").arg(&exe).arg("--rtl").arg(root.join("rtl"));
        command.arg("--target").arg(&target);
        if !mode.is_empty() {
            command.arg(mode);
        }
        let build = command.output().unwrap();
        if !build.status.success() {
            let message = String::from_utf8_lossy(&build.stdout);
            if failures.is_empty() && message.contains(&format!("target {target} (yang tersedia")) {
                eprintln!("corpus: odinpc does not generate {target} yet; skipped\n{message}");
                return;
            }
            failures.push(format!("{name}: compile failed\n{message}"));
            continue;
        }
        let work = tmp.join(format!("{}.work", exe.file_stem().unwrap().to_string_lossy()));
        let _ = std::fs::remove_dir_all(&work);
        std::fs::create_dir_all(&work).unwrap();
        let args: Vec<String> = std::fs::read_to_string(src.with_extension("args"))
            .map(|s| s.split_whitespace().map(String::from).collect())
            .unwrap_or_default();
        let input = std::fs::read(src.with_extension("in")).unwrap_or_default();
        let mut command = match runner.split_first() {
            Some((program, prefix)) => {
                let mut c = Command::new(program);
                c.args(prefix.iter().map(|a| a.replace("{cwd}", &work.to_string_lossy())));
                c.arg(&exe);
                c
            }
            None => Command::new(&exe),
        };
        let mut child = command
            .args(&args)
            .current_dir(&work)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child.stdin.take().unwrap().write_all(&input).unwrap();
        let run = child.wait_with_output().unwrap();
        // A program whose behaviour is rightly different on one OS (DOS attributes, paths, CR LF
        // text files) has expectations of its own there: NAME.<os>.out / NAME.<os>.code, made on
        // that OS.
        let os = target.rsplit('-').next().unwrap_or("");
        let expected = |ext: &str| {
            let own = src.with_extension(format!("{os}.{ext}"));
            if own.exists() { own } else { src.with_extension(ext) }
        };
        let mut want_out = std::fs::read(expected("out")).unwrap();
        let want_code: i32 =
            std::fs::read_to_string(expected("code")).map(|s| s.trim().parse().unwrap()).unwrap_or(0);
        let code = run.status.code().unwrap_or(-1);
        let mut got_out = run.stdout.clone();
        if target.ends_with("windows") {
            // WriteLn ends lines with CR LF on Windows; the shared expectations have LF.
            got_out = String::from_utf8_lossy(&got_out).replace("\r\n", "\n").into_bytes();
            want_out = String::from_utf8_lossy(&want_out).replace("\r\n", "\n").into_bytes();
        }
        if got_out != want_out || code != want_code {
            failures.push(format!(
                "{name}: exit {code} (want {want_code})\n--- got\n{}--- want\n{}--- stderr\n{}",
                String::from_utf8_lossy(&got_out),
                String::from_utf8_lossy(&want_out),
                String::from_utf8_lossy(&run.stderr)
            ));
        }
    }
    assert!(failures.is_empty(), "{} of {} programs differ:\n{}", failures.len(), list.len(), failures.join("\n"));
}
