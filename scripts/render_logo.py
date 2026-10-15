#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Render assets/odin-logo-master.png into the PNG and ICNS files the IDE uses,
and refresh the logo embedded in assets/banner.svg.

The master is the ODIN Turbo Pascal logo from the OTP v2.0 project. Large sizes
show the whole logo; icon sizes up to 64 px and the README banner show only the
emblem (Odin, lightning bolt and book), because the wordmark is unreadable there
and the banner has its own.

Developer tool only: the IDE stays stdlib-only and reads the generated PNGs.
Needs Pillow (python3 -m pip install pillow) and, for odin.icns, the macOS
iconutil. Rerun scripts/package_app.py afterwards to refresh the .app.
"""
import base64
import io
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Butuh Pillow untuk merender logo: python3 -m pip install pillow")

ASSETS = Path(__file__).resolve().parent.parent / "assets"
MASTER = ASSETS / "odin-logo-master.png"
# Emblem without the wordmark, in master pixels (the master is 1254 x 1254).
EMBLEM_BOX = (102, 334, 1152, 1244)
ICONSET = {"icon_16x16": 16, "icon_16x16@2x": 32, "icon_32x32": 32, "icon_32x32@2x": 64,
           "icon_128x128": 128, "icon_128x128@2x": 256, "icon_256x256": 256,
           "icon_256x256@2x": 512, "icon_512x512": 512, "icon_512x512@2x": 1024}


def emblem(master):
    """The emblem, padded with the master's black background into a square."""
    part = master.crop(EMBLEM_BOX)
    side = max(part.size)
    square = Image.new("RGB", (side, side), "black")
    square.paste(part, ((side - part.width) // 2, (side - part.height) // 2))
    return square


def tile(image, size):
    """A macOS-style icon: the image on a rounded square with a transparent margin."""
    inner = round(size * 0.805)
    offset = (size - inner) // 2
    mask = Image.new("L", (inner * 4, inner * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner * 4 - 1, inner * 4 - 1), radius=round(inner * 4 * 0.2), fill=255)
    mask = mask.resize((inner, inner), Image.LANCZOS)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(image.resize((inner, inner), Image.LANCZOS), (offset, offset), mask)
    return icon


def png_bytes(image):
    """PNG with a 64-color palette: the art is black, yellow, white and pink, and
    the resampled halftone would otherwise make the files ten times larger."""
    method = Image.Quantize.FASTOCTREE if image.mode == "RGBA" else Image.Quantize.MEDIANCUT
    buffer = io.BytesIO()
    image.quantize(colors=64, method=method, dither=Image.Dither.NONE).save(buffer, "PNG", optimize=True)
    return buffer.getvalue()


def save(image, path):
    path.write_bytes(png_bytes(image))


master = Image.open(MASTER).convert("RGB")
save(tile(master, 1024), ASSETS / "odin.png")
save(master.resize((280, 280), Image.LANCZOS), ASSETS / "odin-logo.png")
save(master.resize((200, 200), Image.LANCZOS), ASSETS / "odin-logo-small.png")

# README banner: a 220 x 220 slot, embedded at twice that size for sharp displays.
banner = ASSETS / "banner.svg"
data = "data:image/png;base64," + base64.b64encode(png_bytes(tile(emblem(master), 440))).decode()
text, count = re.subn(r"data:image/png;base64,[A-Za-z0-9+/=]+", data, banner.read_text(encoding="utf-8"))
if not count:
    raise SystemExit("banner.svg tidak berisi gambar logo tertanam.")
banner.write_text(text, encoding="utf-8")

if shutil.which("iconutil"):
    with tempfile.TemporaryDirectory() as directory:
        iconset = Path(directory) / "odin.iconset"
        iconset.mkdir()
        small = emblem(master)
        for name, size in ICONSET.items():
            save(tile(small if size <= 64 else master, size), iconset / f"{name}.png")
        subprocess.run(["iconutil", "-c", "icns", "-o", str(ASSETS / "odin.icns"), str(iconset)], check=True)
else:
    print("iconutil tidak ditemukan; odin.icns tidak diperbarui.", file=sys.stderr)
print(ASSETS)
