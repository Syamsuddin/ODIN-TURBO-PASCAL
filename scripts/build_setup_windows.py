#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Builds the single-file offline Windows installer: python scripts/build_setup_windows.py

Run it on Windows with Inno Setup 6.3 or later installed (CI: choco install innosetup). It
  1. stages the app with stage_windows.py,
  2. puts a private Python with Tk in staging\\python (python.org's installer, pinned by SHA-256,
     run quietly into that folder),
  3. puts vcruntime140.dll next to odinpc.exe if that build still links the C runtime dynamically,
  4. checks the staged tree compiles and runs a program with the private Python,
  5. runs ISCC on scripts/odin_setup.iss.
The result is dist/OdinTurboPascal-VERSION-Setup-x64.exe. Options: --python-installer FILE uses a
Python installer you already downloaded (it must still match the pinned SHA-256); --out DIR.
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
import stage_windows
from odin import __version__

# The installer from https://www.python.org/ftp/python/3.13.16/. To change the version, download
# the new installer from python.org over HTTPS, compare with the signature published next to it
# (.asc, .crt), and replace both values.
PYTHON_VERSION = "3.13.16"
PYTHON_URL = f"https://www.python.org/ftp/python/{PYTHON_VERSION}/python-{PYTHON_VERSION}-amd64.exe"
PYTHON_SHA256 = "fb4f9f5d438b2396da0086dc70b935c530cb578e37adc6d354f7ad2037fee83b"
# Only what Odin needs: the standard library with Tcl/Tk; no pip, tests, docs, headers or launcher.
PYTHON_OPTIONS = ("InstallAllUsers=0", "Include_pip=0", "Include_test=0", "Include_doc=0", "Include_dev=0",
                  "Include_tools=0", "Include_launcher=0", "Include_tcltk=1", "Include_lib=1", "Include_exe=1",
                  "Include_symbols=0", "Include_debug=0", "Shortcuts=0", "AssociateFiles=0", "CompileAll=0",
                  "PrependPath=0", "InstallLauncherAllUsers=0")
ISCC_PATHS = (r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe", r"C:\Program Files\Inno Setup 6\ISCC.exe",
              str(Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Inno Setup 6" / "ISCC.exe"))
# Files of the web version, which is never shipped (CLAUDE.md): a build that finds one stops.
WEB_FILES = ("odin/server.py", "odin/store.py", "odin/mysql.py", "odin/websocket.py", "odin/sandbox.py", "web")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def python_installer(given, work):
    path = Path(given) if given else work / f"python-{PYTHON_VERSION}-amd64.exe"
    if not path.is_file():
        print(f"Mengunduh {PYTHON_URL}")
        urllib.request.urlretrieve(PYTHON_URL, path)
    if sha256(path) != PYTHON_SHA256:
        raise SystemExit(f"SHA-256 {path} tidak sama dengan nilai yang disematkan; installer Python ditolak.")
    return path


def install_python(installer, target):
    command = [str(installer), "/quiet", f"TargetDir={target}", *PYTHON_OPTIONS]
    subprocess.run(command, check=True, timeout=900)
    for name in ("python.exe", "pythonw.exe", "vcruntime140.dll", "DLLs/_tkinter.pyd", "tcl/tcl8.6/init.tcl", "Lib/tkinter/__init__.py"):
        if not (target / name).exists():
            raise SystemExit(f"Python terpasang tetapi {name} tidak ada: bukan installer lengkap dengan Tcl/Tk?")
    # Bytecode caches and import libraries are not needed to run.
    for leftover in list(target.rglob("__pycache__")) + [target / "Doc", target / "include", target / "libs"]:
        shutil.rmtree(leftover, ignore_errors=True)
    (target / "NEWS.txt").unlink(missing_ok=True)


def odinpc_for_setup():
    """The odinpc.exe to ship: a fresh build wins over the committed one, which links the C
    runtime dynamically (the old build)."""
    fresh = ROOT / "toolchain" / "target" / "release" / "odinpc.exe"
    if fresh.is_file():
        return fresh
    return ROOT / "toolchain" / "odinpc.exe"


def bundle_c_runtime(odinpc, python_dir):
    """An odinpc.exe built with the dynamic C runtime imports VCRUNTIME140.dll, which a clean
    Windows lacks. The private Python carries that DLL; it goes next to odinpc.exe, where the
    loader looks first. A static build (toolchain/.cargo/config.toml) needs nothing."""
    if b"vcruntime140" not in odinpc.read_bytes().lower():
        return False
    shutil.copy2(python_dir / "vcruntime140.dll", odinpc.parent / "vcruntime140.dll")
    return True


def build(out, python_installer_path=None):
    if sys.platform != "win32":
        raise SystemExit("Setup Windows harus dibangun di Windows (Inno Setup hanya berjalan di Windows).")
    iscc = shutil.which("ISCC") or next((p for p in ISCC_PATHS if Path(p).is_file()), None)
    if not iscc:
        raise SystemExit("ISCC.exe tidak ditemukan. Pasang Inno Setup 6.3+ (choco install innosetup).")
    odinpc = odinpc_for_setup()
    if not odinpc.is_file():
        raise SystemExit("odinpc.exe belum ada: jalankan cargo build --release di toolchain/.")
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="odin-setup-") as directory:
        work = Path(directory)
        staging = stage_windows.stage(work / "app")
        (staging / "toolchain").mkdir(exist_ok=True)
        shutil.copy2(odinpc, staging / "toolchain" / "odinpc.exe")
        (staging / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts" / "check_windows.py", staging / "scripts" / "check_windows.py")
        for name in WEB_FILES:
            if (staging / name).exists():
                raise SystemExit(f"{name} (versi web) ikut terbawa ke paket. Hentikan: versi web tidak boleh dirilis.")
        install_python(python_installer(python_installer_path, work), staging / "python")
        if bundle_c_runtime(staging / "toolchain" / "odinpc.exe", staging / "python"):
            print("odinpc.exe memakai runtime C dinamis: vcruntime140.dll dari Python disertakan di sampingnya.")
        python = staging / "python" / "python.exe"
        print("Pemeriksaan: Python pribadi + Tk + compile dengan odinpc.exe")
        subprocess.run([str(python), "-E", "-c", "import tkinter; print('Tk', tkinter.TkVersion)"], check=True, timeout=60)
        subprocess.run([str(python), "-E", "-X", "utf8", str(staging / "scripts" / "check_windows.py")], check=True, timeout=300)
        # The check imports odin, which may leave bytecode caches; the setup must not carry them.
        for cache in staging.rglob("__pycache__"):
            shutil.rmtree(cache, ignore_errors=True)
        subprocess.run([iscc, f"/DVersion={__version__}", f"/DStaging={staging}", f"/DOutDir={out}",
                        str(ROOT / "scripts" / "odin_setup.iss")], check=True, timeout=1800)
    setup = out / f"OdinTurboPascal-{__version__}-Setup-x64.exe"
    print(f"{setup} ({setup.stat().st_size / 1048576:.1f} MB)")
    print(f"SHA-256 {sha256(setup)}")
    return setup


def main():
    parser = argparse.ArgumentParser(description="Bangun setup offline Odin Turbo Pascal untuk Windows.")
    parser.add_argument("--python-installer", help="installer Python python.org yang sudah diunduh")
    parser.add_argument("--out", default=str(ROOT / "dist"), help="folder hasil (bawaan: dist/)")
    args = parser.parse_args()
    build(args.out, args.python_installer)


if __name__ == "__main__":
    main()
