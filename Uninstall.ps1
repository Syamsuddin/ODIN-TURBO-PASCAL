# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Removes the Windows installation made by Install.ps1, the counterpart of Uninstall.command:
# the app folder goes to the Recycle Bin, the shortcuts are deleted, and Pascal sources and
# settings (%APPDATA%\OdinTurboPascal) stay. Double-click Uninstall.cmd, or run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Uninstall.ps1
# Keep this file ASCII: Windows PowerShell 5.1 reads a script without BOM in the ANSI code page.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# The app folder cannot move while it is the current folder.
Set-Location -LiteralPath $env:USERPROFILE
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\OdinTurboPascal'
$Links = @((Join-Path ([Environment]::GetFolderPath('Programs')) 'Odin Turbo Pascal.lnk'),
           (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Odin Turbo Pascal.lnk'))

Write-Host 'Odin akan dipindahkan ke Recycle Bin. Kode Pascal dan pengaturan tetap disimpan.'
$Answer = Read-Host 'Lanjutkan? [y/N]'
if ($Answer -match '^[yY]$') {
    if (Test-Path -LiteralPath $InstallDir) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($InstallDir,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            Write-Host 'Aplikasi dipindahkan ke Recycle Bin.'
        } catch {
            Write-Host 'Aplikasi tidak bisa dipindahkan. Tutup Odin Turbo Pascal terlebih dahulu, lalu coba lagi.'
        }
    } else {
        Write-Host 'Aplikasi tidak ditemukan pada lokasi pemasangan standar.'
    }
    foreach ($Link in $Links) {
        if (Test-Path -LiteralPath $Link) { Remove-Item -LiteralPath $Link }
    }
} else {
    Write-Host 'Dibatalkan.'
}
try { [void](Read-Host 'Tekan Enter untuk menutup') } catch { }
