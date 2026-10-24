#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Builds the single-file offline Linux installer: python3 scripts/build_setup_linux.py

The result, dist/OdinTurboPascal-VERSION-linux-ARCH.run, is a shell script followed by a tar.xz
payload (the app, a stripped odinpc, scripts/check_linux.py and a private Python 3.13 with Tk from
python-build-standalone). Installing it downloads nothing and needs no root. Build it on the CPU it
is for (odinpc is built for the machine it is compiled on):

    cd toolchain && cargo build --release && cd ..
    python3 scripts/build_setup_linux.py [--python-archive FILE] [--odinpc FILE] [--out DIR]

The Python archives are pinned by SHA-256 (from the release's SHA256SUMS).
"""
import argparse
import hashlib
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
import stage_windows   # only its copy filter (ignore, FOLDERS) is used here
from odin import __version__

PBS_TAG = "20261013"
PBS_PYTHON = "3.13.16"
PBS_SHA256 = {
    "x86_64": "d0080766b6b74aeb81e1949ef0d9a20e6c17f7b160fb295a69b936ccb17660be",
    "aarch64": "69a30ed26198178732c37b8de0b6b5191479fbacfe526954da776befe38f18e7",
}
FILES = ("main.py", "LICENSE", "THIRD_PARTY.txt", "README.txt")
# Files of the web version, which is never shipped (CLAUDE.md): a build that finds one stops.
WEB_FILES = ("odin/server.py", "odin/store.py", "odin/mysql.py", "odin/websocket.py", "odin/sandbox.py", "web")
# Stdlib test suites are the bulk of what the app does not need.
PRUNE = ("lib/python3.13/test", "lib/python3.13/idlelib/idle_test", "lib/python3.13/tkinter/test",
         "lib/python3.13/lib2to3/tests", "lib/python3.13/ensurepip")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def python_archive(arch, given, work):
    name = f"cpython-{PBS_PYTHON}+{PBS_TAG}-{arch}-unknown-linux-gnu-install_only_stripped.tar.gz"
    path = Path(given) if given else work / name
    if not path.is_file():
        url = f"https://github.com/astral-sh/python-build-standalone/releases/download/{PBS_TAG}/{name.replace('+', '%2B')}"
        print(f"Mengunduh {url}")
        urllib.request.urlretrieve(url, path)
    if sha256(path) != PBS_SHA256[arch]:
        raise SystemExit(f"SHA-256 {path} tidak sama dengan nilai yang disematkan; arsip Python ditolak.")
    return path


def stage(target, arch, python, odinpc):
    target.mkdir(parents=True)
    for folder in stage_windows.FOLDERS:
        shutil.copytree(ROOT / folder, target / folder, ignore=stage_windows.ignore)
    # OTP-AI and the example menus, as in stage_windows.py and package_app.py.
    for folder in ("otp-AI/UNITS", "otp-AI/EXAMPLES", "otp-AI/DATA", "examples-graph", "examples-oop"):
        shutil.copytree(ROOT / folder, target / folder, ignore=stage_windows.ignore)
    for name in FILES:
        shutil.copy2(ROOT / name, target / name)
    for name in WEB_FILES:
        if (target / name).exists():
            raise SystemExit(f"{name} (versi web) ikut terbawa ke paket. Hentikan: versi web tidak boleh dirilis.")
    (target / "scripts").mkdir()
    shutil.copy2(ROOT / "scripts" / "check_linux.py", target / "scripts" / "check_linux.py")
    (target / "toolchain").mkdir()
    shutil.copy2(odinpc, target / "toolchain" / "odinpc")
    if shutil.which("strip"):
        subprocess.run(["strip", str(target / "toolchain" / "odinpc")], check=False)
    (target / "toolchain" / "odinpc").chmod(0o755)
    with tarfile.open(python) as archive:
        # top folder: python/
        archive.extractall(target, **({"filter": "tar"} if hasattr(tarfile, "tar_filter") else {}))
    for name in PRUNE:
        shutil.rmtree(target / "python" / name, ignore_errors=True)
    for cache in target.rglob("__pycache__"):
        shutil.rmtree(cache, ignore_errors=True)


def payload(staging, destination):
    def clean(info):
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info
    with tarfile.open(destination, "w:xz", preset=9) as archive:
        for path in sorted(staging.iterdir()):
            archive.add(path, arcname=path.name, filter=clean)


def build(out, arch, python_path=None, odinpc=None):
    if not sys.platform.startswith("linux"):
        raise SystemExit("Setup Linux dibangun di Linux.")
    odinpc = Path(odinpc or ROOT / "toolchain" / "target" / "release" / "odinpc")
    if not odinpc.is_file():
        raise SystemExit("odinpc belum dibangun: jalankan cargo build --release di toolchain/.")
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="odin-setup-") as directory:
        work = Path(directory)
        staging = work / "app"
        stage(staging, arch, python_archive(arch, python_path, work), odinpc)
        python = staging / "python" / "bin" / "python3"
        print("Pemeriksaan: Python pribadi + Tk + compile dengan odinpc")
        subprocess.run([str(python), "-I", "-c", "import tkinter; print('Tk', tkinter.TkVersion)"], check=True, timeout=60)
        subprocess.run([str(python), "-I", str(staging / "scripts" / "check_linux.py")], check=True, timeout=300)
        for cache in staging.rglob("__pycache__"):
            shutil.rmtree(cache, ignore_errors=True)
        archive = work / "payload.tar.xz"
        payload(staging, archive)
        digest = sha256(archive)
        template = (ROOT / "scripts" / "install_linux.sh.in").read_text()
        header = (template.replace("@VERSION@", __version__).replace("@ARCH@", arch).replace("@SHA256@", digest)
                  .replace("@OFFSET@", "x" * 10))
        offset = len(header.encode())   # the offset is padded with spaces, so its width is fixed
        header = header.replace("x" * 10, f"{offset:>10}", 1)   # (leading zeros would read as octal)
        assert len(header.encode()) == offset
        setup = out / f"OdinTurboPascal-{__version__}-linux-{arch}.run"
        with open(setup, "wb") as handle:
            handle.write(header.encode())
            handle.write(archive.read_bytes())
        setup.chmod(0o755)
    print(f"{setup} ({setup.stat().st_size / 1048576:.1f} MB)")
    print(f"SHA-256 {sha256(setup)}")
    return setup


def main():
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "arm64": "aarch64"}.get(machine, machine)
    parser = argparse.ArgumentParser(description="Bangun pemasang offline Odin Turbo Pascal untuk Linux.")
    parser.add_argument("--python-archive", help="arsip python-build-standalone yang sudah diunduh")
    parser.add_argument("--odinpc", help="odinpc untuk CPU ini (bawaan: toolchain/target/release/odinpc)")
    parser.add_argument("--out", default=str(ROOT / "dist"), help="folder hasil (bawaan: dist/)")
    args = parser.parse_args()
    if arch not in PBS_SHA256:
        raise SystemExit(f"CPU {arch} belum didukung.")
    build(args.out, arch, args.python_archive, args.odinpc)


if __name__ == "__main__":
    main()
