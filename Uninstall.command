#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
set -euo pipefail
ODIN_TARGET="$HOME/Applications/Odin Turbo Pascal.app"
printf 'Odin akan dipindahkan ke Trash. Kode Pascal dan pengaturan tetap disimpan.\n'
read -r -p 'Lanjutkan? [y/N] ' answer
case "$answer" in y|Y)
  if [ -d "$ODIN_TARGET" ]; then
    mkdir -p "$HOME/.Trash"
    mv "$ODIN_TARGET" "$HOME/.Trash/Odin Turbo Pascal-$(date +%Y%m%d-%H%M%S).app"
    printf 'Aplikasi dipindahkan ke Trash.\n'
  else printf 'Aplikasi tidak ditemukan pada lokasi pemasangan standar.\n'; fi;;
  *) printf 'Dibatalkan.\n';;
esac
