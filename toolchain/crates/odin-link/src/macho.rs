// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Mach-O executable writer for x86_64 and arm64 Darwin.
//!
//! The output is a position-independent `MH_EXECUTE` laid out like this:
//!
//! ```text
//! __PAGEZERO   4 GiB, no access
//! __TEXT       r-x  header, load commands, __text (Text), __const (ReadOnly)
//! __DATA       rw-  __got, __const (ReadOnly with absolute pointers),
//!                   __data (Data), __bss (Bss, zero-fill)
//! __LINKEDIT   r--  rebase and bind opcodes, export trie, symbol table,
//!                   indirect symbols, string table, code signature
//! ```
//!
//! Imports are reached through `__got` slots that dyld binds from the
//! classic `LC_DYLD_INFO_ONLY` opcodes; every absolute pointer gets a rebase
//! so ASLR can slide the image. File offsets equal address offsets from the
//! header up to the end of the file-backed part of `__DATA`.

use std::collections::{BTreeMap, HashMap};

use odin_asm::object::{Atom, RelocKind, SectionKind};
use odin_base::sha256::sha256;

use crate::codesign;
use crate::leb::{sleb128, uleb128};
use crate::reloc;
use crate::resolve::{Resolved, Sym};
use crate::trie::export_trie;
use crate::{LinkError, LinkOptions, LinkedImage, Target};

/// Unslid address of the Mach-O header. Everything below is `__PAGEZERO`.
pub(crate) const IMAGE_BASE: u64 = 0x1_0000_0000;
const DYLD: &str = "/usr/lib/dyld";
/// Always loaded first (ordinal 1): dyld refuses programs without it.
const LIBSYSTEM: &str = "/usr/lib/libSystem.B.dylib";
const MH_EXECUTE_HEADER: &str = "__mh_execute_header";

const MH_MAGIC_64: u32 = 0xfeed_facf;
const CPU_TYPE_X86_64: u32 = 0x0100_0007;
const CPU_TYPE_ARM64: u32 = 0x0100_000c;
const CPU_SUBTYPE_X86_64_ALL: u32 = 3;
const CPU_SUBTYPE_ARM64_ALL: u32 = 0;
const MH_EXECUTE: u32 = 2;
const MH_NOUNDEFS: u32 = 0x1;
const MH_DYLDLINK: u32 = 0x4;
const MH_TWOLEVEL: u32 = 0x80;
const MH_PIE: u32 = 0x20_0000;
const HEADER_SIZE: u64 = 32;

const LC_SYMTAB: u32 = 0x2;
const LC_DYSYMTAB: u32 = 0xb;
const LC_LOAD_DYLIB: u32 = 0xc;
const LC_LOAD_DYLINKER: u32 = 0xe;
const LC_SEGMENT_64: u32 = 0x19;
const LC_UUID: u32 = 0x1b;
const LC_CODE_SIGNATURE: u32 = 0x1d;
const LC_BUILD_VERSION: u32 = 0x32;
const LC_DYLD_INFO_ONLY: u32 = 0x8000_0022;
const LC_MAIN: u32 = 0x8000_0028;

const SEGMENT_SIZE: u64 = 72;
const SECTION_SIZE: u64 = 80;
const DYLD_INFO_SIZE: u64 = 48;
const SYMTAB_SIZE: u64 = 24;
const DYSYMTAB_SIZE: u64 = 80;
const UUID_SIZE: u64 = 24;
const BUILD_VERSION_SIZE: u64 = 24;
const MAIN_SIZE: u64 = 24;
const LINKEDIT_DATA_SIZE: u64 = 16;

const VM_PROT_READ: u32 = 1;
const VM_PROT_WRITE: u32 = 2;
const VM_PROT_EXECUTE: u32 = 4;

const S_ZEROFILL: u32 = 0x1;
const S_NON_LAZY_SYMBOL_POINTERS: u32 = 0x6;
const S_ATTR_PURE_INSTRUCTIONS: u32 = 0x8000_0000;
const S_ATTR_SOME_INSTRUCTIONS: u32 = 0x400;

const N_EXT: u8 = 0x1;
const N_SECT: u8 = 0xe;
const REFERENCED_DYNAMICALLY: u16 = 0x10;
const INDIRECT_SYMBOL_LOCAL: u32 = 0x8000_0000;
const PLATFORM_MACOS: u32 = 1;

const REBASE_TYPE_POINTER: u8 = 1;
const REBASE_OPCODE_DONE: u8 = 0x00;
const REBASE_OPCODE_SET_TYPE_IMM: u8 = 0x10;
const REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: u8 = 0x20;
const REBASE_OPCODE_ADD_ADDR_ULEB: u8 = 0x30;
const REBASE_OPCODE_DO_REBASE_IMM_TIMES: u8 = 0x50;
const REBASE_OPCODE_DO_REBASE_ULEB_TIMES: u8 = 0x60;

const BIND_TYPE_POINTER: u8 = 1;
const BIND_OPCODE_DONE: u8 = 0x00;
const BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: u8 = 0x10;
const BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: u8 = 0x20;
const BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: u8 = 0x40;
const BIND_OPCODE_SET_TYPE_IMM: u8 = 0x50;
const BIND_OPCODE_SET_ADDEND_SLEB: u8 = 0x60;
const BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: u8 = 0x70;
const BIND_OPCODE_DO_BIND: u8 = 0x90;

/// Per-architecture parameters.
struct Arch {
    cpu_type: u32,
    cpu_subtype: u32,
    /// Page size the segments are aligned to.
    segment_align: u64,
    /// Minimum alignment of `__text`.
    text_align: u64,
    /// Minimum alignment of each code atom.
    code_atom_align: u64,
    /// Padding between code atoms: `int3` on x86-64, `udf #0` on arm64.
    text_fill: u8,
    arm64: bool,
}

impl Arch {
    fn of(target: Target) -> Arch {
        if target.is_arm64() {
            Arch {
                cpu_type: CPU_TYPE_ARM64,
                cpu_subtype: CPU_SUBTYPE_ARM64_ALL,
                segment_align: 0x4000,
                text_align: 4,
                code_atom_align: 4,
                text_fill: 0,
                arm64: true,
            }
        } else {
            Arch {
                cpu_type: CPU_TYPE_X86_64,
                cpu_subtype: CPU_SUBTYPE_X86_64_ALL,
                segment_align: 0x1000,
                text_align: 16,
                code_atom_align: 1,
                text_fill: 0xcc,
                arm64: false,
            }
        }
    }
}

/// Output sections, in file and load-command order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Out {
    Text,
    Const,
    Got,
    DataConst,
    Data,
    Bss,
}

impl Out {
    const ALL: [Out; 6] = [Out::Text, Out::Const, Out::Got, Out::DataConst, Out::Data, Out::Bss];

    fn in_text_segment(self) -> bool {
        matches!(self, Out::Text | Out::Const)
    }

    /// Section and segment name.
    fn names(self) -> (&'static str, &'static str) {
        match self {
            Out::Text => ("__text", "__TEXT"),
            Out::Const => ("__const", "__TEXT"),
            Out::Got => ("__got", "__DATA"),
            Out::DataConst => ("__const", "__DATA"),
            Out::Data => ("__data", "__DATA"),
            Out::Bss => ("__bss", "__DATA"),
        }
    }

    fn flags(self) -> u32 {
        match self {
            Out::Text => S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS,
            Out::Got => S_NON_LAZY_SYMBOL_POINTERS,
            Out::Bss => S_ZEROFILL,
            Out::Const | Out::DataConst | Out::Data => 0,
        }
    }

    /// Where an atom goes. Read-only data holding absolute pointers needs
    /// rebasing, which dyld can only do in a writable segment.
    fn of(atom: &Atom) -> Out {
        match atom.section {
            SectionKind::Text => Out::Text,
            SectionKind::ReadOnly if atom.relocs.iter().any(|r| r.kind == RelocKind::Abs64) => Out::DataConst,
            SectionKind::ReadOnly => Out::Const,
            SectionKind::Data => Out::Data,
            SectionKind::Bss => Out::Bss,
        }
    }
}

/// A placed output section.
struct Section {
    out: Out,
    addr: u64,
    size: u64,
    align: u64,
}

