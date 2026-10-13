# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Document, settings, diagnostics and native Free Pascal build services."""
from __future__ import annotations

import functools
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


def data_dir() -> Path:
    base = Path.home() / ("Library/Application Support" if sys.platform == "darwin" else ".local/share")
    path = base / "OdinTurboPascal"
    path.mkdir(parents=True, exist_ok=True)
    return path


def atomic_write(path: Path, content: bytes) -> None:
    """Commit in the destination directory, leaving the old file on failure."""
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".odin-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        if path.exists():
            os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@dataclass
class Document:
    text: str = ""
    path: Path | None = None
    encoding: str = "utf-8"
    newline: str = "\n"
    saved_text: str = ""
    disk_hash: str = ""
    breakpoints: set[int] = field(default_factory=set)

    @classmethod
    def read(cls, path: Path) -> "Document":
        path = path.expanduser().resolve()
        raw = path.read_bytes()
        encoding = "utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8"
        try:
            text = raw.decode(encoding)
        except UnicodeDecodeError:
            encoding = "cp437"
            text = raw.decode(encoding)
        newline = "\r\n" if "\r\n" in text else "\n"
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        return cls(text, path, encoding, newline, text, hashlib.sha256(raw).hexdigest())

    @property
    def dirty(self) -> bool:
        return self.text != self.saved_text

    def externally_changed(self) -> bool:
        if not self.path or not self.disk_hash:
            return False
        return not self.path.exists() or hashlib.sha256(self.path.read_bytes()).hexdigest() != self.disk_hash

    def save(self, path: Path | None = None) -> None:
        target = (path or self.path)
        if target is None:
            raise ValueError("File belum diberi nama.")
        raw = self.text.replace("\n", self.newline).encode(self.encoding)
        atomic_write(target, raw)
        self.path = target.resolve()
        self.saved_text = self.text
        self.disk_hash = hashlib.sha256(raw).hexdigest()


DEFAULTS = {
    "compiler": "", "mode": "tp", "font_size": 17,
    "syntax": False, "tab_width": 2, "range_checks": True,
    "overflow_checks": True, "debug_info": True,
    "unit_paths": [], "include_paths": [], "arguments": "",
    "recent": [], "geometry": "1120x740", "main_file": "",
}


class Settings:
    def __init__(self, path: Path | None = None):
        self.path = path or data_dir() / "settings.json"
        self.values = dict(DEFAULTS)
        self.values["recent"] = []
        try:
            saved = json.loads(self.path.read_text())
            for key, default in DEFAULTS.items():
                if key in saved and type(saved[key]) is type(default):
                    self.values[key] = saved[key]
        except (OSError, ValueError, TypeError):
            pass
        self.values["font_size"] = min(30, max(10, self.values["font_size"]))
        self.values["tab_width"] = min(8, max(1, self.values["tab_width"]))
        if self.values["mode"] not in ("tp", "objfpc", "delphi"):
            self.values["mode"] = "tp"

    def __getitem__(self, key):
        return self.values[key]

    def __setitem__(self, key, value):
        self.values[key] = value

    def save(self):
        atomic_write(self.path, json.dumps(self.values, indent=2).encode())

    def add_recent(self, path):
        value = str(Path(path).resolve())
        self["recent"] = [value] + [p for p in self["recent"] if p != value][:11]
        self.save()


@dataclass(frozen=True)
class Diagnostic:
    file: str
    line: int
    column: int
    kind: str
    message: str


DIAGNOSTIC = re.compile(r"^(.+?)\((\d+),(\d+)\)\s+(Fatal|Error|Warning|Note|Hint):\s*(.*)$", re.I)


def parse_diagnostics(output: str) -> list[Diagnostic]:
    result = []
    for line in output.splitlines():
        match = DIAGNOSTIC.match(line)
        if match:
            file, row, col, kind, message = match.groups()
            result.append(Diagnostic(file, int(row), int(col), kind, message))
    return result


def locate_compiler(preferred="") -> str | None:
    candidates = [preferred, shutil.which("fpc"), "/opt/homebrew/bin/fpc", "/usr/local/bin/fpc"]
    for value in candidates:
        if value and Path(value).is_file() and os.access(value, os.X_OK):
            return str(Path(value).absolute())
    return None


