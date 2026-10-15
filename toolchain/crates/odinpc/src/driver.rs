// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! The compilation pipeline: find and order units, analyse, generate code,
//! assemble the RTL shims and link.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use odin_base::{Diagnostic, FileId, SourceMap, Span, code};
use odin_codegen::{Os, c_library};
use odin_syntax::ast::{self, Module};
use odin_syntax::{LexOptions, find_file_ci, parse_file};

use crate::options::Options;

/// What a successful front end run produced.
pub struct Checked {
    pub program: odin_ir::Program,
    pub warnings: Vec<Diagnostic>,
    pub lines: u32,
    /// The source was a unit: it was checked, but there is no executable.
    pub is_unit: bool,
}

/// A compile failure: the first error plus warnings seen before it.
pub struct Failed {
    pub error: Diagnostic,
    pub warnings: Vec<Diagnostic>,
}

impl From<Diagnostic> for Failed {
    fn from(error: Diagnostic) -> Self {
        Failed { error, warnings: Vec::new() }
    }
}

struct LoadedUnit {
    name: String,
    module: Module,
    interface_uses: Vec<ast::Ident>,
    implementation_uses: Vec<ast::Ident>,
}

/// The RTL directory: `--rtl`, `$ODIN_RTL`, or an `rtl` folder above the
/// executable (repository and app bundle layouts).
pub fn rtl_dir(options: &Options) -> Option<PathBuf> {
    if let Some(p) = &options.rtl {
        return Some(p.clone());
    }
    if let Some(p) = std::env::var_os("ODIN_RTL") {
        return Some(PathBuf::from(p));
    }
    let exe = std::env::current_exe().ok()?;
    let mut dir = exe.parent();
    while let Some(d) = dir {
        let candidate = d.join("rtl");
        if candidate.join("system").join("system.pas").is_file() {
            return Some(candidate);
        }
        dir = d.parent();
    }
    None
}

struct Loader<'a> {
    map: &'a mut SourceMap,
    lex: LexOptions,
    dirs: Vec<PathBuf>,
    units: HashMap<String, LoadedUnit>,
    warnings: Vec<Diagnostic>,
}

impl Loader<'_> {
    fn find_unit(&self, name: &str) -> Option<PathBuf> {
        let lower = name.to_ascii_lowercase();
        for dir in &self.dirs {
            for ext in ["pas", "pp"] {
                if let Some(p) = find_file_ci(dir, &format!("{lower}.{ext}")) {
                    return Some(p);
                }
            }
        }
        None
    }

    fn parse(&mut self, path: &Path, span: Span) -> Result<(FileId, Module), Diagnostic> {
        let id = self
            .map
            .load(path)
            .map_err(|e| Diagnostic::error_with(code::FILE_NOT_FOUND, span, format!(": {} ({e})", path.display())))?;
        let parsed = parse_file(self.map, id, &self.lex)?;
        self.warnings.extend(parsed.warnings);
        Ok((id, parsed.module))
    }

    /// Loads unit `name` (and, recursively, the units it uses).
    fn load(&mut self, name: &ast::Ident) -> Result<(), Diagnostic> {
        let key = name.key();
        if self.units.contains_key(&key) {
            return Ok(());
        }
        let Some(path) = self.find_unit(&key) else {
            return Err(Diagnostic::error_with(
                code::FILE_NOT_FOUND,
                name.span,
                format!(": unit {}{}", name.name, missing_unit_hint(&key)),
            ));
        };
        let (_, module) = self.parse(&path, name.span)?;
        let Module::Unit(unit) = &module else {
            return Err(Diagnostic::error_with(
                code::UNIT_EXPECTED,
                name.span,
                format!(": {} bukan unit", path.display()),
            ));
        };
        if unit.name.key() != key {
            return Err(Diagnostic::error_with(
                code::UNIT_NAME_MISMATCH,
                unit.name.span,
                format!(": {} di berkas {}", unit.name.name, path.display()),
            ));
        }
        let interface_uses = unit.interface_uses.clone();
        let implementation_uses = unit.implementation_uses.clone();
        self.units.insert(
            key,
            LoadedUnit {
                name: name.key(),
                module,
                interface_uses: interface_uses.clone(),
                implementation_uses: implementation_uses.clone(),
            },
        );
        for u in interface_uses.iter().chain(implementation_uses.iter()) {
            if !u.is("SYSTEM") {
                self.load(u)?;
            }
        }
        Ok(())
    }
}

