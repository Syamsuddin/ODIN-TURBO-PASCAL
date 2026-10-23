// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Builds the `.odbg` description of a linked program.

use std::collections::BTreeMap;

use odin_base::{FileId, SourceMap};
use odin_debuginfo::{DebugInfo, FieldInfo, GlobalInfo, LocalInfo, LocalKind, RoutineInfo, TypeInfo, TypeKind};
use odin_ir::{LocalKind as IrLocal, Program, Type, TypeId, rtl};

pub fn describe(
    map: &SourceMap,
    program: &Program,
    out: &odin_codegen::Output,
    symbols: &BTreeMap<String, u64>,
    image_base: u64,
) -> DebugInfo {
    let files = (0..map.len()).map(|i| map.file(FileId(i as u32)).path.to_string_lossy().into_owned()).collect();
    let line_of = |span: odin_base::Span| -> (u32, u32) {
        if (span.file.0 as usize) < map.len() { (span.file.0, map.location(span).line) } else { (0, 0) }
    };
    let lines = out.debug_points.iter().map(|&s| line_of(s)).collect();
    let mut addresses: Vec<(u64, u32, u32)> = out
        .lines
        .iter()
        .filter_map(|e| {
            let base = symbols.get(&e.symbol)?;
            let (file, line) = line_of(e.span);
            Some((base + e.offset as u64, file, line))
        })
        .collect();
    addresses.sort();
    addresses.dedup_by_key(|e| e.0);
    let routines = program
        .routines
        .iter()
        .enumerate()
        .map(|(i, r)| {
            let (file, line) = line_of(r.span);
            let slots = &out.frames[i];
            let locals = r
                .locals
                .iter()
                .zip(slots)
                .map(|(l, slot)| LocalInfo {
                    name: l.name.clone(),
                    ty: l.ty.0,
                    kind: match l.kind {
                        IrLocal::Param(_) => LocalKind::Param,
                        IrLocal::OpenHigh(p) => LocalKind::High(p),
                        IrLocal::Result => LocalKind::Result,
                        IrLocal::Var => LocalKind::Var,
                        IrLocal::Temp => LocalKind::Temp,
                    },
                    offset: slot.offset,
                    indirect: slot.indirect,
                })
                .collect();
            RoutineInfo {
                name: r.display.clone(),
                symbol: r.symbol.clone(),
                parent: r.parent.map(|p| p.0),
                file,
                line,
                instrumented: out.instrumented[i],
                // The codegen keeps the static link at [rbp - 8].
                static_link: r.parent.map(|_| -8),
                locals,
            }
        })
        .collect();
    let globals = program
        .globals
        .iter()
        .filter(|g| !g.name.starts_with('$'))
        .filter_map(|g| {
            let address = *symbols.get(&g.symbol)?;
            let scope = g.symbol.rsplit_once('.').map(|(s, _)| s.to_string()).unwrap_or_default();
            Some(GlobalInfo { name: g.name.clone(), scope, ty: g.ty.0, address })
        })
        .collect();
    let t = &program.types;
    let types = (0..t.len())
        .map(|i| {
            let id = TypeId(i as u32);
            let kind = match t.get(id) {
                Type::Int(k) => TypeKind::Int { signed: k.signed },
                Type::Bool => TypeKind::Bool,
                Type::Char => TypeKind::Char,
                Type::Enum { names } => TypeKind::Enum { names: names.clone() },
                Type::Subrange { base, lo, hi } => TypeKind::Subrange { base: base.0, lo: *lo, hi: *hi },
                Type::Real(_) => TypeKind::Real,
                Type::ShortString(max) => TypeKind::String { max: *max },
                Type::Pointer(target) => TypeKind::Pointer { target: target.map(|t| t.0) },
                Type::Array { index, lo, hi, elem } => {
                    TypeKind::Array { index: index.0, lo: *lo, hi: *hi, elem: elem.0 }
                }
                Type::OpenArray { elem } => TypeKind::OpenArray { elem: elem.0 },
                Type::OpenString => TypeKind::OpenString,
                Type::Record { fields, .. } => TypeKind::Record {
                    fields: fields
                        .iter()
                        .map(|f| FieldInfo { name: f.name.clone(), ty: f.ty.0, offset: f.offset })
                        .collect(),
                },
                // The debugger shows an object like a record of its fields
                // (inherited ones first); the VMT pointer stays hidden.
                Type::Object(o) => TypeKind::Record {
                    fields: o
                        .fields
                        .iter()
                        .map(|f| FieldInfo { name: f.name.clone(), ty: f.ty.0, offset: f.offset })
                        .collect(),
                },
                // A class refers to its instance; a class reference is a
                // VMT address.
                Type::Class(instance) => TypeKind::Class { instance: instance.0 },
                Type::ClassRef(_) => TypeKind::Pointer { target: None },
                Type::Set { base, first_byte, .. } => TypeKind::Set { base: base.0, first_byte: *first_byte },
                Type::File { elem, .. } => TypeKind::File { elem: elem.map(|e| e.0) },
                Type::Procedural(_) => TypeKind::Procedural,
                Type::Nil => TypeKind::Nil,
                Type::Untyped => TypeKind::Untyped,
            };
            TypeInfo { name: t.name(id).map(str::to_string), size: t.size(id), kind }
        })
        .collect();
    DebugInfo {
        files,
        image_base,
        anchor: symbols.get(rtl::DBG_LINE).copied().unwrap_or(0),
        stack: symbols.get(rtl::DBG_STACK).copied().unwrap_or(0),
        lines,
        addresses,
        routines,
        globals,
        types,
    }
}
