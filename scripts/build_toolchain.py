#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Builds odinpc for distribution.

On macOS: a release build for x86_64 and for arm64, joined with lipo into a
universal binary at toolchain/target/universal/odinpc, which package_app.py
puts in the .app. Rust needs both targets (rustup target add
x86_64-apple-darwin aarch64-apple-darwin); Xcode's command line tools link
either one on either kind of Mac.

Elsewhere: a release build for this machine (toolchain/target/release/odinpc,
odinpc.exe on Windows), which the IDE finds when run from the source tree.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLCHAIN = ROOT / "toolchain"
MAC_TARGETS = ("x86_64-apple-darwin", "aarch64-apple-darwin")


def cargo(*args):
    cargo_bin = shutil.which("cargo") or str(Path.home() / ".cargo" / "bin" / "cargo")
    subprocess.run([cargo_bin, *args], cwd=TOOLCHAIN, check=True)


def main():
    if sys.platform != "darwin":
        cargo("build", "--release")
        name = "odinpc.exe" if sys.platform == "win32" else "odinpc"
        print(TOOLCHAIN / "target" / "release" / name)
        return
    parts = []
    for target in MAC_TARGETS:
        cargo("build", "--release", "--target", target)
        parts.append(str(TOOLCHAIN / "target" / target / "release" / "odinpc"))
    universal = TOOLCHAIN / "target" / "universal" / "odinpc"
    universal.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["/usr/bin/lipo", "-create", *parts, "-output", str(universal)], check=True)
    subprocess.run(["/usr/bin/lipo", "-info", str(universal)], check=True)
    print(universal)


if __name__ == "__main__":
    main()
