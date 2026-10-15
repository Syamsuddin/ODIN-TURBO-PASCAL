// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! ELF executable writer for x86_64 and aarch64 Linux.
//!
//! The output is a dynamically linked, position-independent executable for
//! glibc: an `ET_DYN` flagged `DF_1_PIE`, linked at address 0, that the
//! kernel hands to ld-linux. ld.so maps it at a random base, loads the
//! libraries in `DT_NEEDED` (libc.so.6 and libm.so.6 for `libc` imports) and
//! applies `.rela.dyn` once, before any code runs (`DF_BIND_NOW`; there is no
//! PLT and no lazy binding). The file is laid out like this:
//!
//! ```text
//! PT_LOAD r--  ELF header, program headers, .interp, .hash, .dynsym,
//!              .dynstr, .rela.dyn, .rodata (ReadOnly)
//! PT_LOAD r-x  .text (Text)
//! PT_LOAD rw-  .data.rel.ro (ReadOnly with absolute pointers), .dynamic,
//!              .got                      <- PT_GNU_RELRO: read-only once
//!                                           ld.so has relocated them
//!              .data (Data), .bss (Bss, zero-fill)
//! (unloaded)   .symtab, .strtab, .shstrtab, section headers
//! ```
//!
//! Each segment starts on a fresh 4 KiB page of the file, so with 4 KiB
//! pages code never shares a page with data. Its address is congruent to its
//! file offset modulo the largest page the architecture allows (`p_align`:
//! 4 KiB on x86_64, 64 KiB on aarch64) and starts past the previous
//! segment's last such page, so the same file loads under 4, 16 and 64 KiB
//! pages. The RELRO part ends on a 4 KiB boundary, so 4 KiB pages protect
//! all of it; larger pages protect only the whole pages inside it, as with
//! GNU ld's output.
//!
//! Relocations end up position-independent. PC-relative fields (`X86Pc32`,
//! `Arm64Branch26`, `Arm64Page21`, `Arm64PageOff12`) are patched and need
//! nothing at load time. The GOT kinds point at a slot that ld.so fills:
//! `R_*_GLOB_DAT` against an imported symbol (function or data, such as
//! `environ`) or `R_*_RELATIVE` for a local target. An `Abs64` field holds
//! the unslid address, for tools, plus an `R_*_RELATIVE` that slides it, or
//! is left zero with an `R_X86_64_64`/`R_AARCH64_ABS64` against an import.
//! Code that refers to an import any other way (a direct `call` or `bl`)
//! is rejected, as on Darwin: the code generator never emits it, and a PLT
//! stub would only add an indirection.
//!
//! `__ehdr_start`, the address of the ELF header (the load base at run
//! time), is defined here as GNU ld does.

use std::collections::{BTreeMap, HashMap};

use odin_asm::object::{Atom, Import, RelocKind, SectionKind};

use crate::layout::{check_input, place, put16, put32, put64};
use crate::reloc;
use crate::resolve::{Resolved, Sym};
use crate::{LinkError, LinkOptions, LinkedImage, Target};

/// The ELF header's address, which the RTL subtracts from runtime addresses
/// to find link-time ones.
const EHDR_START: &str = "__ehdr_start";
/// Names this writer defines: [`Sym::Synthetic`] indexes this list.
pub(crate) const SYNTHETIC: &[&str] = &[EHDR_START];

/// Address the file is linked at; ld.so slides everything by the load base.
const IMAGE_BASE: u64 = 0;
/// Segments start on a fresh page of this size in the file.
const FILE_PAGE: u64 = 0x1000;
/// glibc's C library comes in two objects; `libc` imports may name a
/// function of either (sin, cos, exp, log, pow and atan live in libm).
const GLIBC: [&str; 2] = ["libc.so.6", "libm.so.6"];

const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;
const EV_CURRENT: u8 = 1;
const ELFOSABI_NONE: u8 = 0;
const ET_DYN: u16 = 3;
const EM_X86_64: u16 = 62;
const EM_AARCH64: u16 = 183;

const EHDR_SIZE: u64 = 64;
const PHDR_SIZE: u64 = 56;
const SHDR_SIZE: u64 = 64;
const SYM_SIZE: u64 = 24;
const RELA_SIZE: u64 = 24;
const DYN_SIZE: u64 = 16;
/// Program headers: always the same eight, in [`write`]'s order.
const PHNUM: u64 = 8;

const PT_LOAD: u32 = 1;
const PT_DYNAMIC: u32 = 2;
const PT_INTERP: u32 = 3;
const PT_PHDR: u32 = 6;
const PT_GNU_STACK: u32 = 0x6474_e551;
const PT_GNU_RELRO: u32 = 0x6474_e552;
const PF_X: u32 = 1;
const PF_W: u32 = 2;
const PF_R: u32 = 4;

const SHT_PROGBITS: u32 = 1;
const SHT_SYMTAB: u32 = 2;
const SHT_STRTAB: u32 = 3;
const SHT_RELA: u32 = 4;
const SHT_HASH: u32 = 5;
const SHT_DYNAMIC: u32 = 6;
const SHT_NOBITS: u32 = 8;
const SHT_DYNSYM: u32 = 11;
const SHF_WRITE: u64 = 1;
const SHF_ALLOC: u64 = 2;
const SHF_EXECINSTR: u64 = 4;

const DT_NULL: u64 = 0;
const DT_NEEDED: u64 = 1;
const DT_HASH: u64 = 4;
const DT_STRTAB: u64 = 5;
const DT_SYMTAB: u64 = 6;
const DT_RELA: u64 = 7;
const DT_RELASZ: u64 = 8;
const DT_RELAENT: u64 = 9;
const DT_STRSZ: u64 = 10;
const DT_SYMENT: u64 = 11;
const DT_DEBUG: u64 = 21;
const DT_FLAGS: u64 = 30;
const DT_RELACOUNT: u64 = 0x6fff_fff9;
const DT_FLAGS_1: u64 = 0x6fff_fffb;
const DF_BIND_NOW: u64 = 0x8;
const DF_1_NOW: u64 = 0x1;
const DF_1_PIE: u64 = 0x0800_0000;

const STB_LOCAL: u8 = 0;
const STB_GLOBAL: u8 = 1;
const STT_NOTYPE: u8 = 0;
const STT_OBJECT: u8 = 1;
const STT_FUNC: u8 = 2;
const SHN_UNDEF: u16 = 0;

const R_X86_64_64: u32 = 1;
const R_X86_64_GLOB_DAT: u32 = 6;
const R_X86_64_RELATIVE: u32 = 8;
const R_AARCH64_ABS64: u32 = 257;
const R_AARCH64_GLOB_DAT: u32 = 1025;
const R_AARCH64_RELATIVE: u32 = 1027;

/// Per-architecture parameters.
struct Arch {
    machine: u16,
    /// The dynamic linker, as glibc installs it.
    interp: &'static str,
    /// Largest page size the architecture's kernels use: `p_align` of the
    /// loadable segments.
    max_page: u64,
    /// Minimum alignment of `.text`.
    text_align: u64,
    /// Minimum alignment of each code atom.
    code_atom_align: u64,
    /// Padding between code atoms: `int3` on x86-64, `udf #0` on arm64.
    text_fill: u8,
    r_abs64: u32,
    r_glob_dat: u32,
    r_relative: u32,
}

impl Arch {
    fn of(target: Target) -> Arch {
        if target.is_arm64() {
            Arch {
                machine: EM_AARCH64,
                interp: "/lib/ld-linux-aarch64.so.1",
                max_page: 0x1_0000,
                text_align: 4,
                code_atom_align: 4,
                text_fill: 0,
                r_abs64: R_AARCH64_ABS64,
                r_glob_dat: R_AARCH64_GLOB_DAT,
                r_relative: R_AARCH64_RELATIVE,
            }
        } else {
            Arch {
                machine: EM_X86_64,
                interp: "/lib64/ld-linux-x86-64.so.2",
                max_page: 0x1000,
                text_align: 16,
                code_atom_align: 1,
                text_fill: 0xcc,
                r_abs64: R_X86_64_64,
                r_glob_dat: R_X86_64_GLOB_DAT,
                r_relative: R_X86_64_RELATIVE,
            }
        }
    }
}

/// Output sections holding atoms, in address order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Out {
    Rodata,
    Text,
    RelRo,
    Data,
    Bss,
}

impl Out {
    fn name(self) -> &'static str {
        match self {
            Out::Rodata => ".rodata",
            Out::Text => ".text",
            Out::RelRo => ".data.rel.ro",
            Out::Data => ".data",
            Out::Bss => ".bss",
        }
    }

    /// Where an atom goes. ld.so writes absolute pointers at load time, so
    /// read-only data holding them goes where it may, and is made read-only
    /// again afterwards (RELRO).
    fn of(atom: &Atom) -> Out {
        match atom.section {
            SectionKind::Text => Out::Text,
            SectionKind::ReadOnly if atom.relocs.iter().any(|r| r.kind == RelocKind::Abs64) => Out::RelRo,
            SectionKind::ReadOnly => Out::Rodata,
            SectionKind::Data => Out::Data,
            SectionKind::Bss => Out::Bss,
        }
    }
}

