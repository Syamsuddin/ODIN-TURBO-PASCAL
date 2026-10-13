#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Installer gate: use the actual compiler and SDK, execute its native output."""
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from odin.core import Settings, build

if sys.platform != "darwin":
    raise SystemExit("Pemeriksaan ini harus dijalankan di macOS.")

with tempfile.TemporaryDirectory(prefix="odin-check-") as directory:
    root = Path(directory)
    source = root / "check.pas"
    source.write_text("program check; begin WriteLn('ODIN_NATIVE_OK'); end.\n")
    settings = Settings(root / "settings.json")
    settings["compiler"] = sys.argv[1]
    result = build(source, settings, cache=root / "build")
    if not result.success or not result.executable:
        print(result.output)
        raise SystemExit("Kompilasi gagal. Pastikan FPC dan Xcode Command Line Tools terpasang.")
    description = subprocess.check_output(["/usr/bin/file", str(result.executable)], text=True)
    expected = "arm64" if platform.machine() == "arm64" else "x86_64"
    if expected not in description:
        raise SystemExit(f"Compiler menghasilkan CPU berbeda. Diperlukan {expected}: {description}")
    output = subprocess.check_output([str(result.executable)], text=True, timeout=10)
    if output.strip() != "ODIN_NATIVE_OK":
        raise SystemExit("Program pemeriksaan tidak menghasilkan keluaran yang benar.")
    print(f"OK: compile + run native {expected}")
