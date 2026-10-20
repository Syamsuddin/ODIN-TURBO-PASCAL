#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN_PYTHON=""
ODIN_SUPPORT="$HOME/Library/Application Support/OdinTurboPascal"
if [ -f "$ODIN_SUPPORT/python-path" ]; then
  IFS= read -r ODIN_PYTHON < "$ODIN_SUPPORT/python-path" || true
fi
if [ -z "$ODIN_PYTHON" ] || [ ! -x "$ODIN_PYTHON" ]; then
  printf 'Jalankan Install.command terlebih dahulu.\n'; exit 1
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
"$ODIN_PYTHON" scripts/check_mac.py "Odin Turbo Pascal.app"
"$ODIN_PYTHON" -m unittest discover -s tests -v
printf '\nUji otomatis selesai. Uji Finder, pintasan Mac, dan debugger secara manual.\n'
read -r -p 'Tekan Enter untuk menutup... ' ignored
