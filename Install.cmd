@echo off
rem SPDX-License-Identifier: GPL-3.0-or-later
rem Copyright (c) 2026 Syams Ideris
rem Double-click to install Odin Turbo Pascal on Windows: runs Install.ps1 without
rem changing the PowerShell execution policy of the computer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
