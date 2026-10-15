// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Command-line parsing (no third-party crates).

use std::collections::HashSet;
use std::path::PathBuf;

use odin_syntax::{LexOptions, Switches};

pub const USAGE: &str = "\
Pemakaian:
  odinpc build SOURCE --out EXE [opsi]   kompilasi menjadi executable
  odinpc check SOURCE [opsi]     periksa sintaks
  odinpc version                 versi toolchain
  odinpc debug --exe EXE --ide-fds R,W [--odbg F] [--cwd DIR] -- ARGS
                                 jalankan build --debug di bawah debugger

Opsi:
  --unit-path DIR                direktori unit (boleh berulang)
  --include-path DIR             direktori {$I} (boleh berulang)
  --define NAMA                  simbol kondisional (boleh berulang)
  --range-checks / --no-range-checks
  --overflow-checks / --no-overflow-checks
  --diag-format text|json        bentuk keluaran diagnostik (bawaan: text)
  --out EXE                      berkas executable hasil (build)
  --cache DIR                    direktori cache unit (build)
  --rtl DIR                      direktori sumber RTL (build)
  --build-all                    kompilasi ulang semua unit (build)
  --debug                        sisipkan hook debugger (build)
  --target TARGET                x86_64-darwin, aarch64-darwin, ... (build)
  --dump-ast                     cetak AST (check)";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Command {
    Build,
    Check,
    Version,
    Help,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DiagFormat {
    Text,
    Json,
}

#[derive(Debug)]
pub struct Options {
    pub command: Command,
    pub source: Option<PathBuf>,
    pub unit_paths: Vec<PathBuf>,
    pub include_paths: Vec<PathBuf>,
    pub defines: Vec<String>,
    pub range_checks: bool,
    pub overflow_checks: bool,
    pub diag_format: DiagFormat,
    pub dump_ast: bool,
    pub out: Option<PathBuf>,
    pub cache: Option<PathBuf>,
    pub rtl: Option<PathBuf>,
    pub build_all: bool,
    pub debug: bool,
    pub target: String,
}

/// `x86_64-darwin`, `aarch64-linux`, ...
pub fn host_target() -> String {
    let os = if cfg!(target_os = "macos") { "darwin" } else { std::env::consts::OS };
    format!("{}-{}", std::env::consts::ARCH, os)
}

pub fn parse(args: &[String]) -> Result<Options, String> {
    let mut it = args.iter();
    let command = match it.next().map(String::as_str) {
        Some("build") => Command::Build,
        Some("check") => Command::Check,
        Some("version" | "--version") => Command::Version,
        Some("help" | "--help" | "-h") | None => Command::Help,
        Some(other) => return Err(format!("perintah tidak dikenal: {other}")),
    };
    let mut o = Options {
        command,
        source: None,
        unit_paths: Vec::new(),
        include_paths: Vec::new(),
        defines: Vec::new(),
        range_checks: false,
        overflow_checks: false,
        diag_format: DiagFormat::Text,
        dump_ast: false,
        out: None,
        cache: None,
        rtl: None,
        build_all: false,
        debug: false,
        target: host_target(),
    };
    while let Some(arg) = it.next() {
        let mut value = |name: &str| it.next().cloned().ok_or_else(|| format!("{name} memerlukan nilai"));
        match arg.as_str() {
            "--unit-path" => o.unit_paths.push(value(arg)?.into()),
            "--include-path" => o.include_paths.push(value(arg)?.into()),
            "--define" => o.defines.push(value(arg)?.to_ascii_uppercase()),
            "--range-checks" => o.range_checks = true,
            "--no-range-checks" => o.range_checks = false,
            "--overflow-checks" => o.overflow_checks = true,
            "--no-overflow-checks" => o.overflow_checks = false,
            "--dump-ast" => o.dump_ast = true,
            "--out" => o.out = Some(value(arg)?.into()),
            "--cache" => o.cache = Some(value(arg)?.into()),
            "--rtl" => o.rtl = Some(value(arg)?.into()),
            "--build-all" => o.build_all = true,
            "--debug" => o.debug = true,
            "--target" => o.target = value(arg)?,
            "--diag-format" => {
                o.diag_format = match value(arg)?.as_str() {
                    "json" => DiagFormat::Json,
                    "text" => DiagFormat::Text,
                    other => return Err(format!("format diagnostik tidak dikenal: {other}")),
                }
            }
            s if s.starts_with("--") => return Err(format!("opsi tidak dikenal: {s}")),
            s => {
                if o.source.is_some() {
                    return Err(format!("lebih dari satu berkas sumber: {s}"));
                }
                o.source = Some(s.into());
            }
        }
    }
    if matches!(o.command, Command::Check | Command::Build) && o.source.is_none() {
        return Err("berkas sumber belum diberikan".into());
    }
    if o.command == Command::Build && o.out.is_none() {
        return Err("build memerlukan --out EXE".into());
    }
    Ok(o)
}

impl Options {
    pub fn lex_options(&self) -> LexOptions {
        let mut defines: HashSet<String> = self.defines.iter().cloned().collect();
        defines.insert("ODIN".into());
        defines.insert("VER70".into());
        defines.insert(if self.target.starts_with("aarch64") { "CPUAARCH64" } else { "CPUX86_64" }.into());
        defines.insert("CPU64".into());
        // The same OS symbols as FPC, so RTL sources read alike under both compilers.
        if self.target.ends_with("windows") {
            defines.insert("WINDOWS".into());
            defines.insert("MSWINDOWS".into());
        } else {
            defines.insert(if self.target.ends_with("darwin") { "DARWIN" } else { "LINUX" }.into());
            defines.insert("UNIX".into());
        }
        let mut switches = Switches::tp_default();
        switches.set(Switches::RANGE, self.range_checks);
        switches.set(Switches::OVERFLOW, self.overflow_checks);
        LexOptions { defines, switches, include_paths: self.include_paths.clone() }
    }
}
