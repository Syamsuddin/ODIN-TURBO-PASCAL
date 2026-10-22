#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Copy the IDE into a Windows install folder: python scripts/stage_windows.py TARGET

Install.ps1 runs this with the Python it found, after moving an older install aside. It is the
Windows counterpart of package_app.py: a plain folder instead of an .app bundle, still run by the
user's own Python (pythonw.exe), not a frozen executable. Besides the sources it writes
OdinTurboPascal.pyw (scripts/launcher_windows.pyw) and odin.ico for the shortcuts, made from the
PNG images inside assets/odin.icns. odinpc.exe is copied when a Windows build exists.
"""
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FOLDERS = ("odin", "examples", "docs", "assets", "rtl")
FILES = ("main.py", "LICENSE", "THIRD_PARTY.txt", "README.txt", "Uninstall.ps1", "Uninstall.cmd")
# The logo master is only a source for render_logo.py; odin.icns is the macOS icon.
SKIP = shutil.ignore_patterns("__pycache__", "*.pyc", "odin-logo-master.png", "odin.icns")
TOOLCHAIN = (ROOT / "toolchain" / "odinpc.exe", ROOT / "toolchain" / "target" / "release" / "odinpc.exe")
PNG = b"\x89PNG\r\n\x1a\n"


def git_ignored(directory, names):
    """Names git ignores here (.gitignore or .git/info/exclude); none without git."""
    paths = [str((Path(directory) / name).relative_to(ROOT)) for name in names]
    try:
        result = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--stdin"], input="\n".join(paths),
                                capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return set()
    return {Path(line).name for line in result.stdout.splitlines()}


def ignore(directory, names):
    """copytree filter: as SKIP, and only the Pascal sources from examples/, where the tutorial
    programs (Bab 17, Bab 20) write their data files. Files git ignores stay out, like in
    package_app.py."""
    if Path(directory).name == "examples":
        return {name for name in names if not name.lower().endswith(".pas")}
    return SKIP(directory, names) | git_ignored(directory, names)


def icns_pngs(data):
    """{size: PNG bytes} for the square PNG images in an .icns file."""
    images = {}
    if data[:4] != b"icns":
        raise ValueError("bukan berkas icns")
    offset = 8
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset + 4:offset + 8])[0]
        if length < 8:
            break
        body = data[offset + 8:offset + length]
        if body.startswith(PNG):
            width, height = struct.unpack(">II", body[16:24])
            if width == height:
                images.setdefault(width, body)
        offset += length
    return images


def ico(images):
    """A Windows .ico holding PNG images (Windows Vista and later read PNG entries) of 256 px or less."""
    sizes = sorted(size for size in images if size <= 256)
    if not sizes:
        raise ValueError("tidak ada gambar PNG 256 px atau lebih kecil")
    header = struct.pack("<HHH", 0, 1, len(sizes))
    offset = len(header) + 16 * len(sizes)
    entries, blobs = [], []
    for size in sizes:
        blob = images[size]
        entries.append(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(blob), offset))
        blobs.append(blob)
        offset += len(blob)
    return header + b"".join(entries) + b"".join(blobs)


def stage(target):
    target = Path(target)
    if target.exists():
        raise SystemExit(f"{target} sudah ada. Pindahkan dulu pemasangan lama.")
    target.mkdir(parents=True)
    for folder in FOLDERS:
        shutil.copytree(ROOT / folder, target / folder, ignore=ignore)
    # OTP-AI: unit AI/machine learning yang langsung bisa dipanggil dengan uses.
    shutil.copytree(ROOT / "otp-AI" / "UNITS", target / "otp-AI" / "UNITS", ignore=ignore)
    for name in FILES:
        shutil.copy2(ROOT / name, target / name)
    shutil.copy2(ROOT / "scripts" / "launcher_windows.pyw", target / "OdinTurboPascal.pyw")
    (target / "odin.ico").write_bytes(ico(icns_pngs((ROOT / "assets" / "odin.icns").read_bytes())))
    for odinpc in TOOLCHAIN:
        if odinpc.is_file():
            (target / "toolchain").mkdir()
            shutil.copy2(odinpc, target / "toolchain" / "odinpc.exe")
            break
    return target


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Pemakaian: python scripts/stage_windows.py FOLDER_TUJUAN")
    print(stage(sys.argv[1]))
