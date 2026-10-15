#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Regenerate the x86-64 encoding goldens with the system assembler.

Run on a Mac with Xcode or the Command Line Tools (needs `clang`):

    python3 crates/odin-asm/tests/gen_golden.py

Two files are rewritten next to this script:

* x86_64_golden.txt: one instruction per line. Only the left column (the
  Intel-syntax instruction) is read; the expected bytes and relocations are
  recomputed. Comment lines (`#`) and blank lines are kept.
* x86_64_blocks.golden: generated from x86_64_blocks.s, one line per block
  (a block is everything from a non-`.L` label to the next one).

Each case is assembled by clang as Intel syntax for x86_64-apple-macos, and
the bytes and relocations are read straight from the Mach-O object, so the
script needs no otool/objdump. A relocation is written as
`offset:kind:addend` with kind `pc32`, `got` or `abs64` and the addend in the
convention of odin_asm::object (S + A - P), derived from the value clang
stores in the field: for PC-relative kinds A = field - 4, so the correction
for a trailing immediate (Mach-O X86_64_RELOC_SIGNED_1/2/4) is included.

Labels starting with `.L` are ordinary symbols on Darwin (clang would emit
relocations for them), so in the blocks file they are renamed to block-unique
assembler-temporary `L` labels before assembling.
"""

import os
import re
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
INSNS = os.path.join(HERE, "x86_64_golden.txt")
BLOCKS_SRC = os.path.join(HERE, "x86_64_blocks.s")
BLOCKS_OUT = os.path.join(HERE, "x86_64_blocks.golden")

LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2


def assemble(source):
    """Assemble `source` with clang; return (text bytes, symbols, relocs).

    symbols maps name -> offset in __text; relocs is a list of
    (offset, kind, addend)."""
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "golden.s")
        obj = os.path.join(tmp, "golden.o")
        with open(src, "w") as f:
            f.write(source)
        subprocess.run(
            ["clang", "-target", "x86_64-apple-macos11", "-c", "-x", "assembler", src, "-o", obj],
            check=True,
        )
        with open(obj, "rb") as f:
            data = f.read()
    return parse_macho(data)


def parse_macho(data):
    magic, _cpu, _sub, _ftype, ncmds, _size, _flags, _res = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != 0xFEEDFACF:
        sys.exit("not a 64-bit Mach-O object")
    off = 32
    sections = []
    symtab = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_SEGMENT_64:
            (nsects,) = struct.unpack_from("<I", data, off + 64)
            s = off + 72
            for _ in range(nsects):
                name = data[s : s + 16].rstrip(b"\0").decode()
                seg = data[s + 16 : s + 32].rstrip(b"\0").decode()
                addr, size, offset, _align, reloff, nreloc = struct.unpack_from("<QQIIII", data, s + 32)
                sections.append((seg, name, addr, size, offset, reloff, nreloc))
                s += 80
        elif cmd == LC_SYMTAB:
            symtab = struct.unpack_from("<IIII", data, off + 8)
        off += cmdsize
    text_index = next(i for i, s in enumerate(sections) if s[:2] == ("__TEXT", "__text"))
    _seg, _name, addr, size, offset, reloff, nreloc = sections[text_index]
    text = data[offset : offset + size]

    symoff, nsyms, stroff, _strsize = symtab
    names = []
    symbols = {}
    for i in range(nsyms):
        strx, ntype, nsect, _desc, value = struct.unpack_from("<IBBHQ", data, symoff + 16 * i)
        end = data.index(b"\0", stroff + strx)
        name = data[stroff + strx : end].decode()
        names.append(name)
        if ntype & 0xE0 == 0 and ntype & 0x0E == 0x0E and nsect == text_index + 1:
            symbols[name] = value - addr

    relocs = []
    for i in range(nreloc):
        address, word = struct.unpack_from("<iI", data, reloff + 8 * i)
        rtype = word >> 28
        length = (word >> 25) & 3
        if rtype == 0 and length == 3:
            kind = "abs64"
            addend = struct.unpack_from("<q", text, address)[0]
        elif rtype in (1, 2, 6, 7, 8):  # SIGNED, BRANCH, SIGNED_1/2/4
            kind = "pc32"
            addend = struct.unpack_from("<i", text, address)[0] - 4
        elif rtype in (3, 4):  # GOT_LOAD, GOT
            kind = "got"
            addend = struct.unpack_from("<i", text, address)[0] - 4
        else:
            sys.exit(f"unexpected relocation type {rtype} at {address:#x}")
        relocs.append((address, kind, addend))
    return text, symbols, relocs


def slice_case(text, relocs, start, end):
    hexbytes = " ".join(f"{b:02x}" for b in text[start:end])
    rel = ",".join(f"{o - start}:{k}:{a}" for o, k, a in sorted(relocs) if start <= o < end)
    return hexbytes, rel


def format_line(left, hexbytes, rel):
    line = f"{left:<46} | {hexbytes}"
    return f"{line} | {rel}" if rel else line


def gen_insns():
    with open(INSNS) as f:
        lines = f.read().splitlines()
    cases = []
    source = [".intel_syntax noprefix", ".text"]
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        insn = stripped.split("|")[0].strip()
        cases.append((i, insn))
        source += [f"_t{len(cases) - 1:04}:", f"    {insn}"]
    source.append("_tend:")
    text, symbols, relocs = assemble("\n".join(source) + "\n")
    for n, (i, insn) in enumerate(cases):
        start = symbols[f"_t{n:04}"]
        end = symbols[f"_t{n + 1:04}"] if n + 1 < len(cases) else symbols["_tend"]
        lines[i] = format_line(insn, *slice_case(text, relocs, start, end))
    with open(INSNS, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{INSNS}: {len(cases)} instructions")


BLOCK_LABEL = re.compile(r"^([A-Za-z_$][\w$.]*):")
LOCAL = re.compile(r"\.L([\w$.]+)")


def gen_blocks():
    with open(BLOCKS_SRC) as f:
        lines = f.read().splitlines()
    names = []
    out = []
    for line in lines:
        m = BLOCK_LABEL.match(line)
        if m:
            if names:
                out.append(f"{names[-1]}__end:")
            names.append(m.group(1))
            out.append(".p2align 6")
        k = len(names)
        out.append(LOCAL.sub(lambda m: f"L{k}_{m.group(1)}", line))
    out.append(f"{names[-1]}__end:")
    text, symbols, relocs = assemble("\n".join(out) + "\n")
    result = [
        "# Generated by gen_golden.py from x86_64_blocks.s: block | bytes | relocations.",
        "# Do not edit by hand.",
    ]
    for name in names:
        result.append(format_line(name, *slice_case(text, relocs, symbols[name], symbols[f"{name}__end"])))
    with open(BLOCKS_OUT, "w") as f:
        f.write("\n".join(result) + "\n")
    print(f"{BLOCKS_OUT}: {len(names)} blocks")


if __name__ == "__main__":
    gen_insns()
    gen_blocks()
