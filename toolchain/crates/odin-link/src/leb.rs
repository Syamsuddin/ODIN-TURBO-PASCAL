// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! LEB128 variable-length integers, as used by dyld's rebase, bind and export
//! trie encodings (and later by DWARF-style line tables).

/// Appends `value` as unsigned LEB128.
pub(crate) fn uleb128(out: &mut Vec<u8>, mut value: u64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            out.push(byte);
            return;
        }
        out.push(byte | 0x80);
    }
}

/// Appends `value` as signed LEB128.
pub(crate) fn sleb128(out: &mut Vec<u8>, mut value: i64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        let sign_clear = byte & 0x40 == 0;
        if (value == 0 && sign_clear) || (value == -1 && !sign_clear) {
            out.push(byte);
            return;
        }
        out.push(byte | 0x80);
    }
}

/// Number of bytes [`uleb128`] writes for `value`.
pub(crate) fn uleb128_len(value: u64) -> usize {
    let bits = 64 - value.leading_zeros() as usize;
    bits.div_ceil(7).max(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn u(value: u64) -> Vec<u8> {
        let mut out = Vec::new();
        uleb128(&mut out, value);
        out
    }

    fn s(value: i64) -> Vec<u8> {
        let mut out = Vec::new();
        sleb128(&mut out, value);
        out
    }

    #[test]
    fn unsigned_vectors() {
        assert_eq!(u(0), [0x00]);
        assert_eq!(u(1), [0x01]);
        assert_eq!(u(127), [0x7f]);
        assert_eq!(u(128), [0x80, 0x01]);
        assert_eq!(u(624_485), [0xe5, 0x8e, 0x26]);
        assert_eq!(u(u64::MAX), [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);
    }

    #[test]
    fn signed_vectors() {
        assert_eq!(s(0), [0x00]);
        assert_eq!(s(2), [0x02]);
        assert_eq!(s(-1), [0x7f]);
        assert_eq!(s(63), [0x3f]);
        assert_eq!(s(64), [0xc0, 0x00]);
        assert_eq!(s(-64), [0x40]);
        assert_eq!(s(-65), [0xbf, 0x7f]);
        assert_eq!(s(-123_456), [0xc0, 0xbb, 0x78]);
        assert_eq!(s(i64::MIN), [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x7f]);
        assert_eq!(s(i64::MAX), [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]);
    }

    #[test]
    fn length_matches_encoding() {
        for value in [0, 1, 127, 128, 16_383, 16_384, 1 << 35, u64::MAX] {
            assert_eq!(uleb128_len(value), u(value).len(), "{value}");
        }
    }
}
