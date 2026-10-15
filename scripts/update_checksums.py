#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Regenerate SHA256SUMS.json: every file git tracks except itself, sorted.

Run it last, after package_app.py, so the hashes cover the rebuilt bundle.
New files must be added to git (git add) first to be included.
"""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
listing = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout.decode("utf-8")
sums = {}
for name in sorted(name for name in listing.split("\0") if name and name != "SHA256SUMS.json"):
    path = ROOT / name
    if path.is_file() and not path.is_symlink():
        sums[name] = hashlib.sha256(path.read_bytes()).hexdigest()
(ROOT / "SHA256SUMS.json").write_text(json.dumps(sums, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"SHA256SUMS.json: {len(sums)} berkas")
