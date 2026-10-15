#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Bump the Odin Turbo Pascal version in every file that spells it out.

    python3 scripts/set_version.py 2.0.1 [--date 2026-10-15]

odin/__init__.py is the source the IDE reads at runtime (desktop, status bar,
About). This script also rewrites the copies that cannot read it: the toolchain
workspace (odinpc version), the installer banner, the README/docs headers, the
README badge and install line, the tag comment in examples/HELLO.PAS, and it
turns CHANGELOG's [Unreleased] section into the new release. Every pattern must
match before anything is written, so a reworded file stops the bump instead of
being skipped silently.

Lines that claim a test run and release prose are left to a person; they are
listed at the end, together with the build steps that follow a bump.
"""
import argparse
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/Syamsuddin/ODIN-TURBO-PASCAL"
# package_app.py turns the pre-release forms into Apple's build version (2.0.0a1).
VERSION = re.compile(r"\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?")


def badge(version):
    # shields.io static badges spell a literal dash as "--".
    return version.replace("-", "--")


def edits(old, new, date):
    """(path, pattern, replacement, count): count None means at least one."""
    o = re.escape(old)
    return [
        ("odin/__init__.py", rf'^__version__ = "{o}"$', f'__version__ = "{new}"', 1),
        ("toolchain/Cargo.toml", rf'^version = "{o}"$', f'version = "{new}"', 1),
        # Every package in the lock file is a workspace crate (no third-party crates).
        ("toolchain/Cargo.lock", rf'^version = "{o}"$', f'version = "{new}"', None),
        ("Install.command", rf"ODIN TURBO PASCAL {o}(?=\\n)", f"ODIN TURBO PASCAL {new}", 1),
        ("README.txt", rf"^ODIN TURBO PASCAL {o}$", f"ODIN TURBO PASCAL {new}", 1),
        ("docs/HELP.txt", rf"^Panduan penggunaan {o}$", f"Panduan penggunaan {new}", 1),
        ("docs/COMPATIBILITY.txt", rf"^KOMPATIBILITAS DAN CAKUPAN VERSI {o}$", f"KOMPATIBILITAS DAN CAKUPAN VERSI {new}", 1),
        ("README.md", rf"badge/rilis-{re.escape(badge(old))}-", f"badge/rilis-{badge(new)}-", 1),
        ("README.md", rf"Pemasang ini memasang \*\*rilis {o}\*\*", f"Pemasang ini memasang **rilis {new}**", 1),
        # Whatever tag the comment carries; package_app.py restamps it on every build too.
        ("examples/HELLO.PAS", r"\{ Odin Turbo Pascal v\S+ - program pertama \}", f"{{ Odin Turbo Pascal v{new} - program pertama }}", 1),
        ("CHANGELOG.md", r"^## \[Unreleased\]\n", f"## [Unreleased]\n\n## [{new}] - {date}\n", 1),
        ("CHANGELOG.md", rf"^\[Unreleased\]: {re.escape(REPO_URL)}/compare/v{o}\.\.\.HEAD$",
         f"[Unreleased]: {REPO_URL}/compare/v{new}...HEAD\n[{new}]: {REPO_URL}/compare/v{old}...v{new}", 1),
    ]


FILES = sorted({path for path, *_ in edits("0.0.0", "0.0.1", "2000-01-01")})


def main(argv=None):
    parser = argparse.ArgumentParser(description="Naikkan nomor versi Odin Turbo Pascal di semua berkas.")
    parser.add_argument("version", help="versi baru, misalnya 2.0.1 atau 2.1.0-alpha.1")
    parser.add_argument("--date", default=datetime.date.today().isoformat(), help="tanggal rilis untuk CHANGELOG (YYYY-MM-DD)")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    new, root = args.version, args.root
    if not VERSION.fullmatch(new):
        print(f"Versi tidak sah: {new}. Bentuknya X.Y.Z atau X.Y.Z-alpha.N/-beta.N/-rc.N.", file=sys.stderr)
        return 2
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date):
        print(f"Tanggal tidak sah: {args.date}. Bentuknya YYYY-MM-DD.", file=sys.stderr)
        return 2
    # Bytes in and out, so CRLF files and encodings stay exactly as they were.
    texts = {name: (root / name).read_bytes().decode("utf-8") for name in FILES}
    old = re.search(r'^__version__ = "([^"]+)"$', texts["odin/__init__.py"], re.M).group(1)
    if old == new:
        print(f"Versi sudah {new}; tidak ada yang diubah.", file=sys.stderr)
        return 1
    changelog = texts["CHANGELOG.md"]
    if re.search(rf"^## \[{re.escape(new)}\]", changelog, re.M):
        print(f"CHANGELOG.md sudah punya entri [{new}].", file=sys.stderr)
        return 1
    unreleased = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## \[)", changelog, re.M | re.S)
    if not unreleased or not unreleased.group(1).strip():
        print("Bagian [Unreleased] di CHANGELOG.md kosong. Tulis dulu perubahan rilis ini.", file=sys.stderr)
        return 1
    problems = []
    for name, pattern, replacement, count in edits(old, new, args.date):
        texts[name], found = re.subn(pattern, lambda _: replacement, texts[name], flags=re.M)
        if found == 0 or (count is not None and found != count):
            problems.append(f"  {name}: pola /{pattern}/ cocok {found} kali, seharusnya {count or 'minimal 1'}")
    if problems:
        print(f"Tidak ada berkas yang diubah. Pola berikut tidak cocok untuk {old} -> {new}:", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        return 1
    for name, text in texts.items():
        (root / name).write_bytes(text.encode("utf-8"))
    print(f"Versi {old} -> {new} di {len(FILES)} berkas:")
    print("".join(f"  {name}\n" for name in FILES), end="")
    print(f"""
Tinjau dan tulis sendiri (klaim pengujian dan prosa rilis):
  CHANGELOG.md            ringkasan dan hasil pengujian entri [{new}]
  README.md               blok "Rilis." dan baris Status Pengujian
  README.txt              bagian PENGUJIAN

Langkah berikutnya:
  (cd toolchain && cargo build --release)   # odinpc version {new}
  python3 scripts/package_app.py            # bundle .app, Info.plist, HELLO.PAS
  python3 -m unittest discover -s tests     # dan cargo test di toolchain/
  python3 scripts/update_checksums.py       # SHA256SUMS.json
  git commit, lalu git tag -a v{new}""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
