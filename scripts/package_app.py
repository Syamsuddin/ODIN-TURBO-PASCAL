#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Build an architecture-neutral .app using the installed local Python runtime.

This is not a frozen standalone executable. Runtime installation belongs to
Install.command. Only the build bundle beside this repository is replaced.
"""
import plistlib
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Odin Turbo Pascal.app"
CONTENTS = APP / "Contents"
if APP.exists():
    shutil.rmtree(APP)
(CONTENTS / "MacOS").mkdir(parents=True)
resources = CONTENTS / "Resources"
resources.mkdir()
for folder in ("odin", "examples", "docs", "assets"):
    shutil.copytree(ROOT / folder, resources / folder,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
# The Odin toolchain: the RTL sources and a release build of odinpc
# (cargo build --release in toolchain/). Without odinpc the IDE falls back
# to Free Pascal.
shutil.copytree(ROOT / "rtl", resources / "rtl")
odinpc = ROOT / "toolchain" / "target" / "release" / "odinpc"
if odinpc.is_file():
    (resources / "toolchain").mkdir()
    shutil.copy2(odinpc, resources / "toolchain" / "odinpc")
else:
    print("Peringatan: toolchain/target/release/odinpc belum ada; bundle memakai Free Pascal.")
for name in ("main.py", "LICENSE", "THIRD_PARTY.txt"):
    shutil.copy2(ROOT / name, resources / name)
icon = ROOT / "assets" / "odin.icns"
if icon.exists():
    shutil.copy2(icon, resources / "odin.icns")
launcher = CONTENTS / "MacOS" / "OdinTurboPascal"
shutil.copy2(ROOT / "scripts" / "launcher.sh", launcher)
launcher.chmod(0o755)
metadata = {
    "CFBundleName": "Odin Turbo Pascal",
    "CFBundleDisplayName": "Odin Turbo Pascal",
    "CFBundleIdentifier": "id.digitalkab.odin-turbo-pascal",
    "CFBundleVersion": "1.0.0",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleExecutable": "OdinTurboPascal",
    "CFBundleIconFile": "odin.icns",
    "CFBundlePackageType": "APPL",
    "LSMinimumSystemVersion": "11.0",
    "NSHighResolutionCapable": True,
    "NSHumanReadableCopyright": "Copyright (c) 2026 Syams Ideris. GNU GPL v3 or later.",
    "CFBundleDocumentTypes": [{
        "CFBundleTypeName": "Pascal source",
        "CFBundleTypeExtensions": ["pas", "pp", "inc"],
        "CFBundleTypeRole": "Editor",
        "LSHandlerRank": "Alternate",
    }],
}
with (CONTENTS / "Info.plist").open("wb") as handle:
    plistlib.dump(metadata, handle)
(CONTENTS / "PkgInfo").write_bytes(b"APPL????")
print(APP)
