# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
#
# Local installation on Windows 10 1809 or later (x86-64), the counterpart of Install.command.
# No administrator access is needed to install Odin itself; winget may ask for permission when
# it installs Python or Free Pascal. Double-click Install.cmd, or run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Install.ps1
# Keep this file ASCII: Windows PowerShell 5.1 reads a script without BOM in the ANSI code page.
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$PackageDir = $PSScriptRoot

function Wait-Enter([string]$Prompt) {
    try { [void](Read-Host $Prompt) } catch { }
}

function Exit-Install([string]$Message) {
    if ($Message) { Write-Host $Message }
    Write-Host ''
    Write-Host 'Instalasi belum selesai. Lihat pesan di atas.'
    Wait-Enter 'Tekan Enter untuk menutup'
    exit 1
}

trap {
    Exit-Install ('Kesalahan: ' + $_.Exception.Message)
}

# Python prints paths as UTF-8 and PowerShell reads them as UTF-8, so a user folder with
# non-ASCII letters survives the round trip.
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

if ($env:OS -ne 'Windows_NT') {
    Exit-Install 'Pemasang ini khusus Windows. Untuk macOS: Install.command. Untuk Linux: python3 main.py'
}
if ([Environment]::OSVersion.Version.Build -lt 17763) {
    Exit-Install 'Odin memerlukan Windows 10 versi 1809 (build 17763) atau yang lebih baru, karena User screen memakai ConPTY.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    Exit-Install 'Odin memerlukan Windows 64-bit (x86-64).'
}

# The version comes from the package itself, so the banner never goes stale.
$Version = ''
$VersionLine = Select-String -LiteralPath (Join-Path $PackageDir 'odin\__init__.py') -Pattern '^__version__ = "([^"]+)"'
if ($VersionLine) { $Version = $VersionLine.Matches[0].Groups[1].Value }
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\OdinTurboPascal'
$DataDir = Join-Path $env:APPDATA 'OdinTurboPascal'

Write-Host ''
Write-Host "ODIN TURBO PASCAL $Version"
Write-Host 'Dibuat oleh Syams Ideris'
Write-Host 'Pemasang Windows x86_64'
Write-Host 'Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris'
Write-Host ''
Write-Host "Lokasi aplikasi: $InstallDir"
Write-Host 'Dependensi: Python 3.10+ dengan Tk, Free Pascal.'
Write-Host 'Berkas Pascal pribadi tidak dihapus atau diganti.'
Write-Host ''

# Prints sys.executable when the interpreter is 3.10+ and can open a Tk window.
$PythonCheck = 'import sys, tkinter; assert sys.version_info >= (3, 10); t = tkinter.Tk(); t.withdraw(); t.update(); t.destroy(); print(sys.executable)'

function Test-Python([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Exe @Arguments -c $PythonCheck 2>$null)
        if ($LASTEXITCODE -eq 0 -and $output.Count -gt 0) {
            $path = ([string]$output[-1]).Trim()
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
        }
    } catch { }
    return $null
}

function Find-Python {
    $ErrorActionPreference = 'Continue'
    $candidates = New-Object System.Collections.Generic.List[object]
    if (Get-Command py.exe -ErrorAction SilentlyContinue) {
        # Every Python the py launcher knows, newest first, then its default.
        foreach ($line in @(& py.exe -0p 2>&1 | ForEach-Object { "$_" })) {
            if ($line -match '([A-Za-z]:\\.+?python\.exe)') {
                $candidates.Add([pscustomobject]@{ Exe = $Matches[1]; Arguments = @() })
            }
        }
        $candidates.Add([pscustomobject]@{ Exe = 'py.exe'; Arguments = @('-3') })
    }
    # python.org installers: per user and for all users.
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs\Python'), $env:ProgramFiles)) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Python3*' | Sort-Object Name -Descending)) {
                $candidates.Add([pscustomobject]@{ Exe = (Join-Path $folder.FullName 'python.exe'); Arguments = @() })
            }
        }
    }
    foreach ($command in @(Get-Command python.exe -All -ErrorAction SilentlyContinue)) {
        $candidates.Add([pscustomobject]@{ Exe = $command.Source; Arguments = @() })
    }
    foreach ($candidate in $candidates) {
        if ($candidate.Exe -ne 'py.exe' -and -not (Test-Path -LiteralPath $candidate.Exe -PathType Leaf)) { continue }
        $found = Test-Python $candidate.Exe $candidate.Arguments
        if ($found) { return $found }
    }
    return $null
}

function Get-VersionOrZero([string]$Name) {
    $value = $null
    if ([version]::TryParse($Name, [ref]$value)) { return $value }
    return [version]'0.0'
}