/// A loadable segment.
#[derive(Clone, Copy)]
struct Segment {
    offset: u64,
    vaddr: u64,
    filesz: u64,
    memsz: u64,
}

/// A section header before names and indices are known.
struct Section {
    name: &'static str,
    kind: u32,
    flags: u64,
    addr: u64,
    offset: u64,
    size: u64,
    /// The section `sh_link` refers to, by name.
    link: Option<&'static str>,
    info: u32,
    align: u64,
    entsize: u64,
}

/// A dynamic relocation: `sym` indexes `.dynsym` (0 for none).
struct Rela {
    offset: u64,
    kind: u32,
    sym: u32,
    addend: i64,
}

/// One `.symtab` entry before string offsets are known.
struct Symbol<'a> {
    name: &'a str,
    info: u8,
    shndx: u16,
    value: u64,
    size: u64,
}

pub(crate) fn write(resolved: &Resolved, options: &LinkOptions) -> Result<LinkedImage, LinkError> {
    let arch = Arch::of(options.target);
    check_input(resolved, options, arch.max_page)?;
    let needed = needed_libraries(&resolved.imports)?;

    // Sort live atoms into output sections, keeping input order.
    let mut members: [Vec<usize>; 5] = Default::default();
    for index in resolved.live_atoms() {
        members[Out::of(resolved.atoms[index]) as usize].push(index);
    }

    // One GOT slot per distinct target of a GOT relocation. Every slot and
    // every Abs64 field gets one dynamic relocation; count them now, since
    // `.rela.dyn` comes before the code.
    let is_import = |name: &str| matches!(resolved.lookup(name), Some(Sym::Import(_)));
    let mut got: Vec<&str> = Vec::new();
    let mut got_slot: HashMap<&str, u64> = HashMap::new();
    let (mut nrela, mut nrelative) = (0u64, 0u64);
    for index in resolved.live_atoms() {
        for reloc in &resolved.atoms[index].relocs {
            let new_slot = reloc::uses_got(reloc.kind) && !got_slot.contains_key(reloc.target.as_str());
            if new_slot {
                got_slot.insert(&reloc.target, got.len() as u64);
                got.push(&reloc.target);
            }
            if new_slot || reloc.kind == RelocKind::Abs64 {
                nrela += 1;
                nrelative += u64::from(!is_import(&reloc.target));
            }
        }
    }

    // Dynamic symbols: the null symbol, then the imports. Nothing is
    // exported.
    let mut dynstr = vec![0u8];
    let needed_names: Vec<u32> = needed.iter().map(|soname| add_string(&mut dynstr, soname)).collect();
    let mut dynsym = vec![0u8; SYM_SIZE as usize];
    for import in &resolved.imports {
        let name = add_string(&mut dynstr, &import.name);
        put_symbol(&mut dynsym, name, (STB_GLOBAL << 4) | STT_NOTYPE, SHN_UNDEF, 0, 0);
    }
    let hash = sysv_hash_table(&resolved.imports);
    let mut ndynamic = needed.len() as u64 + 9; // HASH STRTAB SYMTAB STRSZ SYMENT DEBUG FLAGS FLAGS_1 NULL
    if nrela > 0 {
        ndynamic += 3 + u64::from(nrelative > 0); // RELA RELASZ RELAENT RELACOUNT
    }

    // Addresses. Within each segment, address and file offset differ by a
    // constant.
    let mut atom_addr = vec![0u64; resolved.atoms.len()];
    let mut place_atoms = |out: Out, cursor: u64, min_align: u64, atom_align: u64| {
        let atoms = &members[out as usize];
        let sizes = atoms.iter().map(|&a| (u64::from(resolved.atoms[a].align).max(atom_align), resolved.atoms[a].size));
        let (start, addrs, end, align) = place(cursor, sizes, min_align);
        for (&atom, address) in atoms.iter().zip(addrs) {
            atom_addr[atom] = address;
        }
        (start, end, align)
    };
    let interp_addr = EHDR_SIZE + PHDR_SIZE * PHNUM;
    let interp_size = arch.interp.len() as u64 + 1;
    let hash_addr = (interp_addr + interp_size).next_multiple_of(8);
    let dynsym_addr = (hash_addr + hash.len() as u64).next_multiple_of(8);
    let dynstr_addr = dynsym_addr + dynsym.len() as u64;
    let rela_addr = (dynstr_addr + dynstr.len() as u64).next_multiple_of(8);
    let rodata = place_atoms(Out::Rodata, rela_addr + RELA_SIZE * nrela, 1, 1);
    let r_seg = Segment { offset: 0, vaddr: IMAGE_BASE, filesz: rodata.1, memsz: rodata.1 };

    let text_off = rodata.1.next_multiple_of(FILE_PAGE);
    let text_vaddr = next_segment(rodata.1, text_off, arch.max_page);
    let text = place_atoms(Out::Text, text_vaddr, arch.text_align, arch.code_atom_align);
    let x_seg =
        Segment { offset: text_off, vaddr: text_vaddr, filesz: text.1 - text_vaddr, memsz: text.1 - text_vaddr };

    let rw_off = (text_off + x_seg.filesz).next_multiple_of(FILE_PAGE);
    let rw_vaddr = next_segment(text.1, rw_off, arch.max_page);
    let relro = place_atoms(Out::RelRo, rw_vaddr, 1, 1);
    let dynamic_addr = relro.1.next_multiple_of(8);
    let got_addr = dynamic_addr + DYN_SIZE * ndynamic;
    let relro_end = (got_addr + 8 * got.len() as u64).next_multiple_of(FILE_PAGE);
    let data = place_atoms(Out::Data, relro_end, 1, 1);
    let bss = place_atoms(Out::Bss, data.1, 1, 1);
    let w_seg = Segment { offset: rw_off, vaddr: rw_vaddr, filesz: data.1 - rw_vaddr, memsz: bss.1 - rw_vaddr };

    let segments = [r_seg, x_seg, w_seg];
    let file_offset = |addr: u64| {
        let segment = segments.iter().rev().find(|s| addr >= s.vaddr).expect("addresses start at the header");
        segment.offset + (addr - segment.vaddr)
    };

    // Section contents.
    let file_end = w_seg.offset + w_seg.filesz;
    let mut image = vec![0u8; file_end as usize];
    if arch.text_fill != 0 {
        image[file_offset(text.0) as usize..file_offset(text.1) as usize].fill(arch.text_fill);
    }
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        if atom.section != SectionKind::Bss {
            let at = file_offset(atom_addr[index]) as usize;
            image[at..at + atom.bytes.len()].copy_from_slice(&atom.bytes);
        }
    }

    // Relocations. Fields hold unslid values, so tools reading the file see
    // the addresses the symbol table lists.
    let address_of = |sym: Sym| match sym {
        Sym::Local { atom, offset } => Some(atom_addr[atom] + offset),
        Sym::Synthetic(_) => Some(IMAGE_BASE), // __ehdr_start
        Sym::Import(_) => None,
    };
    let mut relas: Vec<Rela> = Vec::with_capacity(nrela as usize);
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        for reloc in &atom.relocs {
            let place = atom_addr[index] + u64::from(reloc.offset);
            let field = &mut image[file_offset(place) as usize..];
            let sym = resolved.lookup(&reloc.target).expect("live relocation targets resolve");
            let target = if reloc::uses_got(reloc.kind) {
                got_addr + 8 * got_slot[reloc.target.as_str()]
            } else if let Some(address) = address_of(sym) {
                address
            } else {
                // Abs64 to an import (checked): ld.so writes the whole value.
                let Sym::Import(import) = sym else { unreachable!() };
                relas.push(Rela { offset: place, kind: arch.r_abs64, sym: import as u32 + 1, addend: reloc.addend });
                field[..8].fill(0);
                continue;
            };
            reloc::patch(reloc.kind, field, place, target, reloc.addend)
                .map_err(|_| LinkError::RelocOutOfRange { atom: atom.name.clone(), target: reloc.target.clone() })?;
            if reloc.kind == RelocKind::Abs64 {
                let value = u64::from_le_bytes(field[..8].try_into().unwrap());
                relas.push(Rela { offset: place, kind: arch.r_relative, sym: 0, addend: value as i64 });
            }
        }
    }
    for (slot, name) in got.iter().enumerate() {
        let addr = got_addr + 8 * slot as u64;
        match resolved.lookup(name).expect("GOT targets resolve") {
            Sym::Import(import) => {
                relas.push(Rela { offset: addr, kind: arch.r_glob_dat, sym: import as u32 + 1, addend: 0 });
            }
            sym => {
                let value = address_of(sym).expect("local GOT targets have an address");
                let at = file_offset(addr) as usize;
                image[at..at + 8].copy_from_slice(&value.to_le_bytes());
                relas.push(Rela { offset: addr, kind: arch.r_relative, sym: 0, addend: value as i64 });
            }
        }
    }
    // `DT_RELACOUNT` promises the first relocations are all RELATIVE, which
    // ld.so then applies without looking anything up.
    relas.sort_by_key(|r| (r.kind != arch.r_relative, r.offset));
    debug_assert_eq!(relas.len() as u64, nrela);
    debug_assert_eq!(relas.iter().filter(|r| r.kind == arch.r_relative).count() as u64, nrelative);
    let mut rela = Vec::with_capacity((RELA_SIZE * nrela) as usize);
    for r in &relas {
        put64(&mut rela, r.offset);
        put64(&mut rela, (u64::from(r.sym) << 32) | u64::from(r.kind));
        put64(&mut rela, r.addend as u64);
    }

    let mut dynamic = Vec::with_capacity((DYN_SIZE * ndynamic) as usize);
    let mut entry = |tag: u64, value: u64| {
        put64(&mut dynamic, tag);
        put64(&mut dynamic, value);
    };
    for &name in &needed_names {
        entry(DT_NEEDED, u64::from(name));
    }
    entry(DT_HASH, hash_addr);
    entry(DT_STRTAB, dynstr_addr);
    entry(DT_SYMTAB, dynsym_addr);
    entry(DT_STRSZ, dynstr.len() as u64);
    entry(DT_SYMENT, SYM_SIZE);
    entry(DT_DEBUG, 0); // ld.so stores its r_debug here for debuggers
    if nrela > 0 {
        entry(DT_RELA, rela_addr);
        entry(DT_RELASZ, RELA_SIZE * nrela);
        entry(DT_RELAENT, RELA_SIZE);
    }
    entry(DT_FLAGS, DF_BIND_NOW);
    entry(DT_FLAGS_1, DF_1_NOW | DF_1_PIE);
    if nrelative > 0 {
        entry(DT_RELACOUNT, nrelative);
    }
    entry(DT_NULL, 0);
    debug_assert_eq!(dynamic.len() as u64, DYN_SIZE * ndynamic);

    let mut copy = |addr: u64, bytes: &[u8]| {
        let at = file_offset(addr) as usize;
        image[at..at + bytes.len()].copy_from_slice(bytes);
    };
    let mut interp = arch.interp.as_bytes().to_vec();
    interp.push(0);
    copy(interp_addr, &interp);
    copy(hash_addr, &hash);
    copy(dynsym_addr, &dynsym);
    copy(dynstr_addr, &dynstr);
    copy(rela_addr, &rela);
    copy(dynamic_addr, &dynamic);

    // Section headers, in address order, then the unloaded tables.
    let alloc = |name, kind, flags, (addr, end): (u64, u64), align, entsize, link| Section {
        name,
        kind,
        flags: SHF_ALLOC | flags,
        addr,
        offset: file_offset(addr),
        size: end - addr,
        link,
        info: 0,
        align,
        entsize,
    };
    let mut sections = vec![
        alloc(".interp", SHT_PROGBITS, 0, (interp_addr, interp_addr + interp_size), 1, 0, None),
        alloc(".hash", SHT_HASH, 0, (hash_addr, hash_addr + hash.len() as u64), 8, 4, Some(".dynsym")),
        Section {
            info: 1, // index of the first non-local symbol
            ..alloc(".dynsym", SHT_DYNSYM, 0, (dynsym_addr, dynstr_addr), 8, SYM_SIZE, Some(".dynstr"))
        },
        alloc(".dynstr", SHT_STRTAB, 0, (dynstr_addr, dynstr_addr + dynstr.len() as u64), 1, 0, None),
    ];
    if nrela > 0 {
        let range = (rela_addr, rela_addr + RELA_SIZE * nrela);
        sections.push(alloc(".rela.dyn", SHT_RELA, 0, range, 8, RELA_SIZE, Some(".dynsym")));
    }
    let atom_section = |out: Out, (start, end, align): (u64, u64, u64)| {
        let (kind, flags) = match out {
            Out::Rodata => (SHT_PROGBITS, 0),
            Out::Text => (SHT_PROGBITS, SHF_EXECINSTR),
            Out::RelRo | Out::Data => (SHT_PROGBITS, SHF_WRITE),
            Out::Bss => (SHT_NOBITS, SHF_WRITE),
        };
        alloc(out.name(), kind, flags, (start, end), align, 0, None)
    };
    for (out, range) in [(Out::Rodata, rodata), (Out::Text, text), (Out::RelRo, relro)] {
        if !members[out as usize].is_empty() {
            sections.push(atom_section(out, range));
        }
    }
    let dynamic_range = (dynamic_addr, dynamic_addr + DYN_SIZE * ndynamic);
    sections.push(alloc(".dynamic", SHT_DYNAMIC, SHF_WRITE, dynamic_range, 8, DYN_SIZE, Some(".dynstr")));
    if !got.is_empty() {
        sections.push(alloc(".got", SHT_PROGBITS, SHF_WRITE, (got_addr, got_addr + 8 * got.len() as u64), 8, 8, None));
    }
    for (out, range) in [(Out::Data, data), (Out::Bss, bss)] {
        if !members[out as usize].is_empty() {
            sections.push(atom_section(out, range));
        }
    }
    let unloaded = |name, kind, link, entsize| Section {
        name,
        kind,
        flags: 0,
        addr: 0,
        offset: 0,
        size: 0,
        link,
        info: 0,
        align: if kind == SHT_SYMTAB { 8 } else { 1 },
        entsize,
    };
    sections.push(unloaded(".symtab", SHT_SYMTAB, Some(".strtab"), SYM_SIZE));
    sections.push(unloaded(".strtab", SHT_STRTAB, None, 0));
    sections.push(unloaded(".shstrtab", SHT_STRTAB, None, 0));

    // Symbol table: every placed atom and label, so debuggers and
    // disassemblers show routine names. All local except the entry point.
    // Imports stay in `.dynsym` only: as undefined symbols of value 0 here,
    // LLVM's objdump would name address 0 (`__ehdr_start`) after one.
    let Sym::Local { atom: entry_atom, offset: entry_offset } = resolved.entry else {
        unreachable!("the entry is defined")
    };
    let entry_addr = atom_addr[entry_atom] + entry_offset;
    // GNU ld's names for the header and the dynamic tables come first, so a
    // disassembler annotates GOT loads as `_GLOBAL_OFFSET_TABLE_+0x8` rather
    // than as an offset from the last routine.
    let mut locals = vec![
        Symbol { name: EHDR_START, info: STT_NOTYPE, shndx: 1, value: IMAGE_BASE, size: 0 },
        Symbol {
            name: "_DYNAMIC",
            info: STT_OBJECT,
            shndx: section_index(&sections, ".dynamic"),
            value: dynamic_addr,
            size: DYN_SIZE * ndynamic,
        },
    ];
    if !got.is_empty() {
        locals.push(Symbol {
            name: "_GLOBAL_OFFSET_TABLE_",
            info: STT_OBJECT,
            shndx: section_index(&sections, ".got"),
            value: got_addr,
            size: 8 * got.len() as u64,
        });
    }
    let mut globals = Vec::new();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        let out = Out::of(atom);
        let kind = if out == Out::Text { STT_FUNC } else { STT_OBJECT };
        let shndx = section_index(&sections, out.name());
        let names = std::iter::once((atom.name.as_str(), 0, atom.size))
            .chain(atom.labels.iter().map(|(name, offset)| (name.as_str(), *offset, 0)));
        for (name, offset, size) in names {
            let value = atom_addr[index] + offset;
            if name == options.entry {
                globals.push(Symbol { name, info: (STB_GLOBAL << 4) | kind, shndx, value, size });
            } else {
                locals.push(Symbol { name, info: (STB_LOCAL << 4) | kind, shndx, value, size });
            }
        }
    }
    locals.sort_by(|a, b| (a.value, a.name).cmp(&(b.value, b.name)));
    let mut strtab = vec![0u8];
    let mut symtab = vec![0u8; SYM_SIZE as usize];
    for symbol in locals.iter().chain(&globals) {
        let name = add_string(&mut strtab, symbol.name);
        put_symbol(&mut symtab, name, symbol.info, symbol.shndx, symbol.value, symbol.size);
    }
    let mut shstrtab = vec![0u8];
    let section_names: Vec<u32> = sections.iter().map(|s| add_string(&mut shstrtab, s.name)).collect();

    let symtab_off = file_end.next_multiple_of(8);
    let strtab_off = symtab_off + symtab.len() as u64;
    let shstrtab_off = strtab_off + strtab.len() as u64;
    let shoff = (shstrtab_off + shstrtab.len() as u64).next_multiple_of(8);
    let tables = [(symtab_off, symtab.len()), (strtab_off, strtab.len()), (shstrtab_off, shstrtab.len())];
    let first_table = sections.len() - tables.len();
    for (section, (offset, size)) in sections[first_table..].iter_mut().zip(tables) {
        section.offset = offset;
        section.size = size as u64;
    }
    sections[first_table].info = 1 + locals.len() as u32; // .symtab: index of the first global

    // ELF header and program headers.
    let shnum = sections.len() as u16 + 1;
    let mut head = Vec::with_capacity((EHDR_SIZE + PHDR_SIZE * PHNUM) as usize);
    head.extend_from_slice(&[0x7f, b'E', b'L', b'F', ELFCLASS64, ELFDATA2LSB, EV_CURRENT, ELFOSABI_NONE]);
    head.extend_from_slice(&[0; 8]); // ABI version and padding
    put16(&mut head, ET_DYN);
    put16(&mut head, arch.machine);
    put32(&mut head, u32::from(EV_CURRENT));
    put64(&mut head, entry_addr);
    put64(&mut head, EHDR_SIZE); // e_phoff
    put64(&mut head, shoff);
    put32(&mut head, 0); // e_flags
    put16(&mut head, EHDR_SIZE as u16);
    put16(&mut head, PHDR_SIZE as u16);
    put16(&mut head, PHNUM as u16);
    put16(&mut head, SHDR_SIZE as u16);
    put16(&mut head, shnum);
    put16(&mut head, shnum - 1); // .shstrtab comes last

    let phdrs_size = PHDR_SIZE * PHNUM;
    let program_header = |out: &mut Vec<u8>, kind: u32, flags: u32, segment: Segment, align: u64| {
        put32(out, kind);
        put32(out, flags);
        put64(out, segment.offset);
        put64(out, segment.vaddr);
        put64(out, segment.vaddr); // p_paddr
        put64(out, segment.filesz);
        put64(out, segment.memsz);
        put64(out, align);
    };
    let span = |addr: u64, size: u64| Segment { offset: file_offset(addr), vaddr: addr, filesz: size, memsz: size };
    let relro_size = relro_end - w_seg.vaddr;
    program_header(&mut head, PT_PHDR, PF_R, span(EHDR_SIZE, phdrs_size), 8);
    program_header(&mut head, PT_INTERP, PF_R, span(interp_addr, interp_size), 1);
    program_header(&mut head, PT_LOAD, PF_R, r_seg, arch.max_page);
    program_header(&mut head, PT_LOAD, PF_R | PF_X, x_seg, arch.max_page);
    program_header(&mut head, PT_LOAD, PF_R | PF_W, w_seg, arch.max_page);
    program_header(&mut head, PT_DYNAMIC, PF_R | PF_W, span(dynamic_addr, DYN_SIZE * ndynamic), 8);
    program_header(&mut head, PT_GNU_RELRO, PF_R, span(w_seg.vaddr, relro_size), 1);
    let no_segment = Segment { offset: 0, vaddr: 0, filesz: 0, memsz: 0 };
    program_header(&mut head, PT_GNU_STACK, PF_R | PF_W, no_segment, 16);
    debug_assert_eq!(head.len() as u64, EHDR_SIZE + phdrs_size);
    image[..head.len()].copy_from_slice(&head);

    // The unloaded tail.
    image.resize(symtab_off as usize, 0);
    image.extend_from_slice(&symtab);
    image.extend_from_slice(&strtab);
    image.extend_from_slice(&shstrtab);
    image.resize(shoff as usize, 0);
    image.extend_from_slice(&[0; SHDR_SIZE as usize]);
    for (section, &name) in sections.iter().zip(&section_names) {
        put32(&mut image, name);
        put32(&mut image, section.kind);
        put64(&mut image, section.flags);
        put64(&mut image, section.addr);
        put64(&mut image, section.offset);
        put64(&mut image, section.size);
        put32(&mut image, section.link.map_or(0, |link| u32::from(section_index(&sections, link))));
        put32(&mut image, section.info);
        put64(&mut image, section.align);
        put64(&mut image, section.entsize);
    }

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

