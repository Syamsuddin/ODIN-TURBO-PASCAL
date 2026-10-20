#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Installer gate on Linux: compile with the package's odinpc, check the ELF executable, run it,
and check that Tk can be used (and which of its shared libraries the system lacks).

    python3 scripts/check_linux.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from odin.core import Settings, build, locate_toolchain

MACHINES = {0x3E: "x86_64", 0xB7: "aarch64"}


def elf_machine(path):
    """The CPU of a Linux executable, or None when the file is not an ELF image."""
    data = Path(path).read_bytes()[:20]
    if data[:4] != b"\x7fELF" or len(data) < 20:
        return None
    return MACHINES.get(int.from_bytes(data[18:20], "little"), "unknown")


def missing_tk_libraries():
    """Shared libraries of _tkinter that the system lacks (the private Python brings Tcl/Tk itself;
    only the X11 libraries come from the system)."""
    import _tkinter
    ldd = shutil.which("ldd")
    if not ldd:
        return []
    out = subprocess.run([ldd, _tkinter.__file__], capture_output=True, text=True).stdout
    return sorted({line.split()[0] for line in out.splitlines() if "not found" in line})


def check():
    with tempfile.TemporaryDirectory(prefix="odin-check-") as directory:
        root = Path(directory)
        source = root / "check.pas"
        source.write_text("program check; begin WriteLn('ODIN_NATIVE_OK'); end.\n")
        result = build(source, Settings(root / "settings.json"), cache=root / "build")
        if not result.success or not result.executable:
            print(result.output)
            raise SystemExit("Kompilasi dengan odinpc gagal.")
        machine = elf_machine(result.executable)
        if machine is None:
            raise SystemExit("odinpc tidak menghasilkan program Linux (ELF).")
        output = subprocess.run([str(result.executable)], capture_output=True, text=True, timeout=10).stdout
        if output.strip() != "ODIN_NATIVE_OK":
            raise SystemExit("Program pemeriksaan tidak menghasilkan keluaran yang benar.")
        print(f"OK: odinpc: compile + run native {machine}")


def main():
    if not sys.platform.startswith("linux"):
        raise SystemExit("Pemeriksaan ini harus dijalankan di Linux.")
    if not locate_toolchain():
        raise SystemExit("Compiler Odin (toolchain/odinpc) tidak ditemukan di paket ini.")
    check()
    try:
        missing = missing_tk_libraries()
    except ImportError:
        raise SystemExit("Python ini tidak punya tkinter.")
    if missing:
        print("Peringatan: pustaka sistem untuk jendela belum ada: " + ", ".join(missing))
        print("Di Ubuntu/Debian: sudo apt install libx11-6 libxft2 libxss1 (lihat apt-file untuk sisanya).")
    else:
        print("OK: Tk dan pustaka X11 tersedia")


if __name__ == "__main__":
    main()
