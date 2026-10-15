@echo off
rem SPDX-License-Identifier: GPL-3.0-or-later
rem Copyright (c) 2026 Syams Ideris
rem Double-click to remove Odin Turbo Pascal from Windows (runs Uninstall.ps1).
cd /d "%USERPROFILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
