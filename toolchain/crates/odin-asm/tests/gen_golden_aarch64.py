#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Regenerate the AArch64 encoding goldens with the system assembler.

Run on a Mac with Xcode or the Command Line Tools (needs `clang`, which
assembles arm64 on Intel Macs too):

    python3 crates/odin-asm/tests/gen_golden_aarch64.py

Two files are rewritten next to this script:

* aarch64_golden.txt: one instruction per line. Only the left column is
  read; the expected words and relocations are recomputed. Comment lines
  (`#`) and blank lines are kept. A line `#@ target elf` makes the
  following instructions assemble for aarch64-linux-gnu (ELF syntax such as
  `:lo12:sym`), `#@ target darwin` switches back to arm64-apple-macos11
  (the default, `sym@PAGEOFF`).
* aarch64_blocks.golden: generated from aarch64_blocks.s (Darwin), one line
  per block (a block is everything from a non-`.L` label to the next one).

The words column lists the 32-bit little-endian words of the code in hex;
`w*n` stands for n copies of w. A relocation is written as
`offset:kind:addend` with kind `branch26`, `page21`, `pageoff12/S` (S is
the access-size scale), `gotpage21`, `gotpageoff12` or `abs64`, in the
convention of odin_asm::object. The script reads Mach-O and ELF objects
itself (no otool/objdump): on Mach-O the addend comes from a preceding
ARM64_RELOC_ADDEND (or the data, for abs64) and the PAGEOFF12 scale from
the instruction it patches; on ELF both come from the RELA entry.

Two adjustments let clang assemble the same blocks as odin_asm::text:

* Labels starting with `.L` are ordinary symbols on Darwin, so they are
  renamed to block-unique assembler-temporary `L` labels.
* clang does not relax out-of-range conditional branches. A line may end in
  `//@ insn || insn ...`: odin_asm assembles the line as written, clang the
  listed instructions instead (the expected relaxed form).
