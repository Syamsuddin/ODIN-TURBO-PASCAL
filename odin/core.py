# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Document, settings, diagnostics and native build services (the Odin toolchain, odinpc)."""
from __future__ import annotations

import bisect
import hashlib
import json
import os
import platform
import re
import shlex
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

# Compiler runs from the IDE (pythonw.exe on Windows has no console) must not flash a console window.
NO_WINDOW = {"creationflags": 0x08000000} if os.name == "nt" else {}   # CREATE_NO_WINDOW


def data_dir() -> Path:
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")
    else:
        base = Path.home() / ("Library/Application Support" if sys.platform == "darwin" else ".local/share")
    path = base / "OdinTurboPascal"
    path.mkdir(parents=True, exist_ok=True)
    return path


def executable_name(stem: str) -> str:
    """The file name of a native program: NAME.exe on Windows, NAME elsewhere."""
    return stem + ".exe" if sys.platform == "win32" else stem


def installer_name() -> str:
    return "Install.ps1" if sys.platform == "win32" else "Install.command"


def split_arguments(text: str) -> list[str]:
    """Run > Parameters as an argv list (never a shell). Quotes group words; on Windows a
    backslash is a path separator, not an escape character."""
    if sys.platform != "win32":
        return shlex.split(text)
    lexer = shlex.shlex(text, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    lexer.escape = ""
    return list(lexer)


def join_command(argv) -> str:
    """argv as the platform's shell would show it (Compiler messages)."""
    return subprocess.list2cmdline(argv) if sys.platform == "win32" else shlex.join(argv)


def lock_instance(path: Path):
    """Opens and locks path for this IDE; None when another instance holds the lock.

    flock on POSIX. On Windows msvcrt.locking on the first byte: no other handle can lock it
    until this one unlocks or closes (unlock_instance)."""
    handle = path.open("a")
    if sys.platform == "win32":
        import errno
        import msvcrt
        try:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as error:
            handle.close()
            if error.errno in (errno.EACCES, errno.EDEADLK):
                return None
            raise
        return handle
    import fcntl
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    return handle


def unlock_instance(handle) -> None:
    if sys.platform == "win32":
        import msvcrt
        try:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
    handle.close()


def replace_file(source, target) -> None:
    """os.replace. On Windows a virus scanner or the search indexer can hold the target for a
    moment, which makes it fail with PermissionError, so it tries again for up to a second."""
    attempts = 20 if os.name == "nt" else 1
    for attempt in range(attempts):
        try:
            os.replace(source, target)
            return
        except PermissionError:
            if attempt == attempts - 1:
                raise
            time.sleep(.05)


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
        replace_file(name, path)
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
        return cls.from_bytes(path.read_bytes(), path)

    @classmethod
    def from_bytes(cls, raw: bytes, path: Path | None = None) -> "Document":
        """Detects the encoding and newline style of raw file contents (Document.read without the disk)."""
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

    def encoded(self) -> bytes:
        """The text as file contents, in the document's encoding and newline style."""
        return self.text.replace("\n", self.newline).encode(self.encoding)

    def save(self, path: Path | None = None) -> None:
        target = (path or self.path)
        if target is None:
            raise ValueError("File belum diberi nama.")
        raw = self.encoded()
        atomic_write(target, raw)
        self.path = target.resolve()
        self.saved_text = self.text
        self.disk_hash = hashlib.sha256(raw).hexdigest()


# "syntax_colors" replaces the old "syntax" key, which was off by default, so saved settings start with colors on.
DEFAULTS = {
    "font_size": 17,
    "syntax_colors": True, "tab_width": 2, "range_checks": True,
    "overflow_checks": True,
    "unit_paths": [], "include_paths": [], "arguments": "",
    "recent": [], "geometry": "1120x740", "main_file": "",
    "graph_window": True,
}


class Settings:
    def __init__(self, path: Path | None = None):
        self.path = path or data_dir() / "settings.json"
        self.values = dict(DEFAULTS)
        self.values["recent"] = []
        try:
            saved = json.loads(self.path.read_text(encoding="utf-8"))
            for key, default in DEFAULTS.items():
                if key in saved and type(saved[key]) is type(default):
                    self.values[key] = saved[key]
        except (OSError, ValueError, TypeError):
            pass
        self.values["font_size"] = min(30, max(10, self.values["font_size"]))
        self.values["tab_width"] = min(8, max(1, self.values["tab_width"]))

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


@dataclass
class BuildResult:
    success: bool
    command: list[str]
    output: str
    diagnostics: list[Diagnostic]
    executable: Path | None
    source: Path
    # NAME.odbg next to the executable (line table; for debug
    # builds also everything the debugger needs).
    debug_info: Path | None = None
    debug: bool = False


PACKAGE_ROOT = Path(__file__).resolve().parent.parent


# Hosts whose native programs odinpc generates (IMPLEMENTATION_PLAN.md, Tahap 8).
# Elsewhere the IDE can edit but not compile.
ODIN_HOSTS = {("darwin", "x86_64"), ("darwin", "aarch64"), ("linux", "x86_64"), ("linux", "aarch64"),
              ("win32", "x86_64")}


def odin_supported() -> bool:
    """odinpc generates native programs for this machine (see ODIN_HOSTS)."""
    machine = {"amd64": "x86_64", "arm64": "aarch64"}.get(platform.machine().lower(), platform.machine().lower())
    return (sys.platform, machine) in ODIN_HOSTS


def locate_toolchain() -> str | None:
    """The odinpc binary (odinpc.exe on Windows): $ODIN_TOOLCHAIN, the app bundle or install
    folder, then a developer build in the repo."""
    name = executable_name("odinpc")
    candidates = [os.environ.get("ODIN_TOOLCHAIN", ""), PACKAGE_ROOT / "toolchain" / name,
                  PACKAGE_ROOT / "toolchain" / "target" / "release" / name,
                  PACKAGE_ROOT / "toolchain" / "target" / "debug" / name]
    for value in candidates:
        if value and Path(value).is_file() and os.access(value, os.X_OK):
            return str(Path(value).absolute())
    return None


def library_unit_paths() -> list[Path]:
    """Bundled unit libraries (OTP-AI) found by `uses` without any Options > Directories entry.
    They come after the user's unit paths, so a user's own unit with the same name wins."""
    path = PACKAGE_ROOT / "otp-AI" / "UNITS"
    return [path] if path.is_dir() else []


SEVERITY = {"fatal": "Fatal", "error": "Error", "warning": "Warning", "note": "Note", "hint": "Hint"}


def build(source: Path, settings: Settings, rebuild=False, cache: Path | None = None, debug=False, wrap=None) -> BuildResult:
    """Compiles source with odinpc. debug=True makes a build for the debugger (with debugger hooks).
    wrap(command) -> command starts odinpc through a wrapper such as a sandbox."""
    source = source.resolve()
    toolchain = locate_toolchain()
    if not toolchain:
        return BuildResult(False, [], f"Compiler Odin (odinpc) tidak ditemukan. Jalankan {installer_name()} kembali.", [], None, source)
    if not odin_supported():
        return BuildResult(False, [], f"odinpc belum bisa membuat program untuk {sys.platform} {platform.machine()}. "
                           "Yang didukung: macOS dan Linux (x86_64, arm64) serta Windows x86_64.", [], None, source)
    stat = Path(toolchain).stat()
    options = {k: settings[k] for k in ("unit_paths", "include_paths", "range_checks", "overflow_checks")}
    # Debug builds (with debugger hooks) live apart from Run builds.
    options["debug_build"] = debug
    key = hashlib.sha256((str(source) + json.dumps(options) + f"odin:{toolchain}:{stat.st_mtime_ns}:{stat.st_size}").encode()).hexdigest()[:16]
    output_dir = (cache or data_dir() / "build") / key
    output_dir.mkdir(parents=True, exist_ok=True)
    exe = output_dir / executable_name(source.stem)
    # A failed rebuild must never launch an older executable.
    exe.unlink(missing_ok=True)
    command = [toolchain, "build", str(source), "--out", str(exe), "--cache", str((cache or data_dir() / "build") / "units"),
               "--rtl", str(PACKAGE_ROOT / "rtl"), "--diag-format", "json",
               "--range-checks" if settings["range_checks"] else "--no-range-checks",
               "--overflow-checks" if settings["overflow_checks"] else "--no-overflow-checks"]
    if rebuild:
        command.append("--build-all")
    if debug:
        command.append("--debug")
    for key, flag in (("unit_paths", "--unit-path"), ("include_paths", "--include-path")):
        for p in settings[key]:
            if p:
                command += [flag, str(Path(p).expanduser().resolve())]
    for path in library_unit_paths():
        command += ["--unit-path", str(path)]
    try:
        # wrap (a sandbox, for example) changes how odinpc is started, not the command shown to the user.
        result = subprocess.run(wrap(command) if wrap else command, cwd=source.parent, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=120, **NO_WINDOW)
    except subprocess.TimeoutExpired:
        return BuildResult(False, command, "Kompilasi melewati batas 120 detik.", [], None, source)
    except OSError as error:
        return BuildResult(False, command, str(error), [], None, source)
    diagnostics, lines, summary, success, odbg = [], [], None, False, None
    for line in result.stdout.decode("utf-8", errors="replace").splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            lines.append(line)
            continue
        if item.get("type") == "diagnostic":
            kind = SEVERITY.get(item.get("severity"), "Error")
            diagnostics.append(Diagnostic(item["file"], int(item["line"]), int(item["column"]), kind, item["message"]))
            lines.append(f"{item['file']}({item['line']},{item['column']}) {kind} {item.get('code', '')}: {item['message']}")
        elif item.get("type") == "result":
            success = bool(item.get("success")) and result.returncode == 0
            summary = f"{item.get('lines', 0)} baris, {item.get('elapsed_ms', 0)} ms."
            odbg = Path(item["debug_info"]) if item.get("debug_info") else None
    stderr = result.stderr.decode("utf-8", errors="replace").strip()
    if stderr:
        lines.append(stderr if result.returncode != 2 else "Kesalahan internal compiler:\n" + stderr)
    if summary:
        lines.append(("Kompilasi berhasil: " if success else "Kompilasi gagal: ") + summary)
    executable = exe if success and exe.exists() else None
    return BuildResult(success, command, "\n".join(lines), diagnostics, executable, source,
                       odbg if executable and odbg and odbg.exists() else None, debug)


def runtime_error_location(debug_info: Path, report: str):
    """Maps the RTL's $ODIN_ERROR_FILE report ("code address header") to (code, source path, line).
    The line is None when the address is not in the program's code."""
    try:
        code, address, header = (int(v) for v in report.split()[:3])
        info = json.loads(Path(debug_info).read_text(encoding="utf-8"))
        link = address - header + int(info["image_base"])
        starts = [entry[0] for entry in info["addresses"]]
        i = bisect.bisect_right(starts, link) - 1
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if i < 0:
        return code, None, None
    _, file, line = info["addresses"][i]
    return code, Path(info["files"][file]), line


# Word lists for syntax_spans(), lower case because Pascal ignores case. RESERVED is TP7's reserved words and
# standard directives, the class words odinpc understands, and a few more Object Pascal words, so code from newer
# dialects still reads well.
RESERVED = set("""and array asm begin case const constructor destructor div do downto else end exports file for function
goto if implementation in inherited inline interface label library mod not object of or packed procedure program record
repeat set shl shr string then to type unit until uses var while with xor absolute assembler external far forward
interrupt near private public protected published strict virtual dynamic override abstract reintroduce overload
class is as try except finally raise out property threadvar""".split())
CONSTANTS = set("true false nil maxint maxlongint".split())
TYPES = set("""integer shortint smallint longint int64 byte word cardinal qword real single double extended comp char
boolean bytebool wordbool longbool shortstring text pointer""".split())
# Standard procedures and functions of the System and Crt units.
BUILTINS = set("""abs append arctan assign assigned blockread blockwrite break chdir chr close clreol clrscr concat
continue copy cos dec delay delete delline dispose eof eoln erase exclude exit exp filepos filesize fillchar frac freemem
getdir getmem gotoxy halt high highvideo inc include insert insline int ioresult keypressed length ln low lowvideo
maxavail memavail mkdir move new normvideo nosound odd ord paramcount paramstr pi pos pred random randomize read readkey
readln rename reset rewrite rmdir round runerror seek seekeof seekeoln sin sizeof sound sqr sqrt str succ textbackground
textcolor textmode trunc truncate upcase val wherex wherey window write writeln""".split())
TOKENS = re.compile("|".join((
    r"(?P<directive>\{\$[^}]*\}|\(\*\$[\s\S]*?\*\))",
    r"(?P<comment>\{[^}]*\}|\(\*[\s\S]*?\*\)|//[^\n]*)",
    r"(?P<string>'(?:[^'\n]|'')*'?|#(?:\$[0-9A-Fa-f]+|[0-9]+))",
    r"(?P<number>\$[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)",
    r"(?P<word>[A-Za-z_][A-Za-z0-9_]*)",
    r"(?P<operator>:=|<=|>=|<>|\.\.|[-+*/=<>()\[\];:,.^@])")))


def syntax_spans(text: str):
    """Yields (kind, start, end) for each token the editor colors. kind is one of directive, comment, string (also
    #13 character constants), number, operator, reserved, constant, type, routine, builtin, identifier. A name
    declared after procedure or function is a routine wherever it appears; an unterminated string ends the line."""
    tokens = [(match.lastgroup, match.start(), match.end()) for match in TOKENS.finditer(text)]
    routines, declaring = set(), False
    for kind, start, end in tokens:
        if kind == "word":
            word = text[start:end].lower()
            if declaring:
                routines.add(word)
            declaring = word in ("procedure", "function")
        elif kind not in ("comment", "directive"):
            declaring = False
    for kind, start, end in tokens:
        if kind == "word":
            word = text[start:end].lower()
            kind = ("reserved" if word in RESERVED else "constant" if word in CONSTANTS else "type" if word in TYPES
                    else "routine" if word in routines else "builtin" if word in BUILTINS else "identifier")
        yield kind, start, end
