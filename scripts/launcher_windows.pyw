# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Windows launcher: the Start menu and Desktop shortcuts run it as pythonw.exe -X utf8.

scripts/stage_windows.py copies it into the install folder as OdinTurboPascal.pyw, next to
main.py. Like scripts/launcher.sh on macOS it starts in the home folder, appends the output to
launch.log in the data folder (pythonw.exe has no console, so a traceback would vanish) and
tells the user when the IDE cannot start."""
import ctypes
import os
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming") / "OdinTurboPascal"


def alert(message):
    try:
        box = ctypes.WinDLL("user32").MessageBoxW
        box.argtypes = (ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint)
        box.restype = ctypes.c_int
        box(None, message, "Odin Turbo Pascal", 0x10)   # MB_ICONERROR
    except (AttributeError, OSError):
        pass


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    sys.stdout = sys.stderr = open(DATA / "launch.log", "a", encoding="utf-8", buffering=1)
    os.chdir(Path.home())
    sys.path.insert(0, str(HERE))
    try:
        from odin.app import main as run
        run()
    except Exception:
        traceback.print_exc()
        alert(f"Aplikasi gagal dibuka. Lihat {DATA / 'launch.log'} atau pasang ulang dengan Setup.exe (atau Install.cmd).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
