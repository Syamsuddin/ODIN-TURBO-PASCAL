#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Installer gate: compile with odinpc and execute its native output.

With an app bundle as argument (Install.command passes the one it installs),
the odin package, odinpc and the RTL inside that bundle are checked; without
one, those of this source tree.
"""
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() / "Contents" / "Resources" if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
if not (ROOT / "odin" / "core.py").is_file():
    raise SystemExit(f"Aplikasi Odin tidak ditemukan di {ROOT}.")
sys.path.insert(0, str(ROOT))
from odin.core import Settings, build, locate_toolchain  # noqa: E402

if sys.platform != "darwin":
    raise SystemExit("Pemeriksaan ini harus dijalankan di macOS.")
if not locate_toolchain():
    raise SystemExit(f"Compiler Odin (odinpc) tidak ditemukan di {ROOT}.")

with tempfile.TemporaryDirectory(prefix="odin-check-") as directory:
    root = Path(directory)
    source = root / "check.pas"
    source.write_text("program check; begin WriteLn('ODIN_NATIVE_OK'); end.\n")
    result = build(source, Settings(root / "settings.json"), cache=root / "build")
    if not result.success or not result.executable:
        print(result.output)
        raise SystemExit("Kompilasi dengan odinpc gagal.")
    description = subprocess.check_output(["/usr/bin/file", str(result.executable)], text=True)
    expected = "arm64" if platform.machine() == "arm64" else "x86_64"
    if expected not in description:
        raise SystemExit(f"odinpc menghasilkan CPU berbeda. Diperlukan {expected}: {description}")
    # On Apple Silicon the kernel kills a program whose code signature is invalid, so running it also
    # checks the ad-hoc signature that odinpc's linker writes.
    output = subprocess.check_output([str(result.executable)], text=True, timeout=10)
    if output.strip() != "ODIN_NATIVE_OK":
        raise SystemExit("Program pemeriksaan tidak menghasilkan keluaran yang benar.")
    print(f"OK: odinpc compile + run native {expected}")
