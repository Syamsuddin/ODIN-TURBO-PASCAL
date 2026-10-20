#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Write expected outputs for new programs of the Pascal test corpus with odinpc.

For each named tests/pascal/<dir>/NAME.PAS this compiles the program with
odinpc, runs it with NAME.in as standard input and NAME.args as arguments,
and writes NAME.out (standard output) and NAME.code (exit status), which the
corpus test (toolchain/crates/odinpc/tests/corpus.rs) compares with.

The expectations come from Odin itself, so read them against Turbo Pascal 7
behaviour before committing them, like the Odin Vision snapshots. Existing
expectations are never replaced without --force. With --os OS the files are
NAME.OS.out and NAME.OS.code: the expectations for a program whose behaviour
rightly differs on that system (DOS attributes and paths, CR LF text files on
Windows), made on that system.

Usage: python3 scripts/bless_corpus.py [--os OS] [--force] NAME [NAME ...]
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from odin.core import executable_name, locate_toolchain  # noqa: E402

CORPUS = ROOT / "tests" / "pascal"
SKIP_DIRS = {"syntax", "errors", "semantic", "crt", "vision", "debug"}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--os", help="write NAME.OS.out / NAME.OS.code (e.g. windows)")
    parser.add_argument("--force", action="store_true", help="replace existing expectations")
    parser.add_argument("names", nargs="+", help="programs (file stems)")
    args = parser.parse_args()
    odinpc = locate_toolchain()
    if not odinpc:
        raise SystemExit("odinpc tidak ditemukan: cargo build --release di toolchain/.")
    wanted = {n.upper() for n in args.names}
    cases = sorted(p for p in CORPUS.rglob("*.PAS") if p.parent.name not in SKIP_DIRS and p.stem.upper() in wanted)
    missing = wanted - {p.stem.upper() for p in cases}
    if missing:
        raise SystemExit("Tidak ada di korpus: " + ", ".join(sorted(missing)))
    suffix = f".{args.os}" if args.os else ""
    with tempfile.TemporaryDirectory(prefix="odin-bless-") as tmp:
        tmp = Path(tmp)
        for src in cases:
            rel = src.relative_to(CORPUS).as_posix()
            # Units used by corpus programs have no output of their own.
            if re.match(r"\s*(\{[^}]*\}\s*)*unit\b", src.read_text(errors="replace"), re.I):
                print(f"skip   {rel} (unit)")
                continue
            out = src.with_suffix(f"{suffix}.out")
            if out.exists() and not args.force:
                print(f"skip   {rel} ({out.name} sudah ada; --force untuk mengganti)")
                continue
            exe = tmp / executable_name(src.stem)
            build = subprocess.run([odinpc, "build", str(src), "--out", str(exe), "--rtl", str(ROOT / "rtl")],
                                   capture_output=True, text=True)
            if build.returncode != 0:
                print(f"FAIL   {rel}: odinpc could not compile it\n{build.stdout}{build.stderr}")
                continue
            stdin = src.with_suffix(".in").read_bytes() if src.with_suffix(".in").exists() else b""
            argv = src.with_suffix(".args").read_text().split() if src.with_suffix(".args").exists() else []
            # One folder per program: Windows cannot always remove what the last one left
            # (read-only attributes set by the Dos tests).
            work = tmp / f"work-{src.stem}"
            work.mkdir()
            run = subprocess.run([str(exe), *argv], input=stdin, capture_output=True, cwd=work, timeout=20)
            out.write_bytes(run.stdout)
            src.with_suffix(f"{suffix}.code").write_text(f"{run.returncode}\n")
            print(f"ok     {rel} (exit {run.returncode}): periksa {out.name} sebelum commit")


if __name__ == "__main__":
    main()