/// A placed segment. `sections` indexes [`Section`]s.
struct Segment {
    name: &'static str,
    vmaddr: u64,
    vmsize: u64,
    fileoff: u64,
    filesize: u64,
    prot: u32,
    sections: std::ops::Range<usize>,
}

/// A pointer dyld fills with an imported symbol's address plus `addend`.
struct Bind {
    addr: u64,
    import: usize,
    addend: i64,
}

/// One `nlist_64` entry before string table offsets are known.
struct Symbol<'a> {
    name: &'a str,
    n_type: u8,
    n_sect: u8,
    n_desc: u16,
    value: u64,
}

pub(crate) fn write(resolved: &Resolved, options: &LinkOptions) -> Result<LinkedImage, LinkError> {
    let arch = Arch::of(options.target);
    check(resolved, options, &arch)?;

    // Sort live atoms into output sections, keeping input order.
    let mut members: [Vec<usize>; 6] = Default::default();
    for index in resolved.live_atoms() {
        members[Out::of(resolved.atoms[index]) as usize].push(index);
    }

    // One GOT slot per distinct target of a GOT relocation. Imports are
    // bound by dyld; local targets (allowed, if unusual) are rebased.
    let mut got: Vec<&str> = Vec::new();
    let mut got_slot: HashMap<&str, u64> = HashMap::new();
    for index in resolved.live_atoms() {
        for reloc in &resolved.atoms[index].relocs {
            if reloc::uses_got(reloc.kind) && !got_slot.contains_key(reloc.target.as_str()) {
                got_slot.insert(&reloc.target, got.len() as u64);
                got.push(&reloc.target);
            }
        }
    }

    let mut dylibs: Vec<&str> = vec![LIBSYSTEM];
    for import in &resolved.imports {
        if !dylibs.contains(&import.library.as_str()) {
            dylibs.push(&import.library);
        }
    }
    let ordinal =
        |import: usize| dylibs.iter().position(|&d| d == resolved.imports[import].library).unwrap() as u64 + 1;

    let present: Vec<Out> = Out::ALL
        .into_iter()
        .filter(|&out| if out == Out::Got { !got.is_empty() } else { !members[out as usize].is_empty() })
        .collect();
    let text_sections = present.iter().filter(|o| o.in_text_segment()).count();
    let data_sections = present.len() - text_sections;

    // Load commands, sized before layout: their size depends only on counts.
    let dylinker_size = load_string_size(12, DYLD);
    let dylib_sizes: Vec<u64> = dylibs.iter().map(|d| load_string_size(24, d)).collect();
    let mut sizeofcmds = SEGMENT_SIZE // __PAGEZERO
        + SEGMENT_SIZE + SECTION_SIZE * text_sections as u64
        + SEGMENT_SIZE // __LINKEDIT
        + DYLD_INFO_SIZE + SYMTAB_SIZE + DYSYMTAB_SIZE + dylinker_size + UUID_SIZE + BUILD_VERSION_SIZE + MAIN_SIZE
        + dylib_sizes.iter().sum::<u64>()
        + LINKEDIT_DATA_SIZE;
    let mut ncmds = 11 + dylibs.len() as u32;
    if data_sections > 0 {
        sizeofcmds += SEGMENT_SIZE + SECTION_SIZE * data_sections as u64;
        ncmds += 1;
    }

    // Addresses. `addr - IMAGE_BASE` is also the file offset of everything
    // except `__bss`.
    let mut atom_addr = vec![0u64; resolved.atoms.len()];
    let mut atom_sect = vec![0u8; resolved.atoms.len()];
    let mut sections: Vec<Section> = Vec::new();
    let mut cursor = IMAGE_BASE + HEADER_SIZE + sizeofcmds;
    let mut segments: Vec<Segment> = Vec::new();
    let mut data_file_end = 0;
    for (i, &out) in present.iter().enumerate() {
        if i == text_sections {
            // __DATA starts on a fresh page after __TEXT.
            cursor = cursor.next_multiple_of(arch.segment_align);
        }
        if out == Out::Bss {
            data_file_end = cursor;
        }
        let min_align = match out {
            Out::Text => arch.text_align,
            Out::Got => 8,
            _ => 1,
        };
        let (addr, end, align) = if out == Out::Got {
            let addr = cursor.next_multiple_of(8);
            (addr, addr + 8 * got.len() as u64, 8)
        } else {
            let atoms = &members[out as usize];
            let atom_align = if out == Out::Text { arch.code_atom_align } else { 1 };
            let sizes =
                atoms.iter().map(|&a| (u64::from(resolved.atoms[a].align).max(atom_align), resolved.atoms[a].size));
            let (addr, addrs, end, align) = place(cursor, sizes, min_align);
            for (&atom, atom_address) in atoms.iter().zip(addrs) {
                atom_addr[atom] = atom_address;
                atom_sect[atom] = (sections.len() + 1) as u8;
            }
            (addr, end, align)
        };
        sections.push(Section { out, addr, size: end - addr, align });
        cursor = end;
        if i + 1 == text_sections {
            let vmsize = (cursor - IMAGE_BASE).next_multiple_of(arch.segment_align);
            segments.push(Segment {
                name: "__TEXT",
                vmaddr: IMAGE_BASE,
                vmsize,
                fileoff: 0,
                filesize: vmsize,
                prot: VM_PROT_READ | VM_PROT_EXECUTE,
                sections: 0..i + 1,
            });
        }
    }
    let text = &segments[0];
    let text_filesize = text.filesize;
    let mut linkedit_addr = IMAGE_BASE + text.vmsize;
    let mut linkedit_off = text.filesize;
    if data_sections > 0 {
        if !present.contains(&Out::Bss) {
            data_file_end = cursor;
        }
        let vmaddr = IMAGE_BASE + text_filesize;
        let vmsize = (cursor - vmaddr).next_multiple_of(arch.segment_align);
        let filesize = (data_file_end - vmaddr).next_multiple_of(arch.segment_align);
        segments.push(Segment {
            name: "__DATA",
            vmaddr,
            vmsize,
            fileoff: text_filesize,
            filesize,
            prot: VM_PROT_READ | VM_PROT_WRITE,
            sections: text_sections..present.len(),
        });
        linkedit_addr = vmaddr + vmsize;
        linkedit_off = text_filesize + filesize;
    }
    let data_segment_index = 2u8; // __PAGEZERO, __TEXT, __DATA
    let data_vmaddr = IMAGE_BASE + text_filesize;
    let got_addr = sections.iter().find(|s| s.out == Out::Got).map_or(0, |s| s.addr);

    // Section contents.
    let mut image = vec![0u8; linkedit_off as usize];
    if arch.text_fill != 0 {
        let text = &sections[0];
        let start = (text.addr - IMAGE_BASE) as usize;
        image[start..start + text.size as usize].fill(arch.text_fill);
    }
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        if atom.section != SectionKind::Bss {
            let at = (atom_addr[index] - IMAGE_BASE) as usize;
            image[at..at + atom.bytes.len()].copy_from_slice(&atom.bytes);
        }
    }

    // Relocations.
    let address_of = |sym: Sym| match sym {
        Sym::Local { atom, offset } => Some(atom_addr[atom] + offset),
        Sym::Import(_) => None,
    };
    let mut rebases: Vec<u64> = Vec::new();
    let mut binds: Vec<Bind> = Vec::new();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        for reloc in &atom.relocs {
            let place = atom_addr[index] + u64::from(reloc.offset);
            let field = &mut image[(place - IMAGE_BASE) as usize..];
            let sym = resolved.lookup(&reloc.target).expect("live relocation targets resolve");
            let target = if reloc::uses_got(reloc.kind) {
                got_addr + 8 * got_slot[reloc.target.as_str()]
            } else if let Some(address) = address_of(sym) {
                address
            } else {
                // Abs64 to an import (checked): dyld writes the whole value.
                let Sym::Import(import) = sym else { unreachable!() };
                binds.push(Bind { addr: place, import, addend: reloc.addend });
                field[..8].fill(0);
                continue;
            };
            reloc::patch(reloc.kind, field, place, target, reloc.addend)
                .map_err(|_| LinkError::RelocOutOfRange { atom: atom.name.clone(), target: reloc.target.clone() })?;
            if reloc.kind == RelocKind::Abs64 {
                rebases.push(place);
            }
        }
    }
    for (slot, name) in got.iter().enumerate() {
        let addr = got_addr + 8 * slot as u64;
        let sym = resolved.lookup(name).expect("GOT targets resolve");
        match address_of(sym) {
            Some(value) => {
                let at = (addr - IMAGE_BASE) as usize;
                image[at..at + 8].copy_from_slice(&value.to_le_bytes());
                rebases.push(addr);
            }
            None => {
                let Sym::Import(import) = sym else { unreachable!() };
                binds.push(Bind { addr, import, addend: 0 });
            }
        }
    }

    // __LINKEDIT contents.
    let rebase_info = rebase_opcodes(data_segment_index, data_vmaddr, &mut rebases);
    binds.sort_by_key(|b| b.addr);
    let bind_info =
        bind_opcodes(data_segment_index, data_vmaddr, &binds, |i| (ordinal(i), resolved.imports[i].name.as_str()));
    let Sym::Local { atom: entry_atom, offset: entry_offset } = resolved.entry else {
        unreachable!("the entry is defined")
    };
    let entry_addr = atom_addr[entry_atom] + entry_offset;
    let exports = export_trie(&[(MH_EXECUTE_HEADER, 0), (&options.entry, entry_addr - IMAGE_BASE)]);

    let mut locals: Vec<Symbol> = Vec::new();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        let names = std::iter::once((atom.name.as_str(), 0)).chain(atom.labels.iter().map(|(n, o)| (n.as_str(), *o)));
        for (name, offset) in names {
            if name != options.entry {
                locals.push(Symbol {
                    name,
                    n_type: N_SECT,
                    n_sect: atom_sect[index],
                    n_desc: 0,
                    value: atom_addr[index] + offset,
                });
            }
        }
    }
    locals.sort_by(|a, b| (a.value, a.name).cmp(&(b.value, b.name)));
    let mut extdefs = vec![
        Symbol {
            name: MH_EXECUTE_HEADER,
            n_type: N_SECT | N_EXT,
            n_sect: 1,
            n_desc: REFERENCED_DYNAMICALLY,
            value: IMAGE_BASE,
        },
        Symbol {
            name: &options.entry,
            n_type: N_SECT | N_EXT,
            n_sect: atom_sect[entry_atom],
            n_desc: 0,
            value: entry_addr,
        },
    ];
    extdefs.sort_by_key(|s| s.name);
    let mut undefs: Vec<(usize, Symbol)> = (0..resolved.imports.len())
        .map(|i| {
            (
                i,
                Symbol {
                    name: &resolved.imports[i].name,
                    n_type: N_EXT,
                    n_sect: 0,
                    n_desc: (ordinal(i) << 8) as u16,
                    value: 0,
                },
            )
        })
        .collect();
    undefs.sort_by_key(|(_, s)| s.name);
    let first_undef = locals.len() + extdefs.len();
    let mut import_symbol = vec![0u32; resolved.imports.len()];
    for (position, (import, _)) in undefs.iter().enumerate() {
        import_symbol[*import] = (first_undef + position) as u32;
    }

    let mut strtab = b" \0".to_vec();
    let mut symtab = Vec::new();
    let all_symbols = locals.iter().chain(&extdefs).chain(undefs.iter().map(|(_, s)| s));
    for symbol in all_symbols {
        put32(&mut symtab, strtab.len() as u32);
        symtab.push(symbol.n_type);
        symtab.push(symbol.n_sect);
        put16(&mut symtab, symbol.n_desc);
        put64(&mut symtab, symbol.value);
        strtab.extend_from_slice(symbol.name.as_bytes());
        strtab.push(0);
    }
    let nsyms = (first_undef + undefs.len()) as u32;
    strtab.resize(strtab.len().next_multiple_of(8), 0);
    let mut indirect = Vec::new();
    for name in &got {
        match resolved.lookup(name) {
            Some(Sym::Import(import)) => put32(&mut indirect, import_symbol[import]),
            _ => put32(&mut indirect, INDIRECT_SYMBOL_LOCAL),
        }
    }
    let nindirect = got.len() as u32;
    indirect.resize(indirect.len().next_multiple_of(8), 0);

    let mut linkedit = Vec::new();
    let mut append = |blob: &[u8]| -> (u64, u64) {
        if blob.is_empty() {
            return (0, 0);
        }
        let offset = linkedit_off + linkedit.len() as u64;
        linkedit.extend_from_slice(blob);
        (offset, blob.len() as u64)
    };
    let rebase_range = append(&rebase_info);
    let bind_range = append(&bind_info);
    let export_range = append(&exports);
    let symtab_range = append(&symtab);
    let indirect_range = append(&indirect);
    let strtab_range = append(&strtab);
    let signature_off = (linkedit_off + linkedit.len() as u64).next_multiple_of(16);
    let signature_size =
        (codesign::signature_size(&options.identifier, signature_off as usize) as u64).next_multiple_of(16);
    let file_size = signature_off + signature_size;
    if file_size > u64::from(u32::MAX) {
        return Err(LinkError::Unsupported(format!(
            "the executable would be {file_size} bytes; Mach-O offsets stop at 4 GiB"
        )));
    }
    let linkedit_filesize = file_size - linkedit_off;
    segments.push(Segment {
        name: "__LINKEDIT",
        vmaddr: linkedit_addr,
        vmsize: linkedit_filesize.next_multiple_of(arch.segment_align),
        fileoff: linkedit_off,
        filesize: linkedit_filesize,
        prot: VM_PROT_READ,
        sections: 0..0,
    });

    // Header and load commands.
    let mut head = Vec::with_capacity((HEADER_SIZE + sizeofcmds) as usize);
    put32(&mut head, MH_MAGIC_64);
    put32(&mut head, arch.cpu_type);
    put32(&mut head, arch.cpu_subtype);
    put32(&mut head, MH_EXECUTE);
    put32(&mut head, ncmds);
    put32(&mut head, sizeofcmds as u32);
    put32(&mut head, MH_NOUNDEFS | MH_DYLDLINK | MH_TWOLEVEL | MH_PIE);
    put32(&mut head, 0);

    let pagezero =
        Segment { name: "__PAGEZERO", vmaddr: 0, vmsize: IMAGE_BASE, fileoff: 0, filesize: 0, prot: 0, sections: 0..0 };
    for segment in std::iter::once(&pagezero).chain(&segments) {
        segment_command(&mut head, segment, &sections[segment.sections.clone()]);
    }

    put32(&mut head, LC_DYLD_INFO_ONLY);
    put32(&mut head, DYLD_INFO_SIZE as u32);
    for (offset, size) in [rebase_range, bind_range, (0, 0), (0, 0), export_range] {
        put32(&mut head, offset as u32);
        put32(&mut head, size as u32);
    }

    put32(&mut head, LC_SYMTAB);
    put32(&mut head, SYMTAB_SIZE as u32);
    put32(&mut head, symtab_range.0 as u32);
    put32(&mut head, nsyms);
    put32(&mut head, strtab_range.0 as u32);
    put32(&mut head, strtab_range.1 as u32);

    put32(&mut head, LC_DYSYMTAB);
    put32(&mut head, DYSYMTAB_SIZE as u32);
    for value in [0, locals.len(), locals.len(), extdefs.len(), first_undef, undefs.len()] {
        put32(&mut head, value as u32); // ilocalsym, nlocalsym, iextdefsym, nextdefsym, iundefsym, nundefsym
    }
    for _ in 0..6 {
        put32(&mut head, 0); // tocoff, ntoc, modtaboff, nmodtab, extrefsymoff, nextrefsyms
    }
    put32(&mut head, indirect_range.0 as u32);
    put32(&mut head, nindirect);
    for _ in 0..4 {
        put32(&mut head, 0); // extreloff, nextrel, locreloff, nlocrel
    }

    put32(&mut head, LC_LOAD_DYLINKER);
    put_load_string(&mut head, dylinker_size, 12, DYLD);

    put32(&mut head, LC_UUID);
    put32(&mut head, UUID_SIZE as u32);
    let uuid_at = head.len();
    head.extend_from_slice(&[0; 16]);

    let version =
        |(major, minor, patch): (u16, u8, u8)| (u32::from(major) << 16) | (u32::from(minor) << 8) | u32::from(patch);
    put32(&mut head, LC_BUILD_VERSION);
    put32(&mut head, BUILD_VERSION_SIZE as u32);
    put32(&mut head, PLATFORM_MACOS);
    put32(&mut head, version(options.min_os)); // minos
    put32(&mut head, version(options.min_os)); // sdk: no SDK is involved
    put32(&mut head, 0); // ntools

    put32(&mut head, LC_MAIN);
    put32(&mut head, MAIN_SIZE as u32);
    put64(&mut head, entry_addr - IMAGE_BASE);
    put64(&mut head, 0); // stacksize: default

    for (dylib, &size) in dylibs.iter().zip(&dylib_sizes) {
        put32(&mut head, LC_LOAD_DYLIB);
        put32(&mut head, size as u32);
        put32(&mut head, 24); // name offset
        put32(&mut head, 2); // timestamp
        put32(&mut head, 0x1_0000); // current version 1.0.0
        put32(&mut head, 0x1_0000); // compatibility version 1.0.0
        let name_start = head.len();
        head.extend_from_slice(dylib.as_bytes());
        head.resize(name_start + size as usize - 24, 0);
    }

    put32(&mut head, LC_CODE_SIGNATURE);
    put32(&mut head, LINKEDIT_DATA_SIZE as u32);
    put32(&mut head, signature_off as u32);
    put32(&mut head, signature_size as u32);
    debug_assert_eq!(head.len() as u64, HEADER_SIZE + sizeofcmds);
    image[..head.len()].copy_from_slice(&head);

    // Assemble the file; the UUID hashes everything before the signature,
    // and the signature hashes everything including the UUID.
    image.extend_from_slice(&linkedit);
    image.resize(file_size as usize, 0);
    let digest = sha256(&image[..signature_off as usize]);
    let mut uuid: [u8; 16] = digest[..16].try_into().unwrap();
    uuid[6] = (uuid[6] & 0x0f) | 0x80; // RFC 9562 version 8 (custom)
    uuid[8] = (uuid[8] & 0x3f) | 0x80; // RFC 4122 variant
    image[uuid_at..uuid_at + 16].copy_from_slice(&uuid);
    codesign::sign(&mut image, signature_off as usize, &options.identifier, (0, text_filesize));

    let mut symbols = BTreeMap::new();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        symbols.insert(atom.name.clone(), atom_addr[index]);
        for (label, offset) in &atom.labels {
            symbols.insert(label.clone(), atom_addr[index] + offset);
        }
    }
    Ok(LinkedImage { bytes: image, image_base: IMAGE_BASE, symbols })
}

