// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Immediate encodings: `add`/`sub` 12-bit immediates, logical bitmask
//! immediates, `fmov` 8-bit floating-point immediates, and the instruction
//! sequences [`mov_imm`](super::Assembler::mov_imm) uses to build any
//! constant.

/// The `sh:imm12` field (bits 22–10) of `add`/`sub` (immediate) for
/// `value`: 0–4095, or a multiple of 4096 up to 4095 × 4096 (`lsl #12`).
pub(crate) fn add_imm(value: u64) -> Option<u32> {
    if value < 1 << 12 {
        Some((value as u32) << 10)
    } else if value & 0xfff == 0 && value < 1 << 24 {
        Some(1 << 22 | ((value >> 12) as u32) << 10)
    } else {
        None
    }
}

/// Encodes `value` as a logical (bitmask) immediate of a `bits`-bit (32 or
/// 64) instruction, returning the 13-bit `N:immr:imms` field.
///
/// Encodable values are a run of ones, rotated, repeated across elements of
/// 2, 4, 8, 16, 32 or 64 bits: `0xff`, `0xfffffff0`,
/// `0x5555_5555_5555_5555`, `0x00ff_00ff_00ff_00ff`. Zero and all ones are
/// never encodable. Only the low `bits` bits of `value` are used.
pub fn logical_imm(value: u64, bits: u32) -> Option<u32> {
    let mask = if bits == 64 { u64::MAX } else { (1u64 << bits) - 1 };
    let v = value & mask;
    if v == 0 || v == mask {
        return None;
    }
    // Smallest element that repeats to make up the value.
    let mut size = bits;
    while size > 2 {
        let half = size / 2;
        let hmask = (1u64 << half) - 1;
        if v & hmask != (v >> half) & hmask {
            break;
        }
        size = half;
    }
    let emask = if size == 64 { u64::MAX } else { (1u64 << size) - 1 };
    let elem = v & emask;
    let ones = elem.count_ones();
    let run = (1u64 << ones) - 1; // ones < size: elem is neither 0 nor all ones
    // elem = ROR(run, immr): find the rotation that brings the run to bit 0.
    let rotl = |x: u64, r: u32| if r == 0 { x } else { ((x << r) | (x >> (size - r))) & emask };
    let immr = (0..size).find(|&r| rotl(elem, r) == run)?;
    let n = (size == 64) as u32;
    let imms = ((!(size - 1) << 1) & 0x3f) | (ones - 1);
    Some(n << 12 | immr << 6 | imms)
}

/// Encodes `value` as the 8-bit immediate of `fmov` (scalar): ±(16..31)/16
/// × 2^e with e from -3 to 4, i.e. ±0.125 to ±31.0 in steps that need at
/// most 4 fraction bits. Zero is not encodable (`fmov` from `xzr` instead).
/// Such a value is exact in both single and double precision.
pub fn fp_imm8(value: f64) -> Option<u8> {
    let bits = value.to_bits();
    let sign = (bits >> 63) as u8;
    let exp = ((bits >> 52) & 0x7ff) as u32;
    let frac = bits & ((1u64 << 52) - 1);
    if frac & ((1u64 << 48) - 1) != 0 || !(0x3fc..=0x403).contains(&exp) {
        return None;
    }
    // exp = NOT(b) : b b b b b b b b : c d (bit 10 is the inverse of b).
    let b = 1 - (exp >> 10) as u8;
    Some(sign << 7 | b << 6 | ((exp & 3) as u8) << 4 | (frac >> 48) as u8)
}

/// One instruction of a constant-building sequence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum MovStep {
    /// `movz rd, #imm, lsl #shift`
    Movz(u16, u8),
    /// `movn rd, #imm, lsl #shift`
    Movn(u16, u8),
    /// `movk rd, #imm, lsl #shift`
    Movk(u16, u8),
    /// `orr rd, zr, #bitmask` with the `N:immr:imms` field.
    Orr(u32),
}