/// Orders units so that every unit follows the units its interface uses.
/// A unit reached through an implementation `uses` comes right after its
/// user when it can; when its interface leads back to a unit still being
/// ordered (TP allows that cycle) it is ordered once that unit is done.
fn order_units(units: &HashMap<String, LoadedUnit>, roots: &[ast::Ident]) -> Result<Vec<String>, Diagnostic> {
    #[derive(Clone, Copy, PartialEq)]
    enum Mark {
        Visiting,
        Done,
    }
    struct Order<'a> {
        units: &'a HashMap<String, LoadedUnit>,
        marks: HashMap<String, Mark>,
        out: Vec<String>,
        deferred: Vec<(String, Span)>,
    }
    impl Order<'_> {
        /// With `soft`, meeting a unit still being visited returns false
        /// instead of a circular-reference error.
        fn visit(&mut self, key: &str, span: Span, soft: bool) -> Result<bool, Diagnostic> {
            match self.marks.get(key) {
                Some(Mark::Done) => return Ok(true),
                Some(Mark::Visiting) if soft => return Ok(false),
                Some(Mark::Visiting) => {
                    return Err(Diagnostic::error_with(code::CIRCULAR_UNIT, span, format!(": {key}")));
                }
                None => {}
            }
            self.marks.insert(key.to_string(), Mark::Visiting);
            let u = &self.units[key];
            for dep in &u.interface_uses {
                if !dep.is("SYSTEM") && !self.visit(&dep.key(), dep.span, soft)? {
                    return Ok(false);
                }
            }
            self.marks.insert(key.to_string(), Mark::Done);
            self.out.push(key.to_string());
            for dep in &u.implementation_uses {
                let k = dep.key();
                if dep.is("SYSTEM") || self.marks.contains_key(&k) {
                    continue;
                }
                let (marks, len) = (self.marks.clone(), self.out.len());
                if !self.visit(&k, dep.span, true)? {
                    self.marks = marks;
                    self.out.truncate(len);
                    self.deferred.push((k, dep.span));
                }
            }
            Ok(true)
        }
    }
    let mut order = Order { units, marks: HashMap::new(), out: vec!["SYSTEM".to_string()], deferred: Vec::new() };
    order.marks.insert("SYSTEM".to_string(), Mark::Done);
    for r in roots {
        if !r.is("SYSTEM") {
            order.visit(&r.key(), r.span, false)?;
        }
        while !order.deferred.is_empty() {
            let (key, span) = order.deferred.remove(0);
            order.visit(&key, span, false)?;
        }
    }
    Ok(order.out)
}