/// Rejects input this writer cannot express.
fn check(resolved: &Resolved, options: &LinkOptions, arch: &Arch) -> Result<(), LinkError> {
    if options.identifier.is_empty() || options.identifier.contains('\0') {
        return Err(LinkError::Malformed(
            "the code-signing identifier must be non-empty and free of NUL bytes".to_string(),
        ));
    }
    if resolved.defines(MH_EXECUTE_HEADER) {
        return Err(LinkError::Duplicate { name: MH_EXECUTE_HEADER.to_string() });
    }
    let Sym::Local { atom: entry, .. } = resolved.entry else { unreachable!("the entry is defined") };
    if resolved.atoms[entry].section != SectionKind::Text {
        return Err(LinkError::Unsupported(format!("entry symbol `{}` is not in a code atom", options.entry)));
    }
    let triple = options.target.triple();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        if u64::from(atom.align) > arch.segment_align {
            return Err(LinkError::Unsupported(format!(
                "atom `{}` asks for {}-byte alignment, more than a {triple} page",
                atom.name, atom.align
            )));
        }
        for reloc in &atom.relocs {
            let kind = reloc.kind;
            if (arch.arm64 && reloc::is_x86(kind)) || (!arch.arm64 && reloc::is_arm64(kind)) {
                return Err(LinkError::Unsupported(format!(
                    "`{}` has a {kind:?} relocation, which does not exist on {triple}",
                    atom.name
                )));
            }
            if kind == RelocKind::Abs64 && atom.section == SectionKind::Text {
                return Err(LinkError::Unsupported(format!(
                    "`{}` stores the absolute address of `{}` in code, which would need a text relocation",
                    atom.name, reloc.target
                )));
            }
            if !reloc::uses_got(kind)
                && kind != RelocKind::Abs64
                && let Some(Sym::Import(_)) = resolved.lookup(&reloc.target)
            {
                return Err(LinkError::Unsupported(format!(
                    "`{}` refers to imported `{}` with {kind:?}; imports are reached through their GOT slot \
                     (X86GotPc32, or Arm64GotPage21 with Arm64GotPageOff12)",
                    atom.name, reloc.target
                )));
            }
        }
    }
    Ok(())
}

