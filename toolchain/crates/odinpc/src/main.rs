// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! `odinpc`: the Odin Pascal toolchain driver.
//!
//! Exit codes: 0 success, 1 compile errors, 2 usage or internal error.
//! With `--diag-format json` every stdout line is one JSON object (see
//! IMPLEMENTATION_PLAN.md section 6.1).

mod debuginfo;
mod driver;
mod metrics;
mod options;

use std::process::ExitCode;
use std::time::Instant;

use odin_base::json::JsonWriter;
use odin_base::{Diagnostic, SourceMap};
use odin_syntax::{dump, parse_file};

use options::{Command, DiagFormat, Options};

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|a| a == "debug") {
        return ExitCode::from(odin_debug::session::main(&args[1..]) as u8);
    }
    let options = match options::parse(&args) {
        Ok(o) => o,
        Err(message) => {
            eprintln!("odinpc: {message}");
            eprintln!("{}", options::USAGE);
            return ExitCode::from(2);
        }
    };
    match options.command {
        Command::Help => {
            println!("{}", options::USAGE);
            ExitCode::SUCCESS
        }
        Command::Version => {
            println!("odinpc {} ({})", env!("CARGO_PKG_VERSION"), options::host_target());
            ExitCode::SUCCESS
        }
        Command::Check => check(&options),
        Command::Metrics => metrics(&options),
        Command::Build => build(&options),
    }
}

/// Reports diagnostics in the requested format.
struct Reporter<'a> {
    format: DiagFormat,
    map: &'a SourceMap,
}

impl Reporter<'_> {
    fn diagnostic(&self, d: &Diagnostic) {
        match self.format {
            DiagFormat::Json => println!("{}", d.to_json(self.map)),
            DiagFormat::Text => println!("{}", d.render(self.map)),
        }
    }

    fn result(&self, success: bool, lines: u32, started: Instant) {
        let ms = started.elapsed().as_millis() as i64;
        match self.format {
            DiagFormat::Json => {
                let mut w = JsonWriter::object();
                w.field_str("type", "result");
                w.field_bool("success", success);
                w.field_num("lines", lines as i64);
                w.field_num("elapsed_ms", ms);
                println!("{}", w.finish());
            }
            DiagFormat::Text if success => println!("Pemeriksaan berhasil: {lines} baris, {ms} ms."),
            DiagFormat::Text => {}
        }
    }

    fn result_with_exe(
        &self,
        success: bool,
        lines: u32,
        started: Instant,
        exe: &std::path::Path,
        odbg: &std::path::Path,
    ) {
        let ms = started.elapsed().as_millis() as i64;
        match self.format {
            DiagFormat::Json => {
                let mut w = JsonWriter::object();
                w.field_str("type", "result");
                w.field_bool("success", success);
                w.field_str("executable", &exe.to_string_lossy());
                w.field_str("debug_info", &odbg.to_string_lossy());
                w.field_num("lines", lines as i64);
                w.field_num("elapsed_ms", ms);
                println!("{}", w.finish());
            }
            DiagFormat::Text => println!("Kompilasi berhasil: {lines} baris, {ms} ms. Executable: {}", exe.display()),
        }
    }
}

fn check(options: &Options) -> ExitCode {
    let started = Instant::now();
    let mut map = SourceMap::new();
    let result = driver::check(&mut map, options);
    let reporter = Reporter { format: options.diag_format, map: &map };
    match result {
        Ok(checked) => {
            for w in &checked.warnings {
                reporter.diagnostic(w);
            }
            if options.dump_ast {
                let source = options.source.as_ref().expect("checked by options::parse");
                if let Some(id) = map.find(&odin_base::canonical(&source).unwrap_or_default()) {
                    let mut tmp = SourceMap::new();
                    let id2 = tmp.add(map.file(id).path.clone(), map.file(id).bytes.clone());
                    if let Ok(p) = parse_file(&mut tmp, id2, &options.lex_options()) {
                        print!("{}", dump::module(&p.module));
                    }
                }
            }
            reporter.result(true, checked.lines, started);
            ExitCode::SUCCESS
        }
        Err(failed) => {
            for w in &failed.warnings {
                reporter.diagnostic(w);
            }
            reporter.diagnostic(&failed.error);
            reporter.result(false, 0, started);
            ExitCode::from(1)
        }
    }
}

/// `odinpc metrics`: checks the program like `check`, then prints what
/// `metrics::describe` finds in the user's files.
fn metrics(options: &Options) -> ExitCode {
    let started = Instant::now();
    let mut map = SourceMap::new();
    let result = driver::check(&mut map, options);
    let reporter = Reporter { format: options.diag_format, map: &map };
    let checked = match result {
        Ok(c) => c,
        Err(failed) => {
            for w in &failed.warnings {
                reporter.diagnostic(w);
            }
            reporter.diagnostic(&failed.error);
            reporter.result(false, 0, started);
            return ExitCode::from(1);
        }
    };
    for w in &checked.warnings {
        reporter.diagnostic(w);
    }
    let Some(rtl) = driver::rtl_dir(options) else {
        reporter.result(false, 0, started);
        return ExitCode::from(1);
    };
    let source = options.source.as_ref().expect("checked by options::parse");
    let main_file = map.find(&odin_base::canonical(source).unwrap_or_default()).unwrap_or(odin_base::FileId(0));
    let user = driver::user_files(&map, &rtl);
    let found = metrics::describe(&map, &checked.program, &user, main_file, &options.lex_options());
    match options.diag_format {
        DiagFormat::Json => println!("{}", found.to_json(&map)),
        DiagFormat::Text => print!("{}", found.to_text(&map)),
    }
    reporter.result(true, checked.lines, started);
    ExitCode::SUCCESS
}

fn build(options: &Options) -> ExitCode {
    let started = Instant::now();
    let mut map = SourceMap::new();
    let result = driver::check(&mut map, options);
    let reporter = Reporter { format: options.diag_format, map: &map };
    let checked = match result {
        Ok(c) => c,
        Err(failed) => {
            for w in &failed.warnings {
                reporter.diagnostic(w);
            }
            reporter.diagnostic(&failed.error);
            reporter.result(false, 0, started);
            return ExitCode::from(1);
        }
    };
    for w in &checked.warnings {
        reporter.diagnostic(w);
    }
    let out = options.out.as_ref().expect("checked by options::parse");
    if checked.is_unit {
        // A unit on its own: checked, no executable (and none left behind).
        let _ = std::fs::remove_file(out);
        reporter.result(true, checked.lines, started);
        return ExitCode::SUCCESS;
    }
    let built = match driver::build(&map, options, &checked) {
        Ok(b) => b,
        Err(d) => {
            reporter.diagnostic(&d);
            reporter.result(false, checked.lines, started);
            return ExitCode::from(1);
        }
    };
    // NAME.odbg sits next to the executable: line table for runtime error
    // positions, and everything `odinpc debug` needs for a --debug build.
    let odbg = driver::debug_info_path(out);
    if let Err(e) = std::fs::write(&odbg, built.debug_info.to_json()) {
        eprintln!("odinpc: {}: {e}", odbg.display());
        return ExitCode::from(2);
    }
    if let Err(e) = driver::write_executable(out, &built.bytes) {
        eprintln!("odinpc: {}: {e}", out.display());
        return ExitCode::from(2);
    }
    reporter.result_with_exe(true, checked.lines, started, out, &odbg);
    ExitCode::SUCCESS
}
