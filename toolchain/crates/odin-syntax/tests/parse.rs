// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Parser tests: the bundled examples, the grammar torture program, the
//! error corpus (positions checked against FPC 3.2.2), and precedence.
//!
//! Golden AST dumps live in `tests/golden/`; regenerate them with
//! `ODIN_BLESS=1 cargo test -p odin-syntax --test parse`.

use std::path::{Path, PathBuf};

use odin_base::SourceMap;
use odin_syntax::{LexOptions, dump, parse_file};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

fn parse_path(path: &Path) -> Result<String, String> {
    let mut map = SourceMap::new();
    let id = map.load(path).unwrap();
    parse_file(&mut map, id, &LexOptions::default()).map(|p| dump::module(&p.module)).map_err(|d| d.render(&map))
}

fn parse_text(src: &str) -> Result<String, (u16, u32, u32)> {
    let mut map = SourceMap::new();
    let id = map.add("t.pas", src.as_bytes().to_vec());
    match parse_file(&mut map, id, &LexOptions::default()) {
        Ok(p) => Ok(dump::module(&p.module)),
        Err(d) => {
            let loc = map.location(d.span);
            Err((d.code, loc.line, loc.column))
        }
    }
}

fn check_golden(name: &str, actual: &str) {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/golden").join(format!("{name}.ast"));
    if std::env::var_os("ODIN_BLESS").is_some() {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, actual).unwrap();
        return;
    }
    let expected = std::fs::read_to_string(&path)
        .unwrap_or_else(|_| panic!("missing golden {}; run with ODIN_BLESS=1", path.display()));
    assert_eq!(actual, expected, "AST dump of {name} changed; rerun with ODIN_BLESS=1 if intended");
}

#[test]
fn every_example_parses() {
    let mut count = 0;
    for entry in std::fs::read_dir(repo().join("examples")).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_some_and(|e| e.eq_ignore_ascii_case("pas")) {
            let dumped = parse_path(&path).unwrap_or_else(|e| panic!("{e}"));
            check_golden(path.file_stem().unwrap().to_str().unwrap(), &dumped);
            count += 1;
        }
    }
    assert_eq!(count, 90);
}

#[test]
fn torture_program_parses() {
    let dumped = parse_path(&repo().join("tests/pascal/syntax/TORTURE.PAS")).unwrap_or_else(|e| panic!("{e}"));
    check_golden("TORTURE", &dumped);
}

#[test]
fn error_corpus_matches_fpc_positions() {
    let dir = repo().join("tests/pascal/errors");
    let mut count = 0;
    for entry in std::fs::read_dir(&dir).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_none_or(|e| e != "PAS") {
            continue;
        }
        let expected = std::fs::read_to_string(path.with_extension("err")).unwrap();
        let want: Vec<u32> = expected.split_whitespace().map(|n| n.parse().unwrap()).collect();
        let mut map = SourceMap::new();
        let id = map.load(&path).unwrap();
        let err = parse_file(&mut map, id, &LexOptions::default())
            .err()
            .unwrap_or_else(|| panic!("{} parsed without error", path.display()));
        let loc = map.location(err.span);
        assert_eq!(
            (err.code as u32, loc.line, loc.column),
            (want[0], want[1], want[2]),
            "{}: got {}",
            path.display(),
            err.render(&map)
        );
        count += 1;
    }
    assert!(count >= 15);
}

fn body_of(src: &str) -> String {
    let dumped = parse_text(&format!("begin\n{src}\nend.")).unwrap_or_else(|e| panic!("{e:?}"));
    let joined = dumped.lines().skip(2).map(str::trim).collect::<Vec<_>>().join(" ");
    // Drop the closers of "(begin" and "(program".
    joined.strip_suffix("))").unwrap().to_string()
}

#[test]
fn operator_precedence() {
    assert_eq!(body_of("x := -a * b + c"), "(:= x (+ (* (neg a) b) c))");
    assert_eq!(body_of("x := -1 and 3"), "(:= x (and (neg 1) 3))");
    assert_eq!(body_of("x := not a and b or c"), "(:= x (or (and (not a) b) c))");
    assert_eq!(body_of("x := a + b * c = d - e"), "(:= x (= (+ a (* b c)) (- d e)))");
    assert_eq!(body_of("x := a - b - c"), "(:= x (- (- a b) c))");
    assert_eq!(body_of("x := i in [1, 3..5]"), "(:= x (in i [1, 3..5]))");
    assert_eq!(body_of("p^.f[i].g := @q"), "(:= (. (index (. (^ p) f) i) g) (@ q))");
}

