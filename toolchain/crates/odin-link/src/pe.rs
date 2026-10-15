// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! PE32+ executable writer for x86-64 Windows.
//!
//! The output is a console program (`IMAGE_SUBSYSTEM_WINDOWS_CUI`) that the
//! loader may place anywhere (ASLR with high entropy), laid out like this:
//!
//! ```text
//! RVA 0       headers  DOS header and stub, "PE\0\0", COFF header, PE32+
//!                      optional header, section table (SizeOfHeaders 0x200,
//!                      or 0x400 with four sections)
//! RVA 0x1000  .text    r-x  code atoms, int3 (0xCC) between them
//!             .rdata   r--  IAT, GOT slots of local symbols, read-only
//!                           atoms, import directory, import lookup tables,
//!                           hint/name table, DLL names
//!             .data    rw-  data atoms, then bss atoms as a zero-filled tail
//!                           (VirtualSize > SizeOfRawData)
//!             .reloc   r--  base relocations (discardable)
//! ```
//!
//! Sections start on 4 KiB pages in memory and on 512-byte boundaries in the
//! file; empty ones are left out (`.text` never is).
//!
//! **Imports.** Imports are bound by name from their DLL (hint 0), grouped
//! by DLL name compared case-insensitively, as the loader compares them; the
//! first spelling seen is the one written. The IAT plays the role of the
//! Mach-O GOT: an `X86GotPc32` relocation to an import (`call [rip+slot]`,
//! `mov reg, [rip+slot]`) addresses its IAT slot, which the loader fills
//! with the function's (or, for a data import, the variable's) address.
//! There are no `jmp [rip+slot]` thunks: an `X86Pc32` or `Abs64` relocation
//! to an import is rejected, because `X86Pc32` cannot tell `call sym` from
//! `lea reg, [rip+sym]`, and a thunk would be the wrong answer for data
//! imports. All IAT blocks form one run at the start of `.rdata`, named by
//! the IAT data directory, as MSVC and lld lay it out: the loader makes that
//! range writable while it binds, then restores read-only.
//!
//! **Relocations.** Every `Abs64` field, and the GOT slot of every local
//! symbol reached through `X86GotPc32` (unusual, but legal as on Darwin),
//! gets an `IMAGE_REL_BASED_DIR64` entry, one block per 4 KiB page. Fields
//! hold unslid addresses (ImageBase 0x1_4000_0000 + RVA). As on Darwin,
//! `Abs64` in code is rejected: it would dirty code pages, and keeping one
//! rule for every x86-64 target means an object that links for one links
//! for all.
//!
//! **`__ImageBase`.** A synthetic symbol at the DOS header, as MSVC's linker
//! provides it: `lea reg, [rip + __ImageBase]` yields the actual load
//! address, so the RTL can turn a code address into an RVA (TP-style runtime
//! error addresses, `.odbg` line lookup).
//!
//! **Entry point.** `AddressOfEntryPoint` is the entry symbol, which
//! Windows calls like any Win64 function (rsp is 8 mod 16, the PEB address
//! in rcx). It must end the program with `ExitProcess`: returning ends only
//! the main thread, and the process lives on while other threads (such as
//! the loader's own workers) do.
//!
//! **Header choices.** OS and subsystem version 6.0: what MSVC and lld write
//! for x64, so the most travelled loader path; 10.0 would add no loader
//! behaviour a console program uses, and the real floor (Windows 10 1809)
//! comes from the APIs the RTL imports, not from the header. Stack: 8 MiB
//! reserved, as on macOS and Linux, because Pascal programs recurse; 4 KiB
//! committed (the default), so the stack grows one guard page at a time and
//! the code generator must probe frames larger than 4 KiB page by page
//! (`__chkstk` is not imported). Heap: the 1 MiB / 4 KiB defaults (only
//! the process heap uses them). `DllCharacteristics`: `DYNAMIC_BASE |
//! HIGH_ENTROPY_VA | NX_COMPAT | TERMINAL_SERVER_AWARE`. The checksum is
//! computed (the loader ignores it for programs, but it costs nothing).
//! `TimeDateStamp` is 0, so output is deterministic.
//!
//! **Not written.** No COFF symbol table (debug information lives in the
//! IDE's `.odbg`), no `.pdata`/`.xdata` unwind tables, no resources, no TLS,
//! no load configuration (so no CFG). Without `.pdata` Windows treats every
//! function as a leaf when it unwinds: exceptions must be handled by a
//! vectored exception handler (the RTL's plan), frame-based SEH and C++ EH
//! cannot cross Odin frames, ucrt's `longjmp` (which unwinds) must not be
//! used across them, and debuggers show broken call stacks.

use std::collections::{BTreeMap, HashMap};

use odin_asm::object::{Atom, Object, RelocKind, SectionKind};

use crate::reloc;
use crate::resolve::{self, Resolved, Sym};
use crate::{LinkError, LinkOptions, LinkedImage};

/// Preferred load address, the usual one for 64-bit programs. ASLR moves
/// the image; [`LinkedImage::symbols`] use this unslid base.
pub(crate) const IMAGE_BASE: u64 = 0x1_4000_0000;
/// Synthetic symbol at the DOS header, i.e. at the image base.
pub(crate) const IMAGE_BASE_SYMBOL: &str = "__ImageBase";

const SECTION_ALIGN: u64 = 0x1000;
const FILE_ALIGN: u64 = 0x200;
/// `e_lfanew`: the PE signature follows the 64-byte DOS header and the
/// 64-byte DOS stub.
const PE_OFFSET: u64 = 0x80;
const COFF_HEADER_SIZE: u64 = 20;
const DIRECTORIES: usize = 16;
const OPTIONAL_HEADER_SIZE: u64 = 112 + 8 * DIRECTORIES as u64;
const SECTION_HEADER_SIZE: u64 = 40;
const IMPORT_DESCRIPTOR_SIZE: u64 = 20;

const IMAGE_FILE_MACHINE_AMD64: u16 = 0x8664;
const IMAGE_FILE_EXECUTABLE_IMAGE: u16 = 0x0002;
const IMAGE_FILE_LARGE_ADDRESS_AWARE: u16 = 0x0020;
const PE32_PLUS_MAGIC: u16 = 0x020b;
const IMAGE_SUBSYSTEM_WINDOWS_CUI: u16 = 3;
const DLL_HIGH_ENTROPY_VA: u16 = 0x0020;
const DLL_DYNAMIC_BASE: u16 = 0x0040;
const DLL_NX_COMPAT: u16 = 0x0100;
const DLL_TERMINAL_SERVER_AWARE: u16 = 0x8000;
/// Operating system and subsystem version (Vista); see the module comment.
const OS_VERSION: (u16, u16) = (6, 0);
const STACK_RESERVE: u64 = 8 << 20;
const STACK_COMMIT: u64 = 0x1000;
const HEAP_RESERVE: u64 = 1 << 20;
const HEAP_COMMIT: u64 = 0x1000;

const DIRECTORY_IMPORT: usize = 1;
const DIRECTORY_BASERELOC: usize = 5;
const DIRECTORY_IAT: usize = 12;

const SCN_CNT_CODE: u32 = 0x0000_0020;
const SCN_CNT_INITIALIZED_DATA: u32 = 0x0000_0040;
const SCN_CNT_UNINITIALIZED_DATA: u32 = 0x0000_0080;
const SCN_MEM_DISCARDABLE: u32 = 0x0200_0000;
const SCN_MEM_EXECUTE: u32 = 0x2000_0000;
const SCN_MEM_READ: u32 = 0x4000_0000;
const SCN_MEM_WRITE: u32 = 0x8000_0000;

const IMAGE_REL_BASED_ABSOLUTE: u16 = 0;
const IMAGE_REL_BASED_DIR64: u16 = 10;

/// `push cs; pop ds; mov dx, 0x0e; mov ah, 9; int 21h; mov ax, 4c01h;
/// int 21h`: prints the message that follows and exits with code 1.
const DOS_STUB_CODE: [u8; 14] = [0x0e, 0x1f, 0xba, 0x0e, 0x00, 0xb4, 0x09, 0xcd, 0x21, 0xb8, 0x01, 0x4c, 0xcd, 0x21];
const DOS_STUB_MESSAGE: &[u8] = b"This program cannot be run in DOS mode.\r\r\n$";