/// The shortest sequence that sets a `bits`-bit register to `value` (only
/// the low `bits` bits are used).
///
/// A single instruction is chosen the way clang chooses the encoding of
/// `mov rd, #imm`: `movz`, then `movn`, then `orr`. Longer sequences are a
/// `movz` or `movn` followed by `movk`s for the remaining 16-bit chunks, or
/// an `orr` of a nearby bitmask pattern followed by `movk`s, whichever is
/// shortest (`movz` first on ties).
pub(crate) fn mov_plan(value: u64, bits: u32) -> Vec<MovStep> {
    let n = (bits / 16) as usize;
    let mask = if bits == 64 { u64::MAX } else { (1u64 << bits) - 1 };
    let v = value & mask;
    let chunk = |x: u64, i: usize| (x >> (16 * i)) as u16;
    let chunks: Vec<u16> = (0..n).map(|i| chunk(v, i)).collect();
    let shift = |i: usize| (16 * i) as u8;

    // movz/movn chains: the first chunk that differs from the background
    // (0 or 0xffff) is set by movz/movn, the others by movk.
    let chain = |background: u16| -> Vec<MovStep> {
        let mut steps = Vec::new();
        for (i, &c) in chunks.iter().enumerate() {
            if c == background {
                continue;
            }
            steps.push(match (steps.is_empty(), background) {
                (true, 0) => MovStep::Movz(c, shift(i)),
                (true, _) => MovStep::Movn(!c, shift(i)),
                (false, _) => MovStep::Movk(c, shift(i)),
            });
        }
        if steps.is_empty() {
            steps.push(if background == 0 { MovStep::Movz(0, 0) } else { MovStep::Movn(0, 0) });
        }
        steps
    };
    let movz = chain(0);
    let movn = chain(0xffff);
    if movz.len() == 1 {
        return movz;
    }
    if movn.len() == 1 {
        return movn;
    }
    if let Some(field) = logical_imm(v, bits) {
        return vec![MovStep::Orr(field)];
    }

    // orr of a bitmask pattern that agrees with `v` on most chunks, then
    // movk for the chunks where it does not.
    let mut patterns: Vec<u64> = Vec::new();
    let replicate = |unit: u64, width: u32| (0..bits / width).fold(0u64, |acc, k| acc | unit << (k * width));
    for &c in &chunks {
        patterns.push(replicate(c as u64, 16));
    }
    if bits == 64 {
        patterns.push(replicate(v & 0xffff_ffff, 32));
        patterns.push(replicate(v >> 32, 32));
    }
    for i in 0..n {
        let cleared = v & !(0xffffu64 << (16 * i));
        for fill in chunks.iter().copied().chain([0, 0xffff]) {
            patterns.push(cleared | (fill as u64) << (16 * i));
        }
    }
    let mut best = if movn.len() < movz.len() { movn } else { movz };
    for p in patterns {
        let Some(field) = logical_imm(p, bits) else { continue };
        let fixes: Vec<usize> = (0..n).filter(|&i| chunk(p & mask, i) != chunks[i]).collect();
        if 1 + fixes.len() < best.len() {
            best = std::iter::once(MovStep::Orr(field))
                .chain(fixes.into_iter().map(|i| MovStep::Movk(chunks[i], shift(i))))
                .collect();
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Decodes a logical immediate field (the reference definition from the
    /// architecture manual), to check the encoder against.
    fn decode_logical(field: u32, bits: u32) -> u64 {
        let n = field >> 12;
        let immr = (field >> 6) & 0x3f;
        let imms = field & 0x3f;
        let len = 31 - ((n << 6) | (!imms & 0x3f)).leading_zeros();
        let size = 1u32 << len;
        let s = imms & (size - 1);
        let r = immr & (size - 1);
        let emask = if size == 64 { u64::MAX } else { (1u64 << size) - 1 };
        let run = (1u64 << (s + 1)) - 1;
        let elem = if r == 0 { run } else { ((run >> r) | (run << (size - r))) & emask };
        (0..bits / size).fold(0, |acc, k| acc | elem << (k * size))
    }

    #[test]
    fn logical_immediates_round_trip() {
        // Every encodable 32- and 64-bit pattern: element size, run length
        // and rotation.
        let mut count = 0;
        for bits in [32u32, 64] {
            let mut size = 2;
            while size <= bits {
                for ones in 1..size {
                    for rot in 0..size {
                        let emask = if size == 64 { u64::MAX } else { (1u64 << size) - 1 };
                        let run = (1u64 << ones) - 1;
                        let elem = if rot == 0 { run } else { ((run >> rot) | (run << (size - rot))) & emask };
                        let v = (0..bits / size).fold(0, |acc, k| acc | elem << (k * size));
                        let field = logical_imm(v, bits).unwrap_or_else(|| panic!("{v:#x} ({bits} bits)"));
                        assert_eq!(decode_logical(field, bits), v, "{v:#x}");
                        count += 1;
                    }
                }
                size *= 2;
            }
        }
        assert_eq!(count, 1302 + 5334);
        for (v, bits) in [(0, 64), (u64::MAX, 64), (0xffff_ffff, 32), (5, 64), (0x1234, 32), (0xff00_ff01, 32)] {
            assert_eq!(logical_imm(v, bits), None, "{v:#x}");
        }
        // Known encodings (from clang): and w0, w1, #0xfffffffe; orr x0, x1, #0xffffffffffffff00.
        assert_eq!(logical_imm(0xffff_fffe, 32), Some(0x1f << 6 | 0x1e));
        assert_eq!(logical_imm(0xffff_ffff_ffff_ff00, 64), Some(1 << 12 | 0x38 << 6 | 0x37));
    }

    #[test]
    fn fp_immediates() {
        assert_eq!(fp_imm8(1.0), Some(0x70));
        assert_eq!(fp_imm8(1.5), Some(0x78));
        assert_eq!(fp_imm8(-0.125), Some(0xc0));
        assert_eq!(fp_imm8(31.0), Some(0x3f));
        assert_eq!(fp_imm8(0.125), Some(0x40));
        assert_eq!(fp_imm8(2.0), Some(0x00));
        for bad in [0.0, -0.0, 0.1, 32.0, 0.0625, 1.03125, f64::NAN, f64::INFINITY] {
            assert_eq!(fp_imm8(bad), None, "{bad}");
        }
        // All 256 encodings round-trip through their f64 value.
        for imm in 0..=255u8 {
            let sign = if imm & 0x80 != 0 { -1.0 } else { 1.0 };
            let exp = ((imm >> 4) & 7) as i32;
            let exp = if exp >= 4 { exp - 8 } else { exp } + 1; // b=1 → -3..0, b=0 → 1..4
            let mant = 1.0 + (imm & 15) as f64 / 16.0;
            let value = sign * mant * 2f64.powi(exp);
            assert_eq!(fp_imm8(value), Some(imm), "{value}");
        }
    }

    /// Runs a plan on a `bits`-bit register.
    fn eval(plan: &[MovStep], bits: u32) -> u64 {
        let mask = if bits == 64 { u64::MAX } else { (1u64 << bits) - 1 };
        let mut r = 0u64;
        for step in plan {
            r = match *step {
                MovStep::Movz(imm, sh) => (imm as u64) << sh,
                MovStep::Movn(imm, sh) => !((imm as u64) << sh),
                MovStep::Movk(imm, sh) => (r & !(0xffffu64 << sh)) | (imm as u64) << sh,
                MovStep::Orr(field) => decode_logical(field, bits),
            } & mask;
        }
        r
    }

    #[test]
    fn mov_plans_build_the_value() {
        let mut seed = 0x9e37_79b9_7f4a_7c15u64;
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        let mut values = vec![
            0,
            1,
            u64::MAX,
            0xffff,
            0x1_0000,
            0xffff_ffff,
            0x8000_0000_0000_0000,
            0x1234_5678_9abc_def0,
            0xffff_ffff_0000_0001,
            0x5555_5555_5555_5555,
            0x5555_5555_5555_1234,
            0x00ff_00ff_1234_00ff,
            0x7fff_ffff,
            0xffff_0000_ffff_0000,
        ];
        for _ in 0..2000 {
            let r = next();
            // Random values, and random values with chunks of 0 / 0xffff.
            let mut v = r;
            for i in 0..4 {
                match (r >> (60 - 2 * i)) & 3 {
                    0 => v &= !(0xffffu64 << (16 * i)),
                    1 => v |= 0xffffu64 << (16 * i),
                    _ => {}
                }
            }
            values.push(v);
            values.push(r);
        }
        for v in values {
            for bits in [32, 64] {
                let mask = if bits == 64 { u64::MAX } else { 0xffff_ffff };
                let plan = mov_plan(v, bits);
                assert_eq!(eval(&plan, bits), v & mask, "{v:#x} ({bits} bits): {plan:?}");
                assert!(plan.len() <= (bits / 16) as usize, "{v:#x}: {plan:?}");
            }
        }
        // clang's single-instruction choices.
        assert_eq!(mov_plan(0, 64), [MovStep::Movz(0, 0)]);
        assert_eq!(mov_plan(u64::MAX, 64), [MovStep::Movn(0, 0)]);
        assert_eq!(mov_plan(0xffff_0000, 32), [MovStep::Movz(0xffff, 16)]);
        assert_eq!(mov_plan(0x7fff_ffff, 32), [MovStep::Movn(0x8000, 16)]);
        assert!(matches!(mov_plan(0xffff_ffff, 64)[..], [MovStep::Orr(_)]));
        // orr + movk beats a 4-instruction chain.
        assert_eq!(mov_plan(0x5555_5555_5555_1234, 64).len(), 2);
    }
}
