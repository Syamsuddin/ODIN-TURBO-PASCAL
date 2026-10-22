#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p BIN BUILD
compiler="${FPC_BIN:-fpc}"
for src in EXAMPLES/*.PAS TESTS/*.PAS; do
  "$compiler" -Mtp -B -Cr -Co -Ci -Ct -FuUNITS -FiEXAMPLES -FUBUILD -FEBIN "$src"
done
printf '%s\n' 'Build selesai. Jalankan ./BIN/TESTALL dan ./BIN/TESTADV dari folder otp-AI.'
