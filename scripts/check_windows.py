#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Installer gate on Windows: compile with the real Free Pascal, check the PE executable, run it.
When the package carries odinpc.exe (toolchain/odinpc.exe), the same check runs with the Odin
backend too.

    python scripts/check_windows.py C:\\FPC\\3.2.2\\bin\\x86_64-win64\\fpc.exe
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


def check(compiler, backend):
    with tempfile.TemporaryDirectory(prefix="odin-check-") as directory:
        root = Path(directory)
        source = root / "check.pas"
        source.write_text("program check; begin WriteLn('ODIN_NATIVE_OK'); end.\n")
        settings = Settings(root / "settings.json")
        settings["compiler"] = compiler
        settings["backend"] = backend
        result = build(source, settings, cache=root / "build")
        name = "Free Pascal" if backend == "fpc" else "toolchain Odin (odinpc.exe)"
        if not result.success or not result.executable:
            print(result.output)
            raise SystemExit(f"Kompilasi dengan {name} gagal. Pastikan {name} terpasang dengan benar.")
        machine = pe_machine(result.executable)
        if machine not in ("x86_64", "i386"):
            raise SystemExit(f"{name} tidak menghasilkan program Windows x86: {machine}")
        output = subprocess.run([str(result.executable)], capture_output=True, text=True, timeout=10, **NO_WINDOW).stdout
        if output.strip() != "ODIN_NATIVE_OK":
            raise SystemExit(f"Program pemeriksaan dari {name} tidak menghasilkan keluaran yang benar.")
        print(f"OK: {name}: compile + run native {machine}")


def main(compiler):
    if sys.platform != "win32":
        raise SystemExit("Pemeriksaan ini harus dijalankan di Windows.")
    check(compiler, "fpc")
    if locate_toolchain():
        check(compiler, "odin")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Pemakaian: python scripts/check_windows.py PATH_FPC")
    main(sys.argv[1])
