// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Step-counting golden tests: every `tests/steps/NAME.PAS` is built with
//! `--count-steps`, run with the variables of `NAME.env` (one `KEY=VALUE` per
//! line) and `NAME.in` as input, and its report (`$ODIN_STATS_FILE`) must be
//! byte for byte `NAME.stats`, its output `NAME.out` and its exit status
//! `NAME.code` (0 when missing).
//!
//! The expectations are the same files on every target: the point of the
//! report is that steps, heap and call depth do not depend on the OS or the
//! CPU. CI runs this on macOS (Intel and Apple Silicon), Linux (x86_64 and
//! arm64) and Windows.
//!
//! `ODIN_CORPUS_TARGET`, `ODIN_CORPUS_RUNNER` and `ODIN_CORPUS_TMP` work as in
//! `corpus.rs`. A runner passes the environment through `env`: the variables
//! go right after the runner's `env` command and its options, e.g.
//! `limactl shell odin-linux -- env -C {cwd} qemu-aarch64-static -L /usr/aarch64-linux-gnu`.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

fn host_target() -> String {
    let os = if cfg!(target_os = "macos") { "darwin" } else { std::env::consts::OS };
    format!("{}-{}", std::env::consts::ARCH, os)
}

/// The runner's arguments with `KEY=VALUE` assignments after its `env`
/// command and that command's options.
fn with_env(prefix: &[String], vars: &[(String, String)]) -> Vec<String> {
    let mut out = Vec::new();
    let mut it = prefix.iter().peekable();
    let mut placed = false;
    while let Some(arg) = it.next() {
        out.push(arg.clone());
        if arg == "env" && !placed {
            while let Some(next) = it.peek() {
                if !next.starts_with('-') {
                    break;
                }
                let option = it.next().unwrap().clone();
                let takes_value = matches!(option.as_str(), "-C" | "-u" | "--chdir" | "--unset");
                out.push(option);
                if takes_value && let Some(value) = it.next() {
                    out.push(value.clone());
                }
            }
            out.extend(vars.iter().map(|(k, v)| format!("{k}={v}")));
            placed = true;
        }
    }
    out
}

#[test]
fn step_reports_match_golden_files() {
    let root = repo();
    let odinpc = env!("CARGO_BIN_EXE_odinpc");
    let target = std::env::var("ODIN_CORPUS_TARGET").unwrap_or_else(|_| host_target());
    let runner: Vec<String> = std::env::var("ODIN_CORPUS_RUNNER")
        .map(|r| r.split_whitespace().map(String::from).collect())
        .unwrap_or_default();
    if runner.is_empty() && target != host_target() {
        eprintln!("steps: no ODIN_CORPUS_RUNNER to run {target} programs on {}; skipped", host_target());
        return;
    }
    let tmp = match std::env::var("ODIN_CORPUS_TMP") {
        Ok(dir) => PathBuf::from(dir),
        Err(_) => PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("steps"),
    }
    .join(format!("steps-{target}"));
    std::fs::create_dir_all(&tmp).unwrap();
    let dir = root.join("tests/steps");
    let mut list: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "PAS"))
        .collect();
    list.sort();
    assert!(!list.is_empty(), "no programs in tests/steps");
    let mut failures = Vec::new();
    for src in &list {
        let stem = src.file_stem().unwrap().to_string_lossy().to_string();
        let mut exe = tmp.join(&stem);
        if target.ends_with("windows") {
            exe.set_extension("exe");
        }
        let build = Command::new(odinpc)
            .arg("build")
            .arg(src)
            .arg("--out")
            .arg(&exe)
            .arg("--rtl")
            .arg(root.join("rtl"))
            .arg("--target")
            .arg(&target)
            .arg("--count-steps")
            .output()
            .unwrap();
        if !build.status.success() {
            failures.push(format!("{stem}: compile failed\n{}", String::from_utf8_lossy(&build.stdout)));
            continue;
        }
        let work = tmp.join(format!("{stem}.work"));
        let _ = std::fs::remove_dir_all(&work);
        std::fs::create_dir_all(&work).unwrap();
        let report = work.join("stats.txt");
        let mut vars: Vec<(String, String)> = std::fs::read_to_string(src.with_extension("env"))
            .unwrap_or_default()
            .lines()
            .filter_map(|l| l.split_once('=').map(|(k, v)| (k.trim().to_string(), v.trim().to_string())))
            .collect();
        vars.push(("ODIN_STATS_FILE".into(), report.to_string_lossy().into_owned()));
        let mut command = match runner.split_first() {
            Some((program, prefix)) => {
                let prefix: Vec<String> = prefix.iter().map(|a| a.replace("{cwd}", &work.to_string_lossy())).collect();
                let mut c = Command::new(program);
                c.args(with_env(&prefix, &vars));
                c.arg(&exe);
                c
            }
            None => Command::new(&exe),
        };
        command.envs(vars.iter().map(|(k, v)| (k.as_str(), v.as_str())));
        let input = std::fs::read(src.with_extension("in")).unwrap_or_default();
        let mut child = command
            .current_dir(&work)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child.stdin.take().unwrap().write_all(&input).unwrap();
        let run = child.wait_with_output().unwrap();
        let code = run.status.code().unwrap_or(-1);
        let want_code: i32 =
            std::fs::read_to_string(src.with_extension("code")).map(|s| s.trim().parse().unwrap()).unwrap_or(0);
        // WriteLn ends lines with CR LF on Windows; the report always uses LF.
        let got_out = String::from_utf8_lossy(&run.stdout).replace("\r\n", "\n");
        let want_out = std::fs::read_to_string(src.with_extension("out")).unwrap();
        let got_stats = std::fs::read_to_string(&report).unwrap_or_else(|e| format!("(no report: {e})\n"));
        let want_stats = std::fs::read_to_string(src.with_extension("stats")).unwrap();
        if code != want_code || got_out != want_out || got_stats != want_stats {
            failures.push(format!(
                "{stem}: exit {code} (want {want_code})\n--- output\n{got_out}--- want\n{want_out}--- report\n{got_stats}--- want\n{want_stats}--- stderr\n{}",
                String::from_utf8_lossy(&run.stderr)
            ));
        }
    }
    assert!(failures.is_empty(), "{} of {} programs differ:\n{}", failures.len(), list.len(), failures.join("\n"));
}

#[test]
fn runner_env_goes_after_env_options() {
    let prefix: Vec<String> =
        ["shell", "vm", "--", "env", "-C", "/w", "qemu", "-L", "/l"].iter().map(|s| s.to_string()).collect();
    let vars = vec![("A".to_string(), "1".to_string())];
    assert_eq!(with_env(&prefix, &vars), ["shell", "vm", "--", "env", "-C", "/w", "A=1", "qemu", "-L", "/l"]);
}
