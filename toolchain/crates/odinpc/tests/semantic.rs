// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Semantic error corpus: `odinpc check` on every
//! `tests/pascal/semantic/NAME.PAS` must report the error code, line and
//! column in `NAME.err` as its first error.

use std::path::{Path, PathBuf};
use std::process::Command;

use odin_base::json;

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

#[test]
fn semantic_errors_are_reported_where_expected() {
    let root = repo();
    let dir = root.join("tests/pascal/semantic");
    let mut entries: Vec<PathBuf> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().path()).collect();
    entries.sort();
    let mut checked = 0;
    let mut failures = Vec::new();
    for src in entries.iter().filter(|p| p.extension().is_some_and(|e| e == "PAS")) {
        let want: Vec<i64> = std::fs::read_to_string(src.with_extension("err"))
            .unwrap()
            .split_whitespace()
            .map(|n| n.parse().unwrap())
            .collect();
        let out = Command::new(env!("CARGO_BIN_EXE_odinpc"))
            .args(["check", src.to_str().unwrap(), "--diag-format", "json", "--rtl"])
            .arg(root.join("rtl"))
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&out.stdout);
        let first_error = text.lines().filter_map(|l| json::parse(l).ok()).find(|v| {
            v.get("type").and_then(|t| t.as_str()) == Some("diagnostic")
                && v.get("severity").and_then(|s| s.as_str()) == Some("error")
        });
        let got = first_error
            .map(|v| ["code", "line", "column"].map(|k| v.get(k).and_then(|x| x.as_i64()).unwrap_or(-1)).to_vec());
        if got.as_deref() != Some(&want[..]) {
            failures.push(format!("{}: got {got:?}, want {want:?}\n{text}", src.display()));
        }
        checked += 1;
    }
    assert!(checked >= 12, "only {checked} cases");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