/// Links `objects` into a PE32+ executable. `__ImageBase` enters resolution
/// as a zero-size atom of an extra object, so references to it resolve and
/// smart linking needs no special case (and defining it elsewhere is a
/// duplicate); layout then puts it at the image base instead of in a
/// section.
pub(crate) fn link(objects: &[Object], options: &LinkOptions) -> Result<LinkedImage, LinkError> {
    let linker = Object {
        name: "(linker)".to_string(),
        atoms: vec![Atom::new(IMAGE_BASE_SYMBOL, SectionKind::ReadOnly, 1, Vec::new())],
        imports: Vec::new(),
    };
    let resolved =
        resolve::resolve_with(objects.iter().chain([&linker]), &options.entry, |a, b| a.eq_ignore_ascii_case(b))?;
    write(&resolved, options)
}

/// One DLL's share of the import tables. Offsets are from the start of
/// `.rdata`.
struct Dll<'a> {
    /// As first spelled by an import.
    name: &'a str,
    /// Indices into [`Resolved::imports`], in order of first reference.
    imports: Vec<usize>,
    /// The DLL's block of the IAT: an 8-byte slot per import, then a null.
    iat: u64,
    /// Its import lookup table, laid out like `iat`.
    ilt: u64,
    /// The NUL-terminated DLL name.
    name_at: u64,
}

/// A section ready to be written.
struct Section {
    name: &'static str,
    rva: u64,
    virtual_size: u64,
    /// File-backed contents (at most `virtual_size` bytes); the loader
    /// zero-fills the rest.
    raw: Vec<u8>,
    flags: u32,
    /// File offset, 0 when `raw` is empty.
    pointer: u64,
}