# The same places as windows_fpc_candidates() in odin/core.py.
function Find-Fpc {
    $candidates = @()
    $command = Get-Command fpc.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $drive = $env:SystemDrive
    if (-not $drive) { $drive = 'C:' }
    $roots = @()
    foreach ($parent in @("$drive\FPC", "$drive\lazarus\fpc")) {
        if (Test-Path -LiteralPath $parent) {
            $roots += @(Get-ChildItem -LiteralPath $parent -Directory |
                Sort-Object -Property @{ Expression = { Get-VersionOrZero $_.Name } } -Descending |
                ForEach-Object { $_.FullName })
        }
    }
    $tools = $env:ChocolateyToolsLocation
    if (-not $tools) { $tools = "$drive\tools" }
    $roots += (Join-Path $tools 'freepascal')
    foreach ($root in $roots) {
        foreach ($target in @('x86_64-win64', 'i386-win32')) {
            $candidates += (Join-Path $root "bin\$target\fpc.exe")
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

$Python = Find-Python
$Fpc = Find-Fpc

if (-not $Python -or -not $Fpc) {
    $Winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    Write-Host 'Dependensi belum lengkap:'
    if (-not $Python) { Write-Host '  - Python 3.10+ dengan Tk' }
    if (-not $Fpc) { Write-Host '  - Free Pascal' }
    Write-Host ''
    Write-Host 'Pilih metode pemasangan:'
    if ($Winget) {
        Write-Host '1. winget: pasang dari katalog paket Windows (memerlukan internet).'
    } else {
        Write-Host '1. winget: belum tersedia di Windows ini (pasang App Installer dari Microsoft Store).'
    }
    Write-Host '2. Manual: unduh dari situs resmi Python dan Free Pascal.'
    $Method = Read-Host 'Pilihan [1/2]'
    if ($Method -eq '1' -and $Winget) {
        if (-not $Python) {
            & winget.exe install --id Python.Python.3.13 --exact --scope user --accept-package-agreements --accept-source-agreements
        }
        if (-not $Fpc) {
            Write-Host 'Windows mungkin meminta izin administrator untuk memasang Free Pascal.'
            & winget.exe install --id FreePascal.FreePascalCompiler --exact --accept-package-agreements --accept-source-agreements
        }
        $Python = Find-Python
        $Fpc = Find-Fpc
        if (-not $Python) { Exit-Install 'Python dengan Tk belum ditemukan. Tutup jendela ini, lalu jalankan Install.cmd kembali.' }
        if (-not $Fpc) { Exit-Install 'Free Pascal belum ditemukan. Tutup jendela ini, lalu jalankan Install.cmd kembali.' }
    } else {
        if (-not $Python) { Start-Process 'https://www.python.org/downloads/windows/' }
        if (-not $Fpc) { Start-Process 'https://www.freepascal.org/download.html' }
        Write-Host ''
        Write-Host 'Pasang Python 3.10 atau yang lebih baru (dengan pilihan tcl/tk) dan Free Pascal untuk Windows x86_64.'
        Write-Host 'Setelah selesai, jalankan kembali Install.cmd.'
        Exit-Install ''
    }
}
Write-Host "Python: $Python"
Write-Host "Free Pascal: $Fpc"

Write-Host ''
Write-Host 'Memeriksa kompilasi native...'
& $Python (Join-Path $PackageDir 'scripts\check_windows.py') $Fpc
if ($LASTEXITCODE -ne 0) { Exit-Install 'Pemeriksaan kompilasi native gagal.' }

$Pythonw = Join-Path (Split-Path -Parent $Python) 'pythonw.exe'
if (-not (Test-Path -LiteralPath $Pythonw -PathType Leaf)) {
    Exit-Install "pythonw.exe tidak ditemukan di samping $Python."
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InstallDir) | Out-Null
if (Test-Path -LiteralPath $InstallDir) {
    $Answer = Read-Host 'Aplikasi sudah ada. Ganti aplikasi dan simpan cadangan versi sebelumnya? [y/N]'
    if ($Answer -notmatch '^[yY]$') {
        Write-Host 'Pemasangan dibatalkan.'
        Wait-Enter 'Tekan Enter untuk menutup'
        exit 0
    }
    $Backup = $InstallDir + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    try {
        Move-Item -LiteralPath $InstallDir -Destination $Backup
    } catch {
        Exit-Install 'Aplikasi lama tidak bisa dipindahkan. Tutup Odin Turbo Pascal terlebih dahulu.'
    }
    Write-Host "Cadangan versi sebelumnya: $Backup"
}
& $Python (Join-Path $PackageDir 'scripts\stage_windows.py') $InstallDir
if ($LASTEXITCODE -ne 0) { Exit-Install 'Penyalinan aplikasi gagal.' }

# Like the macOS installer: the data folder records which Python runs Odin.
[System.IO.File]::WriteAllText((Join-Path $DataDir 'python-path'), "$Python`n", (New-Object System.Text.UTF8Encoding($false)))

# Start menu and Desktop shortcuts: pythonw.exe (no console window) in UTF-8 mode, like the
# PYTHONUTF8=1 of the macOS launcher, running the launcher in the install folder.
$Launcher = Join-Path $InstallDir 'OdinTurboPascal.pyw'
$Arguments = "-X utf8 `"$Launcher`""
$Shell = New-Object -ComObject WScript.Shell
foreach ($Folder in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
    $Link = $Shell.CreateShortcut((Join-Path $Folder 'Odin Turbo Pascal.lnk'))
    $Link.TargetPath = $Pythonw
    $Link.Arguments = $Arguments
    $Link.WorkingDirectory = $env:USERPROFILE
    $Link.IconLocation = (Join-Path $InstallDir 'odin.ico') + ',0'
    $Link.Description = 'Odin Turbo Pascal'
    $Link.Save()
}

Write-Host ''
Write-Host "Selesai. Aplikasi terpasang di $InstallDir"
Write-Host 'Buka Odin Turbo Pascal dari menu Start atau Desktop.'
Start-Process -FilePath $Pythonw -ArgumentList $Arguments -WorkingDirectory $env:USERPROFILE
Wait-Enter 'Tekan Enter untuk menutup pemasang'
