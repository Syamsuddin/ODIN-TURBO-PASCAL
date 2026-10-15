#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Build an architecture-neutral .app using the installed local Python runtime.

This is not a frozen standalone executable. Runtime installation belongs to
Install.command. Only the build bundle beside this repository is replaced,
apart from the version tag comment in examples/HELLO.PAS.
"""
import plistlib
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION = re.search(r'__version__ = "([^"]+)"', (ROOT / "odin" / "__init__.py").read_text()).group(1)
# Info.plist: the short version is numeric; a pre-release such as 2.0.0-alpha.1
# becomes the build version 2.0.0a1 (Apple's development/alpha/beta form).
SHORT_VERSION = VERSION.split("-")[0]
BUILD_VERSION = re.sub(r"-(alpha|beta|rc)\.?(\d*)", lambda m: {"alpha": "a", "beta": "b", "rc": "fc"}[m.group(1)] + (m.group(2) or "1"), VERSION)
# HELLO.PAS is the IDE's default page. Its comment carries the release tag
# (v2.0.0), brought in step with odin/__init__.py on every build.
hello = ROOT / "examples" / "HELLO.PAS"
source = hello.read_bytes()
stamped, found = re.subn(rb"(\{ Odin Turbo Pascal )v\S+( - program pertama \})", b"\\g<1>v" + VERSION.encode() + b"\\g<2>", source)
if found != 1:
    raise SystemExit("examples/HELLO.PAS: komentar tag versi '{ Odin Turbo Pascal vX.Y.Z - program pertama }' tidak ditemukan.")
if stamped != source:
    hello.write_bytes(stamped)
APP = ROOT / "Odin Turbo Pascal.app"
CONTENTS = APP / "Contents"
if APP.exists():
    shutil.rmtree(APP)
(CONTENTS / "MacOS").mkdir(parents=True)
resources = CONTENTS / "Resources"
resources.mkdir()
# The logo master (odin-logo-master.png) is only a source for scripts/render_logo.py.
for folder in ("odin", "examples", "docs", "assets"):
    shutil.copytree(ROOT / folder, resources / folder,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "odin-logo-master.png"))
# The Odin toolchain: the RTL sources and odinpc, preferably the universal
# x86_64 + arm64 build of scripts/build_toolchain.py, else the release build
# for this Mac (cargo build --release in toolchain/). Without odinpc the IDE
# falls back to Free Pascal.
shutil.copytree(ROOT / "rtl", resources / "rtl")
odinpc = ROOT / "toolchain" / "target" / "universal" / "odinpc"
if not odinpc.is_file():
    odinpc = ROOT / "toolchain" / "target" / "release" / "odinpc"
    print("Peringatan: odinpc universal belum dibangun (scripts/build_toolchain.py); bundle hanya untuk CPU Mac ini.")
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
    "CFBundleVersion": BUILD_VERSION,
    "CFBundleShortVersionString": SHORT_VERSION,
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