"""

import os
import re
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
INSNS = os.path.join(HERE, "aarch64_golden.txt")
BLOCKS_SRC = os.path.join(HERE, "aarch64_blocks.s")
BLOCKS_OUT = os.path.join(HERE, "aarch64_blocks.golden")

TARGETS = {"darwin": "arm64-apple-macos11", "elf": "aarch64-linux-gnu"}

LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2


def assemble(source, target):
    """Assemble `source` with clang; return (text bytes, symbols, relocs).

    symbols maps name -> offset in the text section; relocs is a list of
    (offset, kind, addend)."""
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "golden.s")
        obj = os.path.join(tmp, "golden.o")
        with open(src, "w") as f:
            f.write(source)
        subprocess.run(
            ["clang", "-target", TARGETS[target], "-c", "-x", "assembler", src, "-o", obj],
            check=True,
        )
        with open(obj, "rb") as f:
            data = f.read()
    return parse_macho(data) if target == "darwin" else parse_elf(data)


def pageoff_scale(insn):
    """Scale of a PAGEOFF12 field: log2 of the access size for a load/store
    (unsigned offset), 0 for `add`."""
    if insn & 0x3B000000 == 0x39000000:
        size, v, opc = insn >> 30, (insn >> 26) & 1, (insn >> 22) & 3
        return 4 if v and opc & 2 else size
    if insn & 0x7F800000 == 0x11000000:  # add (immediate), 32 or 64 bit
        return 0
    sys.exit(f"PAGEOFF12 on an unexpected instruction {insn:#010x}")


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
    symbols = {}
    for i in range(nsyms):
        strx, ntype, nsect, _desc, value = struct.unpack_from("<IBBHQ", data, symoff + 16 * i)
        end = data.index(b"\0", stroff + strx)
        name = data[stroff + strx : end].decode()
        if ntype & 0xE0 == 0 and ntype & 0x0E == 0x0E and nsect == text_index + 1:
            symbols[name] = value - addr

    relocs = []
    pending_addend = 0
    for i in range(nreloc):
        address, word = struct.unpack_from("<iI", data, reloff + 8 * i)
        symbolnum = word & 0xFFFFFF
        length = (word >> 25) & 3
        rtype = word >> 28
        if rtype == 10:  # ARM64_RELOC_ADDEND: the addend of the next entry
            pending_addend = symbolnum - (1 << 24) if symbolnum & 0x800000 else symbolnum
            continue
        addend, pending_addend = pending_addend, 0
        if rtype == 0 and length == 3:
            kind = "abs64"
            addend = struct.unpack_from("<q", text, address)[0]
        elif rtype == 2:
            kind = "branch26"
        elif rtype == 3:
            kind = "page21"
        elif rtype == 4:
            kind = f"pageoff12/{pageoff_scale(struct.unpack_from('<I', text, address)[0])}"
        elif rtype == 5:
            kind = "gotpage21"
        elif rtype == 6:
            kind = "gotpageoff12"
        else:
            sys.exit(f"unexpected relocation type {rtype} at {address:#x}")
        relocs.append((address, kind, addend))
    return text, symbols, relocs


ELF_RELOCS = {
    257: "abs64",
    282: "branch26",  # JUMP26
    283: "branch26",  # CALL26
    275: "page21",  # ADR_PREL_PG_HI21
    277: "pageoff12/0",  # ADD_ABS_LO12_NC
    278: "pageoff12/0",  # LDST8_ABS_LO12_NC
    284: "pageoff12/1",  # LDST16_ABS_LO12_NC
    285: "pageoff12/2",  # LDST32_ABS_LO12_NC
    286: "pageoff12/3",  # LDST64_ABS_LO12_NC
    299: "pageoff12/4",  # LDST128_ABS_LO12_NC
    311: "gotpage21",  # ADR_GOT_PAGE
    312: "gotpageoff12",  # LD64_GOT_LO12_NC
}


def parse_elf(data):
    if data[:4] != b"\x7fELF" or data[4] != 2:
        sys.exit("not a 64-bit ELF object")
    (shoff,) = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    headers = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    shstr = headers[shstrndx][4]

    def name_at(table_offset, idx):
        end = data.index(b"\0", table_offset + idx)
        return data[table_offset + idx : end].decode()

    names = [name_at(shstr, h[0]) for h in headers]
    text_index = names.index(".text")
    text = data[headers[text_index][4] : headers[text_index][4] + headers[text_index][5]]
    symtab = headers[names.index(".symtab")]
    strtab = headers[symtab[6]][4]
    symbols = {}
    for i in range(symtab[5] // 24):
        st_name, _info, _other, shndx, value, _size = struct.unpack_from("<IBBHQQ", data, symtab[4] + 24 * i)
        if shndx == text_index and st_name:
            symbols[name_at(strtab, st_name)] = value
    relocs = []
    if ".rela.text" in names:
        rela = headers[names.index(".rela.text")]
        for i in range(rela[5] // 24):
            offset, info, addend = struct.unpack_from("<QQq", data, rela[4] + 24 * i)
            rtype = info & 0xFFFFFFFF
            if rtype not in ELF_RELOCS:
                sys.exit(f"unexpected relocation type {rtype} at {offset:#x}")
            relocs.append((offset, ELF_RELOCS[rtype], addend))
    return text, symbols, relocs


def words(code):
    if len(code) % 4:
        sys.exit("code is not a whole number of 32-bit words")
    ws = [f"{w:08x}" for (w,) in struct.iter_unpack("<I", code)]
    out = []
    i = 0
    while i < len(ws):
        j = i
        while j < len(ws) and ws[j] == ws[i]:
            j += 1
        if j - i >= 4:
            out.append(f"{ws[i]}*{j - i}")
        else:
            out.extend(ws[i:j])
        i = j
    return " ".join(out)


def slice_case(text, relocs, start, end):
    rel = ",".join(f"{o - start}:{k}:{a}" for o, k, a in sorted(relocs) if start <= o < end)
    return words(text[start:end]), rel


def format_line(left, hexwords, rel):
    line = f"{left:<46} | {hexwords}"
    return f"{line} | {rel}" if rel else line


MARKER = re.compile(r"^#@\s*target\s+(\w+)\s*$")


def gen_insns():
    with open(INSNS) as f:
        lines = f.read().splitlines()
    cases = {"darwin": [], "elf": []}
    target = "darwin"
    for i, line in enumerate(lines):
        stripped = line.strip()
        m = MARKER.match(stripped)
        if m:
            target = m.group(1)
            if target not in TARGETS:
                sys.exit(f"line {i + 1}: unknown target {target}")
            continue
        if not stripped or stripped.startswith("#"):
            continue
        cases[target].append((i, stripped.split("|")[0].strip()))
    total = 0
    for target, items in cases.items():
        if not items:
            continue
        source = [".text"]
        for n, (_i, insn) in enumerate(items):
            source += [f"_t{n:04}:", f"    {insn}"]
        source.append("_tend:")
        text, symbols, relocs = assemble("\n".join(source) + "\n", target)
        for n, (i, insn) in enumerate(items):
            start = symbols[f"_t{n:04}"]
            end = symbols[f"_t{n + 1:04}"] if n + 1 < len(items) else symbols["_tend"]
            lines[i] = format_line(insn, *slice_case(text, relocs, start, end))
        total += len(items)
    with open(INSNS, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{INSNS}: {total} instructions")


BLOCK_LABEL = re.compile(r"^([A-Za-z_$][\w$.]*):")
LOCAL = re.compile(r"\.L([\w$.]+)")
RELAXED = re.compile(r"^(\s*)[^#/\s].*?//@\s*(.*)$")  # an instruction, then //@


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
        r = RELAXED.match(line)
        expanded = [r.group(1) + part.strip() for part in r.group(2).split("||")] if r else [line]
        out += [LOCAL.sub(lambda m: f"L{k}_{m.group(1)}", x) for x in expanded]
    out.append(f"{names[-1]}__end:")
    text, symbols, relocs = assemble("\n".join(out) + "\n", "darwin")
    result = [
        "# Generated by gen_golden_aarch64.py from aarch64_blocks.s: block | words | relocations.",
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
