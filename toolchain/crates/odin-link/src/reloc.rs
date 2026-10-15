// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Relocation arithmetic: computes a field's value and patches it into the
//! instruction or data bytes. Range and alignment are checked; nothing wraps.

use odin_asm::object::RelocKind;

/// Size in bytes of the field a relocation of `kind` patches.
pub(crate) fn field_size(kind: RelocKind) -> usize {
    match kind {
        RelocKind::Abs64 => 8,
        _ => 4,
    }
}

/// Whether `kind` addresses the target's GOT slot rather than the target.
pub(crate) fn uses_got(kind: RelocKind) -> bool {
    matches!(kind, RelocKind::X86GotPc32 | RelocKind::Arm64GotPage21 | RelocKind::Arm64GotPageOff12)
}

/// Whether `kind` only appears in x86-64 code.
pub(crate) fn is_x86(kind: RelocKind) -> bool {
    matches!(kind, RelocKind::X86Pc32 | RelocKind::X86GotPc32)
}

/// Whether `kind` only appears in AArch64 code.
pub(crate) fn is_arm64(kind: RelocKind) -> bool {
    !is_x86(kind) && kind != RelocKind::Abs64
}

/// The value does not fit the field, or is not a multiple of what the
/// instruction scales it by.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct OutOfRange;

/// Patches the field of `kind` at the start of `field`. `place` is the
/// field's address, `target` the address of the target (for the GOT kinds,
/// of its GOT slot) and `addend` the relocation's addend.
pub(crate) fn patch(kind: RelocKind, field: &mut [u8], place: u64, target: u64, addend: i64) -> Result<(), OutOfRange> {
    let s_plus_a = i128::from(target) + i128::from(addend);
    let pc_rel = s_plus_a - i128::from(place);
    match kind {
        RelocKind::X86Pc32 | RelocKind::X86GotPc32 => {
            let value = i32::try_from(pc_rel).map_err(|_| OutOfRange)?;
            field[..4].copy_from_slice(&value.to_le_bytes());
        }
        RelocKind::Abs64 => {
            let value = u64::try_from(s_plus_a).map_err(|_| OutOfRange)?;
            field[..8].copy_from_slice(&value.to_le_bytes());
        }
        RelocKind::Arm64Branch26 => {
            if pc_rel & 3 != 0 {
                return Err(OutOfRange);
            }
            let words = signed_bits(pc_rel >> 2, 26)?;
            update_insn(field, 0x03ff_ffff, words as u32 & 0x03ff_ffff);
        }
        RelocKind::Arm64Page21 | RelocKind::Arm64GotPage21 => {
            if s_plus_a < 0 {
                return Err(OutOfRange);
            }
            let pages = (s_plus_a >> 12) - (i128::from(place) >> 12);
            let pages = signed_bits(pages, 21)? as u32;
            let immlo = pages & 0x3;
            let immhi = (pages >> 2) & 0x7_ffff;
            update_insn(field, 0x6000_0000 | (0x7_ffff << 5), (immlo << 29) | (immhi << 5));
        }
        RelocKind::Arm64PageOff12 { scale } => page_off12(field, s_plus_a, scale)?,
        RelocKind::Arm64GotPageOff12 => page_off12(field, s_plus_a, 3)?,
    }
    Ok(())
}

fn page_off12(field: &mut [u8], s_plus_a: i128, scale: u8) -> Result<(), OutOfRange> {
    if s_plus_a < 0 || scale > 4 {
        return Err(OutOfRange);
    }
    let low = (s_plus_a & 0xfff) as u32;
    if low & ((1 << scale) - 1) != 0 {
        return Err(OutOfRange);
    }
    update_insn(field, 0xfff << 10, (low >> scale) << 10);
    Ok(())
}

/// `value` if it fits a signed field of `bits` bits.
fn signed_bits(value: i128, bits: u32) -> Result<i64, OutOfRange> {
    let limit = 1i128 << (bits - 1);
    if value < -limit || value >= limit {
        return Err(OutOfRange);
    }
    Ok(value as i64)
}

