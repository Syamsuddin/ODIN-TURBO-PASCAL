// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! `odinpc metrics` on the programs in `tests/metrics/`: the notes a
//! program with known problems gets, its routine figures and facts, and the
//! shape that similarity is computed from.

use std::path::{Path, PathBuf};
use std::process::Command;

use odin_base::json::{Value, parse};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

/// The `metrics` line of `odinpc metrics --diag-format json` on `name`.
fn metrics(name: &str) -> Value {
    let root = repo();
    let out = Command::new(env!("CARGO_BIN_EXE_odinpc"))
        .arg("metrics")
        .arg(root.join("tests/metrics").join(name))
        .arg("--rtl")
        .arg(root.join("rtl"))
        .arg("--diag-format")
        .arg("json")
        .output()
        .unwrap();
    let text = String::from_utf8(out.stdout).unwrap();
    assert!(out.status.success(), "odinpc metrics {name} failed:\n{text}");
    let line = text.lines().find(|l| l.contains("\"type\":\"metrics\"")).expect("a metrics line");
    parse(line).unwrap()
}

fn num(v: &Value, key: &str) -> i64 {
    v.get(key).and_then(Value::as_i64).unwrap_or_else(|| panic!("{key} missing"))
}

fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or_else(|| panic!("{key} missing"))
}

fn shape(v: &Value) -> Vec<String> {
    v.get("shape")
        .and_then(Value::as_array)
        .unwrap()
        .iter()
        .map(|pair| pair.as_array().unwrap()[1].as_str().unwrap().to_string())
        .collect()
}

#[test]
fn notes_routines_and_facts_of_a_program_with_known_problems() {
    let m = metrics("CATATAN.PAS");
    let notes: Vec<(i64, String, String)> = m
        .get("notes")
        .and_then(Value::as_array)
        .unwrap()
        .iter()
        .map(|n| (num(n, "line"), text(n, "code").to_string(), text(n, "message").to_string()))
        .collect();
    let codes: Vec<(i64, &str)> = notes.iter().map(|(l, c, _)| (*l, c.as_str())).collect();
    assert_eq!(
        codes,
        [
            (4, "unused-var"),
            (6, "magic-number"),
            (8, "result-unset"),
            (21, "global-write"),
            (23, "unused-var"),
            (33, "magic-number"),
            (39, "deep-nesting"),
            (39, "magic-number"),
            (50, "goto"),
        ]
    );
    assert_eq!(notes[0].2, "Variabel `tak` dideklarasikan tetapi tidak dipakai.");
    assert_eq!(notes[1].2, "Angka 365 muncul 3 kali; jadikan `const`.");
    assert_eq!(notes[2].2, "Fungsi `TanpaHasil` tidak pernah mengisi hasilnya.");
    assert_eq!(notes[3].2, "`Tambah` mengubah variabel global `total`.");
    assert_eq!(notes[6].2, "Blok di `Dalam` bersarang 5 tingkat; pertimbangkan prosedur terpisah.");

    let routines = m.get("routines").and_then(Value::as_array).unwrap();
    let figures: Vec<(&str, i64, i64, i64, bool)> = routines
        .iter()
        .map(|r| {
            (
                text(r, "name"),
                num(r, "statements"),
                num(r, "nesting"),
                num(r, "complexity"),
                r.get("recursive").and_then(Value::as_bool).unwrap(),
            )
        })
        .collect();
    assert_eq!(
        figures,
        [
            ("Catatan", 8, 0, 1, false),
            ("TanpaHasil", 1, 0, 1, false),
            ("Fakt", 3, 1, 2, true),
            ("Tambah", 2, 0, 1, false),
            ("Dalam", 7, 5, 7, false),
        ]
    );

    let facts = m.get("facts").unwrap();
    assert_eq!(num(facts, "routines"), 4);
    assert_eq!(num(facts, "statements"), 21);
    assert_eq!(num(facts, "max_nesting"), 5);
    assert_eq!(num(facts, "gotos"), 1);
    assert_eq!(facts.get("arrays").and_then(Value::as_bool), Some(true));
    assert_eq!(facts.get("records").and_then(Value::as_bool), Some(false));
    // x, y, tak: Integer (2 bytes, as in TP), total: LongInt, data: 365 Integers.
    assert_eq!(num(facts, "global_bytes"), 3 * 2 + 4 + 365 * 2);
    let recursive: Vec<&str> =
        facts.get("recursive").and_then(Value::as_array).unwrap().iter().map(|v| v.as_str().unwrap()).collect();
    assert_eq!(recursive, ["Fakt"]);
}

#[test]
fn renaming_and_reformatting_keep_the_shape() {
    let a = shape(&metrics("ANTRE_A.PAS"));
    let b = shape(&metrics("ANTRE_B.PAS"));
    let c = shape(&metrics("ANTRE_C.PAS"));
    assert!(a.len() > 40, "shape too short: {a:?}");
    assert_eq!(a, b);
    assert_ne!(a, c);
    // The shape names statements and operators, never the names or values.
    assert!(a.iter().all(|t| t != "waktu" && t != "1000"));
}