/// Places atoms given as `(align, size)` one after another from `cursor`.
/// Returns the section start (aligned to the largest alignment, at least
/// `min_align`), each atom's address, the end and the section alignment.
fn place(cursor: u64, atoms: impl Iterator<Item = (u64, u64)>, min_align: u64) -> (u64, Vec<u64>, u64, u64) {
    let atoms: Vec<(u64, u64)> = atoms.collect();
    let align = atoms.iter().map(|&(align, _)| align).fold(min_align, u64::max);
    let start = cursor.next_multiple_of(align);
    let mut at = start;
    let mut addrs = Vec::with_capacity(atoms.len());
    for (align, size) in atoms {
        at = at.next_multiple_of(align);
        addrs.push(at);
        at += size;
    }
    (start, addrs, at, align)
}

/// Rebase opcodes sliding every pointer at `addrs` (all in segment
/// `segment`, which starts at `segment_addr`), padded to 8 bytes; empty
/// when there is nothing to rebase.
fn rebase_opcodes(segment: u8, segment_addr: u64, addrs: &mut [u64]) -> Vec<u8> {
    let mut out = Vec::new();
    if addrs.is_empty() {
        return out;
    }
    addrs.sort_unstable();
    out.push(REBASE_OPCODE_SET_TYPE_IMM | REBASE_TYPE_POINTER);
    let mut next: Option<u64> = None;
    let mut i = 0;
    while i < addrs.len() {
        let start = addrs[i];
        let mut run = 1;
        while i + run < addrs.len() && addrs[i + run] == start + 8 * run as u64 {
            run += 1;
        }
        match next {
            Some(at) if start == at => {}
            Some(at) if start > at => {
                out.push(REBASE_OPCODE_ADD_ADDR_ULEB);
                uleb128(&mut out, start - at);
            }
            _ => {
                out.push(REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB | segment);
                uleb128(&mut out, start - segment_addr);
            }
        }
        if run < 16 {
            out.push(REBASE_OPCODE_DO_REBASE_IMM_TIMES | run as u8);
        } else {
            out.push(REBASE_OPCODE_DO_REBASE_ULEB_TIMES);
            uleb128(&mut out, run as u64);
        }
        next = Some(start + 8 * run as u64);
        i += run;
    }
    out.push(REBASE_OPCODE_DONE);
    out.resize(out.len().next_multiple_of(8), REBASE_OPCODE_DONE);
    out
}

/// Bind opcodes for `binds` (sorted by address, all in segment `segment`);
/// `import` maps an import index to its dylib ordinal and symbol name.
fn bind_opcodes<'a>(
    segment: u8,
    segment_addr: u64,
    binds: &[Bind],
    import: impl Fn(usize) -> (u64, &'a str),
) -> Vec<u8> {
    let mut out = Vec::new();
    if binds.is_empty() {
        return out;
    }
    out.push(BIND_OPCODE_SET_TYPE_IMM | BIND_TYPE_POINTER);
    let (mut ordinal, mut symbol, mut addend) = (None, None, 0);
    for bind in binds {
        let (lib, name) = import(bind.import);
        if ordinal != Some(lib) {
            if lib < 16 {
                out.push(BIND_OPCODE_SET_DYLIB_ORDINAL_IMM | lib as u8);
            } else {
                out.push(BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB);
                uleb128(&mut out, lib);
            }
            ordinal = Some(lib);
        }
        if symbol != Some(bind.import) {
            out.push(BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM);
            out.extend_from_slice(name.as_bytes());
            out.push(0);
            symbol = Some(bind.import);
        }
        if addend != bind.addend {
            out.push(BIND_OPCODE_SET_ADDEND_SLEB);
            sleb128(&mut out, bind.addend);
            addend = bind.addend;
        }
        out.push(BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB | segment);
        uleb128(&mut out, bind.addr - segment_addr);
        out.push(BIND_OPCODE_DO_BIND);
    }
    out.push(BIND_OPCODE_DONE);
    out.resize(out.len().next_multiple_of(8), BIND_OPCODE_DONE);
    out
}