/// Index of the section header called `name` (header 0 is the null one).
fn section_index(sections: &[Section], name: &str) -> u16 {
    sections.iter().position(|s| s.name == name).expect("the section exists") as u16 + 1
}

/// Address of a segment at file offset `offset` that follows a segment
/// ending at `prev_end`: congruent to `offset` modulo `max_page`, and past
/// the last `max_page` page of the previous segment, so the two never share
/// a page, whatever the kernel's page size.
fn next_segment(prev_end: u64, offset: u64, max_page: u64) -> u64 {
    prev_end.next_multiple_of(max_page) + offset % max_page
}

/// Sonames for `DT_NEEDED`, in order of first use. `libc`, as the code
/// generator names the C library, needs both halves of glibc; ELF looks an
/// import up in every loaded library, so which half defines it does not
/// matter. Other libraries are named by their soname (`libfoo.so.1`).
fn needed_libraries<'a>(imports: &[&'a Import]) -> Result<Vec<&'a str>, LinkError> {
    let mut needed: Vec<&'a str> = Vec::new();
    for import in imports {
        if import.name.is_empty() || import.name.contains('\0') {
            return Err(LinkError::Malformed(format!("import name {:?} is empty or holds a NUL byte", import.name)));
        }
        let library = import.library.as_str();
        let sonames: Vec<&'a str> = match library {
            "libc" => GLIBC.to_vec(),
            "libm" => vec![GLIBC[1]],
            _ if is_soname(library) => vec![library],
            _ => {
                return Err(LinkError::Unsupported(format!(
                    "`{}` is imported from `{library}`, which is not a Linux shared library; \
                     name it `libc` or by a soname such as `libfoo.so.1`",
                    import.name
                )));
            }
        };
        for soname in sonames {
            if !needed.contains(&soname) {
                needed.push(soname);
            }
        }
    }
    Ok(needed)
}

