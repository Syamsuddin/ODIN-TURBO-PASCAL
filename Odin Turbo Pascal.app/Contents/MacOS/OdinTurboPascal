#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
set -euo pipefail
ODIN_CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
ODIN_SUPPORT="$HOME/Library/Application Support/OdinTurboPascal"
mkdir -p "$ODIN_SUPPORT"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
if [ "$(/usr/sbin/sysctl -in hw.optional.arm64 2>/dev/null || true)" = 1 ] && [ "$(uname -m)" != arm64 ]; then
  exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
fi
ODIN_PYTHON=""
if [ -f "$ODIN_SUPPORT/python-path" ]; then
  IFS= read -r ODIN_PYTHON < "$ODIN_SUPPORT/python-path" || true
fi
if [ -z "$ODIN_PYTHON" ] || [ ! -x "$ODIN_PYTHON" ]; then
  for candidate in /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
      /opt/homebrew/opt/python@3.13/bin/python3.13 /usr/local/opt/python@3.13/bin/python3.13 \
      /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if [ -x "$candidate" ] && "$candidate" -c 'import sys, tkinter; assert sys.version_info >= (3,10)' >/dev/null 2>&1; then
      ODIN_PYTHON="$candidate"; break
    fi
  done
fi
if [ -z "$ODIN_PYTHON" ] || [ ! -x "$ODIN_PYTHON" ]; then
  /usr/bin/osascript -e 'display alert "Odin Turbo Pascal" message "Python dengan Tk belum tersedia. Jalankan Install.command dari paket unduhan terlebih dahulu." as critical'
  exit 1
fi
cd "$HOME"
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUTF8=1
"$ODIN_PYTHON" "$ODIN_CONTENTS/Resources/main.py" "$@" >> "$ODIN_SUPPORT/launch.log" 2>&1 || {
  /usr/bin/osascript -e 'display alert "Odin Turbo Pascal" message "Aplikasi gagal dibuka. Lihat ~/Library/Application Support/OdinTurboPascal/launch.log atau jalankan Install.command kembali." as critical'
  exit 1
}
