#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Builds the single-file offline macOS installer: python3 scripts/build_setup_mac.py

The result, dist/OdinTurboPascal-VERSION-macos-ARCH.pkg, installs "Odin Turbo Pascal.app" into
~/Applications for the current user (no administrator password). The app carries its own Python 3.13
with Tk (python-build-standalone, pinned by SHA-256) and odinpc, so nothing is downloaded when
installing and no Python, Homebrew or Xcode tools are needed. Steps:
  1. package_app.py builds the bundle in a temporary folder (the repository is left alone),
  2. the private Python goes into Contents/Resources/python,
  3. the bundle is checked (Tk, then odinpc compile + run via check_mac.py),
  4. pkgbuild + productbuild make the installer.
Build it on a Mac of the architecture it is for (x86_64 by default on an Intel Mac). Needs
scripts' prerequisites: cargo build --release in toolchain/ (or scripts/build_toolchain.py).
Options: --python-archive FILE, --arch x86_64|arm64, --out DIR.
"""
import argparse
import hashlib
import platform
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from odin import __version__

PBS_TAG = "20261013"
PBS_PYTHON = "3.13.16"
PBS_SHA256 = {
    "x86_64": "f507ae04eb7747cd97cb484e8c5d83936cbfc52d9b08a1f35c00b47c707b1ae1",
    "arm64": "16a5332fb0dcb77f163fc8f8cbccd95be1644cc53e68e5d2a79f50afd6680a0e",
}
PBS_NAME_ARCH = {"x86_64": "x86_64", "arm64": "aarch64"}
IDENTIFIER = "id.digitalkab.odin-turbo-pascal"
APP_NAME = "Odin Turbo Pascal.app"
WEB_FILES = ("odin/server.py", "odin/store.py", "odin/mysql.py", "odin/websocket.py", "odin/sandbox.py", "web")
PRUNE = ("lib/python3.13/test", "lib/python3.13/idlelib/idle_test", "lib/python3.13/tkinter/test",
         "lib/python3.13/lib2to3/tests", "lib/python3.13/ensurepip")

DISTRIBUTION = """<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Odin Turbo Pascal</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="license.txt"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="{arch}"/>
    <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"/>
    <volume-check>
        <allowed-os-versions><os-version min="11.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline><line choice="default"><line choice="{identifier}"/></line></choices-outline>
    <choice id="default"/>
    <choice id="{identifier}" visible="false"><pkg-ref id="{identifier}"/></choice>
    <pkg-ref id="{identifier}" version="{version}" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
"""
WELCOME = """<html><body style="font-family: -apple-system, Helvetica; font-size: 13px">
<h2>Odin Turbo Pascal {version}</h2>
<p>Pemasang ini memasang <b>Odin Turbo Pascal</b> di folder <b>Applications</b> milik Anda
(<code>~/Applications</code>), lengkap dengan compiler Pascal (<code>odinpc</code>) dan Python+Tk
sendiri. <b>Tidak memerlukan internet</b>, kata sandi administrator, Python, Homebrew, maupun Xcode.</p>
<p>Program Pascal dan pengaturan Anda tidak diubah.</p>
<p style="color:#555">Dibuat oleh Syams Ideris. Lisensi GNU GPL v3 atau yang lebih baru.</p>
</body></html>
"""
CONCLUSION = """<html><body style="font-family: -apple-system, Helvetica; font-size: 13px">
<h2>Pemasangan selesai</h2>
<p>Buka <b>Odin Turbo Pascal</b> dari <code>~/Applications</code> (Finder: Go &gt; Home &gt; Applications).
Pemasang sudah mengompilasi dan menjalankan program uji dengan <code>odinpc</code> sebelum selesai.</p>
<p>File &gt; New, tulis program, F2 untuk menyimpan, Ctrl+F9 untuk menjalankan.</p>
</body></html>
"""
# Both scripts get the install location as $2; they run as the installing user.
PREINSTALL = """#!/bin/bash
# An update replaces the old bundle whole, so no stale file of an older version stays.
rm -rf "$2/Odin Turbo Pascal.app"
exit 0
"""
POSTINSTALL = """#!/bin/bash
APP="$2/Odin Turbo Pascal.app"
[ -d "$APP" ] || APP="$HOME/Applications/Odin Turbo Pascal.app"
chmod 755 "$APP/Contents/MacOS/OdinTurboPascal" "$APP/Contents/Resources/toolchain/odinpc" 2>/dev/null
LOG="${TMPDIR:-/tmp}/odin-install-check.log"
# The gate of Install.command: compile and run a small program with the installed odinpc.
if ! PYTHONDONTWRITEBYTECODE=1 "$APP/Contents/Resources/python/bin/python3" -E -I \\
        "$APP/Contents/Resources/scripts/check_mac.py" "$APP" > "$LOG" 2>&1; then
    echo "Pemeriksaan kompilasi Odin gagal; lihat $LOG" >&2
    cat "$LOG" >&2
    exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1
