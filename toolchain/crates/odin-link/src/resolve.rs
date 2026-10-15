// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Symbol resolution and smart linking, independent of the output format.
//!
//! Atom names, labels and imports share one namespace across the link. Only
//! atoms reachable from the entry symbol or marked `keep` survive; undefined
//! names are reported only when a surviving atom refers to them, so dead code
//! may mention symbols the link does not provide.

use std::collections::HashMap;

use odin_asm::object::{Atom, Import, Object, RelocKind, SectionKind};

use crate::LinkError;
use crate::reloc::field_size;

/// What a name refers to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Sym {
    /// A place inside the atom with this index in [`Resolved::atoms`].
    Local { atom: usize, offset: u64 },
    /// The import with this index in [`Resolved::imports`].
    Import(usize),
}

/// The input after symbol resolution and smart linking.
pub(crate) struct Resolved<'a> {
    /// Every input atom: objects in order, each object's atoms in order.
    pub atoms: Vec<&'a Atom>,
    /// Whether smart linking kept the atom with the same index.
    pub live: Vec<bool>,
    /// Imports some live atom refers to, in order of first reference.
    pub imports: Vec<&'a Import>,
    /// The entry symbol.
    pub entry: Sym,
    /// Atom and label names.
    defined: HashMap<&'a str, (usize, u64)>,
    /// Indices into `imports`.
    import_index: HashMap<&'a str, usize>,
}

impl<'a> Resolved<'a> {
    /// What `name` refers to. Every relocation target of a live atom
    /// resolves.
    pub fn lookup(&self, name: &str) -> Option<Sym> {
        if let Some(&(atom, offset)) = self.defined.get(name) {
            return Some(Sym::Local { atom, offset });
        }
        self.import_index.get(name).map(|&index| Sym::Import(index))
    }

    /// Indices of the live atoms, in input order.
    pub fn live_atoms(&self) -> impl Iterator<Item = usize> + '_ {
        (0..self.atoms.len()).filter(|&i| self.live[i])
    }

    /// Whether some atom or label is called `name`.
    pub fn defines(&self, name: &str) -> bool {
        self.defined.contains_key(name)
    }
}

/// Resolves names across `objects` and marks the atoms reachable from
/// `entry`.
pub(crate) fn resolve<'a>(objects: &'a [Object], entry: &str) -> Result<Resolved<'a>, LinkError> {
    resolve_with(objects, entry, |a, b| a == b)
}

/// [`resolve`] over any sequence of objects (so a format writer can add a
/// synthetic one, such as PE's `__ImageBase`), with `same_library` deciding
/// whether two library names mean one library: Windows compares DLL names
/// case-insensitively, so `KERNEL32.dll` and `kernel32.dll` must not make
/// one import a duplicate.
pub(crate) fn resolve_with<'a, I>(
    objects: I,
    entry: &str,
    same_library: impl Fn(&str, &str) -> bool,
) -> Result<Resolved<'a>, LinkError>
where
    I: IntoIterator<Item = &'a Object> + Clone,
{
    let mut atoms: Vec<&Atom> = Vec::new();
    let mut defined: HashMap<&str, (usize, u64)> = HashMap::new();
    for object in objects.clone() {
        for atom in &object.atoms {
            validate(object, atom)?;
            let index = atoms.len();
            atoms.push(atom);
            let names =
                std::iter::once((atom.name.as_str(), 0)).chain(atom.labels.iter().map(|(n, o)| (n.as_str(), *o)));
            for (name, offset) in names {
                if defined.insert(name, (index, offset)).is_some() {
                    return Err(LinkError::Duplicate { name: name.to_string() });
                }
            }
        }
    }

    let mut declared: HashMap<&str, &Import> = HashMap::new();
    for import in objects.into_iter().flat_map(|o| &o.imports) {
        if defined.contains_key(import.name.as_str()) {
            return Err(LinkError::Duplicate { name: import.name.clone() });
        }
        match declared.get(import.name.as_str()) {
            Some(seen) if !same_library(&seen.library, &import.library) => {
                return Err(LinkError::Duplicate { name: import.name.clone() });
            }
            Some(_) => {}
            None => {
                declared.insert(&import.name, import);
            }
        }
    }

    let Some(&(entry_atom, entry_offset)) = defined.get(entry) else {
        return Err(LinkError::Undefined { name: entry.to_string(), referenced_from: "(entry point)".to_string() });
    };

    // Mark everything reachable from the roots. Unknown names are skipped
    // here and reported below, in input order.
    let mut live = vec![false; atoms.len()];
    let mut work = vec![entry_atom];
    work.extend((0..atoms.len()).filter(|&i| atoms[i].keep));
    while let Some(index) = work.pop() {
        if std::mem::replace(&mut live[index], true) {
            continue;
        }
        for reloc in &atoms[index].relocs {
            if let Some(&(target, _)) = defined.get(reloc.target.as_str())
                && !live[target]
            {
                work.push(target);
            }
        }
    }

    let mut imports = Vec::new();
    let mut import_index = HashMap::new();
    for index in (0..atoms.len()).filter(|&i| live[i]) {
        for reloc in &atoms[index].relocs {
            let name = reloc.target.as_str();
            if defined.contains_key(name) || import_index.contains_key(name) {
                continue;
            }
            let Some(import) = declared.get(name) else {
                return Err(LinkError::Undefined {
                    name: name.to_string(),
                    referenced_from: atoms[index].name.clone(),
                });
            };
            import_index.insert(import.name.as_str(), imports.len());
            imports.push(*import);
        }
    }

    Ok(Resolved {
        atoms,
        live,
        imports,
        entry: Sym::Local { atom: entry_atom, offset: entry_offset },
        defined,
        import_index,
    })
}