fn write(resolved: &Resolved, options: &LinkOptions) -> Result<LinkedImage, LinkError> {
    check(resolved, options)?;
    let Some(Sym::Local { atom: image_base_atom, .. }) = resolved.lookup(IMAGE_BASE_SYMBOL) else {
        unreachable!("the linker defines {IMAGE_BASE_SYMBOL}")
    };

    // Sort live atoms by section kind, keeping input order.
    let mut members: [Vec<usize>; 4] = Default::default();
    for index in resolved.live_atoms().filter(|&i| i != image_base_atom) {
        let kind = match resolved.atoms[index].section {
            SectionKind::Text => 0,
            SectionKind::ReadOnly => 1,
            SectionKind::Data => 2,
            SectionKind::Bss => 3,
        };
        members[kind].push(index);
    }
    let [text_atoms, rdata_atoms, data_atoms, bss_atoms] = &members;

    let mut dlls: Vec<Dll> = Vec::new();
    for (index, import) in resolved.imports.iter().enumerate() {
        match dlls.iter_mut().find(|dll| dll.name.eq_ignore_ascii_case(&import.library)) {
            Some(dll) => dll.imports.push(index),
            None => dlls.push(Dll { name: &import.library, imports: vec![index], iat: 0, ilt: 0, name_at: 0 }),
        }
    }

    // A GOT slot for each local target of a GOT relocation (imports use
    // their IAT slot instead), and whether `.reloc` will have anything.
    let mut got: Vec<&str> = Vec::new();
    let mut got_slot: HashMap<&str, u64> = HashMap::new();
    let mut has_base_relocs = false;
    for index in resolved.live_atoms() {
        for r in &resolved.atoms[index].relocs {
            has_base_relocs |= r.kind == RelocKind::Abs64;
            if reloc::uses_got(r.kind)
                && matches!(resolved.lookup(&r.target), Some(Sym::Local { .. }))
                && !got_slot.contains_key(r.target.as_str())
            {
                got_slot.insert(&r.target, got.len() as u64);
                got.push(&r.target);
            }
        }
    }
    has_base_relocs |= !got.is_empty();

    // Offsets inside each section.
    let size = |i: usize| resolved.atoms[i].size;
    let align = |i: usize| u64::from(resolved.atoms[i].align);
    let mut offset = vec![0u64; resolved.atoms.len()];

    let mut cursor = 0;
    for &i in text_atoms {
        offset[i] = place(&mut cursor, align(i), size(i));
    }
    // An empty entry atom still needs a non-empty section.
    let text_size = cursor.max(1);

    let mut cursor = 0;
    for dll in &mut dlls {
        dll.iat = cursor;
        cursor += 8 * (dll.imports.len() as u64 + 1);
    }
    let iat_size = cursor;
    let got_at = place(&mut cursor, 8, 8 * got.len() as u64);
    for &i in rdata_atoms {
        offset[i] = place(&mut cursor, align(i), size(i));
    }
    let descriptors_at =
        if dlls.is_empty() { 0 } else { place(&mut cursor, 4, IMPORT_DESCRIPTOR_SIZE * (dlls.len() as u64 + 1)) };
    for dll in &mut dlls {
        dll.ilt = place(&mut cursor, 8, 8 * (dll.imports.len() as u64 + 1));
    }
    let mut hint_name = vec![0u64; resolved.imports.len()];
    for dll in &dlls {
        for &import in &dll.imports {
            // Hint, name, NUL; each entry starts on an even offset.
            hint_name[import] = place(&mut cursor, 2, 2 + resolved.imports[import].name.len() as u64 + 1);
        }
    }
    for dll in &mut dlls {
        dll.name_at = place(&mut cursor, 1, dll.name.len() as u64 + 1);
    }
    let rdata_size = cursor;

    let mut cursor = 0;
    for &i in data_atoms {
        offset[i] = place(&mut cursor, align(i), size(i));
    }
    let data_raw = cursor;
    for &i in bss_atoms {
        offset[i] = place(&mut cursor, align(i), size(i));
    }
    let data_size = cursor;

    // Section addresses. An empty section is left out but still gets an
    // address, so its zero-size atoms have one; nothing follows it there.
    let section_count = 1 + u64::from(rdata_size > 0) + u64::from(data_size > 0) + u64::from(has_base_relocs);
    let headers_size = PE_OFFSET + 4 + COFF_HEADER_SIZE + OPTIONAL_HEADER_SIZE + SECTION_HEADER_SIZE * section_count;
    let size_of_headers = headers_size.next_multiple_of(FILE_ALIGN);
    let text_rva = size_of_headers.next_multiple_of(SECTION_ALIGN);
    let rdata_rva = (text_rva + text_size).next_multiple_of(SECTION_ALIGN);
    let data_rva = (rdata_rva + rdata_size).next_multiple_of(SECTION_ALIGN);
    let reloc_rva = (data_rva + data_size).next_multiple_of(SECTION_ALIGN);
    let section_rva = |kind: SectionKind| match kind {
        SectionKind::Text => text_rva,
        SectionKind::ReadOnly => rdata_rva,
        SectionKind::Data | SectionKind::Bss => data_rva,
    };
    let mut atom_va = vec![0u64; resolved.atoms.len()];
    for index in resolved.live_atoms() {
        atom_va[index] = IMAGE_BASE + section_rva(resolved.atoms[index].section) + offset[index];
    }
    atom_va[image_base_atom] = IMAGE_BASE;
    let mut iat_slot = vec![0u64; resolved.imports.len()];
    for dll in &dlls {
        for (j, &import) in dll.imports.iter().enumerate() {
            iat_slot[import] = IMAGE_BASE + rdata_rva + dll.iat + 8 * j as u64;
        }
    }

    // Section contents.
    let mut text = vec![0xcc; text_size as usize];
    let mut rdata = vec![0u8; rdata_size as usize];
    let mut data = vec![0u8; data_raw as usize];
    for index in resolved.live_atoms().filter(|&i| i != image_base_atom) {
        let atom = resolved.atoms[index];
        if let Some(buffer) = contents(atom.section, &mut text, &mut rdata, &mut data) {
            let at = offset[index] as usize;
            buffer[at..at + atom.bytes.len()].copy_from_slice(&atom.bytes);
        }
    }

    // Relocations. `base_relocs` collects the RVA of every pointer the
    // loader must slide.
    let mut base_relocs: Vec<u64> = Vec::new();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        for r in &atom.relocs {
            let place = atom_va[index] + u64::from(r.offset);
            let target = match resolved.lookup(&r.target).expect("live relocation targets resolve") {
                // Only X86GotPc32 reaches an import (checked).
                Sym::Import(import) => iat_slot[import],
                Sym::Local { .. } if reloc::uses_got(r.kind) => {
                    IMAGE_BASE + rdata_rva + got_at + 8 * got_slot[r.target.as_str()]
                }
                Sym::Local { atom, offset } => atom_va[atom] + offset,
            };
            let buffer =
                contents(atom.section, &mut text, &mut rdata, &mut data).expect("bss atoms have no relocations");
            let field = &mut buffer[(offset[index] + u64::from(r.offset)) as usize..];
            reloc::patch(r.kind, field, place, target, r.addend)
                .map_err(|_| LinkError::RelocOutOfRange { atom: atom.name.clone(), target: r.target.clone() })?;
            if r.kind == RelocKind::Abs64 {
                base_relocs.push(place - IMAGE_BASE);
            }
        }
    }
    for (slot, name) in got.iter().enumerate() {
        let Some(Sym::Local { atom, offset }) = resolved.lookup(name) else { unreachable!("GOT slots are local") };
        let at = got_at + 8 * slot as u64;
        set64(&mut rdata, at, atom_va[atom] + offset);
        base_relocs.push(rdata_rva + at);
    }

    // Import directory, lookup tables, IAT (the same entries until the
    // loader overwrites them), hint/name entries and DLL names.
    for (d, dll) in dlls.iter().enumerate() {
        let descriptor = descriptors_at + IMPORT_DESCRIPTOR_SIZE * d as u64;
        set32(&mut rdata, descriptor, (rdata_rva + dll.ilt) as u32); // OriginalFirstThunk
        set32(&mut rdata, descriptor + 4, 0); // TimeDateStamp: not bound
        set32(&mut rdata, descriptor + 8, 0); // ForwarderChain
        set32(&mut rdata, descriptor + 12, (rdata_rva + dll.name_at) as u32);
        set32(&mut rdata, descriptor + 16, (rdata_rva + dll.iat) as u32); // FirstThunk
        for (j, &import) in dll.imports.iter().enumerate() {
            // Bit 63 clear: import by name.
            let entry = rdata_rva + hint_name[import];
            set64(&mut rdata, dll.ilt + 8 * j as u64, entry);
            set64(&mut rdata, dll.iat + 8 * j as u64, entry);
            let name = resolved.imports[import].name.as_bytes();
            let at = (hint_name[import] + 2) as usize; // hint 0: the loader searches by name
            rdata[at..at + name.len()].copy_from_slice(name);
        }
        let at = dll.name_at as usize;
        rdata[at..at + dll.name.len()].copy_from_slice(dll.name.as_bytes());
    }
    let reloc = base_relocation_blocks(&mut base_relocs);
    debug_assert_eq!(has_base_relocs, !reloc.is_empty());

    let mut sections = vec![Section {
        name: ".text",
        rva: text_rva,
        virtual_size: text_size,
        raw: text,
        flags: SCN_CNT_CODE | SCN_MEM_EXECUTE | SCN_MEM_READ,
        pointer: 0,
    }];
    if rdata_size > 0 {
        sections.push(Section {
            name: ".rdata",
            rva: rdata_rva,
            virtual_size: rdata_size,
            raw: rdata,
            flags: SCN_CNT_INITIALIZED_DATA | SCN_MEM_READ,
            pointer: 0,
        });
    }
    if data_size > 0 {
        let contents = if data_raw > 0 { SCN_CNT_INITIALIZED_DATA } else { SCN_CNT_UNINITIALIZED_DATA };
        sections.push(Section {
            name: ".data",
            rva: data_rva,
            virtual_size: data_size,
            raw: data,
            flags: contents | SCN_MEM_READ | SCN_MEM_WRITE,
            pointer: 0,
        });
    }
    if !reloc.is_empty() {
        sections.push(Section {
            name: ".reloc",
            rva: reloc_rva,
            virtual_size: reloc.len() as u64,
            raw: reloc,
            flags: SCN_CNT_INITIALIZED_DATA | SCN_MEM_DISCARDABLE | SCN_MEM_READ,
            pointer: 0,
        });
    }
    debug_assert_eq!(sections.len() as u64, section_count);

    let mut file_size = size_of_headers;
    for section in &mut sections {
        if !section.raw.is_empty() {
            section.pointer = file_size;
            file_size += (section.raw.len() as u64).next_multiple_of(FILE_ALIGN);
        }
    }
    let last = sections.last().expect(".text is always present");
    let size_of_image = (last.rva + last.virtual_size).next_multiple_of(SECTION_ALIGN);
    if size_of_image > u64::from(u32::MAX) || file_size > u64::from(u32::MAX) {
        return Err(LinkError::Unsupported(format!(
            "the image would span {size_of_image} bytes ({file_size} in the file); PE32+ stops at 4 GiB"
        )));
    }
    let raw_size = |name: &str| {
        sections
            .iter()
            .filter(|s| s.name == name)
            .map(|s| (s.raw.len() as u64).next_multiple_of(FILE_ALIGN))
            .sum::<u64>()
    };
    let size_of_code = raw_size(".text");
    let size_of_initialized_data = raw_size(".rdata") + raw_size(".data") + raw_size(".reloc");
    let size_of_uninitialized_data = (data_size - data_raw).next_multiple_of(FILE_ALIGN);

    let mut directories = [(0u64, 0u64); DIRECTORIES];
    if !dlls.is_empty() {
        directories[DIRECTORY_IMPORT] = (rdata_rva + descriptors_at, IMPORT_DESCRIPTOR_SIZE * (dlls.len() as u64 + 1));
        directories[DIRECTORY_IAT] = (rdata_rva, iat_size);
    }
    if has_base_relocs {
        let reloc = sections.last().unwrap();
        directories[DIRECTORY_BASERELOC] = (reloc.rva, reloc.virtual_size);
    }
    let Sym::Local { atom: entry_atom, offset: entry_offset } = resolved.entry else {
        unreachable!("the entry is defined")
    };
    let entry_rva = atom_va[entry_atom] + entry_offset - IMAGE_BASE;

    // Headers.
    let mut file = Vec::with_capacity(file_size as usize);
    dos_header(&mut file);
    file.extend_from_slice(b"PE\0\0");
    put16(&mut file, IMAGE_FILE_MACHINE_AMD64);
    put16(&mut file, sections.len() as u16);
    put32(&mut file, 0); // TimeDateStamp: 0 keeps the output deterministic
    put32(&mut file, 0); // PointerToSymbolTable
    put32(&mut file, 0); // NumberOfSymbols
    put16(&mut file, OPTIONAL_HEADER_SIZE as u16);
    put16(&mut file, IMAGE_FILE_EXECUTABLE_IMAGE | IMAGE_FILE_LARGE_ADDRESS_AWARE);

    let optional_header = file.len();
    put16(&mut file, PE32_PLUS_MAGIC);
    file.push(env!("CARGO_PKG_VERSION_MAJOR").parse().unwrap_or(0)); // MajorLinkerVersion
    file.push(env!("CARGO_PKG_VERSION_MINOR").parse().unwrap_or(0)); // MinorLinkerVersion
    put32(&mut file, size_of_code as u32);
    put32(&mut file, size_of_initialized_data as u32);
    put32(&mut file, size_of_uninitialized_data as u32);
    put32(&mut file, entry_rva as u32);
    put32(&mut file, text_rva as u32); // BaseOfCode
    put64(&mut file, IMAGE_BASE);
    put32(&mut file, SECTION_ALIGN as u32);
    put32(&mut file, FILE_ALIGN as u32);
    put16(&mut file, OS_VERSION.0); // MajorOperatingSystemVersion
    put16(&mut file, OS_VERSION.1);
    put16(&mut file, 0); // MajorImageVersion
    put16(&mut file, 0);
    put16(&mut file, OS_VERSION.0); // MajorSubsystemVersion
    put16(&mut file, OS_VERSION.1);
    put32(&mut file, 0); // Win32VersionValue
    put32(&mut file, size_of_image as u32);
    put32(&mut file, size_of_headers as u32);
    let checksum_at = file.len();
    put32(&mut file, 0); // CheckSum, filled in last
    put16(&mut file, IMAGE_SUBSYSTEM_WINDOWS_CUI);
    put16(&mut file, DLL_HIGH_ENTROPY_VA | DLL_DYNAMIC_BASE | DLL_NX_COMPAT | DLL_TERMINAL_SERVER_AWARE);
    put64(&mut file, STACK_RESERVE);
    put64(&mut file, STACK_COMMIT);
    put64(&mut file, HEAP_RESERVE);
    put64(&mut file, HEAP_COMMIT);
    put32(&mut file, 0); // LoaderFlags
    put32(&mut file, DIRECTORIES as u32);
    for (rva, size) in directories {
        put32(&mut file, rva as u32);
        put32(&mut file, size as u32);
    }
    debug_assert_eq!((file.len() - optional_header) as u64, OPTIONAL_HEADER_SIZE);

    for section in &sections {
        let mut name = [0u8; 8];
        name[..section.name.len()].copy_from_slice(section.name.as_bytes());
        file.extend_from_slice(&name);
        put32(&mut file, section.virtual_size as u32);
        put32(&mut file, section.rva as u32);
        put32(&mut file, (section.raw.len() as u64).next_multiple_of(FILE_ALIGN) as u32); // SizeOfRawData
        put32(&mut file, section.pointer as u32);
        put32(&mut file, 0); // PointerToRelocations
        put32(&mut file, 0); // PointerToLinenumbers
        put16(&mut file, 0); // NumberOfRelocations
        put16(&mut file, 0); // NumberOfLinenumbers
        put32(&mut file, section.flags);
    }
    debug_assert_eq!(file.len() as u64, headers_size);

    for section in &sections {
        if !section.raw.is_empty() {
            file.resize(section.pointer as usize, 0);
            file.extend_from_slice(&section.raw);
        }
    }
    file.resize(file_size as usize, 0);
    let sum = checksum(&file, checksum_at);
    file[checksum_at..checksum_at + 4].copy_from_slice(&sum.to_le_bytes());

    let mut symbols = BTreeMap::new();
    for index in resolved.live_atoms().filter(|&i| i != image_base_atom) {
        let atom = resolved.atoms[index];
        symbols.insert(atom.name.clone(), atom_va[index]);
        for (label, offset) in &atom.labels {
            symbols.insert(label.clone(), atom_va[index] + offset);
        }
    }
    // The header is always there, referenced or not.
    symbols.insert(IMAGE_BASE_SYMBOL.to_string(), IMAGE_BASE);
    Ok(LinkedImage { bytes: file, image_base: IMAGE_BASE, symbols })
}