/// Replaces the bits selected by `mask` in a little-endian instruction word.
fn update_insn(field: &mut [u8], mask: u32, bits: u32) {
    let insn = u32::from_le_bytes(field[..4].try_into().unwrap());
    let insn = (insn & !mask) | (bits & mask);
    field[..4].copy_from_slice(&insn.to_le_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(kind: RelocKind, insn: u32, place: u64, target: u64, addend: i64) -> Result<u32, OutOfRange> {
        let mut field = insn.to_le_bytes();
        patch(kind, &mut field, place, target, addend)?;
        Ok(u32::from_le_bytes(field))
    }

    #[test]
    fn x86_pc32() {
        // lea rsi, [rip + msg]: field at 0x1000, instruction ends at 0x1004.
        let value = run(RelocKind::X86Pc32, 0, 0x1000, 0x2000, -4).unwrap();
        assert_eq!(value as i32, 0x2000 - 0x1004);
        let back = run(RelocKind::X86Pc32, 0, 0x2000, 0x1000, -4).unwrap();
        assert_eq!(back as i32, 0x1000 - 0x2004);
        // An imm8 after the displacement moves the end of the instruction.
        assert_eq!(run(RelocKind::X86GotPc32, 0, 0x10, 0x30, -5).unwrap() as i32, 0x30 - 0x15);
        let far = 0x1_0000_0000u64;
        assert_eq!(run(RelocKind::X86Pc32, 0, 0, far, 0), Err(OutOfRange));
        assert_eq!(run(RelocKind::X86Pc32, 0, far, 0, 0), Err(OutOfRange));
        assert!(run(RelocKind::X86Pc32, 0, 0, 0x7fff_ffff, 0).is_ok());
        assert_eq!(run(RelocKind::X86Pc32, 0, 0, 0x8000_0000, 0), Err(OutOfRange));
    }

    #[test]
    fn abs64() {
        let mut field = [0xaa; 8];
        patch(RelocKind::Abs64, &mut field, 0, 0x1_0000_4000, 16).unwrap();
        assert_eq!(u64::from_le_bytes(field), 0x1_0000_4010);
        assert_eq!(patch(RelocKind::Abs64, &mut field, 0, 8, -16), Err(OutOfRange));
    }

    #[test]
    fn arm64_branch26() {
        const BL: u32 = 0x9400_0000;
        assert_eq!(run(RelocKind::Arm64Branch26, BL, 0x18, 0x38, 0).unwrap(), 0x9400_0008);
        assert_eq!(run(RelocKind::Arm64Branch26, BL, 0x38, 0x18, 0).unwrap(), 0x97ff_fff8);
        let max = (1u64 << 27) - 4;
        assert_eq!(run(RelocKind::Arm64Branch26, BL, 0, max, 0).unwrap(), 0x95ff_ffff);
        assert_eq!(run(RelocKind::Arm64Branch26, BL, 0, max + 4, 0), Err(OutOfRange));
        assert_eq!(run(RelocKind::Arm64Branch26, BL, 1 << 27, 0, 0).unwrap(), 0x9600_0000);
        assert_eq!(run(RelocKind::Arm64Branch26, BL, (1 << 27) + 4, 0, 0), Err(OutOfRange));
        assert_eq!(run(RelocKind::Arm64Branch26, BL, 0, 0x40, 2), Err(OutOfRange));
    }

    #[test]
    fn arm64_page21() {
        const ADRP_X1: u32 = 0x9000_0001;
        // One page forward: immlo = 1.
        assert_eq!(run(RelocKind::Arm64Page21, ADRP_X1, 0x1_0000_0ffc, 0x1_0000_1000, 0).unwrap(), 0xb000_0001);
        // Same page, any offset.
        assert_eq!(run(RelocKind::Arm64Page21, ADRP_X1, 0x1_0000_0000, 0x1_0000_0fff, 0).unwrap(), ADRP_X1);
        // Five pages: immlo = 1, immhi = 1.
        assert_eq!(run(RelocKind::Arm64GotPage21, ADRP_X1, 0, 0x5000, 0).unwrap(), 0xb000_0021);
        // One page back: all ones.
        assert_eq!(run(RelocKind::Arm64Page21, ADRP_X1, 0x2000, 0x1000, 0).unwrap(), 0xf0ff_ffe1);
        // The addend moves the target, not the place.
        assert_eq!(run(RelocKind::Arm64Page21, ADRP_X1, 0, 0xff8, 8).unwrap(), 0xb000_0001);
        assert!(run(RelocKind::Arm64Page21, ADRP_X1, 0, (1 << 32) - 0x1000, 0).is_ok());
        assert_eq!(run(RelocKind::Arm64Page21, ADRP_X1, 0, 1 << 32, 0), Err(OutOfRange));
    }

    #[test]
    fn arm64_page_off12() {
        const ADD_X1: u32 = 0x9100_0021;
        const LDR_X16: u32 = 0xf940_0210;
        assert_eq!(run(RelocKind::Arm64PageOff12 { scale: 0 }, ADD_X1, 0, 0x1_0000_0abc, 0).unwrap(), 0x912a_f021);
        assert_eq!(run(RelocKind::Arm64PageOff12 { scale: 0 }, ADD_X1, 0, 0x3ff8, 9).unwrap(), 0x9100_0421);
        assert_eq!(run(RelocKind::Arm64GotPageOff12, LDR_X16, 0, 0x4018, 0).unwrap(), 0xf9400e10);
        assert_eq!(run(RelocKind::Arm64PageOff12 { scale: 3 }, LDR_X16, 0, 0x4018, 0).unwrap(), 0xf9400e10);
        assert_eq!(run(RelocKind::Arm64GotPageOff12, LDR_X16, 0, 0x4014, 0), Err(OutOfRange));
        assert_eq!(run(RelocKind::Arm64PageOff12 { scale: 2 }, LDR_X16, 0, 0x4014, 0).unwrap(), 0xf9401610);
        assert_eq!(run(RelocKind::Arm64PageOff12 { scale: 5 }, LDR_X16, 0, 0, 0), Err(OutOfRange));
    }

    #[test]
    fn kind_classes() {
        assert!(uses_got(RelocKind::X86GotPc32) && uses_got(RelocKind::Arm64GotPageOff12));
        assert!(!uses_got(RelocKind::Abs64) && !uses_got(RelocKind::Arm64Page21));
        assert!(is_x86(RelocKind::X86Pc32) && !is_x86(RelocKind::Abs64));
        assert!(is_arm64(RelocKind::Arm64Branch26) && !is_arm64(RelocKind::Abs64) && !is_arm64(RelocKind::X86GotPc32));
        assert_eq!(field_size(RelocKind::Abs64), 8);
        assert_eq!(field_size(RelocKind::Arm64PageOff12 { scale: 3 }), 4);
    }
}