/// Checks the invariants the object model documents but cannot enforce,
/// since its fields are public.
fn validate(object: &Object, atom: &Atom) -> Result<(), LinkError> {
    let fail = |what: String| Err(LinkError::Malformed(format!("{}: atom `{}`: {what}", object.name, atom.name)));
    if !atom.align.is_power_of_two() {
        return fail(format!("alignment {} is not a power of two", atom.align));
    }
    if atom.section == SectionKind::Bss {
        if !atom.bytes.is_empty() || !atom.relocs.is_empty() {
            return fail("zero-initialized atoms have neither bytes nor relocations".to_string());
        }
    } else if atom.size != atom.bytes.len() as u64 {
        return fail(format!("size {} differs from its {} bytes", atom.size, atom.bytes.len()));
    }
    for (label, offset) in &atom.labels {
        if *offset > atom.size {
            return fail(format!("label `{label}` at offset {offset} lies past the end"));
        }
    }
    for reloc in &atom.relocs {
        if reloc.offset as usize + field_size(reloc.kind) > atom.bytes.len() {
            return fail(format!("relocation to `{}` at offset {} lies past the end", reloc.target, reloc.offset));
        }
        if let RelocKind::Arm64PageOff12 { scale } = reloc.kind
            && scale > 4
        {
            return fail(format!("relocation to `{}` has scale {scale}", reloc.target));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use odin_asm::object::RelocKind::*;

    const LIBSYSTEM: &str = "/usr/lib/libSystem.B.dylib";

    fn code(name: &str) -> Atom {
        Atom::new(name, SectionKind::Text, 1, vec![0; 16])
    }

    fn import(name: &str) -> Import {
        Import { name: name.to_string(), library: LIBSYSTEM.to_string() }
    }

    fn object(name: &str, atoms: Vec<Atom>, imports: Vec<Import>) -> Object {
        Object { name: name.to_string(), atoms, imports }
    }

    fn live_names<'a>(resolved: &Resolved<'a>) -> Vec<&'a str> {
        resolved.live_atoms().map(|i| resolved.atoms[i].name.as_str()).collect()
    }

    #[test]
    fn smart_linking_follows_relocations_and_keep() {
        let objects = [
            object(
                "main",
                vec![
                    code("_main").reloc(0, X86Pc32, "_a", -4).reloc(4, X86GotPc32, "_write", -4),
                    code("_a").reloc(0, X86Pc32, "_b_mid", -4),
                    code("_dead").reloc(0, X86Pc32, "_dead2", -4),
                    code("_dead2").reloc(0, X86Pc32, "_dead", -4).reloc(4, X86GotPc32, "_unused_import", -4),
                ],
                vec![import("_write"), import("_unused_import")],
            ),
            object(
                "unit",
                vec![
                    Atom { labels: vec![("_b_mid".to_string(), 8)], ..code("_b") },
                    code("_table").keep().reloc(0, Abs64, "_c", 0),
                    code("_c"),
                    code("_dropped_too"),
                ],
                vec![import("_write")],
            ),
        ];
        let resolved = resolve(&objects, "_main").unwrap();
        assert_eq!(live_names(&resolved), ["_main", "_a", "_b", "_table", "_c"]);
        assert_eq!(resolved.imports, [&import("_write")]);
        assert_eq!(resolved.entry, Sym::Local { atom: 0, offset: 0 });
        assert_eq!(resolved.lookup("_b_mid"), Some(Sym::Local { atom: 4, offset: 8 }));
        assert_eq!(resolved.lookup("_write"), Some(Sym::Import(0)));
        assert_eq!(resolved.lookup("_unused_import"), None);
    }

    #[test]
    fn entry_may_be_a_label() {
        let objects = [object("m", vec![Atom { labels: vec![("start".to_string(), 4)], ..code("_main") }], vec![])];
        let resolved = resolve(&objects, "start").unwrap();
        assert_eq!(resolved.entry, Sym::Local { atom: 0, offset: 4 });
    }

    #[test]
    fn duplicates_are_errors() {
        let dup = |objects: &[Object]| match resolve(objects, "_main") {
            Err(LinkError::Duplicate { name }) => name,
            other => panic!("expected a duplicate, got {:?}", other.err()),
        };
        let a = object("a", vec![code("_main"), code("_x")], vec![]);
        assert_eq!(dup(&[a.clone(), object("b", vec![code("_x")], vec![])]), "_x");
        assert_eq!(dup(&[a.clone(), a]), "_main");
        assert_eq!(dup(&[object("a", vec![code("_main"), code("_x"), code("_x")], vec![])]), "_x");
        let labelled = Atom { labels: vec![("_x".to_string(), 0)], ..code("_y") };
        assert_eq!(dup(&[object("a", vec![code("_main"), code("_x"), labelled], vec![])]), "_x");
        assert_eq!(dup(&[object("a", vec![code("_main"), code("_write")], vec![import("_write")])]), "_write");
        let other_lib = Import { name: "_write".to_string(), library: "/usr/lib/libc++.1.dylib".to_string() };
        assert_eq!(dup(&[object("a", vec![code("_main")], vec![import("_write"), other_lib])]), "_write");
        // The same import declared twice is fine.
        assert!(
            resolve(&[object("a", vec![code("_main")], vec![import("_write"), import("_write")])], "_main").is_ok()
        );
    }

    #[test]
    fn library_names_compare_by_the_given_rule() {
        let upper = Import { name: "ExitProcess".to_string(), library: "KERNEL32.dll".to_string() };
        let lower = Import { name: "ExitProcess".to_string(), library: "kernel32.dll".to_string() };
        let main = code("_main").reloc(0, X86GotPc32, "ExitProcess", -4);
        let objects = [object("a", vec![main], vec![upper.clone()]), object("b", vec![], vec![lower])];
        assert!(matches!(resolve(&objects, "_main"), Err(LinkError::Duplicate { .. })));
        let resolved = resolve_with(&objects, "_main", |a, b| a.eq_ignore_ascii_case(b)).unwrap();
        assert_eq!(resolved.imports, [&upper], "the first declaration wins");
        // Extra objects can be chained on.
        let extra = object("extra", vec![code("_extra").keep()], vec![]);
        let resolved = resolve_with(objects.iter().chain([&extra]), "_main", |a, b| a.eq_ignore_ascii_case(b)).unwrap();
        assert_eq!(live_names(&resolved), ["_main", "_extra"]);
    }

    #[test]
    fn undefined_is_reported_only_for_live_atoms() {
        let objects = [object(
            "a",
            vec![
                code("_main").reloc(0, X86Pc32, "_helper", -4),
                code("_helper").reloc(0, X86Pc32, "_nowhere", -4),
                code("_dead").reloc(0, X86Pc32, "_missing", -4),
            ],
            vec![],
        )];
        assert_eq!(
            resolve(&objects, "_main").err(),
            Some(LinkError::Undefined { name: "_nowhere".to_string(), referenced_from: "_helper".to_string() })
        );
        assert_eq!(
            resolve(&objects, "_start").err(),
            Some(LinkError::Undefined { name: "_start".to_string(), referenced_from: "(entry point)".to_string() })
        );
        let dead_only = [object("a", vec![code("_main"), code("_dead").reloc(0, X86Pc32, "_missing", -4)], vec![])];
        assert!(resolve(&dead_only, "_main").is_ok());
    }

    #[test]
    fn malformed_atoms_are_rejected() {
        let malformed = |atom: Atom| {
            matches!(resolve(&[object("a", vec![code("_main"), atom], vec![])], "_main"), Err(LinkError::Malformed(_)))
        };
        assert!(malformed(Atom { align: 3, ..code("_x") }));
        assert!(malformed(Atom { size: 17, ..code("_x") }));
        assert!(malformed(Atom { labels: vec![("_end".to_string(), 17)], ..code("_x") }));
        assert!(malformed(code("_x").reloc(13, X86Pc32, "_main", 0)));
        assert!(malformed(code("_x").reloc(9, Abs64, "_main", 0)));
        assert!(malformed(code("_x").reloc(0, Arm64PageOff12 { scale: 5 }, "_main", 0)));
        assert!(malformed(Atom { relocs: code("_y").reloc(0, Abs64, "_main", 0).relocs, ..Atom::bss("_x", 8, 8) }));
        assert!(!malformed(Atom { labels: vec![("_end".to_string(), 16)], ..code("_x") }));
        assert!(!malformed(code("_x").reloc(12, X86Pc32, "_main", 0)));
    }
}