/// Whether `library` names a shared object: `libfoo.so`, `libfoo.so.1`,
/// or a path to one.
fn is_soname(library: &str) -> bool {
    let file = library.rsplit('/').next().unwrap_or(library);
    !library.contains('\0') && (file.ends_with(".so") || file.contains(".so."))
}

/// The SysV `DT_HASH` table over the dynamic symbols: the null symbol, then
/// one per import. ld.so needs a hash table to search the executable, even
/// one that defines nothing it would find.
fn sysv_hash_table(imports: &[&Import]) -> Vec<u8> {
    let nchain = imports.len() + 1;
    // The bucket counts GNU ld picks from: the largest not above the number
    // of symbols.
    const BUCKETS: [u32; 16] = [1, 3, 17, 37, 67, 97, 131, 197, 263, 521, 1031, 2053, 4099, 8209, 16411, 32771];
    let nbucket = BUCKETS.iter().copied().take_while(|&b| b as usize <= nchain).last().unwrap_or(1);
    let mut buckets = vec![0u32; nbucket as usize];
    let mut chains = vec![0u32; nchain];
    for (i, import) in imports.iter().enumerate() {
        let symbol = i as u32 + 1;
        let bucket = (elf_hash(import.name.as_bytes()) % nbucket) as usize;
        chains[symbol as usize] = buckets[bucket];
        buckets[bucket] = symbol;
    }
    let mut out = Vec::with_capacity(4 * (2 + buckets.len() + chains.len()));
    put32(&mut out, nbucket);
    put32(&mut out, nchain as u32);
    for value in buckets.into_iter().chain(chains) {
        put32(&mut out, value);
    }
    out
}

/// The System V ABI's ELF hash function.
fn elf_hash(name: &[u8]) -> u32 {
    let mut h: u32 = 0;
    for &c in name {
        h = (h << 4).wrapping_add(u32::from(c));
        let g = h & 0xf000_0000;
        h ^= g >> 24;
        h &= !g;
    }
    h
}

/// Appends `text` and a NUL to a string table; returns its offset.
fn add_string(table: &mut Vec<u8>, text: &str) -> u32 {
    let offset = table.len() as u32;
    table.extend_from_slice(text.as_bytes());
    table.push(0);
    offset
}