exit 0
"""


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def python_archive(arch, given, work):
    name = f"cpython-{PBS_PYTHON}+{PBS_TAG}-{PBS_NAME_ARCH[arch]}-apple-darwin-install_only_stripped.tar.gz"
    path = Path(given) if given else work / name
    if not path.is_file():
        url = f"https://github.com/astral-sh/python-build-standalone/releases/download/{PBS_TAG}/{name.replace('+', '%2B')}"
        print(f"Mengunduh {url}")
        urllib.request.urlretrieve(url, path)
    if sha256(path) != PBS_SHA256[arch]:
        raise SystemExit(f"SHA-256 {path} tidak sama dengan nilai yang disematkan; arsip Python ditolak.")
    return path


def run(*command, **kwargs):
    subprocess.run([str(c) for c in command], check=True, **kwargs)


def build(out, arch, python_path=None):
    if sys.platform != "darwin":
        raise SystemExit("Setup macOS dibangun di macOS (pkgbuild dan productbuild).")
    native = {"arm64": "arm64", "x86_64": "x86_64"}.get(platform.machine())
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="odin-pkg-") as directory:
        work = Path(directory)
        run(sys.executable, ROOT / "scripts" / "package_app.py", work / "bundle")
        app = work / "bundle" / APP_NAME
        resources = app / "Contents" / "Resources"
        for name in WEB_FILES:
            if (resources / name).exists():
                raise SystemExit(f"{name} (versi web) ikut terbawa ke bundel. Hentikan: versi web tidak boleh dirilis.")
        with tarfile.open(python_archive(arch, python_path, work)) as archive:
            archive.extractall(resources, **({"filter": "tar"} if hasattr(tarfile, "tar_filter") else {}))
        for name in PRUNE:
            shutil.rmtree(resources / "python" / name, ignore_errors=True)
        (resources / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts" / "check_mac.py", resources / "scripts" / "check_mac.py")
        python = resources / "python" / "bin" / "python3"
        if native == arch:
            print("Pemeriksaan: Python pribadi + Tk + compile dengan odinpc")
            run(python, "-E", "-I", "-c", "import tkinter; print('Tk', tkinter.TkVersion)", timeout=60)
            run(python, "-E", "-I", resources / "scripts" / "check_mac.py", app, timeout=300,
                env={"PYTHONDONTWRITEBYTECODE": "1", "PATH": "/usr/bin:/bin"})
        else:
            print(f"Peringatan: Mac ini {native}, bundel untuk {arch}: pemeriksaan dilewati (jalankan di Mac {arch}).")
        for cache in app.rglob("__pycache__"):
            shutil.rmtree(cache, ignore_errors=True)
        # pkgbuild: not relocatable, always overwrite (an update must replace the app wherever the old one was).
        root = work / "root"
        root.mkdir()
        run("/usr/bin/ditto", app, root / APP_NAME)
        plist = work / "component.plist"
        run("/usr/bin/pkgbuild", "--analyze", "--root", root, plist)
        components = plistlib.loads(plist.read_bytes())
        for component in components:
            component.update(BundleIsRelocatable=False, BundleIsVersionChecked=False, BundleOverwriteAction="upgrade")
        plist.write_bytes(plistlib.dumps(components))
        scripts = work / "scripts"
        scripts.mkdir()
        for name, text in (("preinstall", PREINSTALL), ("postinstall", POSTINSTALL)):
            (scripts / name).write_text(text)
            (scripts / name).chmod(0o755)
        packages = work / "packages"
        packages.mkdir()
        run("/usr/bin/pkgbuild", "--root", root, "--component-plist", plist, "--identifier", IDENTIFIER,
            "--version", __version__, "--install-location", "/Applications", "--scripts", scripts, packages / "component.pkg")
        resources_dir = work / "installer-resources"
        resources_dir.mkdir()
        (resources_dir / "welcome.html").write_text(WELCOME.format(version=__version__))
        (resources_dir / "conclusion.html").write_text(CONCLUSION)
        shutil.copy2(ROOT / "LICENSE", resources_dir / "license.txt")
        distribution = work / "distribution.xml"
        distribution.write_text(DISTRIBUTION.format(arch=arch, identifier=IDENTIFIER, version=__version__))
        pkg = out / f"OdinTurboPascal-{__version__}-macos-{arch}.pkg"
        pkg.unlink(missing_ok=True)
        run("/usr/bin/productbuild", "--distribution", distribution, "--package-path", packages,
            "--resources", resources_dir, pkg)
    print(f"{pkg} ({pkg.stat().st_size / 1048576:.1f} MB)")
    print(f"SHA-256 {sha256(pkg)}")
    return pkg


def main():
    machine = platform.machine()
    parser = argparse.ArgumentParser(description="Bangun pemasang offline Odin Turbo Pascal untuk macOS.")
    parser.add_argument("--python-archive", help="arsip python-build-standalone yang sudah diunduh")
    parser.add_argument("--arch", choices=sorted(PBS_SHA256), default=machine if machine in PBS_SHA256 else "x86_64")
    parser.add_argument("--out", default=str(ROOT / "dist"), help="folder hasil (bawaan: dist/)")
    args = parser.parse_args()
    build(args.out, args.arch, args.python_archive)


if __name__ == "__main__":
    main()