#[test]
fn statements() {
    assert_eq!(body_of("WriteLn(x:10:2, y:3)"), "(do (call WriteLn x:10:2 y:3))");
    assert_eq!(body_of(";;"), "(empty) (empty) (empty)");
    assert_eq!(body_of("1: goto 1"), "(label 1 (goto 1))");
    assert_eq!(body_of("inherited Init(1)"), "(do (call (inherited Init) 1))");
    assert_eq!(body_of("s := 'a'#13^J'b'"), "(:= s 'a'#13#10'b')");
}

#[test]
fn typed_constants_and_pointer_types() {
    let d = parse_text(
        "const X: Integer = (1 + 2) * 3; Y: array[1..2] of Byte = (1, 2); type P = ^T; Q = ^Integer; begin end.",
    )
    .unwrap();
    assert!(d.contains("(const X : Integer = (* (+ 1 2) 3))"), "{d}");
    assert!(d.contains("(const Y : (array [(.. 1 2)] Byte) = (1, 2))"), "{d}");
    assert!(d.contains("(type P = (^ T))"), "{d}");
    assert!(d.contains("(type Q = (^ Integer))"), "{d}");
}

#[test]
fn units() {
    let d = parse_text(
        "unit U; interface uses Crt; const C = 1; procedure P(var X: Integer); function F: Integer; cdecl; external 'c' name 'f';\
         implementation procedure P(var X: Integer); begin X := C end; begin P(Y) end.",
    )
    .unwrap();
    assert!(d.contains("(procedure P (var X: Integer)\n      declaration)"), "{d}");
    assert!(d.contains("(external 'c' name 'f')"), "{d}");
    assert!(d.contains("(init"), "{d}");
    // A unit without initialization ends with a bare "end.".
    assert!(parse_text("unit U; interface implementation end.").is_ok());
}

#[test]
fn eof_inside_block() {
    assert_eq!(parse_text("begin\n  x := 1;\n"), Err((10, 3, 1)));
}

#[test]
fn class_declarations() {
    let d = parse_text(
        "type TB = class; TC = class of TB; \
         TB = class(TObject) \
           strict private FX: Integer; \
           protected class var Count: Integer; \
           public constructor Create(A: Integer); overload; destructor Destroy; override; \
           function Area: Real; virtual; abstract; class function Kind: String; \
           property X: Integer read FX write FX; \
           property Items[I: Integer]: Integer read GetItem; default; \
         end; \
         TE = class(TB); \
         class function TB.Kind: String; begin Kind := 'b' end; \
         begin inherited; x := a is TB; y := (a as TB).X end.",
    )
    .unwrap();
    assert!(d.contains("(type TB = (class-forward))"), "{d}");
    assert!(d.contains("(type TC = (class-of TB))"), "{d}");
    assert!(d.contains("(strict-private FX: Integer)"), "{d}");
    assert!(d.contains("(protected class-var Count: Integer)"), "{d}");
    assert!(d.contains("(constructor Create (A: Integer) [overload])"), "{d}");
    assert!(d.contains("(destructor Destroy [override])"), "{d}");
    assert!(d.contains("(function Area : Real [virtual] [abstract])"), "{d}");
    assert!(d.contains("(class function Kind : string)"), "{d}");
    assert!(d.contains("(property X : Integer read FX write FX)"), "{d}");
    assert!(d.contains("(property Items [I: Integer] : Integer read GetItem default)"), "{d}");
    assert!(d.contains("(type TE = (class (TB)))"), "{d}");
    assert!(d.contains("(class function TB.Kind : string"), "{d}");
    assert!(d.contains("(do (inherited))"), "{d}");
    assert!(d.contains("(:= x (is a TB))"), "{d}");
    assert!(d.contains("(:= y (. (as a TB) X))"), "{d}");
}

#[test]
fn class_words_stay_identifiers_in_tp7_code() {
    // A TP7 program may use every word of the class extension as a name.
    let d = parse_text(
        "type R = record Property, Override: Integer; Class: Char end; \
         var Is, As, Strict, Published: Integer; Abstract: R; \
         procedure Overload(Dynamic: Integer); begin end; \
         begin Is := As + 1; Abstract.Property := Is * As; Overload(Is) end.",
    )
    .unwrap();
    assert!(d.contains("(record (Property Override: Integer) (Class: Char))"), "{d}");
    assert!(d.contains("(:= Is (+ As 1))"), "{d}");
    assert!(d.contains("(:= (. Abstract Property) (* Is As))"), "{d}");
    assert!(d.contains("(do (call Overload Is))"), "{d}");
}
