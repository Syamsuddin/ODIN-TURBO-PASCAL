#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Installer gate on Windows: compile with the package's odinpc.exe (toolchain/odinpc.exe),
check the PE executable, run it.

    python scripts/check_windows.py
"""
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from odin.core import NO_WINDOW, Settings, build, locate_toolchain

# IMAGE_FILE_HEADER.Machine
MACHINES = {0x8664: "x86_64", 0x014C: "i386", 0xAA64: "arm64"}


def pe_machine(path):
    """The CPU of a Windows executable, or None when the file is not a PE image."""
    data = Path(path).read_bytes()
    if data[:2] != b"MZ" or len(data) < 64:
        return None
    offset = struct.unpack("<I", data[60:64])[0]
    if data[offset:offset + 4] != b"PE\0\0":
        return None
    return MACHINES.get(struct.unpack("<H", data[offset + 4:offset + 6])[0], "unknown")


def check():
    with tempfile.TemporaryDirectory(prefix="odin-check-") as directory:
        root = Path(directory)
        source = root / "check.pas"
        source.write_text("program check; begin WriteLn('ODIN_NATIVE_OK'); end.\n")
        result = build(source, Settings(root / "settings.json"), cache=root / "build")
        if not result.success or not result.executable:
            print(result.output)
            raise SystemExit("Kompilasi dengan odinpc.exe gagal.")
        machine = pe_machine(result.executable)
        if machine != "x86_64":
            raise SystemExit(f"odinpc.exe tidak menghasilkan program Windows x86_64: {machine}")
        output = subprocess.run([str(result.executable)], capture_output=True, text=True, timeout=10, **NO_WINDOW).stdout
        if output.strip() != "ODIN_NATIVE_OK":
            raise SystemExit("Program pemeriksaan tidak menghasilkan keluaran yang benar.")
        print(f"OK: odinpc.exe: compile + run native {machine}")


def main():
    if sys.platform != "win32":
        raise SystemExit("Pemeriksaan ini harus dijalankan di Windows.")
    if not locate_toolchain():
        raise SystemExit("Compiler Odin (toolchain\\odinpc.exe) tidak ditemukan di paket ini.")
    check()


if __name__ == "__main__":
    main()
