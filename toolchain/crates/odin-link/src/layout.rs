// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Pieces every executable writer shares: the input checks that do not
//! depend on the file format, atom placement and little-endian writers.

use odin_asm::object::{RelocKind, SectionKind};

use crate::reloc;
use crate::resolve::{Resolved, Sym};
use crate::{LinkError, LinkOptions};

/// Rejects input no writer can express: an entry point outside code, atoms
/// aligned beyond a `page`, relocations of the other architecture, absolute
/// addresses in code (they would need a text relocation), and imports
/// reached other than through their GOT slot or an absolute pointer in data.
pub(crate) fn check_input(resolved: &Resolved, options: &LinkOptions, page: u64) -> Result<(), LinkError> {
    let Sym::Local { atom: entry, .. } = resolved.entry else { unreachable!("the entry is defined") };
    if resolved.atoms[entry].section != SectionKind::Text {
        return Err(LinkError::Unsupported(format!("entry symbol `{}` is not in a code atom", options.entry)));
    }
    let arm64 = options.target.is_arm64();
    let triple = options.target.triple();
    for index in resolved.live_atoms() {
        let atom = resolved.atoms[index];
        if u64::from(atom.align) > page {
            return Err(LinkError::Unsupported(format!(
                "atom `{}` asks for {}-byte alignment, more than a {triple} page",
                atom.name, atom.align
            )));
        }
        for reloc in &atom.relocs {
            let kind = reloc.kind;
            if (arm64 && reloc::is_x86(kind)) || (!arm64 && reloc::is_arm64(kind)) {
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
pub(crate) fn place(cursor: u64, atoms: impl Iterator<Item = (u64, u64)>, min_align: u64) -> (u64, Vec<u64>, u64, u64) {
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

pub(crate) fn put16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

pub(crate) fn put32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

pub(crate) fn put64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placement() {
        let (start, addrs, end, align) = place(0x1003, [(1, 3), (16, 5), (4, 0), (4, 4)].into_iter(), 1);
        assert_eq!((start, align), (0x1010, 16));
        assert_eq!(addrs, [0x1010, 0x1020, 0x1028, 0x1028]);
        assert_eq!(end, 0x102c);
        let (start, addrs, end, align) = place(0x1003, std::iter::empty(), 8);
        assert_eq!((start, addrs.len(), end, align), (0x1008, 0, 0x1008, 8));
    }
}