/// Parses and analyses the program and every unit it needs.
pub fn check(map: &mut SourceMap, options: &Options) -> Result<Checked, Failed> {
    let source = options.source.as_ref().expect("checked by options::parse");
    let lex = options.lex_options();
    let main_id = map.load(source).map_err(|e| {
        Failed::from(Diagnostic::error_with(
            code::FILE_NOT_FOUND,
            Span::default(),
            format!(": {} ({e})", source.display()),
        ))
    })?;
    let parsed = parse_file(map, main_id, &lex)?;
    let mut warnings = parsed.warnings;
    // A unit compiled on its own is checked through a program that only
    // uses it, like TP producing a .TPU without an executable.
    let standalone_unit = match &parsed.module {
        Module::Unit(u) => Some(u.clone()),
        Module::Program(_) => None,
    };
    let synthetic;
    let program = match &parsed.module {
        Module::Program(p) => p,
        Module::Unit(u) => {
            let start = Span::new(main_id, 0, 0);
            synthetic = ast::Program {
                name: None,
                params: Vec::new(),
                uses: vec![u.name.clone()],
                block: ast::Block { decls: Vec::new(), body: ast::Body::Statements(Vec::new(), start) },
                span: start,
            };
            &synthetic
        }
    };
    let Some(rtl) = rtl_dir(options) else {
        return Err(Failed {
            error: Diagnostic::error_with(
                code::FILE_NOT_FOUND,
                Span::new(main_id, 0, 0),
                ": direktori RTL Odin (--rtl)",
            ),
            warnings,
        });
    };
    let mut dirs = vec![source.parent().map(Path::to_path_buf).unwrap_or_default()];
    dirs.extend(options.unit_paths.iter().cloned());
    dirs.push(rtl.clone());
    dirs.push(rtl.join("system"));
    dirs.push(rtl.join("vision"));
    let mut loader = Loader { map, lex, dirs, units: HashMap::new(), warnings: Vec::new() };
    if let Some(u) = &standalone_unit {
        loader.units.insert(
            u.name.key(),
            LoadedUnit {
                name: u.name.key(),
                module: Module::Unit(u.clone()),
                interface_uses: u.interface_uses.clone(),
                implementation_uses: u.implementation_uses.clone(),
            },
        );
        for dep in u.interface_uses.iter().chain(u.implementation_uses.iter()) {
            if !dep.is("SYSTEM") {
                if let Err(error) = loader.load(dep) {
                    warnings.append(&mut loader.warnings);
                    return Err(Failed { error, warnings });
                }
            }
        }
    }
    let system = ast::Ident { name: "System".into(), span: Span::new(main_id, 0, 0) };
    let mut result = loader.load(&system);
    if result.is_ok() {
        for u in &program.uses {
            if !u.is("SYSTEM") {
                result = loader.load(u);
                if result.is_err() {
                    break;
                }
            }
        }
    }
    warnings.append(&mut loader.warnings);
    if let Err(error) = result {
        return Err(Failed { error, warnings });
    }
    let order =
        order_units(&loader.units, &program.uses).map_err(|error| Failed { error, warnings: warnings.clone() })?;
    let mut units = loader.units;
    let mut sources = Vec::new();
    for key in order {
        let u = units.remove(&key).expect("ordered unit was loaded");
        sources.push(odin_sema::UnitSource { name: u.name, module: u.module });
    }
    let program_module = Module::Program(program.clone());
    sources.push(odin_sema::UnitSource { name: "$PROGRAM".into(), module: program_module });
    let lines = (0..map.len()).map(|i| map.file(FileId(i as u32)).line_count()).sum();
    match odin_sema::analyze(map, sources) {
        Ok(a) => {
            warnings.extend(a.warnings);
            Ok(Checked { program: a.program, warnings, lines, is_unit: standalone_unit.is_some() })
        }
        Err(error) => Err(Failed { error, warnings }),
    }
}

/// A linked program and its debug description.
pub struct Built {
    pub bytes: Vec<u8>,
    pub debug_info: odin_debuginfo::DebugInfo,
}

