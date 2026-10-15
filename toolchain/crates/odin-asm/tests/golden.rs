// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Compares odin_asm encodings with goldens produced by clang (see
//! `gen_golden.py`): every instruction of `x86_64_golden.txt` on its own, and
//! every block of `x86_64_blocks.s` as a whole. Relocations must match in
//! offset, kind and addend; their fields are masked before comparing bytes,
//! since Mach-O keeps part of the addend in the field and odin_asm does not.

use odin_asm::text::assemble;
use odin_asm::{Atom, RelocKind};

struct Expected {
    bytes: Vec<u8>,
    relocs: Vec<(u32, RelocKind, i64)>,
}

fn parse_line(line: &str) -> Option<(String, Expected)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let cols: Vec<&str> = line.split('|').map(str::trim).collect();
    assert!(cols.len() >= 2, "golden line without bytes (rerun gen_golden.py): {line}");
    let bytes = cols[1].split_whitespace().map(|h| u8::from_str_radix(h, 16).unwrap()).collect();
    let relocs = match cols.get(2) {
        None => Vec::new(),
        Some(r) => r
            .split(',')
            .map(|item| {
                let f: Vec<&str> = item.split(':').collect();
                let kind = match f[1] {
                    "pc32" => RelocKind::X86Pc32,
                    "got" => RelocKind::X86GotPc32,
                    "abs64" => RelocKind::Abs64,
                    k => panic!("unknown reloc kind {k}"),
                };
                (f[0].parse().unwrap(), kind, f[2].parse().unwrap())
            })
            .collect(),
    };
    Some((cols[0].to_string(), Expected { bytes, relocs }))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" ")
}

/// Compares one atom with its golden; returns a description of any mismatch.
fn compare(atom: &Atom, want: &Expected) -> Option<String> {
    let got: Vec<(u32, RelocKind, i64)> = atom.relocs.iter().map(|r| (r.offset, r.kind, r.addend)).collect();
    if got != want.relocs {
        return Some(format!("relocations {got:?}, expected {:?}", want.relocs));
    }
    let mut ours = atom.bytes.clone();
    let mut theirs = want.bytes.clone();
    for &(offset, kind, _) in &want.relocs {
        let len = if kind == RelocKind::Abs64 { 8 } else { 4 };
        for b in [&mut ours, &mut theirs] {
            let end = (offset as usize + len).min(b.len());
            b[(offset as usize).min(end)..end].fill(0);
        }
    }
    (ours != theirs).then(|| format!("bytes {}, expected {}", hex(&atom.bytes), hex(&want.bytes)))
}

#[test]
fn instructions_match_clang() {
    let golden = include_str!("x86_64_golden.txt");
    let mut failures = Vec::new();
    let mut count = 0;
    for line in golden.lines() {
        let Some((insn, want)) = parse_line(line) else { continue };
        count += 1;
        match assemble(&format!("_t:\n    {insn}\n"), "golden.s") {
            Err(e) => failures.push(format!("{insn}: {e}")),
            Ok(obj) => {
                if let Some(msg) = compare(&obj.atoms[0], &want) {
                    failures.push(format!("{insn}: {msg}"));
                }
            }
        }
    }
    assert!(count > 400, "only {count} golden instructions");
    assert!(
        failures.is_empty(),
        "{} of {count} instructions differ from clang:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn blocks_match_clang() {
    let obj = assemble(include_str!("x86_64_blocks.s"), "x86_64_blocks.s").unwrap();
    let golden = include_str!("x86_64_blocks.golden");
    let mut failures = Vec::new();
    let mut count = 0;
    for line in golden.lines() {
        let Some((name, want)) = parse_line(line) else { continue };
        count += 1;
        let atom = obj.atoms.iter().find(|a| a.name == name).unwrap_or_else(|| panic!("no atom {name}"));
        if let Some(msg) = compare(atom, &want) {
            failures.push(format!("{name}: {msg}"));
        }
    }
    assert_eq!(count, obj.atoms.len(), "every block has a golden");
    assert!(failures.is_empty(), "blocks differ from clang:\n{}", failures.join("\n"));
}