/// Rejects input this writer cannot express.
fn check(resolved: &Resolved, options: &LinkOptions) -> Result<(), LinkError> {
    let Sym::Local { atom: entry, .. } = resolved.entry else { unreachable!("the entry is defined") };
    if resolved.atoms[entry].section != SectionKind::Text {
        return Err(LinkError::Unsupported(format!("entry symbol `{}` is not in a code atom", options.entry)));
    }
    for import in &resolved.imports {
        for (what, text) in [("name", &import.name), ("DLL name", &import.library)] {
            if text.is_empty() || text.contains('\0') {
                return Err(LinkError::Malformed(format!(
                    "import `{}` from `{}`: the {what} must be non-empty and free of NUL bytes",
                    import.name, import.library
                )));
            }
        }
    }
    let triple = options.target.triple();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        if u64::from(atom.align) > SECTION_ALIGN {
            return Err(LinkError::Unsupported(format!(
                "atom `{}` asks for {}-byte alignment, more than a {triple} page",
                atom.name, atom.align
            )));
        }
        for r in &atom.relocs {
            let kind = r.kind;
            if reloc::is_arm64(kind) {
                return Err(LinkError::Unsupported(format!(
                    "`{}` has a {kind:?} relocation, which does not exist on {triple}",
                    atom.name
                )));
            }
            if kind == RelocKind::Abs64 && atom.section == SectionKind::Text {
                return Err(LinkError::Unsupported(format!(
                    "`{}` stores the absolute address of `{}` in code, which would need a text relocation",
                    atom.name, r.target
                )));
            }
            if let Some(Sym::Import(_)) = resolved.lookup(&r.target) {
                match kind {
                    RelocKind::X86GotPc32 => {}
                    RelocKind::Abs64 => {
                        return Err(LinkError::Unsupported(format!(
                            "`{}` stores the address of imported `{}`; the Windows loader only fills IAT slots, \
                             so load it from there (X86GotPc32) at run time",
                            atom.name, r.target
                        )));
                    }
                    _ => {
                        return Err(LinkError::Unsupported(format!(
                            "`{}` refers to imported `{}` with {kind:?}; imports are reached through their IAT \
                             slot (X86GotPc32)",
                            atom.name, r.target
                        )));
                    }
                }
            }
        }
    }
    Ok(())
}

/// The buffer holding atoms of `kind`, or `None` for bss.
fn contents<'b>(
    kind: SectionKind,
    text: &'b mut [u8],
    rdata: &'b mut [u8],
    data: &'b mut [u8],
) -> Option<&'b mut [u8]> {
    match kind {
        SectionKind::Text => Some(text),
        SectionKind::ReadOnly => Some(rdata),
        SectionKind::Data => Some(data),
        SectionKind::Bss => None,
    }
}

/// Places `size` bytes aligned to `align` at `cursor`, advances it, and
/// returns where they went.
fn place(cursor: &mut u64, align: u64, size: u64) -> u64 {
    let at = cursor.next_multiple_of(align);
    *cursor = at + size;
    at
}

/// The contents of `.reloc`: one block per 4 KiB page, each a page RVA, a
/// block size and a `DIR64` entry per pointer at `rvas`, padded to 4 bytes
/// with an `ABSOLUTE` (no-op) entry. Empty when there is nothing to slide.
fn base_relocation_blocks(rvas: &mut [u64]) -> Vec<u8> {
    rvas.sort_unstable();
    let mut out = Vec::new();
    let mut i = 0;
    while i < rvas.len() {
        let page = rvas[i] & !0xfff;
        let start = out.len();
        put32(&mut out, page as u32);
        put32(&mut out, 0); // SizeOfBlock, patched below
        while i < rvas.len() && rvas[i] & !0xfff == page {
            put16(&mut out, (IMAGE_REL_BASED_DIR64 << 12) | (rvas[i] & 0xfff) as u16);
            i += 1;
        }
        if (out.len() - start) % 4 != 0 {
            put16(&mut out, IMAGE_REL_BASED_ABSOLUTE);
        }
        let block_size = (out.len() - start) as u32;
        out[start + 4..start + 8].copy_from_slice(&block_size.to_le_bytes());
    }
    out
}

/// The 64-byte DOS header and a 64-byte stub that prints the customary
/// message under DOS. `e_lfanew` points past both, to the PE signature.
fn dos_header(out: &mut Vec<u8>) {
    put16(out, 0x5a4d); // e_magic "MZ"
    put16(out, PE_OFFSET as u16); // e_cblp: the DOS image is the 128 bytes before "PE"
    put16(out, 1); // e_cp: one 512-byte page
    put16(out, 0); // e_crlc: no relocations
    put16(out, 4); // e_cparhdr: a 64-byte header
    put16(out, 0x10); // e_minalloc: 256 bytes, room for the stack below
    put16(out, 0xffff); // e_maxalloc
    put16(out, 0); // e_ss
    put16(out, 0xb8); // e_sp
    put16(out, 0); // e_csum
    put16(out, 0); // e_ip
    put16(out, 0); // e_cs
    put16(out, 0x40); // e_lfarlc
    put16(out, 0); // e_ovno
    out.resize(0x3c, 0); // e_res, e_oemid, e_oeminfo, e_res2
    put32(out, PE_OFFSET as u32); // e_lfanew
    out.extend_from_slice(&DOS_STUB_CODE);
    out.extend_from_slice(DOS_STUB_MESSAGE);
    out.resize(PE_OFFSET as usize, 0);
}