fn segment_command(out: &mut Vec<u8>, segment: &Segment, sections: &[Section]) {
    put32(out, LC_SEGMENT_64);
    put32(out, (SEGMENT_SIZE + SECTION_SIZE * sections.len() as u64) as u32);
    put_name(out, segment.name);
    put64(out, segment.vmaddr);
    put64(out, segment.vmsize);
    put64(out, segment.fileoff);
    put64(out, segment.filesize);
    put32(out, segment.prot); // maxprot
    put32(out, segment.prot); // initprot
    put32(out, sections.len() as u32);
    put32(out, 0); // flags
    for section in sections {
        let (sectname, segname) = section.out.names();
        put_name(out, sectname);
        put_name(out, segname);
        put64(out, section.addr);
        put64(out, section.size);
        put32(out, if section.out == Out::Bss { 0 } else { (section.addr - IMAGE_BASE) as u32 });
        put32(out, section.align.trailing_zeros());
        put32(out, 0); // reloff
        put32(out, 0); // nreloc
        put32(out, section.out.flags());
        put32(out, 0); // reserved1: first indirect symbol, __got starts the table
        put32(out, 0); // reserved2
        put32(out, 0); // reserved3
    }
}

/// Size of a load command holding a fixed part of `fixed` bytes followed by
/// `text` and a NUL, padded to 8 bytes.
fn load_string_size(fixed: u64, text: &str) -> u64 {
    (fixed + text.len() as u64 + 1).next_multiple_of(8)
}

/// Writes `cmdsize`, the string offset and the padded string of a load
/// command whose `cmd` was just written.
fn put_load_string(out: &mut Vec<u8>, size: u64, offset: u32, text: &str) {
    let start = out.len() - 4;
    put32(out, size as u32);
    put32(out, offset);
    out.extend_from_slice(text.as_bytes());
    out.resize(start + size as usize, 0);
}

fn put_name(out: &mut Vec<u8>, name: &str) {
    let mut field = [0u8; 16];
    field[..name.len()].copy_from_slice(name.as_bytes());
    out.extend_from_slice(&field);
}