fn put_symbol(out: &mut Vec<u8>, name: u32, info: u8, shndx: u16, value: u64, size: u64) {
    put32(out, name);
    out.push(info);
    out.push(0); // st_other: default visibility
    put16(out, shndx);
    put64(out, value);
    put64(out, size);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link;
    use odin_asm::object::Object;
    use odin_asm::object::RelocKind::*;

    fn u16_at(data: &[u8], at: usize) -> u16 {
        u16::from_le_bytes(data[at..at + 2].try_into().unwrap())
    }

    fn u32_at(data: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(data[at..at + 4].try_into().unwrap())
    }

    fn u64_at(data: &[u8], at: usize) -> u64 {
        u64::from_le_bytes(data[at..at + 8].try_into().unwrap())
    }

    fn cstr(data: &[u8], at: usize) -> String {
        String::from_utf8(data[at..].iter().take_while(|&&b| b != 0).copied().collect()).unwrap()
    }

    #[derive(Clone, Copy, Debug)]
    struct Phdr {
        kind: u32,
        flags: u32,
        offset: u64,
        vaddr: u64,
        paddr: u64,
        filesz: u64,
        memsz: u64,
        align: u64,
    }

    fn phdrs(file: &[u8]) -> Vec<Phdr> {
        let (phoff, phnum) = (u64_at(file, 32) as usize, u16_at(file, 56) as usize);
        (0..phnum)
            .map(|i| {
                let at = phoff + PHDR_SIZE as usize * i;
                Phdr {
                    kind: u32_at(file, at),
                    flags: u32_at(file, at + 4),
                    offset: u64_at(file, at + 8),
                    vaddr: u64_at(file, at + 16),
                    paddr: u64_at(file, at + 24),
                    filesz: u64_at(file, at + 32),
                    memsz: u64_at(file, at + 40),
                    align: u64_at(file, at + 48),
                }
            })
            .collect()
    }

    fn loads(file: &[u8]) -> Vec<Phdr> {
        phdrs(file).into_iter().filter(|p| p.kind == PT_LOAD).collect()
    }

    /// File offset of the byte the loader maps at `addr`.
    fn mapped(file: &[u8], addr: u64) -> usize {
        let load = loads(file)
            .into_iter()
            .find(|l| l.vaddr <= addr && addr < l.vaddr + l.filesz)
            .unwrap_or_else(|| panic!("{addr:#x} is not file-backed"));
        (load.offset + addr - load.vaddr) as usize
    }

    #[derive(Debug)]
    struct Shdr {
        name: String,
        kind: u32,
        flags: u64,
        addr: u64,
        offset: u64,
        size: u64,
        link: u32,
        info: u32,
        align: u64,
        entsize: u64,
    }

    fn shdrs(file: &[u8]) -> Vec<Shdr> {
        let (shoff, shnum, shstrndx) = (u64_at(file, 40) as usize, u16_at(file, 60), u16_at(file, 62));
        let header = |i: u16| shoff + SHDR_SIZE as usize * usize::from(i);
        let names = u64_at(file, header(shstrndx) + 24) as usize;
        (0..shnum)
            .map(|i| {
                let at = header(i);
                Shdr {
                    name: cstr(file, names + u32_at(file, at) as usize),
                    kind: u32_at(file, at + 4),
                    flags: u64_at(file, at + 8),
                    addr: u64_at(file, at + 16),
                    offset: u64_at(file, at + 24),
                    size: u64_at(file, at + 32),
                    link: u32_at(file, at + 40),
                    info: u32_at(file, at + 44),
                    align: u64_at(file, at + 48),
                    entsize: u64_at(file, at + 56),
                }
            })
            .collect()
    }

    fn index(sections: &[Shdr], name: &str) -> usize {
        sections.iter().position(|s| s.name == name).unwrap_or_else(|| panic!("no {name}"))
    }

    /// `.dynamic` as ld.so finds it, through PT_DYNAMIC.
    fn dynamic(file: &[u8]) -> Vec<(u64, u64)> {
        let header = phdrs(file).into_iter().find(|p| p.kind == PT_DYNAMIC).unwrap();
        let at = mapped(file, header.vaddr);
        let entries: Vec<(u64, u64)> = (0..(header.filesz / DYN_SIZE) as usize)
            .map(|i| (u64_at(file, at + 16 * i), u64_at(file, at + 16 * i + 8)))
            .collect();
        assert_eq!(entries.last(), Some(&(DT_NULL, 0)));
        entries
    }

    fn tag(entries: &[(u64, u64)], tag: u64) -> u64 {
        entries.iter().find(|e| e.0 == tag).unwrap_or_else(|| panic!("no tag {tag:#x}")).1
    }

    /// Dynamic symbols as (name, st_info, st_shndx), counted by the hash
    /// table's `nchain` as ld.so does.
    fn dynsyms(file: &[u8]) -> Vec<(String, u8, u16)> {
        let entries = dynamic(file);
        let (symtab, strtab) = (tag(&entries, DT_SYMTAB), tag(&entries, DT_STRTAB));
        let nchain = u32_at(file, mapped(file, tag(&entries, DT_HASH)) + 4) as u64;
        (0..nchain)
            .map(|i| {
                let at = mapped(file, symtab + SYM_SIZE * i);
                let name = cstr(file, mapped(file, strtab + u64::from(u32_at(file, at))));
                (name, file[at + 4], u16_at(file, at + 6))
            })
            .collect()
    }

    /// Looks `name` up in `DT_HASH` the way ld.so does.
    fn hash_lookup(file: &[u8], name: &str) -> Option<u32> {
        let names = dynsyms(file);
        let hash = mapped(file, tag(&dynamic(file), DT_HASH));
        let nbucket = u32_at(file, hash);
        let nchain = u32_at(file, hash + 4) as usize;
        let mut symbol = u32_at(file, hash + 8 + 4 * (elf_hash(name.as_bytes()) % nbucket) as usize);
        while symbol != 0 {
            if names[symbol as usize].0 == name {
                return Some(symbol);
            }
            symbol = u32_at(file, hash + 8 + 4 * nbucket as usize + 4 * symbol as usize);
            assert!((symbol as usize) < nchain);
        }
        None
    }

    /// `.rela.dyn` as ld.so finds it: (offset, type, symbol, addend).
    fn relas(file: &[u8]) -> Vec<(u64, u32, u32, i64)> {
        let entries = dynamic(file);
        if !entries.iter().any(|e| e.0 == DT_RELA) {
            return Vec::new();
        }
        assert_eq!(tag(&entries, DT_RELAENT), RELA_SIZE);
        let at = mapped(file, tag(&entries, DT_RELA));
        (0..(tag(&entries, DT_RELASZ) / RELA_SIZE) as usize)
            .map(|i| {
                let r = at + RELA_SIZE as usize * i;
                let info = u64_at(file, r + 8);
                (u64_at(file, r), info as u32, (info >> 32) as u32, u64_at(file, r + 16) as i64)
            })
            .collect()
    }

    /// `.symtab` as (name, st_info, st_shndx, st_value, st_size).
    fn symtab(file: &[u8]) -> Vec<(String, u8, u16, u64, u64)> {
        let sections = shdrs(file);
        let table = &sections[index(&sections, ".symtab")];
        let strings = &sections[table.link as usize];
        (0..(table.size / SYM_SIZE) as usize)
            .map(|i| {
                let at = table.offset as usize + SYM_SIZE as usize * i;
                let name = cstr(file, strings.offset as usize + u32_at(file, at) as usize);
                (name, file[at + 4], u16_at(file, at + 6), u64_at(file, at + 8), u64_at(file, at + 16))
            })
            .collect()
    }

    fn libc(name: &str) -> Import {
        Import { name: name.to_string(), library: "libc".to_string() }
    }

    fn object(atoms: Vec<Atom>, imports: Vec<Import>) -> Vec<Object> {
        vec![Object { name: "test".to_string(), atoms, imports }]
    }

    fn x86(objects: &[Object]) -> Result<LinkedImage, LinkError> {
        link(objects, &LinkOptions::new(Target::X86_64Linux, "main", "test"))
    }

    fn arm64(objects: &[Object]) -> Result<LinkedImage, LinkError> {
        link(objects, &LinkOptions::new(Target::Aarch64Linux, "main", "test"))
    }

    /// Program headers every output has, whatever the architecture: the
    /// fixed list, loadable segments a loader with pages of up to
    /// `max_page` bytes accepts, and the RELRO and stack headers.
    fn check_program_headers(file: &[u8], max_page: u64) {
        let ph = phdrs(file);
        let kinds: Vec<u32> = ph.iter().map(|p| p.kind).collect();
        assert_eq!(kinds, [PT_PHDR, PT_INTERP, PT_LOAD, PT_LOAD, PT_LOAD, PT_DYNAMIC, PT_GNU_RELRO, PT_GNU_STACK]);
        let flags: Vec<u32> = ph.iter().map(|p| p.flags).collect();
        assert_eq!(flags, [PF_R, PF_R, PF_R, PF_R | PF_X, PF_R | PF_W, PF_R | PF_W, PF_R, PF_R | PF_W]);
        assert_eq!((ph[0].offset, ph[0].vaddr, ph[0].filesz), (EHDR_SIZE, EHDR_SIZE, PHDR_SIZE * PHNUM));

        let loads = loads(file);
        assert_eq!((loads[0].offset, loads[0].vaddr), (0, 0), "the headers are loaded at the base");
        for load in &loads {
            assert_eq!(load.align, max_page);
            assert_eq!(load.offset % FILE_PAGE, 0, "each segment starts a file page");
            assert_eq!(load.offset % max_page, load.vaddr % max_page, "{load:?}");
            assert_eq!(load.paddr, load.vaddr);
            assert!(load.filesz <= load.memsz);
            assert!(load.offset + load.filesz <= file.len() as u64);
        }
        for pair in loads.windows(2) {
            // No page of any size up to `max_page` holds two segments.
            let end = (pair[0].vaddr + pair[0].memsz).next_multiple_of(max_page);
            assert!(end <= pair[1].vaddr - pair[1].vaddr % max_page, "{pair:?}");
            assert!(pair[0].offset + pair[0].filesz <= pair[1].offset);
        }
        // Headers that describe loaded data lie inside one PT_LOAD, at the
        // matching offset.
        for header in ph.iter().filter(|p| matches!(p.kind, PT_PHDR | PT_INTERP | PT_DYNAMIC | PT_GNU_RELRO)) {
            let load = loads
                .iter()
                .find(|l| l.vaddr <= header.vaddr && header.vaddr + header.filesz <= l.vaddr + l.filesz)
                .unwrap_or_else(|| panic!("{header:?} is not loaded"));
            assert_eq!(header.offset - load.offset, header.vaddr - load.vaddr);
        }
        let (relro, rw) = (ph[6], loads[2]);
        assert_eq!((relro.offset, relro.vaddr), (rw.offset, rw.vaddr), "RELRO opens the writable segment");
        assert_eq!((relro.vaddr + relro.memsz) % FILE_PAGE, 0, "and ends on a page boundary");
        assert_eq!(relro.filesz, relro.memsz);
        assert_eq!((ph[7].filesz, ph[7].memsz), (0, 0));
    }

    /// Every allocated section lies in the PT_LOAD whose permissions match
    /// its flags, at the offset the loader maps it from; `.dynamic` is
    /// PT_DYNAMIC; the RELRO segment holds exactly the relocated read-only
    /// sections.
    fn check_sections(file: &[u8]) {
        let sections = shdrs(file);
        let ph = phdrs(file);
        assert_eq!(usize::from(u16_at(file, 62)), sections.len() - 1, "e_shstrndx");
        assert_eq!(sections.last().unwrap().name, ".shstrtab");
        for section in sections.iter().filter(|s| s.flags & SHF_ALLOC != 0) {
            let load = loads(file)
                .into_iter()
                .find(|l| l.vaddr <= section.addr && section.addr + section.size <= l.vaddr + l.memsz)
                .unwrap_or_else(|| panic!("{section:?} is not loaded"));
            assert_eq!(section.flags & SHF_WRITE != 0, load.flags & PF_W != 0, "{}", section.name);
            assert_eq!(section.flags & SHF_EXECINSTR != 0, load.flags & PF_X != 0, "{}", section.name);
            assert_eq!(section.addr % section.align, 0, "{}", section.name);
            if section.kind != SHT_NOBITS {
                assert_eq!(section.offset - load.offset, section.addr - load.vaddr, "{}", section.name);
                assert!(section.addr + section.size <= load.vaddr + load.filesz, "{}", section.name);
            }
        }
        let relro = ph[6];
        for section in sections.iter().filter(|s| s.flags & SHF_WRITE != 0) {
            let inside = section.addr >= relro.vaddr && section.addr + section.size <= relro.vaddr + relro.memsz;
            let expected = matches!(section.name.as_str(), ".data.rel.ro" | ".dynamic" | ".got");
            assert_eq!(inside, expected, "{} and RELRO", section.name);
        }
        let dynamic_section = &sections[index(&sections, ".dynamic")];
        assert_eq!((dynamic_section.addr, dynamic_section.size), (ph[5].vaddr, ph[5].filesz));
        let link = |name: &str| sections[index(&sections, name)].link as usize;
        assert_eq!(link(".hash"), index(&sections, ".dynsym"));
        assert_eq!(link(".dynsym"), index(&sections, ".dynstr"));
        assert_eq!(link(".dynamic"), index(&sections, ".dynstr"));
        assert_eq!(link(".symtab"), index(&sections, ".strtab"));
        assert_eq!(sections[index(&sections, ".dynsym")].entsize, SYM_SIZE);
        assert_eq!(sections[index(&sections, ".symtab")].entsize, SYM_SIZE);
        let entries = dynamic(file);
        assert_eq!(tag(&entries, DT_HASH), sections[index(&sections, ".hash")].addr);
        assert_eq!(tag(&entries, DT_SYMTAB), sections[index(&sections, ".dynsym")].addr);
        assert_eq!(tag(&entries, DT_STRTAB), sections[index(&sections, ".dynstr")].addr);
        assert_eq!(tag(&entries, DT_STRSZ), sections[index(&sections, ".dynstr")].size);
        if let Some(rela) = sections.iter().find(|s| s.name == ".rela.dyn") {
            assert_eq!(rela.link as usize, index(&sections, ".dynsym"));
            assert_eq!((tag(&entries, DT_RELA), tag(&entries, DT_RELASZ)), (rela.addr, rela.size));
        }
    }

    /// One atom of every kind, odd alignments, pointer tables in read-only
    /// data and in data, `__ehdr_start`, imports used and unused.
    fn sample() -> Vec<Object> {
        object(
            vec![
                Atom::new("main", SectionKind::Text, 1, vec![0x90; 24])
                    .reloc(0, X86GotPc32, "write", -4)
                    .reloc(4, X86Pc32, "helper", -4)
                    .reloc(8, X86Pc32, "vtable", -4)
                    .reloc(12, X86Pc32, "counter", -4)
                    .reloc(16, X86Pc32, "jump_table", -4)
                    .reloc(20, X86Pc32, EHDR_START, -4),
                Atom::new("helper", SectionKind::Text, 16, vec![0x8d, 0, 0, 0, 0, 0xc3])
                    .reloc(1, X86Pc32, "text_str", -4),
                Atom::new("text_str", SectionKind::ReadOnly, 1, b"hi\0".to_vec()),
                Atom::new("jump_table", SectionKind::ReadOnly, 8, vec![0; 16])
                    .reloc(0, Abs64, "helper", 0)
                    .reloc(8, Abs64, "main", 3),
                Atom {
                    labels: vec![("vtable_end".to_string(), 24)],
                    ..Atom::new("vtable", SectionKind::Data, 8, vec![0; 24])
                }
                .reloc(0, Abs64, "text_str", 1)
                .reloc(8, Abs64, "counter", 0)
                .reloc(16, Abs64, "exit", 16),
                Atom::bss("counter", 0x2345, 32),
                Atom::new("dead", SectionKind::Text, 1, vec![0xff, 0x15, 0, 0, 0, 0])
                    .reloc(2, X86GotPc32, "unused", -4),
            ],
            vec![libc("write"), libc("exit"), libc("unused")],
        )
    }

    #[test]
    fn x86_64_layout() {
        let image = x86(&sample()).unwrap();
        let file = &image.bytes;
        let sym = |name: &str| image.symbols[name];
        assert_eq!(image.image_base, 0);

        // ELF header.
        assert_eq!(&file[..16], &[0x7f, b'E', b'L', b'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!((u16_at(file, 16), u16_at(file, 18), u32_at(file, 20)), (ET_DYN, EM_X86_64, 1));
        assert_eq!(u64_at(file, 24), sym("main"), "e_entry");
        assert_eq!((u64_at(file, 32), u32_at(file, 48)), (EHDR_SIZE, 0), "e_phoff, e_flags");
        assert_eq!([u16_at(file, 52), u16_at(file, 54), u16_at(file, 56), u16_at(file, 58)], [64, 56, 8, 64]);
        check_program_headers(file, 0x1000);
        check_sections(file);
        let ph = phdrs(file);
        let interp = mapped(file, ph[1].vaddr);
        assert_eq!(&file[interp..interp + ph[1].filesz as usize], b"/lib64/ld-linux-x86-64.so.2\0");
        // x86-64 pages are 4 KiB: addresses equal file offsets.
        assert!(loads(file).iter().all(|l| l.offset == l.vaddr));

        let sections = shdrs(file);
        let names: Vec<&str> = sections.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(
            names,
            [
                "",
                ".interp",
                ".hash",
                ".dynsym",
                ".dynstr",
                ".rela.dyn",
                ".rodata",
                ".text",
                ".data.rel.ro",
                ".dynamic",
                ".got",
                ".data",
                ".bss",
                ".symtab",
                ".strtab",
                ".shstrtab"
            ]
        );
        let section = |name: &str| &sections[index(&sections, name)];
        assert_eq!(section(".text").align, 16);
        assert_eq!(section(".got").size, 8, "only write goes through the GOT");
        assert_eq!((section(".bss").kind, section(".bss").align), (SHT_NOBITS, 32));
        let rw = loads(file)[2];
        assert_eq!(rw.memsz - rw.filesz, section(".bss").addr + section(".bss").size - (rw.vaddr + rw.filesz));

        // Atoms: placement, alignment, smart linking.
        assert_eq!(sym("main"), section(".text").addr);
        assert_eq!(sym("helper"), (sym("main") + 24).next_multiple_of(16));
        assert_eq!(sym("text_str"), section(".rodata").addr);
        assert_eq!(sym("jump_table"), section(".data.rel.ro").addr);
        assert_eq!(sym("vtable"), section(".data").addr);
        assert_eq!(sym("vtable_end"), sym("vtable") + 24);
        assert_eq!(sym("counter"), section(".bss").addr);
        assert_eq!(sym("counter") % 32, 0);
        assert_eq!(image.symbols.len(), 7);
        assert!(!image.symbols.contains_key("dead"));
        assert!(!file.windows(7).any(|w| w == b"unused\0"), "unused imports leave no trace");
        let gap = mapped(file, sym("main") + 24)..mapped(file, sym("helper"));
        assert!(!gap.is_empty() && file[gap].iter().all(|&b| b == 0xcc), "int3 between code atoms");

        // Dynamic section.
        let entries = dynamic(file);
        let tags: Vec<u64> = entries.iter().map(|e| e.0).collect();
        assert_eq!(
            tags,
            [
                DT_NEEDED,
                DT_NEEDED,
                DT_HASH,
                DT_STRTAB,
                DT_SYMTAB,
                DT_STRSZ,
                DT_SYMENT,
                DT_DEBUG,
                DT_RELA,
                DT_RELASZ,
                DT_RELAENT,
                DT_FLAGS,
                DT_FLAGS_1,
                DT_RELACOUNT,
                DT_NULL
            ]
        );
        let strtab = tag(&entries, DT_STRTAB);
        let needed: Vec<String> =
            entries.iter().filter(|e| e.0 == DT_NEEDED).map(|e| cstr(file, mapped(file, strtab + e.1))).collect();
        assert_eq!(needed, GLIBC);
        assert_eq!(tag(&entries, DT_SYMENT), SYM_SIZE);
        assert_eq!(tag(&entries, DT_DEBUG), 0);
        assert_eq!(tag(&entries, DT_FLAGS), DF_BIND_NOW);
        assert_eq!(tag(&entries, DT_FLAGS_1), DF_1_NOW | DF_1_PIE);

        // Dynamic symbols: the imports in order of first use, undefined.
        let undefined = (STB_GLOBAL << 4) | STT_NOTYPE;
        assert_eq!(
            dynsyms(file),
            [("".to_string(), 0, 0), ("write".to_string(), undefined, 0), ("exit".to_string(), undefined, 0)]
        );
        assert_eq!(hash_lookup(file, "write"), Some(1));
        assert_eq!(hash_lookup(file, "exit"), Some(2));
        assert_eq!(hash_lookup(file, "main"), None, "nothing is exported");

        // Relocations: RELATIVE first, counted by DT_RELACOUNT.
        let got = section(".got").addr;
        assert_eq!(
            relas(file),
            [
                (sym("jump_table"), R_X86_64_RELATIVE, 0, sym("helper") as i64),
                (sym("jump_table") + 8, R_X86_64_RELATIVE, 0, sym("main") as i64 + 3),
                (sym("vtable"), R_X86_64_RELATIVE, 0, sym("text_str") as i64 + 1),
                (sym("vtable") + 8, R_X86_64_RELATIVE, 0, sym("counter") as i64),
                (got, R_X86_64_GLOB_DAT, 1, 0),
                (sym("vtable") + 16, R_X86_64_64, 2, 16),
            ]
        );
        assert_eq!(tag(&entries, DT_RELACOUNT), 4);
        // Fields hold unslid values (the RELATIVE addend); ld.so fills the rest.
        for (offset, kind, _, addend) in relas(file) {
            let expected = if kind == R_X86_64_RELATIVE { addend as u64 } else { 0 };
            assert_eq!(u64_at(file, mapped(file, offset)), expected, "{offset:#x}");
        }
        let rel32 = |name: &str, offset: u64| i64::from(u32_at(file, mapped(file, sym(name) + offset)) as i32);
        assert_eq!(rel32("helper", 1), sym("text_str") as i64 - (sym("helper") as i64 + 5));
        assert_eq!(rel32("main", 0), got as i64 - (sym("main") as i64 + 4), "GOT slot");
        assert_eq!(rel32("main", 4), sym("helper") as i64 - (sym("main") as i64 + 8));
        assert_eq!(rel32("main", 12), sym("counter") as i64 - (sym("main") as i64 + 16));
        assert_eq!(rel32("main", 20), -(sym("main") as i64 + 24), "__ehdr_start is the header");
        let helper = mapped(file, sym("helper"));
        assert_eq!((file[helper], file[helper + 5]), (0x8d, 0xc3), "bytes around the field are kept");

        // Symbol table: locals sorted by address, then the entry point.
        // Imports live in `.dynsym` only.
        let symbols = symtab(file);
        let first_global = section(".symtab").info as usize;
        assert!(symbols[1..first_global].iter().all(|s| s.1 >> 4 == STB_LOCAL));
        assert_eq!(first_global, symbols.len() - 1, "the entry point is the only global");
        assert!(symbols[1..first_global].windows(2).all(|w| w[0].3 <= w[1].3), "sorted by address");
        let entry = |name: &str| symbols.iter().find(|s| s.0 == name).unwrap_or_else(|| panic!("no {name}")).clone();
        let shndx = |name: &str| index(&sections, name) as u16;
        let func = |bind: u8| (bind << 4) | STT_FUNC;
        let object = (STB_LOCAL << 4) | STT_OBJECT;
        assert_eq!(entry("main"), ("main".to_string(), func(STB_GLOBAL), shndx(".text"), sym("main"), 24));
        assert_eq!(entry("helper"), ("helper".to_string(), func(STB_LOCAL), shndx(".text"), sym("helper"), 6));
        assert_eq!(entry("text_str").1, object);
        assert_eq!(entry("jump_table").2, shndx(".data.rel.ro"));
        assert_eq!(entry("vtable_end"), ("vtable_end".to_string(), object, shndx(".data"), sym("vtable") + 24, 0));
        assert_eq!(entry("counter"), ("counter".to_string(), object, shndx(".bss"), sym("counter"), 0x2345));
        assert_eq!(entry(EHDR_START), (EHDR_START.to_string(), STT_NOTYPE, 1, 0, 0));
        assert_eq!(entry("_DYNAMIC").3, section(".dynamic").addr);
        assert_eq!(entry("_GLOBAL_OFFSET_TABLE_").3, got);
        assert!(symbols.iter().all(|s| s.2 != SHN_UNDEF || s.0.is_empty()), "nothing undefined");
        for (name, &address) in &image.symbols {
            assert_eq!(entry(name).3, address, "{name}");
        }
        assert_eq!(symbols.len(), 1 + 3 + 7, "null, header and tables, atoms and labels");
    }

    #[test]
    fn arm64_layout_allows_64k_pages() {
        let objects = object(
            vec![
                Atom::new("main", SectionKind::Text, 1, vec![0; 16])
                    .reloc(0, Arm64GotPage21, "exit", 0)
                    .reloc(4, Arm64GotPageOff12, "exit", 0)
                    .reloc(8, Arm64Branch26, "f", 0)
                    .reloc(12, Arm64Page21, EHDR_START, 0),
                Atom::new("f", SectionKind::Text, 1, vec![0; 6]),
                Atom::new("g", SectionKind::Text, 1, vec![0xff; 4]).keep(),
                Atom::new("pointers", SectionKind::Data, 8, vec![0; 16])
                    .keep()
                    .reloc(0, Abs64, "exit", 8)
                    .reloc(8, Abs64, "g", 0),
            ],
            vec![libc("exit")],
        );
        let image = arm64(&objects).unwrap();
        let file = &image.bytes;
        let sym = |name: &str| image.symbols[name];
        assert_eq!(u16_at(file, 18), EM_AARCH64);
        check_program_headers(file, 0x1_0000);
        check_sections(file);
        let ph = phdrs(file);
        let interp = mapped(file, ph[1].vaddr);
        assert_eq!(&file[interp..interp + ph[1].filesz as usize], b"/lib/ld-linux-aarch64.so.1\0");
        // The file is not padded to 64 KiB; addresses are.
        let loads = loads(file);
        assert_eq!(loads[1].offset, 0x1000);
        assert_eq!(loads[1].vaddr, 0x1_1000);
        assert!(file.len() < 0x4000);

        // Code atoms are word aligned; padding is zero (udf #0).
        assert_eq!(u64_at(file, 24), sym("main"));
        assert_eq!(sym("main") % 4, 0);
        assert_eq!(sym("f"), sym("main") + 16);
        assert_eq!(sym("g"), sym("f") + 8);
        let code = mapped(file, sym("main"));
        assert_eq!(u32_at(file, code + 8), 2, "b f: two words forward");
        assert_eq!(&file[code + 22..code + 24], &[0, 0]);
        // ADRP/LDR reach the GOT slot; ADRP reaches back to the header.
        let page_delta = |insn: u32| {
            let imm = ((insn >> 29) & 3) | (((insn >> 5) & 0x7_ffff) << 2);
            i64::from((imm << 11) as i32 >> 11)
        };
        let sections = shdrs(file);
        let got = sections[index(&sections, ".got")].addr;
        assert_eq!(page_delta(u32_at(file, code)), (got >> 12) as i64 - (sym("main") >> 12) as i64);
        assert_eq!(u64::from((u32_at(file, code + 4) >> 10) & 0xfff) * 8, got & 0xfff);
        assert_eq!(page_delta(u32_at(file, code + 12)), -(((sym("main") + 12) >> 12) as i64));

        assert_eq!(
            relas(file),
            [
                (sym("pointers") + 8, R_AARCH64_RELATIVE, 0, sym("g") as i64),
                (got, R_AARCH64_GLOB_DAT, 1, 0),
                (sym("pointers"), R_AARCH64_ABS64, 1, 8),
            ]
        );
        assert_eq!(tag(&dynamic(file), DT_RELACOUNT), 1);
    }

    #[test]
    fn no_imports_no_libraries() {
        let image = x86(&object(vec![Atom::new("main", SectionKind::Text, 1, vec![0xc3])], vec![])).unwrap();
        let file = &image.bytes;
        check_program_headers(file, 0x1000);
        check_sections(file);
        let tags: Vec<u64> = dynamic(file).iter().map(|e| e.0).collect();
        assert_eq!(tags, [DT_HASH, DT_STRTAB, DT_SYMTAB, DT_STRSZ, DT_SYMENT, DT_DEBUG, DT_FLAGS, DT_FLAGS_1, DT_NULL]);
        let names: Vec<String> = shdrs(file).into_iter().map(|s| s.name).collect();
        assert_eq!(
            names,
            ["", ".interp", ".hash", ".dynsym", ".dynstr", ".text", ".dynamic", ".symtab", ".strtab", ".shstrtab"]
        );
        assert_eq!(dynsyms(file), [("".to_string(), 0, 0)]);
        let rw = loads(file)[2];
        assert_eq!((rw.filesz, rw.memsz), (0x1000, 0x1000), ".dynamic, padded to the end of RELRO");
    }

    #[test]
    fn local_got_slots_are_relative() {
        let objects = object(
            vec![
                Atom::new("main", SectionKind::Text, 1, vec![0; 16])
                    .reloc(2, X86GotPc32, "value", -4)
                    .reloc(8, X86GotPc32, EHDR_START, -4),
                Atom::new("value", SectionKind::Data, 8, vec![7; 8]),
            ],
            vec![],
        );
        let image = x86(&objects).unwrap();
        let file = &image.bytes;
        let sections = shdrs(file);
        let got = &sections[index(&sections, ".got")];
        assert_eq!(got.size, 16);
        assert_eq!(
            relas(file),
            [(got.addr, R_X86_64_RELATIVE, 0, image.symbols["value"] as i64), (got.addr + 8, R_X86_64_RELATIVE, 0, 0)]
        );
        assert_eq!(u64_at(file, got.offset as usize), image.symbols["value"]);
        assert_eq!(tag(&dynamic(file), DT_RELACOUNT), 2);
        assert!(!dynamic(file).iter().any(|e| e.0 == DT_NEEDED));
    }

    /// Links a `main` reaching each `(name, library)` import through the
    /// GOT, and returns the DT_NEEDED sonames.
    fn needed_of(imports: &[(&str, &str)]) -> Result<Vec<String>, LinkError> {
        let mut main = Atom::new("main", SectionKind::Text, 1, vec![0; 4 * imports.len()]);
        for (i, (name, _)) in imports.iter().enumerate() {
            main = main.reloc(4 * i as u32, X86GotPc32, *name, -4);
        }
        let imports = imports
            .iter()
            .map(|(name, library)| Import { name: name.to_string(), library: library.to_string() })
            .collect();
        let file = x86(&object(vec![main], imports))?.bytes;
        let entries = dynamic(&file);
        let strtab = tag(&entries, DT_STRTAB);
        Ok(entries.iter().filter(|e| e.0 == DT_NEEDED).map(|e| cstr(&file, mapped(&file, strtab + e.1))).collect())
    }

    #[test]
    fn libraries_become_needed_sonames() {
        assert_eq!(needed_of(&[]).unwrap(), Vec::<String>::new());
        assert_eq!(needed_of(&[("cos", "libm")]).unwrap(), ["libm.so.6"]);
        assert_eq!(needed_of(&[("write", "libc"), ("cos", "libc"), ("sin", "libm")]).unwrap(), GLIBC);
        assert_eq!(
            needed_of(&[("XOpenDisplay", "libX11.so.6"), ("cos", "libm"), ("write", "libc")]).unwrap(),
            ["libX11.so.6", "libm.so.6", "libc.so.6"]
        );
        assert_eq!(needed_of(&[("f", "/opt/odin/lib/libodin.so")]).unwrap(), ["/opt/odin/lib/libodin.so"]);
        for library in ["/usr/lib/libSystem.B.dylib", "c", "libc.dylib", "libfoo.a", ""] {
            assert!(
                matches!(needed_of(&[("write", library)]), Err(LinkError::Unsupported(_))),
                "{library:?} is not a soname"
            );
        }
        assert!(matches!(needed_of(&[("wr\0ite", "libc")]), Err(LinkError::Malformed(_))));
    }

    #[test]
    fn hash_table_finds_every_import() {
        let names: Vec<String> = (0..40).map(|i| format!("import_{i}")).collect();
        let mut main = Atom::new("main", SectionKind::Text, 1, vec![0; 4 * names.len()]);
        for (i, name) in names.iter().enumerate() {
            main = main.reloc(4 * i as u32, X86GotPc32, name, -4);
        }
        let imports = names.iter().map(|n| libc(n)).collect();
        let file = x86(&object(vec![main], imports)).unwrap().bytes;
        let hash = mapped(&file, tag(&dynamic(&file), DT_HASH));
        assert_eq!((u32_at(&file, hash), u32_at(&file, hash + 4)), (37, 41), "nbucket, nchain");
        for (i, name) in names.iter().enumerate() {
            assert_eq!(hash_lookup(&file, name), Some(i as u32 + 1), "{name}");
        }
        assert_eq!(hash_lookup(&file, "import_40"), None);
    }

    #[test]
    fn elf_hash_matches_the_abi() {
        assert_eq!(elf_hash(b""), 0);
        assert_eq!(elf_hash(b"printf"), 0x0779_05a6);
        assert_eq!(elf_hash(b"exit"), 0x0006_cf04);
        // Long enough for the top nibble to fold back in.
        assert_eq!(elf_hash(b"__libc_start_main"), 0x0177_ff8e);
    }

    #[test]
    fn output_is_deterministic() {
        assert_eq!(x86(&sample()).unwrap(), x86(&sample()).unwrap());
    }

    #[test]
    fn rejected_input() {
        let unsupported = |result: Result<LinkedImage, LinkError>| matches!(result, Err(LinkError::Unsupported(_)));
        let main = || Atom::new("main", SectionKind::Text, 1, vec![0; 8]);
        let write = || vec![libc("write")];
        // Imports are reached through the GOT only: no PLT.
        assert!(unsupported(x86(&object(vec![main().reloc(0, X86Pc32, "write", -4)], write()))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, Arm64Branch26, "write", 0)], write()))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, Arm64Page21, "write", 0)], write()))));
        // No text relocations.
        assert!(unsupported(x86(&object(vec![main().reloc(0, Abs64, "main", 0)], vec![]))));
        // Relocations of the other architecture.
        assert!(unsupported(x86(&object(vec![main().reloc(0, Arm64Branch26, "main", 0)], vec![]))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, X86Pc32, "main", 0)], vec![]))));
        assert!(unsupported(arm64(&object(vec![main().reloc(0, X86GotPc32, "write", -4)], write()))));
        // The entry point must be code.
        assert!(unsupported(x86(&object(vec![Atom::new("main", SectionKind::Data, 1, vec![0; 8])], vec![]))));
        // Alignment up to a page: 4 KiB on x86-64, 64 KiB on aarch64.
        let aligned =
            |align: u32| object(vec![main(), Atom::new("big", SectionKind::Data, align, vec![0; 8]).keep()], vec![]);
        assert!(unsupported(x86(&aligned(0x2000))));
        assert!(arm64(&aligned(0x1_0000)).is_ok());
        assert!(unsupported(arm64(&aligned(0x2_0000))));
        // `__ehdr_start` belongs to the linker.
        let duplicate = Some(LinkError::Duplicate { name: EHDR_START.to_string() });
        assert_eq!(
            x86(&object(vec![main(), Atom::new(EHDR_START, SectionKind::Data, 1, vec![0])], vec![])).err(),
            duplicate
        );
        assert_eq!(x86(&object(vec![main()], vec![libc(EHDR_START)])).err(), duplicate);
        // Undefined symbols.
        assert_eq!(
            x86(&object(vec![main().reloc(0, X86Pc32, "nowhere", -4)], vec![])).err(),
            Some(LinkError::Undefined { name: "nowhere".to_string(), referenced_from: "main".to_string() })
        );
        let options = LinkOptions::new(Target::X86_64Linux, "_start", "test");
        assert_eq!(
            link(&object(vec![main()], vec![]), &options).err(),
            Some(LinkError::Undefined { name: "_start".to_string(), referenced_from: "(entry point)".to_string() })
        );
        // The code-signing identifier is Darwin's business.
        assert!(link(&object(vec![main()], vec![]), &LinkOptions::new(Target::X86_64Linux, "main", "")).is_ok());
    }

    #[test]
    fn out_of_range_relocations() {
        let out_of_range = LinkError::RelocOutOfRange { atom: "main".to_string(), target: "far".to_string() };
        // x86-64: rel32 reaches +-2 GiB.
        let far_x86 = |gap: u64| {
            object(
                vec![
                    Atom::new("main", SectionKind::Text, 1, vec![0; 8]).reloc(0, X86Pc32, "far", -4),
                    Atom::bss("gap", gap, 8).keep(),
                    Atom::bss("far", 8, 8),
                ],
                vec![],
            )
        };
        assert!(x86(&far_x86(0x7000_0000)).is_ok());
        assert_eq!(x86(&far_x86(0x8000_0000)).err(), Some(out_of_range.clone()));
        // aarch64: B/BL reaches +-128 MiB.
        let far_arm = |gap: u64| {
            object(
                vec![
                    Atom::new("main", SectionKind::Text, 4, vec![0; 4]).reloc(0, Arm64Branch26, "far", 0),
                    Atom::bss("gap", gap, 8).keep(),
                    Atom::bss("far", 8, 8),
                ],
                vec![],
            )
        };
        assert!(arm64(&far_arm(0x700_0000)).is_ok());
        assert_eq!(arm64(&far_arm(0x800_0000)).err(), Some(out_of_range.clone()));
        // aarch64: an 8-byte load needs an 8-byte aligned target. `.data`
        // starts a page, so `far` sits 4 bytes into it.
        let misaligned = object(
            vec![
                Atom::new("main", SectionKind::Text, 4, vec![0; 4]).reloc(0, Arm64PageOff12 { scale: 3 }, "far", 0),
                Atom::new("pad", SectionKind::Data, 4, vec![0; 4]).keep(),
                Atom::new("far", SectionKind::Data, 4, vec![0; 4]),
            ],
            vec![],
        );
        assert_eq!(arm64(&misaligned).err(), Some(out_of_range));
    }
}
