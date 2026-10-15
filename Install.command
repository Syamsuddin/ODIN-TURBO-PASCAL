#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
# Local installation. Supports Intel and Apple Silicon; no administrator access
# is needed to install Odin itself. Homebrew manages its own dependency install.
set -euo pipefail
cd "$(dirname "$0")"
ODIN_PACKAGE_DIR="$PWD"
trap 'code=$?; if [ "$code" -ne 0 ]; then printf "\nInstalasi belum selesai. Lihat pesan di atas.\n"; read -r -p "Tekan Enter untuk menutup... " ignored || true; fi' EXIT
if [ "$(uname -s)" != "Darwin" ]; then
  printf 'Pemasang ini khusus macOS. Untuk Linux: python3 main.py\n'
  exit 1
fi
ODIN_ARCH="$(uname -m)"
if [ "$(/usr/sbin/sysctl -in hw.optional.arm64 2>/dev/null || true)" = "1" ]; then
  ODIN_ARCH=arm64
  if [ "$(uname -m)" != "arm64" ]; then
    exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
  fi
fi
case "$ODIN_ARCH" in arm64|x86_64) ;; *) printf 'Arsitektur tidak didukung.\n'; exit 1;; esac
printf '\nODIN TURBO PASCAL 2.0.1\nDibuat oleh Syams Ideris\nPemasang macOS %s\nLisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris\n\n' "$ODIN_ARCH"
printf 'Lokasi aplikasi: ~/Applications/Odin Turbo Pascal.app\n'
printf 'Dependensi: Python 3.10+ dengan Tk, Free Pascal, Xcode Command Line Tools.\n'
printf 'Berkas Pascal pribadi tidak dihapus atau diganti.\n\n'

ODIN_PYTHON=""
find_python() {
  ODIN_PYTHON=""
  for candidate in /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
      /opt/homebrew/opt/python@3.13/bin/python3.13 \
      /usr/local/opt/python@3.13/bin/python3.13 \
      /opt/homebrew/bin/python3 /usr/local/bin/python3 \
      "$(command -v python3 || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -c \
      'import sys, tkinter, platform; assert sys.version_info >= (3,10); assert platform.machine() == sys.argv[1]; t=tkinter.Tk(); t.withdraw(); t.update(); t.destroy()' "$ODIN_ARCH" 2>/dev/null; then
      ODIN_PYTHON="$candidate"
      return 0
    fi
  done
  return 1
}
ODIN_FPC=""
find_fpc() {
  ODIN_FPC=""
  for candidate in /opt/homebrew/bin/fpc /usr/local/bin/fpc "$(command -v fpc || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then ODIN_FPC="$candidate"; return 0; fi
  done
  return 1
}
find_python || true
find_fpc || true

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  printf 'Xcode Command Line Tools belum ditemukan. Dialog Apple akan dibuka.\n'
  /usr/bin/xcode-select --install || true
  read -r -p 'Selesaikan pemasangan pada dialog Apple, lalu tekan Enter... ' ignored
  /usr/bin/xcode-select -p >/dev/null
fi

if [ -z "$ODIN_PYTHON" ] || [ -z "$ODIN_FPC" ]; then
  ODIN_BREW="/usr/local/bin/brew"
  if [ "$ODIN_ARCH" = arm64 ]; then ODIN_BREW="/opt/homebrew/bin/brew"; fi
  if [ ! -x "$ODIN_BREW" ]; then
    printf '\nDependensi belum lengkap. Pilih metode pemasangan:\n'
    printf '1. Homebrew: pasang pengelola paket resmi dan dependensi (memerlukan internet).\n'
    printf '2. Manual: Python universal2 dan Free Pascal Intel+ARM64 dari situs resmi.\n'
    read -r -p 'Pilihan [1/2]: ' method
    if [ "$method" = "1" ]; then
      ODIN_BOOTSTRAP="$(mktemp -t odin-homebrew)"
      /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
        https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$ODIN_BOOTSTRAP"
      /bin/bash "$ODIN_BOOTSTRAP"
      rm -f "$ODIN_BOOTSTRAP"
    else
      /usr/bin/open 'https://www.python.org/downloads/macos/'
      /usr/bin/open 'https://www.freepascal.org/down/i386/macosx.html'
      printf '\nPasang Python universal2 dan Free Pascal Intel+ARM64 dari kedua halaman tersebut.\n'
      printf 'Setelah selesai, jalankan kembali Install.command. Lihat README.txt.\n'
      exit 1
    fi
  fi
  if [ -z "$ODIN_PYTHON" ]; then "$ODIN_BREW" install python-tk@3.13; fi
  if [ -z "$ODIN_FPC" ]; then "$ODIN_BREW" install fpc; fi
  find_python
  find_fpc
fi

printf '\nMemeriksa kompilasi native...\n'
"$ODIN_PYTHON" "$ODIN_PACKAGE_DIR/scripts/check_mac.py" "$ODIN_FPC"

ODIN_SUPPORT="$HOME/Library/Application Support/OdinTurboPascal"
ODIN_APPS="$HOME/Applications"
ODIN_TARGET="$ODIN_APPS/Odin Turbo Pascal.app"
mkdir -p "$ODIN_SUPPORT" "$ODIN_APPS"
if [ -e "$ODIN_TARGET" ]; then
  read -r -p 'Aplikasi sudah ada. Ganti aplikasi dan simpan cadangan versi sebelumnya? [y/N] ' answer
  case "$answer" in y|Y)
    mv "$ODIN_TARGET" "$ODIN_APPS/Odin Turbo Pascal.backup-$(date +%Y%m%d-%H%M%S).app";;
    *) printf 'Pemasangan dibatalkan.\n'; exit 0;;
  esac
fi
/usr/bin/ditto "$ODIN_PACKAGE_DIR/Odin Turbo Pascal.app" "$ODIN_TARGET"
printf '%s\n' "$ODIN_PYTHON" > "$ODIN_SUPPORT/python-path"
chmod +x "$ODIN_TARGET/Contents/MacOS/OdinTurboPascal"

# Register the app locally without changing Gatekeeper or clearing quarantine.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$ODIN_TARGET" || true
printf '\nSelesai. Aplikasi terpasang di %s\n' "$ODIN_TARGET"
printf 'Jika macOS meminta persetujuan, gunakan Privacy & Security > Open Anyway.\n'
/usr/bin/open "$ODIN_TARGET"
read -r -p 'Tekan Enter untuk menutup pemasang... ' ignored