fn put16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn put32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn put64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link;
    use odin_asm::object::RelocKind::*;
    use odin_asm::object::{Import, Object};

    fn u32_at(data: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(data[at..at + 4].try_into().unwrap())
    }

    fn u64_at(data: &[u8], at: usize) -> u64 {
        u64::from_le_bytes(data[at..at + 8].try_into().unwrap())
    }

    fn name_at(data: &[u8], at: usize) -> String {
        let field = &data[at..at + 16];
        String::from_utf8(field.iter().take_while(|&&b| b != 0).copied().collect()).unwrap()
    }

    /// Load commands as (cmd, offset of the command in the file).
    fn commands(file: &[u8]) -> Vec<(u32, usize)> {
        assert_eq!(u32_at(file, 0), MH_MAGIC_64);
        let mut at = HEADER_SIZE as usize;
        let mut out = Vec::new();
        for _ in 0..u32_at(file, 16) {
            out.push((u32_at(file, at), at));
            at += u32_at(file, at + 4) as usize;
        }
        assert_eq!(at, HEADER_SIZE as usize + u32_at(file, 20) as usize, "sizeofcmds");
        out
    }

    fn command(file: &[u8], cmd: u32) -> usize {
        commands(file).into_iter().find(|&(c, _)| c == cmd).map(|(_, at)| at).expect("load command present")
    }

    #[derive(Debug)]
    struct Seg {
        name: String,
        vmaddr: u64,
        vmsize: u64,
        fileoff: u64,
        filesize: u64,
        sections: Vec<Sect>,
    }

    #[derive(Debug)]
    struct Sect {
        name: String,
        segment: String,
        addr: u64,
        size: u64,
        offset: u32,
        align: u32,
        flags: u32,
    }

    fn segments(file: &[u8]) -> Vec<Seg> {
        let mut out = Vec::new();
        for (cmd, at) in commands(file) {
            if cmd != LC_SEGMENT_64 {
                continue;
            }
            let sections = (0..u32_at(file, at + 64) as usize)
                .map(|i| {
                    let s = at + 72 + 80 * i;
                    Sect {
                        name: name_at(file, s),
                        segment: name_at(file, s + 16),
                        addr: u64_at(file, s + 32),
                        size: u64_at(file, s + 40),
                        offset: u32_at(file, s + 48),
                        align: u32_at(file, s + 52),
                        flags: u32_at(file, s + 64),
                    }
                })
                .collect();
            out.push(Seg {
                name: name_at(file, at + 8),
                vmaddr: u64_at(file, at + 24),
                vmsize: u64_at(file, at + 32),
                fileoff: u64_at(file, at + 40),
                filesize: u64_at(file, at + 48),
                sections,
            });
        }
        out
    }

    fn libsystem(name: &str) -> Import {
        Import { name: name.to_string(), library: LIBSYSTEM.to_string() }
    }

    fn object(atoms: Vec<Atom>, imports: Vec<Import>) -> Vec<Object> {
        vec![Object { name: "test".to_string(), atoms, imports }]
    }

    fn x86(objects: &[Object]) -> Result<LinkedImage, LinkError> {
        link(objects, &LinkOptions::new(Target::X86_64Darwin, "_main", "test"))
    }

    fn arm64(objects: &[Object]) -> Result<LinkedImage, LinkError> {
        link(objects, &LinkOptions::new(Target::Aarch64Darwin, "_main", "test"))
    }

    /// One atom of every kind, odd alignments, a pointer table in read-only
    /// data and in data, imports used and unused.
    fn sample() -> Vec<Object> {
        object(
            vec![
                Atom::new("_main", SectionKind::Text, 1, vec![0x90; 20])
                    .reloc(0, X86GotPc32, "_write", -4)
                    .reloc(4, X86Pc32, "_helper", -4)
                    .reloc(8, X86Pc32, "_vtable", -4)
                    .reloc(12, X86Pc32, "_counter", -4)
                    .reloc(16, X86Pc32, "_jump_table", -4),
                Atom::new("_helper", SectionKind::Text, 16, vec![0x8d, 0, 0, 0, 0, 0xc3]).reloc(
                    1,
                    X86Pc32,
                    "_text_str",
                    -4,
                ),
                Atom::new("_text_str", SectionKind::ReadOnly, 1, b"hi\0".to_vec()),
                Atom::new("_jump_table", SectionKind::ReadOnly, 8, vec![0; 16])
                    .reloc(0, Abs64, "_helper", 0)
                    .reloc(8, Abs64, "_main", 3),
                Atom {
                    labels: vec![("_vtable_end".to_string(), 24)],
                    ..Atom::new("_vtable", SectionKind::Data, 8, vec![0; 24])
                }
                .reloc(0, Abs64, "_text_str", 1)
                .reloc(8, Abs64, "_counter", 0)
                .reloc(16, Abs64, "_exit", 16),
                Atom::bss("_counter", 0x2345, 32),
                Atom::new("_dead", SectionKind::Text, 1, vec![0xff, 0x15, 0, 0, 0, 0])
                    .reloc(2, X86GotPc32, "_unused", -4),
            ],
            vec![libsystem("_write"), libsystem("_exit"), libsystem("_unused")],
        )
    }

    #[test]
    fn x86_64_layout() {
        let image = x86(&sample()).unwrap();
        let file = &image.bytes;
        assert_eq!(image.image_base, IMAGE_BASE);
        assert_eq!(u32_at(file, 4), CPU_TYPE_X86_64);
        assert_eq!(u32_at(file, 12), MH_EXECUTE);
        assert_eq!(u32_at(file, 24), 0x0020_0085);

        let segs = segments(file);
        let names: Vec<&str> = segs.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, ["__PAGEZERO", "__TEXT", "__DATA", "__LINKEDIT"]);
        assert_eq!((segs[0].vmaddr, segs[0].vmsize, segs[0].filesize), (0, IMAGE_BASE, 0));
        let (text, data, linkedit) = (&segs[1], &segs[2], &segs[3]);
        assert_eq!((text.vmaddr, text.fileoff), (IMAGE_BASE, 0));
        assert_eq!(text.filesize, text.vmsize);
        for seg in &segs[1..] {
            assert_eq!(seg.vmaddr % 0x1000, 0, "{}", seg.name);
            assert_eq!(seg.fileoff % 0x1000, 0, "{}", seg.name);
        }
        assert_eq!(data.vmaddr, text.vmaddr + text.vmsize);
        assert_eq!(data.fileoff, text.filesize);
        assert_eq!(linkedit.vmaddr, data.vmaddr + data.vmsize);
        assert_eq!(linkedit.fileoff, data.fileoff + data.filesize);
        assert_eq!(linkedit.fileoff + linkedit.filesize, file.len() as u64);

        let sects: Vec<(&str, &str)> =
            segs.iter().flat_map(|s| &s.sections).map(|s| (s.segment.as_str(), s.name.as_str())).collect();
        assert_eq!(
            sects,
            [
                ("__TEXT", "__text"),
                ("__TEXT", "__const"),
                ("__DATA", "__got"),
                ("__DATA", "__const"),
                ("__DATA", "__data"),
                ("__DATA", "__bss")
            ]
        );
        let text_sect = &text.sections[0];
        assert_eq!(text_sect.align, 4);
        assert_eq!(text_sect.flags, S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS);
        assert!(text_sect.addr >= IMAGE_BASE + HEADER_SIZE + u64::from(u32_at(file, 20)));
        let got = &data.sections[0];
        assert_eq!((got.size, got.flags), (8, S_NON_LAZY_SYMBOL_POINTERS), "only _write goes through the GOT");
        let bss = &data.sections[3];
        assert_eq!((bss.offset, bss.flags, bss.align), (0, S_ZEROFILL, 5));
        assert!(bss.addr >= data.vmaddr + data.sections[2].size);
        assert!(bss.addr + bss.size <= data.vmaddr + data.vmsize);
        for sect in segs.iter().flat_map(|s| &s.sections).filter(|s| s.name != "__bss") {
            assert_eq!(u64::from(sect.offset), sect.addr - IMAGE_BASE, "{}", sect.name);
        }

        // Atoms: placement, alignment, smart linking.
        let sym = |name: &str| image.symbols[name];
        assert_eq!(sym("_main"), text_sect.addr);
        assert_eq!(sym("_helper") % 16, 0);
        assert_eq!(sym("_helper"), (sym("_main") + 20).next_multiple_of(16));
        assert_eq!(sym("_text_str"), text.sections[1].addr);
        assert_eq!(sym("_jump_table"), data.sections[1].addr);
        assert_eq!(sym("_vtable_end"), sym("_vtable") + 24);
        assert_eq!(sym("_counter"), bss.addr);
        assert_eq!(sym("_counter") % 32, 0);
        assert!(!image.symbols.contains_key("_dead"));
        assert_eq!(image.symbols.len(), 7);
        // Padding between code atoms is int3.
        let gap = (sym("_main") + 20 - IMAGE_BASE) as usize..(sym("_helper") - IMAGE_BASE) as usize;
        assert!(!gap.is_empty() && file[gap].iter().all(|&b| b == 0xcc));

        // Relocated fields hold unslid addresses.
        let at = |name: &str| (sym(name) - IMAGE_BASE) as usize;
        assert_eq!(u64_at(file, at("_vtable")), sym("_text_str") + 1);
        assert_eq!(u64_at(file, at("_vtable") + 8), sym("_counter"));
        assert_eq!(u64_at(file, at("_vtable") + 16), 0, "bound by dyld");
        assert_eq!(u64_at(file, at("_jump_table") + 8), sym("_main") + 3);
        assert_eq!(&file[at("_text_str")..at("_text_str") + 3], b"hi\0");
        let rel32 = |name: &str, offset: u64| i64::from(u32_at(file, at(name) + offset as usize) as i32);
        assert_eq!(&file[at("_helper")..at("_helper") + 6][..1], &[0x8d]);
        assert_eq!(file[at("_helper") + 5], 0xc3);
        assert_eq!(rel32("_helper", 1), sym("_text_str") as i64 - (sym("_helper") as i64 + 5));
        assert_eq!(rel32("_main", 4), sym("_helper") as i64 - (sym("_main") as i64 + 8));
        assert_eq!(rel32("_main", 12), sym("_counter") as i64 - (sym("_main") as i64 + 16));
        assert_eq!(rel32("_main", 0), data.sections[0].addr as i64 - (sym("_main") as i64 + 4), "GOT slot");

        // Exactly four rebases (two in __DATA,__const, two in __data) and two binds.
        let info = command(file, LC_DYLD_INFO_ONLY);
        let (rebase_off, rebase_size) = (u32_at(file, info + 8) as usize, u32_at(file, info + 12) as usize);
        let rebase = &file[rebase_off..rebase_off + rebase_size];
        let rebased: u32 =
            rebase.iter().filter(|&&b| b & 0xf0 == REBASE_OPCODE_DO_REBASE_IMM_TIMES).map(|b| u32::from(b & 0xf)).sum();
        assert_eq!(rebased, 4);
        let (bind_off, bind_size) = (u32_at(file, info + 16) as usize, u32_at(file, info + 20) as usize);
        let bind = &file[bind_off..bind_off + bind_size];
        assert_eq!(bind.iter().filter(|&&b| b == BIND_OPCODE_DO_BIND).count(), 2);
        assert!(bind.windows(7).any(|w| w == b"_write\0"));
        assert!(bind.windows(6).any(|w| w == b"_exit\0"));
        assert!(bind.windows(2).any(|w| w == [BIND_OPCODE_SET_ADDEND_SLEB, 16]));
        assert!(!file.windows(8).any(|w| w == b"_unused\0"), "unused imports leave no trace");
        assert_eq!(u32_at(file, info + 24), 0, "no weak binds");
        assert_eq!(u32_at(file, info + 32), 0, "no lazy binds");

        // Symbol table: locals, then __mh_execute_header and _main, then imports.
        let dysymtab = command(file, LC_DYSYMTAB);
        let counts: Vec<u32> = (0..6).map(|i| u32_at(file, dysymtab + 8 + 4 * i)).collect();
        assert_eq!(counts, [0, 6, 6, 2, 8, 2]);
        let symtab = command(file, LC_SYMTAB);
        let (symoff, nsyms, stroff) =
            (u32_at(file, symtab + 8) as usize, u32_at(file, symtab + 12), u32_at(file, symtab + 16) as usize);
        assert_eq!(nsyms, 10);
        let nlist = |i: usize| {
            let at = symoff + 16 * i;
            let strx = u32_at(file, at) as usize + stroff;
            let name: Vec<u8> = file[strx..].iter().take_while(|&&b| b != 0).copied().collect();
            (
                String::from_utf8(name).unwrap(),
                file[at + 4],
                file[at + 5],
                u16::from_le_bytes([file[at + 6], file[at + 7]]),
                u64_at(file, at + 8),
            )
        };
        assert_eq!(nlist(6), (MH_EXECUTE_HEADER.to_string(), 0x0f, 1, REFERENCED_DYNAMICALLY, IMAGE_BASE));
        assert_eq!(nlist(7), ("_main".to_string(), 0x0f, 1, 0, sym("_main")));
        assert_eq!(nlist(8), ("_exit".to_string(), 0x01, 0, 0x100, 0));
        assert_eq!(nlist(9), ("_write".to_string(), 0x01, 0, 0x100, 0));
        let locals: Vec<(String, u8)> = (0..6).map(|i| (nlist(i).0, nlist(i).2)).collect();
        assert_eq!(locals[0], ("_helper".to_string(), 1));
        assert!(locals.contains(&("_counter".to_string(), 6)));
        assert!((0..5).all(|i| nlist(i).4 <= nlist(i + 1).4), "locals sorted by address");
        let indirect = u32_at(file, dysymtab + 56) as usize;
        assert_eq!(u32_at(file, dysymtab + 60), 1);
        assert_eq!(u32_at(file, indirect), 9, "the GOT slot is _write");

        // Entry point and code signature.
        let main = command(file, LC_MAIN);
        assert_eq!(u64_at(file, main + 8), sym("_main") - IMAGE_BASE);
        let signature = command(file, LC_CODE_SIGNATURE);
        let (sig_off, sig_size) = (u32_at(file, signature + 8) as usize, u32_at(file, signature + 12) as usize);
        assert_eq!(sig_off % 16, 0);
        assert_eq!(sig_off + sig_size, file.len());
        assert_eq!(&file[sig_off..sig_off + 4], &[0xfa, 0xde, 0x0c, 0xc0]);
        let cd = sig_off + 20;
        assert_eq!(u32::from_be_bytes(file[cd + 32..cd + 36].try_into().unwrap()) as usize, sig_off, "codeLimit");
        assert_eq!(u64::from_be_bytes(file[cd + 72..cd + 80].try_into().unwrap()), text.filesize, "execSegLimit");
        let first_hash = cd + 88 + b"test\0".len();
        assert_eq!(&file[first_hash..first_hash + 32], &sha256(&file[..4096]));
    }

    #[test]
    fn load_commands_and_dylibs() {
        let mut objects = sample();
        objects[0].atoms[0] = objects[0].atoms[0].clone().reloc(8, X86GotPc32, "_objc_msgSend", -4);
        objects[0]
            .imports
            .push(Import { name: "_objc_msgSend".to_string(), library: "/usr/lib/libobjc.A.dylib".to_string() });
        let options = LinkOptions { min_os: (12, 3, 1), ..LinkOptions::new(Target::X86_64Darwin, "_main", "test") };
        let file = link(&objects, &options).unwrap().bytes;
        let cmds: Vec<u32> = commands(&file).into_iter().map(|(c, _)| c).collect();
        assert_eq!(
            cmds,
            [
                LC_SEGMENT_64,
                LC_SEGMENT_64,
                LC_SEGMENT_64,
                LC_SEGMENT_64,
                LC_DYLD_INFO_ONLY,
                LC_SYMTAB,
                LC_DYSYMTAB,
                LC_LOAD_DYLINKER,
                LC_UUID,
                LC_BUILD_VERSION,
                LC_MAIN,
                LC_LOAD_DYLIB,
                LC_LOAD_DYLIB,
                LC_CODE_SIGNATURE
            ]
        );
        let dylinker = command(&file, LC_LOAD_DYLINKER);
        assert_eq!(&file[dylinker + 12..dylinker + 26], b"/usr/lib/dyld\0");
        let build = command(&file, LC_BUILD_VERSION);
        assert_eq!(
            [u32_at(&file, build + 8), u32_at(&file, build + 12), u32_at(&file, build + 16)],
            [PLATFORM_MACOS, 0x000c_0301, 0x000c_0301]
        );
        let dylibs: Vec<String> = commands(&file)
            .into_iter()
            .filter(|&(c, _)| c == LC_LOAD_DYLIB)
            .map(|(_, at)| {
                assert_eq!(u32_at(&file, at + 4) % 8, 0);
                assert_eq!(u32_at(&file, at + 20), 0x1_0000, "compatibility version");
                String::from_utf8(file[at + 24..].iter().take_while(|&&b| b != 0).copied().collect()).unwrap()
            })
            .collect();
        assert_eq!(dylibs, [LIBSYSTEM, "/usr/lib/libobjc.A.dylib"]);
        // The second library's import carries ordinal 2.
        let info = command(&file, LC_DYLD_INFO_ONLY);
        let bind = &file[u32_at(&file, info + 16) as usize..][..u32_at(&file, info + 20) as usize];
        assert!(
            bind.windows(2)
                .any(|w| w == [BIND_OPCODE_SET_DYLIB_ORDINAL_IMM | 2, BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM])
        );
    }

    #[test]
    fn arm64_layout_uses_16k_pages() {
        let objects = object(
            vec![
                Atom::new("_main", SectionKind::Text, 1, vec![0; 12])
                    .reloc(0, Arm64GotPage21, "_exit", 0)
                    .reloc(4, Arm64GotPageOff12, "_exit", 0)
                    .reloc(8, Arm64Branch26, "_f", 0),
                Atom::new("_f", SectionKind::Text, 1, vec![0; 6]),
                Atom::new("_g", SectionKind::Text, 1, vec![0; 4]).keep(),
                Atom::new("_d", SectionKind::Data, 8, vec![1; 8]).keep(),
            ],
            vec![libsystem("_exit")],
        );
        let image = arm64(&objects).unwrap();
        let file = &image.bytes;
        assert_eq!((u32_at(file, 4), u32_at(file, 8)), (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL));
        for seg in &segments(file)[1..] {
            assert_eq!(seg.vmaddr % 0x4000, 0, "{}", seg.name);
            assert_eq!(seg.fileoff % 0x4000, 0, "{}", seg.name);
            if seg.name != "__LINKEDIT" {
                assert_eq!(seg.vmsize % 0x4000, 0, "{}", seg.name);
            }
        }
        // Code atoms are at least word aligned; padding is zero (udf #0).
        assert_eq!(image.symbols["_main"] % 4, 0);
        assert_eq!(image.symbols["_g"], image.symbols["_f"] + 8);
        let code = (image.symbols["_main"] - IMAGE_BASE) as usize;
        assert_eq!(u32_at(file, code + 8), 0x0000_0001, "b _f: one word forward, opcode bits from the input");
        assert_eq!(&file[code + 18..code + 20], &[0, 0]);
        // ADRP/LDR reach the GOT slot.
        let got = segments(file)[2].sections[0].addr;
        let pages = (got >> 12) - ((code as u64 + IMAGE_BASE) >> 12);
        let adrp = u32_at(file, code);
        assert_eq!(u64::from(((adrp >> 29) & 3) | (((adrp >> 5) & 0x7_ffff) << 2)), pages);
        assert_eq!(u64::from((u32_at(file, code + 4) >> 10) & 0xfff) * 8, got & 0xfff);
    }

    #[test]
    fn data_segment_with_only_bss() {
        let objects = object(
            vec![
                Atom::new("_main", SectionKind::Text, 1, vec![0; 8]).reloc(0, X86Pc32, "_buf", -4),
                Atom::bss("_buf", 0x1_0000, 16),
            ],
            vec![],
        );
        let image = x86(&objects).unwrap();
        let segs = segments(&image.bytes);
        let data = &segs[2];
        assert_eq!((data.name.as_str(), data.filesize, data.vmsize), ("__DATA", 0, 0x1_0000));
        assert_eq!(segs[3].fileoff, data.fileoff);
        assert_eq!(segs[3].vmaddr, data.vmaddr + 0x1_0000);
        let info = command(&image.bytes, LC_DYLD_INFO_ONLY);
        assert_eq!([u32_at(&image.bytes, info + 8), u32_at(&image.bytes, info + 12)], [0, 0], "nothing to rebase");
    }

    #[test]
    fn code_only_program_has_no_data_segment() {
        let image = x86(&object(vec![Atom::new("_main", SectionKind::Text, 1, vec![0xc3])], vec![])).unwrap();
        let names: Vec<String> = segments(&image.bytes).into_iter().map(|s| s.name).collect();
        assert_eq!(names, ["__PAGEZERO", "__TEXT", "__LINKEDIT"]);
        // libSystem is linked even when nothing is imported.
        assert_eq!(commands(&image.bytes).iter().filter(|(c, _)| *c == LC_LOAD_DYLIB).count(), 1);
    }

    #[test]
    fn local_got_slot_is_rebased() {
        let objects = object(
            vec![
                Atom::new("_main", SectionKind::Text, 1, vec![0; 8]).reloc(2, X86GotPc32, "_value", -4),
                Atom::new("_value", SectionKind::Data, 8, vec![7; 8]),
            ],
            vec![],
        );
        let image = x86(&objects).unwrap();
        let file = &image.bytes;
        let got = &segments(file)[2].sections[0];
        assert_eq!(got.name, "__got");
        assert_eq!(u64_at(file, got.offset as usize), image.symbols["_value"]);
        let main = (image.symbols["_main"] - IMAGE_BASE) as usize;
        assert_eq!(i64::from(u32_at(file, main + 2) as i32), got.addr as i64 - (image.symbols["_main"] as i64 + 6));
        let dysymtab = command(file, LC_DYSYMTAB);
        assert_eq!(u32_at(file, u32_at(file, dysymtab + 56) as usize), INDIRECT_SYMBOL_LOCAL);
        let info = command(file, LC_DYLD_INFO_ONLY);
        assert_ne!(u32_at(file, info + 12), 0, "rebased");
        assert_eq!(u32_at(file, info + 20), 0, "nothing to bind");
    }

    #[test]
    fn output_is_deterministic() {
        let first = x86(&sample()).unwrap();
        assert_eq!(first, x86(&sample()).unwrap());
        let mut changed = sample();
        changed[0].atoms[2].bytes[0] = b'H';
        let second = x86(&changed).unwrap();
        let uuid = |file: &[u8]| {
            let at = command(file, LC_UUID) + 8;
            file[at..at + 16].to_vec()
        };
        assert_ne!(uuid(&first.bytes), uuid(&second.bytes));
        assert_eq!(uuid(&first.bytes)[6] >> 4, 8);
    }

    #[test]
    fn rejected_input() {
        let unsupported = |result: Result<LinkedImage, LinkError>| matches!(result, Err(LinkError::Unsupported(_)));
        let main = || Atom::new("_main", SectionKind::Text, 1, vec![0; 8]);
        let write = || vec![libsystem("_write")];
        assert!(unsupported(x86(&object(vec![main().reloc(0, X86Pc32, "_write", -4)], write()))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, Arm64Page21, "_write", 0)], write()))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, Arm64Branch26, "_write", 0)], write()))));
        assert!(unsupported(x86(&object(vec![main().reloc(0, Abs64, "_main", 0)], vec![]))));
        assert!(unsupported(x86(&object(vec![main().reloc(0, Arm64Branch26, "_main", 0)], vec![]))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, X86Pc32, "_main", 0)], vec![]))));
        assert!(unsupported(x86(&object(vec![Atom::new("_main", SectionKind::Data, 1, vec![0; 8])], vec![]))));
        assert!(unsupported(x86(&object(
            vec![main(), Atom::new("_big", SectionKind::Data, 0x2000, vec![0; 8]).keep()],
            vec![]
        ))));
        assert!(
            arm64(&object(vec![main(), Atom::new("_big", SectionKind::Data, 0x2000, vec![0; 8]).keep()], vec![]))
                .is_ok()
        );
        for target in [Target::X86_64Linux, Target::Aarch64Linux] {
            assert!(unsupported(link(&object(vec![main()], vec![]), &LinkOptions::new(target, "_main", "test"))));
        }
        assert_eq!(
            x86(&object(vec![main(), Atom::new(MH_EXECUTE_HEADER, SectionKind::Data, 1, vec![0])], vec![])).err(),
            Some(LinkError::Duplicate { name: MH_EXECUTE_HEADER.to_string() })
        );
        let unnamed = LinkOptions::new(Target::X86_64Darwin, "_main", "");
        assert!(matches!(link(&object(vec![main()], vec![]), &unnamed), Err(LinkError::Malformed(_))));
    }

    #[test]
    fn out_of_range_relocations() {
        let out_of_range = LinkError::RelocOutOfRange { atom: "_main".to_string(), target: "_far".to_string() };
        // x86-64: rel32 reaches +-2 GiB.
        let far_x86 = |gap: u64| {
            object(
                vec![
                    Atom::new("_main", SectionKind::Text, 1, vec![0; 8]).reloc(0, X86Pc32, "_far", -4),
                    Atom::bss("_gap", gap, 8).keep(),
                    Atom::bss("_far", 8, 8),
                ],
                vec![],
            )
        };
        assert!(x86(&far_x86(0x7000_0000)).is_ok());
        assert_eq!(x86(&far_x86(0x8000_0000)).err(), Some(out_of_range.clone()));
        // arm64: B/BL reaches +-128 MiB.
        let far_arm = |gap: u64| {
            object(
                vec![
                    Atom::new("_main", SectionKind::Text, 4, vec![0; 4]).reloc(0, Arm64Branch26, "_far", 0),
                    Atom::new("_gap", SectionKind::Text, 4, vec![0; 0]).keep(),
                    Atom::bss("_pad", gap, 8).keep(),
                    Atom::bss("_far", 8, 8),
                ],
                vec![],
            )
        };
        assert!(arm64(&far_arm(0x700_0000)).is_ok());
        assert_eq!(arm64(&far_arm(0x800_0000)).err(), Some(out_of_range.clone()));
        // arm64: an 8-byte load needs an 8-byte aligned target.
        let misaligned = object(
            vec![
                Atom::new("_main", SectionKind::Text, 4, vec![0; 4]).reloc(0, Arm64PageOff12 { scale: 3 }, "_far", 0),
                Atom::new("_far", SectionKind::Data, 4, vec![0; 4]),
            ],
            vec![],
        );
        // `_far` is the only data atom, so it is page aligned; push it off by 4.
        let misaligned = vec![Object {
            atoms: vec![
                misaligned[0].atoms[0].clone(),
                Atom::new("_pad", SectionKind::Data, 4, vec![0; 4]).keep(),
                misaligned[0].atoms[1].clone(),
            ],
            ..misaligned[0].clone()
        }];
        assert_eq!(arm64(&misaligned).err(), Some(out_of_range));
    }

    #[test]
    fn placement() {
        let (start, addrs, end, align) = place(0x1003, [(1, 3), (16, 5), (4, 0), (4, 4)].into_iter(), 1);
        assert_eq!((start, align), (0x1010, 16));
        assert_eq!(addrs, [0x1010, 0x1020, 0x1028, 0x1028]);
        assert_eq!(end, 0x102c);
        let (start, addrs, end, align) = place(0x1003, std::iter::empty(), 8);
        assert_eq!((start, addrs.len(), end, align), (0x1008, 0, 0x1008, 8));
    }

    #[test]
    fn rebase_encoding() {
        let seg = IMAGE_BASE + 0x4000;
        let mut addrs = [seg + 0x100, seg + 8, seg, seg + 16];
        assert_eq!(
            rebase_opcodes(2, seg, &mut addrs),
            [0x11, 0x22, 0x00, 0x53, 0x30, 0xe8, 0x01, 0x51, 0x00, 0, 0, 0, 0, 0, 0, 0]
        );
        let mut run: Vec<u64> = (0..20).map(|i| seg + 0x10 + 8 * i).collect();
        assert_eq!(rebase_opcodes(2, seg, &mut run), [0x11, 0x22, 0x10, 0x60, 20, 0x00, 0, 0]);
        assert!(rebase_opcodes(2, seg, &mut []).is_empty());
    }

    #[test]
    fn bind_encoding() {
        let seg = IMAGE_BASE + 0x4000;
        let binds = [
            Bind { addr: seg, import: 0, addend: 0 },
            Bind { addr: seg + 8, import: 1, addend: 0 },
            Bind { addr: seg + 0x20, import: 1, addend: 16 },
        ];
        let names = ["_exit", "_write"];
        let mut expected = vec![0x51, 0x11, 0x40];
        expected.extend_from_slice(b"_exit\0");
        expected.extend_from_slice(&[0x72, 0x00, 0x90, 0x40]);
        expected.extend_from_slice(b"_write\0");
        expected.extend_from_slice(&[0x72, 0x08, 0x90, 0x60, 0x10, 0x72, 0x20, 0x90, 0x00]);
        expected.resize(expected.len().next_multiple_of(8), 0);
        assert_eq!(bind_opcodes(2, seg, &binds, |i| (1, names[i])), expected);
        let far = [Bind { addr: seg, import: 0, addend: -8 }];
        assert_eq!(
            bind_opcodes(2, seg, &far, |_| (20, "_x")),
            [0x51, 0x20, 20, 0x40, b'_', b'x', 0, 0x60, 0x78, 0x72, 0x00, 0x90, 0x00, 0, 0, 0]
        );
    }
}
