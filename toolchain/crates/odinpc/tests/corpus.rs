// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Differential corpus: every `tests/pascal/<dir>/NAME.PAS` that has a
//! `NAME.out` is compiled with `odinpc`, run with `NAME.in` and `NAME.args`,
//! and its standard output and exit status compared with the expectations
//! that `scripts/oracle.py` produced with FPC (`NAME.out`, `NAME.code`).
//!
//! Every program runs twice: built normally and built with `--debug` (with
//! debugger hooks, but no debugger attached). Both must match FPC.
//!
//! `ODIN_CORPUS=crt` limits the run to programs whose path relative to
//! `tests/pascal` contains `crt` (case-insensitive).

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

#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
#[test]
fn pascal_corpus_matches_fpc() {
    let root = repo();
    let odinpc = env!("CARGO_BIN_EXE_odinpc");
    let tmp = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("corpus");
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
    for (src, debug) in list.iter().flat_map(|s| [(s, false), (s, true)]) {
        let mut name = src.strip_prefix(root.join("tests/pascal")).unwrap().display().to_string();
        if debug {
            name.push_str(" (--debug)");
        }
        let exe = tmp.join(src.file_stem().unwrap());
        let mut command = Command::new(odinpc);
        command.arg("build").arg(src).arg("--out").arg(&exe).arg("--rtl").arg(root.join("rtl"));
        if debug {
            command.arg("--debug");
        }
        let build = command.output().unwrap();
        if !build.status.success() {
            failures.push(format!("{name}: compile failed\n{}", String::from_utf8_lossy(&build.stdout)));
            continue;
        }
        let work = tmp.join(format!("{}.work", src.file_stem().unwrap().to_string_lossy()));
        let _ = std::fs::remove_dir_all(&work);
        std::fs::create_dir_all(&work).unwrap();
        let args: Vec<String> = std::fs::read_to_string(src.with_extension("args"))
            .map(|s| s.split_whitespace().map(String::from).collect())
            .unwrap_or_default();
        let input = std::fs::read(src.with_extension("in")).unwrap_or_default();
        let mut child = Command::new(&exe)
            .args(&args)
            .current_dir(&work)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child.stdin.take().unwrap().write_all(&input).unwrap();
        let run = child.wait_with_output().unwrap();
        let want_out = std::fs::read(src.with_extension("out")).unwrap();
        let want_code: i32 =
            std::fs::read_to_string(src.with_extension("code")).map(|s| s.trim().parse().unwrap()).unwrap_or(0);
        let code = run.status.code().unwrap_or(-1);
        if run.stdout != want_out || code != want_code {
            failures.push(format!(
                "{name}: exit {code} (want {want_code})\n--- got\n{}--- want\n{}--- stderr\n{}",
                String::from_utf8_lossy(&run.stdout),
                String::from_utf8_lossy(&want_out),
                String::from_utf8_lossy(&run.stderr)
            ));
        }
    }
    assert!(failures.is_empty(), "{} of {} programs differ:\n{}", failures.len(), list.len(), failures.join("\n"));
}