/// Generates and links the executable.
pub fn build(map: &SourceMap, options: &Options, checked: &Checked) -> Result<Built, Diagnostic> {
    let (os, target) = match options.target.as_str() {
        "x86_64-darwin" => (Os::Darwin, odin_link::Target::X86_64Darwin),
        "x86_64-linux" => (Os::Linux, odin_link::Target::X86_64Linux),
        "x86_64-windows" => (Os::Windows, odin_link::Target::X86_64Windows),
        other => {
            let hint = match other {
                "aarch64-darwin" | "aarch64-linux" => "; arm64 menyusul di Tahap 8c",
                _ => "",
            };
            return Err(Diagnostic::error_with(
                code::NOT_SUPPORTED,
                Span::default(),
                format!(": target {other} (yang tersedia: x86_64-darwin, x86_64-linux, x86_64-windows{hint})"),
            ));
        }
    };
    let rtl = rtl_dir(options).ok_or_else(|| Diagnostic::error_with(code::FILE_NOT_FOUND, Span::default(), ": RTL"))?;
    // --debug instruments the user's sources, never the RTL.
    let mut debug_files = std::collections::HashSet::new();
    if options.debug {
        let rtl_root = rtl.canonicalize().unwrap_or_else(|_| rtl.clone());
        for i in 0..map.len() {
            let path = &map.file(FileId(i as u32)).path;
            let path = path.canonicalize().unwrap_or_else(|_| path.clone());
            if !path.starts_with(&rtl_root) {
                debug_files.insert(FileId(i as u32));
            }
        }
    }
    let mut out = odin_codegen::x86_64::generate(&checked.program, &odin_codegen::Options { os, debug_files })
        .map_err(|e| Diagnostic::error_with(code::CODEGEN_ERROR, e.span, format!(": {}", e.message)))?;
    let shim_path = rtl.join("system").join("arch").join(format!("{}.s", options.target));
    let shim_text = std::fs::read_to_string(&shim_path).map_err(|e| {
        Diagnostic::error_with(code::FILE_NOT_FOUND, Span::default(), format!(": {} ({e})", shim_path.display()))
    })?;
    let shim = odin_asm::text::assemble(&shim_text, &shim_path.to_string_lossy())
        .map_err(|e| Diagnostic::error_with(code::INTERNAL, Span::default(), format!(": {e}")))?;
    let _ = c_library(os);
    let identifier = options
        .out
        .as_ref()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "program".into());
    // On Linux and Windows the process starts in the shim (`_start`,
    // `mainCRTStartup`), which sets up the C library and calls the code
    // generator's `main`.
    let entry = match os {
        Os::Linux => "_start",
        Os::Windows => "mainCRTStartup",
        Os::Darwin => out.entry.as_str(),
    };
    let link_options = odin_link::LinkOptions::new(target, entry, &identifier);
    let object = std::mem::take(&mut out.object);
    let image = odin_link::link(&[object, shim], &link_options).map_err(|e| {
        let code = match e {
            odin_link::LinkError::Undefined { .. } => code::UNDEFINED_EXTERNAL,
            _ => code::INTERNAL,
        };
        Diagnostic::error_with(code, Span::default(), format!(": {e}"))
    })?;
    let debug_info = crate::debuginfo::describe(map, &checked.program, &out, &image.symbols, image.image_base);
    Ok(Built { bytes: image.bytes, debug_info })
}

/// `NAME.odbg` next to executable `NAME`.
pub fn debug_info_path(exe: &Path) -> PathBuf {
    let mut name = exe.file_name().map(|n| n.to_os_string()).unwrap_or_default();
    name.push(".odbg");
    exe.with_file_name(name)
}

/// Writes the executable next to its final name, then renames it into
/// place, so a failed write never leaves a half-written program.
pub fn write_executable(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(".odinpc-{}.tmp", std::process::id()));
    std::fs::write(&tmp, bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755))?;
    }
    // Windows refuses to rename over an existing file.
    #[cfg(windows)]
    let _ = std::fs::remove_file(path);
    std::fs::rename(&tmp, path)
}

/// Explains a standard TP7 unit that the Odin RTL does not provide (yet).
fn missing_unit_hint(key: &str) -> &'static str {
    if matches!(key, "COLORSEL" | "TEXTVIEW") {
        "; unit Turbo Vision opsional ini belum ada di Odin Vision. Pakai backend FPC untuk program ini"
    } else if matches!(key, "GRAPH" | "GRAPH3" | "OVERLAY" | "WINDOS" | "TURBO3") {
        "; unit era DOS ini tidak tersedia di macOS (lihat docs/COMPATIBILITY.txt)"
    } else {
        ""
    }
}
