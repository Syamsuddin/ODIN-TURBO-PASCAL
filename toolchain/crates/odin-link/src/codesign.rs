// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Ad-hoc, linker-signed embedded code signature: a SuperBlob holding one
//! CodeDirectory with the SHA-256 of every 4 KiB page before the signature.
//! This is the shape Apple's `ld` writes for arm64 executables; the kernel
//! requires it on Apple Silicon and accepts it on Intel.
//!
//! Every field of the signature is big-endian, unlike the rest of Mach-O.

use odin_base::sha256::sha256;

const CSMAGIC_EMBEDDED_SIGNATURE: u32 = 0xfade_0cc0;
const CSMAGIC_CODEDIRECTORY: u32 = 0xfade_0c02;
const CSSLOT_CODEDIRECTORY: u32 = 0;
/// CodeDirectory version with the executable-segment fields.
const CS_SUPPORTSEXECSEG: u32 = 0x2_0400;
const CS_ADHOC: u32 = 0x2;
const CS_LINKER_SIGNED: u32 = 0x2_0000;
const CS_HASHTYPE_SHA256: u8 = 2;
const CS_EXECSEG_MAIN_BINARY: u64 = 0x1;

const PAGE_SIZE_LOG2: u8 = 12;
const PAGE_SIZE: usize = 1 << PAGE_SIZE_LOG2;
const HASH_SIZE: usize = 32;
/// magic, length, count.
const SUPERBLOB_HEADER: usize = 12;
/// type, offset.
const BLOB_INDEX: usize = 8;
/// Fixed part of a version 0x20400 CodeDirectory.
const CODE_DIRECTORY_HEADER: usize = 88;

/// Size in bytes of the signature over the first `code_limit` bytes of a
/// file, signed as `identifier`.
pub(crate) fn signature_size(identifier: &str, code_limit: usize) -> usize {
    SUPERBLOB_HEADER
        + BLOB_INDEX
        + CODE_DIRECTORY_HEADER
        + identifier.len()
        + 1
        + code_limit.div_ceil(PAGE_SIZE) * HASH_SIZE
}

/// Signs `file[..code_limit]` and writes the signature at `code_limit`.
/// `file` must already extend at least [`signature_size`] bytes past
/// `code_limit`, and nothing before `code_limit` may change afterwards.
/// `exec_segment` is the file offset and size of `__TEXT`.
pub(crate) fn sign(file: &mut [u8], code_limit: usize, identifier: &str, exec_segment: (u64, u64)) {
    let pages = code_limit.div_ceil(PAGE_SIZE);
    let ident_offset = CODE_DIRECTORY_HEADER;
    let hash_offset = ident_offset + identifier.len() + 1;
    let directory_len = hash_offset + pages * HASH_SIZE;
    let total = SUPERBLOB_HEADER + BLOB_INDEX + directory_len;
    debug_assert_eq!(total, signature_size(identifier, code_limit));

    let mut blob = Vec::with_capacity(total);
    // SuperBlob with one index entry.
    put32(&mut blob, CSMAGIC_EMBEDDED_SIGNATURE);
    put32(&mut blob, total as u32);
    put32(&mut blob, 1);
    put32(&mut blob, CSSLOT_CODEDIRECTORY);
    put32(&mut blob, (SUPERBLOB_HEADER + BLOB_INDEX) as u32);
    // CodeDirectory.
    put32(&mut blob, CSMAGIC_CODEDIRECTORY);
    put32(&mut blob, directory_len as u32);
    put32(&mut blob, CS_SUPPORTSEXECSEG);
    put32(&mut blob, CS_ADHOC | CS_LINKER_SIGNED);
    put32(&mut blob, hash_offset as u32);
    put32(&mut blob, ident_offset as u32);
    put32(&mut blob, 0); // nSpecialSlots
    put32(&mut blob, pages as u32); // nCodeSlots
    put32(&mut blob, code_limit as u32);
    // hashSize, hashType, platform, pageSize
    blob.extend_from_slice(&[HASH_SIZE as u8, CS_HASHTYPE_SHA256, 0, PAGE_SIZE_LOG2]);
    put32(&mut blob, 0); // spare2
    put32(&mut blob, 0); // scatterOffset
    put32(&mut blob, 0); // teamOffset
    put32(&mut blob, 0); // spare3
    put64(&mut blob, 0); // codeLimit64: unused below 4 GiB
    put64(&mut blob, exec_segment.0);
    put64(&mut blob, exec_segment.1);
    put64(&mut blob, CS_EXECSEG_MAIN_BINARY);
    debug_assert_eq!(blob.len(), SUPERBLOB_HEADER + BLOB_INDEX + CODE_DIRECTORY_HEADER);
    blob.extend_from_slice(identifier.as_bytes());
    blob.push(0);
    for page in file[..code_limit].chunks(PAGE_SIZE) {
        blob.extend_from_slice(&sha256(page));
    }
    debug_assert_eq!(blob.len(), total);
    file[code_limit..code_limit + total].copy_from_slice(&blob);
}

fn put32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_be_bytes());
}

fn put64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn be32(data: &[u8], at: usize) -> u32 {
        u32::from_be_bytes(data[at..at + 4].try_into().unwrap())
    }

    #[test]
    fn size_matches_ld() {
        // `ld` signed a 0xc140-byte arm64 hello world as "hello_arm" with a
        // 534-byte SuperBlob.
        assert_eq!(signature_size("hello_arm", 0xc140), 534);
    }

    #[test]
    fn layout_and_hashes() {
        let code_limit = 5000;
        let size = signature_size("t", code_limit);
        let mut file: Vec<u8> = (0..code_limit + size).map(|i| (i % 251) as u8).collect();
        sign(&mut file, code_limit, "t", (0, 0x1000));
        let sig = &file[code_limit..];
        assert_eq!(be32(sig, 0), CSMAGIC_EMBEDDED_SIGNATURE);
        assert_eq!(be32(sig, 4) as usize, size);
        assert_eq!(be32(sig, 8), 1);
        let cd = &sig[20..];
        assert_eq!(be32(cd, 0), CSMAGIC_CODEDIRECTORY);
        assert_eq!(be32(cd, 8), 0x2_0400);
        assert_eq!(be32(cd, 12), 0x2_0002);
        assert_eq!(be32(cd, 16), 90); // hashOffset
        assert_eq!(be32(cd, 20), 88); // identOffset
        assert_eq!(be32(cd, 28), 2); // nCodeSlots
        assert_eq!(be32(cd, 32) as usize, code_limit);
        assert_eq!(&cd[36..40], &[32, 2, 0, 12]);
        assert_eq!(&cd[72..80], &0x1000u64.to_be_bytes());
        assert_eq!(&cd[88..90], b"t\0");
        let original: Vec<u8> = (0..code_limit).map(|i| (i % 251) as u8).collect();
        assert_eq!(&cd[90..122], &sha256(&original[..4096]));
        assert_eq!(&cd[122..154], &sha256(&original[4096..]));
    }
}
