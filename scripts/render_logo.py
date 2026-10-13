#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Render the SVG sources in assets/ into the PNG and ICNS files the IDE uses.

Developer tool only: the IDE stays stdlib-only and reads the generated PNGs.
Needs cairosvg (python3 -m pip install cairosvg) and, for odin.icns, the
macOS iconutil. Rerun scripts/package_app.py afterwards to refresh the .app.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import cairosvg
except ImportError:
    raise SystemExit("Butuh cairosvg untuk merender logo: python3 -m pip install cairosvg")

ASSETS = Path(__file__).resolve().parent.parent / "assets"
# Sizes up to 64 px use the simplified icon, larger ones show the horns and ravens.
ICONSET = {"icon_16x16": 16, "icon_16x16@2x": 32, "icon_32x32": 32, "icon_32x32@2x": 64,
           "icon_128x128": 128, "icon_128x128@2x": 256, "icon_256x256": 256,
           "icon_256x256@2x": 512, "icon_512x512": 512, "icon_512x512@2x": 1024}


def render(source, target, width):
    cairosvg.svg2png(url=str(ASSETS / source), write_to=str(target), output_width=width)


render("odin-icon.svg", ASSETS / "odin.png", 1024)
render("odin-logo.svg", ASSETS / "odin-logo.png", 280)
render("odin-logo.svg", ASSETS / "odin-logo-small.png", 200)
if shutil.which("iconutil"):
    with tempfile.TemporaryDirectory() as directory:
        iconset = Path(directory) / "odin.iconset"
        iconset.mkdir()
        for name, size in ICONSET.items():
            render("odin-icon-small.svg" if size <= 64 else "odin-icon.svg", iconset / f"{name}.png", size)
        subprocess.run(["iconutil", "-c", "icns", "-o", str(ASSETS / "odin.icns"), str(iconset)], check=True)
else:
    print("iconutil tidak ditemukan; odin.icns tidak diperbarui.", file=sys.stderr)
print(ASSETS)