/// The image checksum as `CheckSumMappedFile` computes it: the file summed
/// as little-endian 16-bit words with end-around carry (the checksum field
/// itself counted as zero), plus the file length.
fn checksum(file: &[u8], field: usize) -> u32 {
    let mut sum: u32 = 0;
    for (i, pair) in file.chunks(2).enumerate() {
        let at = 2 * i;
        if at == field || at == field + 2 {
            continue;
        }
        sum += u32::from(u16::from_le_bytes([pair[0], pair.get(1).copied().unwrap_or(0)]));
        sum = (sum & 0xffff) + (sum >> 16);
    }
    sum.wrapping_add(file.len() as u32)
}

fn set32(out: &mut [u8], at: u64, value: u32) {
    out[at as usize..at as usize + 4].copy_from_slice(&value.to_le_bytes());
}

fn set64(out: &mut [u8], at: u64, value: u64) {
    out[at as usize..at as usize + 8].copy_from_slice(&value.to_le_bytes());
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
    use crate::{Target, link};
    use odin_asm::object::Import;
    use odin_asm::object::RelocKind::*;
    use odin_asm::object::SectionKind::*;

    const KERNEL32: &str = "kernel32.dll";
    const UCRT: &str = "ucrtbase.dll";

    fn u16_at(data: &[u8], at: usize) -> u16 {
        u16::from_le_bytes(data[at..at + 2].try_into().unwrap())
    }

    fn u32_at(data: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(data[at..at + 4].try_into().unwrap())
    }

    fn u64_at(data: &[u8], at: usize) -> u64 {
        u64::from_le_bytes(data[at..at + 8].try_into().unwrap())
    }

    #[derive(Debug)]
    struct Sect {
        name: String,
        virtual_size: u64,
        rva: u64,
        raw_size: u64,
        pointer: u64,
        flags: u32,
    }

    /// Just enough of a PE reader to check the writer independently.
    struct Pe<'f> {
        file: &'f [u8],
        coff: usize,
        opt: usize,
        sections: Vec<Sect>,
    }

    impl<'f> Pe<'f> {
        fn parse(file: &'f [u8]) -> Pe<'f> {
            assert_eq!(&file[..2], b"MZ");
            let pe = u32_at(file, 0x3c) as usize;
            assert_eq!(&file[pe..pe + 4], b"PE\0\0");
            let coff = pe + 4;
            let opt = coff + 20;
            let table = opt + usize::from(u16_at(file, coff + 16));
            let sections = (0..usize::from(u16_at(file, coff + 2)))
                .map(|i| {
                    let at = table + 40 * i;
                    Sect {
                        name: file[at..at + 8].iter().take_while(|&&b| b != 0).map(|&b| b as char).collect(),
                        virtual_size: u32_at(file, at + 8).into(),
                        rva: u32_at(file, at + 12).into(),
                        raw_size: u32_at(file, at + 16).into(),
                        pointer: u32_at(file, at + 20).into(),
                        flags: u32_at(file, at + 36),
                    }
                })
                .collect();
            Pe { file, coff, opt, sections }
        }

        fn opt16(&self, at: usize) -> u16 {
            u16_at(self.file, self.opt + at)
        }

        fn opt32(&self, at: usize) -> u32 {
            u32_at(self.file, self.opt + at)
        }

        fn opt64(&self, at: usize) -> u64 {
            u64_at(self.file, self.opt + at)
        }

        /// (RVA, size) of data directory `index`.
        fn directory(&self, index: usize) -> (u64, u64) {
            (self.opt32(112 + 8 * index).into(), self.opt32(116 + 8 * index).into())
        }

        fn section(&self, name: &str) -> &Sect {
            self.sections.iter().find(|s| s.name == name).unwrap_or_else(|| panic!("no {name}"))
        }

        fn names(&self) -> Vec<&str> {
            self.sections.iter().map(|s| s.name.as_str()).collect()
        }

        /// File offset of the byte at `rva`, which must be file-backed.
        fn offset(&self, rva: u64) -> usize {
            let section = self
                .sections
                .iter()
                .find(|s| (s.rva..s.rva + s.virtual_size.min(s.raw_size)).contains(&rva))
                .unwrap_or_else(|| panic!("{rva:#x} is not file-backed"));
            (section.pointer + rva - section.rva) as usize
        }

        fn at_va(&self, va: u64) -> usize {
            self.offset(va - IMAGE_BASE)
        }

        fn read16(&self, rva: u64) -> u16 {
            u16_at(self.file, self.offset(rva))
        }

        fn read32(&self, rva: u64) -> u32 {
            u32_at(self.file, self.offset(rva))
        }

        fn read64(&self, rva: u64) -> u64 {
            u64_at(self.file, self.offset(rva))
        }

        fn c_string(&self, rva: u64) -> String {
            let bytes = self.file[self.offset(rva)..].iter().take_while(|&&b| b != 0).copied().collect();
            String::from_utf8(bytes).unwrap()
        }

        /// The import directory as (DLL, [(function, IAT slot RVA)]),
        /// checking that each lookup table entry equals its IAT entry, is
        /// by name and has hint 0.
        fn imports(&self) -> Vec<(String, Vec<(String, u64)>)> {
            let (dir, size) = self.directory(DIRECTORY_IMPORT);
            let mut out = Vec::new();
            if dir == 0 {
                assert_eq!(size, 0);
                return out;
            }
            for d in 0.. {
                let at = dir + 20 * d;
                let (ilt, name, iat) = (self.read32(at), self.read32(at + 12), self.read32(at + 16));
                if (ilt, name, iat) == (0, 0, 0) {
                    assert_eq!(size, 20 * (d + 1), "the directory includes the null descriptor");
                    break;
                }
                assert_eq!((self.read32(at + 4), self.read32(at + 8)), (0, 0), "not bound, no forwarders");
                let (ilt, iat) = (u64::from(ilt), u64::from(iat));
                let mut functions = Vec::new();
                for j in 0.. {
                    let entry = self.read64(ilt + 8 * j);
                    assert_eq!(self.read64(iat + 8 * j), entry, "the IAT starts as a copy of the lookup table");
                    if entry == 0 {
                        break;
                    }
                    assert_eq!(entry >> 63, 0, "imported by name");
                    assert_eq!(entry % 2, 0, "hint/name entries are even");
                    assert_eq!(self.read16(entry), 0, "hint");
                    functions.push((self.c_string(entry + 2), iat + 8 * j));
                }
                out.push((self.c_string(name.into()), functions));
            }
            out
        }

        /// RVAs of the `DIR64` entries of the base relocation directory.
        fn base_relocs(&self) -> Vec<u64> {
            let (dir, size) = self.directory(DIRECTORY_BASERELOC);
            let mut out = Vec::new();
            let mut at = dir;
            while at < dir + size {
                let (page, block) = (u64::from(self.read32(at)), u64::from(self.read32(at + 4)));
                assert_eq!(page % 0x1000, 0, "page RVA");
                assert!(block > 8 && block % 4 == 0, "block size {block}");
                let count = (block - 8) / 2;
                for k in 0..count {
                    let entry = self.read16(at + 8 + 2 * k);
                    match entry >> 12 {
                        10 => out.push(page + u64::from(entry & 0xfff)),
                        0 => assert_eq!((k, entry), (count - 1, 0), "padding only ends a block"),
                        other => panic!("relocation type {other}"),
                    }
                }
                at += block;
            }
            assert_eq!(at, dir + size);
            out
        }
    }

    fn import(name: &str, library: &str) -> Import {
        Import { name: name.to_string(), library: library.to_string() }
    }

    fn program(atoms: Vec<Atom>, imports: Vec<Import>) -> Vec<Object> {
        vec![Object { name: "test".to_string(), atoms, imports }]
    }

    fn windows(objects: &[Object]) -> Result<LinkedImage, LinkError> {
        link(objects, &LinkOptions::new(Target::X86_64Windows, "main", "test"))
    }

    /// Atoms of every kind, odd alignments, pointer tables in read-only data
    /// and in data, imports from two DLLs (one spelled three ways, one of
    /// them a data import), an import declared twice, and an unused import
    /// from a third DLL.
    fn sample() -> Vec<Object> {
        let main = Atom::new("main", Text, 1, vec![0x90; 40])
            .reloc(0, X86GotPc32, "GetStdHandle", -4)
            .reloc(4, X86GotPc32, "WriteFile", -4)
            .reloc(8, X86GotPc32, "strlen", -4)
            .reloc(12, X86GotPc32, "_timezone", -4)
            .reloc(16, X86Pc32, "helper", -4)
            .reloc(20, X86Pc32, "table", -4)
            .reloc(24, X86Pc32, "vtable", -4)
            .reloc(28, X86Pc32, "counter", -4)
            .reloc(32, X86GotPc32, "ExitProcess", -4);
        // lea rax, [rip + msg]; ret
        let helper =
            Atom::new("helper", Text, 16, vec![0x48, 0x8d, 0x05, 0, 0, 0, 0, 0xc3]).reloc(3, X86Pc32, "msg", -4);
        let msg = Atom::new("msg", ReadOnly, 1, b"hi\0".to_vec());
        let table =
            Atom::new("table", ReadOnly, 8, vec![0; 16]).reloc(0, Abs64, "helper", 0).reloc(8, Abs64, "main", 3);
        let vtable = Atom { labels: vec![("vtable_end".to_string(), 24)], ..Atom::new("vtable", Data, 8, vec![0; 24]) }
            .reloc(0, Abs64, "msg", 1)
            .reloc(8, Abs64, "counter", 0)
            .reloc(16, Abs64, IMAGE_BASE_SYMBOL, 0x40);
        let counter = Atom::bss("counter", 0x2345, 32);
        let dead = Atom::new("dead", Text, 1, vec![0xff, 0x15, 0, 0, 0, 0]).reloc(2, X86GotPc32, "MessageBoxA", -4);
        vec![
            Object {
                name: "main".to_string(),
                atoms: vec![main, helper, msg, table, vtable, counter, dead],
                imports: vec![
                    import("GetStdHandle", "KERNEL32.dll"),
                    import("strlen", UCRT),
                    import("_timezone", "UCRTBASE.DLL"),
                    import("MessageBoxA", "user32.dll"),
                ],
            },
            Object {
                name: "more".to_string(),
                atoms: vec![],
                imports: vec![
                    import("WriteFile", KERNEL32),
                    import("ExitProcess", "Kernel32.DLL"),
                    import("GetStdHandle", KERNEL32),
                ],
            },
        ]
    }

    #[test]
    fn headers() {
        let image = windows(&sample()).unwrap();
        let file = &image.bytes;
        let pe = Pe::parse(file);
        assert_eq!(image.image_base, IMAGE_BASE);
        // DOS header and stub.
        assert_eq!(u32_at(file, 0x3c), 0x80, "e_lfanew");
        assert_eq!(&file[0x40..0x4e], &DOS_STUB_CODE);
        assert_eq!(&file[0x4e..0x4e + DOS_STUB_MESSAGE.len()], DOS_STUB_MESSAGE);
        // COFF header.
        assert_eq!(u16_at(file, pe.coff), IMAGE_FILE_MACHINE_AMD64);
        assert_eq!(u16_at(file, pe.coff + 2), 4, "NumberOfSections");
        assert_eq!(u32_at(file, pe.coff + 4), 0, "TimeDateStamp");
        assert_eq!((u32_at(file, pe.coff + 8), u32_at(file, pe.coff + 12)), (0, 0), "no symbol table");
        assert_eq!(u16_at(file, pe.coff + 16), 240, "SizeOfOptionalHeader");
        assert_eq!(u16_at(file, pe.coff + 18), 0x0022, "executable, large address aware");
        // Optional header.
        assert_eq!(pe.opt16(0), 0x020b, "PE32+");
        assert_eq!(u64::from(pe.opt32(4)), pe.section(".text").raw_size, "SizeOfCode");
        let initialized: u64 = [".rdata", ".data", ".reloc"].iter().map(|n| pe.section(n).raw_size).sum();
        assert_eq!(u64::from(pe.opt32(8)), initialized, "SizeOfInitializedData");
        // vtable fills 24 bytes of .data; counter ends at 32 + 0x2345.
        assert_eq!(pe.opt32(12), 0x2400, "SizeOfUninitializedData: the bss tail, file-aligned");
        assert_eq!(u64::from(pe.opt32(16)), image.symbols["main"] - IMAGE_BASE, "AddressOfEntryPoint");
        assert_eq!(pe.opt32(20), 0x1000, "BaseOfCode");
        assert_eq!(pe.opt64(24), IMAGE_BASE);
        assert_eq!((pe.opt32(32), pe.opt32(36)), (0x1000, 0x200), "section and file alignment");
        let versions: Vec<u16> = (0..6).map(|i| pe.opt16(40 + 2 * i)).collect();
        assert_eq!(versions, [6, 0, 0, 0, 6, 0], "OS, image and subsystem versions");
        assert_eq!(pe.opt32(52), 0, "Win32VersionValue");
        let last = pe.sections.last().unwrap();
        assert_eq!(u64::from(pe.opt32(56)), (last.rva + last.virtual_size).next_multiple_of(0x1000), "SizeOfImage");
        assert_eq!(pe.opt32(60), 0x400, "SizeOfHeaders: four section headers need 552 bytes");
        assert_eq!(pe.opt32(64), checksum(file, pe.opt + 64), "CheckSum");
        assert_ne!(pe.opt32(64), 0);
        assert_eq!(pe.opt16(68), IMAGE_SUBSYSTEM_WINDOWS_CUI);
        assert_eq!(pe.opt16(70), 0x8160, "high entropy VA, dynamic base, NX, terminal server aware");
        assert_eq!([pe.opt64(72), pe.opt64(80), pe.opt64(88), pe.opt64(96)], [8 << 20, 0x1000, 1 << 20, 0x1000]);
        assert_eq!((pe.opt32(104), pe.opt32(108)), (0, 16), "LoaderFlags, NumberOfRvaAndSizes");
        for index in 0..DIRECTORIES {
            let used = matches!(index, DIRECTORY_IMPORT | DIRECTORY_BASERELOC | DIRECTORY_IAT);
            assert_eq!(pe.directory(index) != (0, 0), used, "directory {index}");
        }
    }

    #[test]
    fn section_table_and_placement() {
        let image = windows(&sample()).unwrap();
        let file = &image.bytes;
        let pe = Pe::parse(file);
        assert_eq!(pe.names(), [".text", ".rdata", ".data", ".reloc"]);
        let flags: Vec<u32> = pe.sections.iter().map(|s| s.flags).collect();
        assert_eq!(flags, [0x6000_0020, 0x4000_0040, 0xc000_0040, 0x4200_0040]);
        // Contiguous in memory from the first page after the headers (the
        // loader insists), aligned and back to back in the file up to its end.
        let (mut rva, mut pointer) = (0x1000, 0x400);
        for s in &pe.sections {
            assert_eq!((s.rva, s.pointer), (rva, pointer), "{}", s.name);
            assert_eq!(s.raw_size % 0x200, 0, "{}", s.name);
            rva = (s.rva + s.virtual_size).next_multiple_of(0x1000);
            pointer += s.raw_size;
        }
        assert_eq!(pointer, file.len() as u64);
        // Bss is the zero-filled tail of .data.
        let data = pe.section(".data");
        assert_eq!(data.raw_size, 0x200);
        assert!(data.virtual_size > data.raw_size);
        let sym = |name: &str| image.symbols[name];
        assert_eq!(sym("counter") % 32, 0);
        assert_eq!(sym("counter") + 0x2345, IMAGE_BASE + data.rva + data.virtual_size);
        // Atoms in their sections, aligned; smart linking.
        assert_eq!(sym("main"), IMAGE_BASE + 0x1000);
        assert_eq!(sym("helper"), IMAGE_BASE + 0x1030, "40 bytes of main, then 16-byte alignment");
        assert_eq!(sym("vtable"), IMAGE_BASE + data.rva);
        assert_eq!(sym("vtable_end"), sym("vtable") + 24);
        let rdata = pe.section(".rdata");
        assert!((rdata.rva..rdata.rva + rdata.virtual_size).contains(&(sym("msg") - IMAGE_BASE)));
        assert_eq!(sym("table") % 8, 0);
        assert_eq!(sym(IMAGE_BASE_SYMBOL), IMAGE_BASE);
        assert!(!image.symbols.contains_key("dead"));
        assert_eq!(image.symbols.len(), 8);
        // Contents; int3 between code atoms.
        let at = |name: &str| pe.at_va(sym(name));
        assert_eq!(&file[at("msg")..at("msg") + 3], b"hi\0");
        assert_eq!(&file[at("main") + 36..at("main") + 40], &[0x90; 4]);
        assert!(file[at("main") + 40..at("helper")].iter().all(|&b| b == 0xcc));
        assert_eq!(file[at("helper") + 7], 0xc3);
        // The unused import and its DLL leave no trace.
        assert!(!file.windows(11).any(|w| w == b"MessageBoxA"));
        assert!(!file.windows(10).any(|w| w.eq_ignore_ascii_case(b"user32.dll")));
    }

    #[test]
    fn import_directory_groups_dlls() {
        let image = windows(&sample()).unwrap();
        let pe = Pe::parse(&image.bytes);
        let imports = pe.imports();
        let names: Vec<(&str, Vec<&str>)> = imports
            .iter()
            .map(|(dll, functions)| (dll.as_str(), functions.iter().map(|(name, _)| name.as_str()).collect()))
            .collect();
        // DLL names compare case-insensitively; the first spelling stays.
        assert_eq!(
            names,
            [
                ("KERNEL32.dll", vec!["GetStdHandle", "WriteFile", "ExitProcess"]),
                ("ucrtbase.dll", vec!["strlen", "_timezone"])
            ]
        );
        // One IAT run at the start of .rdata, each DLL's slots ending in a
        // null one, named by the IAT directory.
        let rdata = pe.section(".rdata").rva;
        let slots: Vec<u64> = imports.iter().flat_map(|(_, f)| f.iter().map(|(_, slot)| slot - rdata)).collect();
        assert_eq!(slots, [0, 8, 16, 32, 40]);
        assert_eq!(pe.directory(DIRECTORY_IAT), (rdata, 56));
        assert_eq!(pe.directory(DIRECTORY_IMPORT).1, 3 * 20, "two descriptors and the null one");
    }

    #[test]
    fn got_relocations_reach_iat_slots() {
        let image = windows(&sample()).unwrap();
        let file = &image.bytes;
        let pe = Pe::parse(file);
        let slot: HashMap<String, u64> =
            pe.imports().into_iter().flat_map(|(_, f)| f).map(|(name, rva)| (name, IMAGE_BASE + rva)).collect();
        let main = image.symbols["main"];
        let rel32 = |at: u64, offset: u64| i64::from(u32_at(file, pe.at_va(at + offset)) as i32);
        for (offset, name) in
            [(0, "GetStdHandle"), (4, "WriteFile"), (8, "strlen"), (12, "_timezone"), (32, "ExitProcess")]
        {
            assert_eq!(rel32(main, offset), slot[name] as i64 - (main + offset + 4) as i64, "{name}");
        }
        assert_eq!(rel32(main, 16), image.symbols["helper"] as i64 - (main + 20) as i64);
        assert_eq!(rel32(main, 28), image.symbols["counter"] as i64 - (main + 32) as i64);
        let helper = image.symbols["helper"];
        assert_eq!(rel32(helper, 3), image.symbols["msg"] as i64 - (helper + 7) as i64);
    }

    #[test]
    fn local_got_slot_is_relocated() {
        let objects = program(
            vec![
                Atom::new("main", Text, 1, vec![0; 8]).reloc(2, X86GotPc32, "value", -4),
                Atom::new("value", Data, 8, vec![7; 8]),
            ],
            vec![],
        );
        let image = windows(&objects).unwrap();
        let pe = Pe::parse(&image.bytes);
        let rdata = pe.section(".rdata");
        assert_eq!(rdata.virtual_size, 8, "just the slot");
        assert_eq!(pe.read64(rdata.rva), image.symbols["value"]);
        assert_eq!(pe.base_relocs(), [rdata.rva]);
        assert_eq!((pe.directory(DIRECTORY_IMPORT), pe.directory(DIRECTORY_IAT)), ((0, 0), (0, 0)));
        let main = image.symbols["main"];
        let rel32 = i64::from(u32_at(&image.bytes, pe.at_va(main) + 2) as i32);
        assert_eq!(rel32, (IMAGE_BASE + rdata.rva) as i64 - (main + 6) as i64);
    }

    #[test]
    fn base_relocations_cover_every_pointer() {
        let image = windows(&sample()).unwrap();
        let file = &image.bytes;
        let pe = Pe::parse(file);
        let sym = |name: &str| image.symbols[name];
        let rva = |name: &str, offset: u64| sym(name) + offset - IMAGE_BASE;
        let mut expected =
            vec![rva("table", 0), rva("table", 8), rva("vtable", 0), rva("vtable", 8), rva("vtable", 16)];
        expected.sort();
        assert_eq!(pe.base_relocs(), expected);
        let reloc = pe.section(".reloc");
        assert_eq!(pe.directory(DIRECTORY_BASERELOC), (reloc.rva, reloc.virtual_size));
        // The fields hold unslid addresses, also in read-only data.
        let pointer = |va: u64| u64_at(file, pe.at_va(va));
        assert_eq!(pointer(sym("table")), sym("helper"));
        assert_eq!(pointer(sym("table") + 8), sym("main") + 3);
        assert_eq!(pointer(sym("vtable")), sym("msg") + 1);
        assert_eq!(pointer(sym("vtable") + 8), sym("counter"));
        assert_eq!(pointer(sym("vtable") + 16), IMAGE_BASE + 0x40);
    }

    #[test]
    fn base_relocation_blocks_span_pages() {
        // A 9 KiB pointer table over three pages: three pointers on the
        // first (an odd count, so the block is padded), two on each of the
        // others.
        let offsets = [0u32, 8, 0xff8, 0x1000, 0x1ff0, 0x2008, 0x23f8];
        let mut table = Atom::new("table", Data, 8, vec![0; 0x2400]);
        for &offset in &offsets {
            table = table.reloc(offset, Abs64, "main", i64::from(offset));
        }
        let main = Atom::new("main", Text, 1, vec![0; 8]).reloc(0, X86Pc32, "table", -4);
        let image = windows(&program(vec![main, table], vec![])).unwrap();
        let pe = Pe::parse(&image.bytes);
        let data = pe.section(".data").rva;
        assert_eq!(pe.base_relocs(), offsets.map(|o| data + u64::from(o)));
        let reloc = pe.section(".reloc");
        let blocks = &image.bytes[reloc.pointer as usize..][..reloc.virtual_size as usize];
        let header = |at: usize| (u64::from(u32_at(blocks, at)), u32_at(blocks, at + 4));
        assert_eq!(header(0), (data, 8 + 3 * 2 + 2), "three entries and padding");
        assert_eq!(header(16), (data + 0x1000, 8 + 2 * 2));
        assert_eq!(header(28), (data + 0x2000, 8 + 2 * 2));
        assert_eq!(blocks.len(), 40);
        assert_eq!(&blocks[8..16], &[0x00, 0xa0, 0x08, 0xa0, 0xf8, 0xaf, 0x00, 0x00]);
        for offset in offsets.map(u64::from) {
            let at = pe.at_va(image.symbols["table"] + offset);
            assert_eq!(u64_at(&image.bytes, at), image.symbols["main"] + offset);
        }
        assert!(base_relocation_blocks(&mut []).is_empty());
    }

    #[test]
    fn image_base_symbol() {
        // lea rax, [rip + __ImageBase]; call [rip + slot of __ImageBase]
        let main = Atom::new("main", Text, 1, vec![0x48, 0x8d, 0x05, 0, 0, 0, 0, 0xff, 0x15, 0, 0, 0, 0])
            .reloc(3, X86Pc32, IMAGE_BASE_SYMBOL, -4)
            .reloc(9, X86GotPc32, IMAGE_BASE_SYMBOL, -4);
        let pointer = Atom::new("pointer", Data, 8, vec![0; 8]).keep().reloc(0, Abs64, IMAGE_BASE_SYMBOL, 0x1000);
        let image = windows(&program(vec![main, pointer], vec![])).unwrap();
        let file = &image.bytes;
        let pe = Pe::parse(file);
        assert_eq!((image.image_base, image.symbols[IMAGE_BASE_SYMBOL]), (IMAGE_BASE, IMAGE_BASE));
        let main = image.symbols["main"];
        assert_eq!(i64::from(u32_at(file, pe.at_va(main) + 3) as i32), IMAGE_BASE as i64 - (main + 7) as i64);
        assert_eq!(&file[..2], b"MZ", "the address is the DOS header");
        let got = pe.section(".rdata").rva;
        assert_eq!(pe.read64(got), IMAGE_BASE);
        assert_eq!(u64_at(file, pe.at_va(image.symbols["pointer"])), IMAGE_BASE + 0x1000);
        assert_eq!(pe.base_relocs(), [got, image.symbols["pointer"] - IMAGE_BASE]);
        // Unreferenced, it is still listed; defining it is a duplicate.
        let image = windows(&program(vec![Atom::new("main", Text, 1, vec![0xc3])], vec![])).unwrap();
        assert_eq!(image.symbols[IMAGE_BASE_SYMBOL], IMAGE_BASE);
        let defined = program(
            vec![Atom::new("main", Text, 1, vec![0xc3]), Atom::new(IMAGE_BASE_SYMBOL, Data, 1, vec![0])],
            vec![],
        );
        assert_eq!(windows(&defined).err(), Some(LinkError::Duplicate { name: IMAGE_BASE_SYMBOL.to_string() }));
    }

    #[test]
    fn code_only_and_bss_only() {
        let image = windows(&program(vec![Atom::new("main", Text, 1, vec![0xc3])], vec![])).unwrap();
        let pe = Pe::parse(&image.bytes);
        assert_eq!(pe.names(), [".text"]);
        assert_eq!((pe.opt32(56), pe.opt32(60)), (0x2000, 0x200), "SizeOfImage, SizeOfHeaders");
        assert_eq!(image.bytes.len(), 0x400);
        assert!((0..DIRECTORIES).all(|index| pe.directory(index) == (0, 0)), "no imports, nothing to relocate");

        let image = windows(&program(
            vec![
                Atom::new("main", Text, 1, vec![0; 8]).reloc(0, X86Pc32, "buf", -4),
                Atom::bss("buf", 0x1_0000, 16),
                Atom::new("empty", ReadOnly, 1, vec![]).keep(),
            ],
            vec![],
        ))
        .unwrap();
        let pe = Pe::parse(&image.bytes);
        assert_eq!(pe.names(), [".text", ".data"]);
        let data = pe.section(".data");
        assert_eq!((data.rva, data.virtual_size, data.raw_size, data.pointer), (0x2000, 0x1_0000, 0, 0));
        assert_eq!(data.flags, SCN_CNT_UNINITIALIZED_DATA | SCN_MEM_READ | SCN_MEM_WRITE);
        assert_eq!((pe.opt32(12), pe.opt32(56)), (0x1_0000, 0x1_2000), "SizeOfUninitializedData, SizeOfImage");
        assert_eq!(image.bytes.len(), 0x400, "headers and .text only");
        // A zero-size atom of a left-out section still has an address.
        assert_eq!(image.symbols["empty"], IMAGE_BASE + 0x2000);
    }

    #[test]
    fn rejected_input() {
        let unsupported = |result: Result<LinkedImage, LinkError>| matches!(result, Err(LinkError::Unsupported(_)));
        let main = || Atom::new("main", Text, 1, vec![0; 8]);
        let kernel32 = || vec![import("ExitProcess", KERNEL32)];
        // Undefined symbols, referenced from a live atom or as the entry.
        assert_eq!(
            windows(&program(vec![main().reloc(0, X86Pc32, "nowhere", -4)], vec![])).err(),
            Some(LinkError::Undefined { name: "nowhere".to_string(), referenced_from: "main".to_string() })
        );
        let start = LinkOptions::new(Target::X86_64Windows, "start", "test");
        assert_eq!(
            link(&program(vec![main()], vec![]), &start).err(),
            Some(LinkError::Undefined { name: "start".to_string(), referenced_from: "(entry point)".to_string() })
        );
        // AArch64 relocations do not exist on this target.
        for kind in [Arm64Branch26, Arm64Page21, Arm64PageOff12 { scale: 0 }, Arm64GotPage21, Arm64GotPageOff12] {
            assert!(unsupported(windows(&program(vec![main().reloc(0, kind, "main", 0)], vec![]))), "{kind:?}");
        }
        // Imports only through their IAT slot.
        assert!(unsupported(windows(&program(vec![main().reloc(0, X86Pc32, "ExitProcess", -4)], kernel32()))));
        let pointer = Atom::new("pointer", Data, 8, vec![0; 8]).keep().reloc(0, Abs64, "ExitProcess", 0);
        assert!(unsupported(windows(&program(vec![main(), pointer], kernel32()))));
        // Text relocations, an entry outside code, alignment beyond a page.
        assert!(unsupported(windows(&program(vec![main().reloc(0, Abs64, "main", 0)], vec![]))));
        assert!(unsupported(windows(&program(vec![Atom::new("main", Data, 1, vec![0; 8])], vec![]))));
        assert!(unsupported(windows(&program(
            vec![main(), Atom::new("big", Data, 0x2000, vec![0; 8]).keep()],
            vec![]
        ))));
        // Empty names and NUL bytes.
        for (name, library) in
            [("", KERNEL32), ("Exit\0Process", KERNEL32), ("ExitProcess", ""), ("ExitProcess", "a\0.dll")]
        {
            let result = windows(&program(vec![main().reloc(0, X86GotPc32, name, -4)], vec![import(name, library)]));
            assert!(matches!(result, Err(LinkError::Malformed(_))), "{name:?} from {library:?}: {result:?}");
        }
        // One name from two DLLs is a duplicate; from one DLL spelled two
        // ways it is not.
        let twice = |library: &str| {
            let imports = vec![import("ExitProcess", KERNEL32), import("ExitProcess", library)];
            windows(&program(vec![main().reloc(0, X86GotPc32, "ExitProcess", -4)], imports))
        };
        assert_eq!(twice(UCRT).err(), Some(LinkError::Duplicate { name: "ExitProcess".to_string() }));
        assert!(twice("KERNEL32.DLL").is_ok());
        // PE32+ stops at 4 GiB.
        assert!(unsupported(windows(&program(vec![main(), Atom::bss("huge", 1 << 32, 8).keep()], vec![]))));
    }

    #[test]
    fn out_of_range_relocations() {
        let far = |gap: u64| {
            program(
                vec![
                    Atom::new("main", Text, 1, vec![0; 8]).reloc(0, X86Pc32, "far", -4),
                    Atom::bss("gap", gap, 8).keep(),
                    Atom::bss("far", 8, 8),
                ],
                vec![],
            )
        };
        assert!(windows(&far(0x7000_0000)).is_ok());
        assert_eq!(
            windows(&far(0x8000_0000)).err(),
            Some(LinkError::RelocOutOfRange { atom: "main".to_string(), target: "far".to_string() })
        );
    }

    #[test]
    fn output_is_deterministic() {
        assert_eq!(windows(&sample()).unwrap(), windows(&sample()).unwrap());
    }

    #[test]
    fn checksum_folds_carries_and_skips_its_field() {
        // Words 0x0201, then the field (skipped), 0xffff, 0x0001 and a last
        // odd byte: 0x0201 + 0xffff = 0x1_0200 folds to 0x0201, + 1 + 7 =
        // 0x0209, plus the length 11.
        let file = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0xff, 0xff, 0x01, 0x00, 0x07];
        assert_eq!(checksum(&file, 2), 0x0209 + 11);
    }
}
