#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Generate expected outputs for the Pascal test corpus with Free Pascal.

FPC (fpc -Mtp) is the oracle: for every tests/pascal/<dir>/NAME.PAS (except
the folders in SKIP_DIRS) this compiles the program, runs it with NAME.in as
standard input and NAME.args as arguments, and writes NAME.out (standard
output) and NAME.code (exit status). Runtime-error messages go to standard
error and are not compared, because they contain addresses.

Programs listed in tests/pascal/DEVIATIONS.md keep their hand-written
expectations: Odin deliberately behaves differently there.

With --os OS the files are NAME.OS.out and NAME.OS.code instead: the
expectations for a program whose behaviour rightly differs on that system
(DOS attributes and paths, CR LF text files on Windows). The corpus test
prefers them when it builds for that OS. Run it there, with FPC there
(.github/workflows/oracle.yml does it on a Windows runner).

Usage: python3 scripts/oracle.py [--fpc PATH] [--os OS] [NAME ...]
Developer machines and CI only; the tests themselves never need FPC.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "tests" / "pascal"
SKIP_DIRS = {"syntax", "errors", "semantic", "crt", "vision", "debug"}


def deviations():
    path = CORPUS / "DEVIATIONS.md"
    if not path.exists():
        return set()
    return {m.group(1) for m in re.finditer(r"`([\w/]+\.PAS)`", path.read_text())}


def sdk_args():
    if sys.platform != "darwin":
        return []
    try:
        sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
        return [f"-XR{sdk}"] if sdk else []
    except (OSError, subprocess.CalledProcessError):
        return []


def unit_args(fpc):
    """Unit folders for an FPC install without fpc.cfg (the Windows Chocolatey package)."""
    compiler = Path(shutil.which(fpc) or fpc)
    if sys.platform != "win32" or (compiler.parent / "fpc.cfg").is_file():
        return []
    units = compiler.parent.parent.parent / "units" / compiler.parent.name
    return [f"-Fu{units}\\*"] if units.is_dir() else []


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fpc", default=os.environ.get("ODIN_FPC") or shutil.which("fpc") or "/usr/local/bin/fpc")
    parser.add_argument("--os", help="write NAME.OS.out / NAME.OS.code (e.g. windows)")
    parser.add_argument("names", nargs="*", help="only these programs (file stems)")
    args = parser.parse_args()
    skip = deviations()
    cases = sorted(p for p in CORPUS.rglob("*.PAS") if p.parent.name not in SKIP_DIRS)
    if args.names:
        wanted = {n.upper() for n in args.names}
        cases = [p for p in cases if p.stem.upper() in wanted]
    with tempfile.TemporaryDirectory(prefix="odin-oracle-") as tmp:
        tmp = Path(tmp)
        for src in cases:
            rel = src.relative_to(CORPUS).as_posix()
            # Units used by corpus programs have no output of their own.
            if re.match(r"\s*(\{[^}]*\}\s*)*unit\b", src.read_text(errors="replace"), re.I):
                continue
            if rel in skip:
                print(f"skip   {rel} (DEVIATIONS.md)")
                continue
            exe = tmp / (src.stem + (".exe" if sys.platform == "win32" else ""))
            build = subprocess.run(
                [args.fpc, "-Mtp", *sdk_args(), *unit_args(args.fpc), f"-FE{tmp}", f"-FU{tmp}", f"-Fu{src.parent}",
                 f"-o{exe}", str(src)],
                capture_output=True,
                text=True,
            )
            if build.returncode != 0:
                print(f"FAIL   {rel}: FPC could not compile it\n{build.stdout}")
                continue
            stdin = src.with_suffix(".in").read_bytes() if src.with_suffix(".in").exists() else b""
            argv = src.with_suffix(".args").read_text().split() if src.with_suffix(".args").exists() else []
            # One folder per program: Windows cannot always remove what the last one left
            # (read-only attributes set by the Dos tests).
            work = tmp / f"work-{src.stem}"
            work.mkdir()
            run = subprocess.run([str(exe), *argv], input=stdin, capture_output=True, cwd=work, timeout=20)
            suffix = f".{args.os}" if args.os else ""
            src.with_suffix(f"{suffix}.out").write_bytes(run.stdout)
            src.with_suffix(f"{suffix}.code").write_text(f"{run.returncode}\n")
            print(f"ok     {rel} (exit {run.returncode})")


if __name__ == "__main__":
    main()