@functools.lru_cache(maxsize=16)
def free_vision_dir(compiler: str, cpu: str | None = None) -> str | None:
    """Turbo Vision (Free Vision) units of this FPC install.

    fpc.cfg adds every units/<target>/* folder; on macOS Apple's univint/Menus.ppu
    is found before Free Vision's Menus, so `uses App` fails with "Can't find unit".
    """
    try:
        info = subprocess.run([compiler, "-iVTPTO"], capture_output=True, text=True, timeout=10).stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return None
    if len(info) != 3:
        return None
    version, default_cpu, target_os = info
    binary = Path(compiler)
    for prefix in dict.fromkeys((binary.parent.parent, binary.resolve().parent.parent)):
        path = prefix / "lib" / "fpc" / version / "units" / f"{cpu or default_cpu}-{target_os}" / "fv"
        if path.is_dir():
            return str(path)
    return None


@dataclass
class BuildResult:
    success: bool
    command: list[str]
    output: str
    diagnostics: list[Diagnostic]
    executable: Path | None
    source: Path


def build(source: Path, settings: Settings, rebuild=False, cache: Path | None = None) -> BuildResult:
    source = source.resolve()
    compiler = locate_compiler(settings["compiler"])
    if not compiler:
        return BuildResult(False, [], "Free Pascal belum ditemukan. Jalankan Install.command atau atur Options > Compiler.", [], None, source)
    # Isolate outputs by source AND compiler settings. Never overwrite user files.
    key = hashlib.sha256((str(source) + json.dumps({k: settings[k] for k in ("mode", "compiler", "unit_paths", "include_paths", "range_checks", "overflow_checks", "debug_info")})).encode()).hexdigest()[:16]
    output_dir = (cache or data_dir() / "build") / key
    output_dir.mkdir(parents=True, exist_ok=True)
    exe = output_dir / source.stem
    # A failed rebuild must never launch an older executable.
    exe.unlink(missing_ok=True)
    command = [compiler, "-M" + settings["mode"], "-FE" + str(output_dir), "-FU" + str(output_dir), "-o" + str(exe)]
    if settings["range_checks"]:
        command.append("-Cr")
    if settings["overflow_checks"]:
        command.append("-Co")
    if settings["debug_info"]:
        command += ["-gl", "-gw"]
    if rebuild:
        command.append("-B")
    for key, flag in (("unit_paths", "-Fu"), ("include_paths", "-Fi")):
        command += [flag + str(Path(p).expanduser().resolve()) for p in settings[key] if p]
    cpu = ("aarch64" if platform.machine() == "arm64" else "x86_64") if sys.platform == "darwin" else None
    # FPC searches -Fu in order: the user's own units still win over Free Vision.
    vision = free_vision_dir(compiler, cpu)
    if vision:
        command.append("-Fu" + vision)
    if sys.platform == "darwin":
        command.append("-P" + cpu)
        try:
            sdk = subprocess.run(["/usr/bin/xcrun", "--show-sdk-path"], capture_output=True, text=True, timeout=10)
            if sdk.returncode == 0 and sdk.stdout.strip():
                command.append("-XR" + sdk.stdout.strip())
        except (OSError, subprocess.TimeoutExpired):
            pass
    command.append(str(source))
    try:
        result = subprocess.run(command, cwd=source.parent, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        output = result.stdout.decode("utf-8", errors="replace")
        success = result.returncode == 0
    except subprocess.TimeoutExpired:
        output, success = "Kompilasi melewati batas 120 detik.", False
    except OSError as error:
        output, success = str(error), False
    return BuildResult(success, command, output, parse_diagnostics(output), exe if success and exe.exists() else None, source)


KEYWORDS = set("and array asm begin case const constructor destructor div do downto else end file for function goto if implementation in inherited inline interface label mod nil not object of or packed procedure program record repeat set shl shr string then to type unit until uses var while with xor true false absolute external forward interrupt near far virtual private public protected class try except finally raise result out property threadvar".split())
TOKENS = re.compile(r"\{[\s\S]*?\}|\(\*[\s\S]*?\*\)|//[^\n]*|'(?:[^']|'')*'|\b[a-zA-Z_][a-zA-Z_0-9]*\b|\$[0-9A-Fa-f]+|\b\d+(?:\.\d+)?\b")


def syntax_spans(text: str):
    for match in TOKENS.finditer(text):
        token = match.group()
        kind = ""
        if token.startswith(("{", "(*", "//")):
            kind = "comment"
        elif token.startswith("'"):
            kind = "string"
        elif token.lower() in KEYWORDS:
            kind = "keyword"
        elif token[0].isdigit() or token[0] == "$":
            kind = "number"
        if kind:
            yield kind, match.start(), match.end()
