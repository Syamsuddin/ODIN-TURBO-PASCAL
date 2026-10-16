#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Build the tutorial book docs/Belajar_Pemrograman_Bahasa_Pascal.pdf (Help > Buku) from book/.

    python3 scripts/build_book.py                                  # the whole book
    python3 scripts/build_book.py --chapters 6,7 --out /tmp/b.pdf  # quick preview of some chapters

Needs Google Chrome (or Chromium; $CHROME overrides) to print HTML to PDF, and PyMuPDF (import fitz)
for the page numbers, running heads, bookmarks and page labels. Program runs need a pseudo-terminal,
so run the script where PTYs are available (not inside the Claude Code sandbox).

Sources in book/: depan.html (front matter), babNN.html (chapters 1-20), penutup.html, lampiran.html
and buku.css. Listings are read from examples/ unchanged. Their output comes from compiling them with
odinpc and running them on an 80x25 PTY while the input is typed a line at a time, as a reader types
it in the User screen. Runs are cached in book/.cache, keyed by source, input and odinpc. The runs of
one chapter share a working folder in document order, so Bab 17 reads the file Bab 17.1 wrote.

Tags the chapter sources use (expanded here; attributes in [] are optional):
  <x-listing src="F.pas" [lines="A-B"]></x-listing>
      Program listing, numbered "Program N.M" after the file name babNN_MM_*.pas.
  <x-run src="F.pas" [input="a\\nb\\n"] [keys="Down Enter Esc"] [shot="N"] [caption=".."]></x-run>
      The run in the User screen; typed input is highlighted. Without input/keys it types BOOK_INPUTS or
      the input of EXAMPLE_RUNS in tests/test_core.py. Crt programs show screen N (1 = before the first key).
  <x-ide [file="F.pas"|name="X.PAS"] [path=".."] [top="1"] [rows="16"] [cursor="L:C"] [menu="Run"] [pick=".."]
         [dialog="examples|messages"] [breakpoints="9,12"] [exec="9"] [error="6"] [watches="I: 3;N: 4"] [locals=".."] [stack=".."]
         [desktop] [dirty] [status=".."] [marks="menu,title,editor,gutter,keys,status"] caption="..">[code]</x-ide>
      An IDE "screenshot" drawn from the real menus (odin/app.py), palette (odin/windows.py) and code.
  <x-code>Pascal fragment, not HTML-escaped</x-code>
  <x-error [name="salah.pas"] [run] [input=".."] caption="..">whole program</x-error>
      The program with odinpc's real diagnostic, or with run, its run (runtime errors).
  <x-diag [name="salah.pas"]>whole program</x-diag>
      Just odinpc's first diagnostic for that program, as inline code (tables of messages).
  <x-ref to="ID"></x-ref>
      "Gambar N.M" or "Tabel N.M" of the figure or table with that id.
Every <figcaption> and <caption> is numbered per chapter. Every example of a chapter must be listed.
"""
from __future__ import annotations

import argparse
import ast
import codecs
import fcntl
import hashlib
import html
import json
import os
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from odin import __author__, __copyright__, __version__, __version_tag__  # noqa: E402
from odin.core import Settings, build, locate_toolchain, syntax_spans  # noqa: E402

try:
    from odin.terminal import PALETTE, Screen
except ImportError:
    # Screen is plain Python; only TerminalView needs Tk, which a Python without _tkinter lacks.
    stub = types.ModuleType("tkinter")
    stub.Text, stub.TclError = object, Exception
    sys.modules["tkinter"] = stub
    from odin.terminal import PALETTE, Screen

BOOK = ROOT / "book"
EXAMPLES = ROOT / "examples"
OUTPUT = ROOT / "docs" / "Belajar_Pemrograman_Bahasa_Pascal.pdf"
CACHE = BOOK / ".cache"

TITLE = "Belajar Pemrograman Bahasa Pascal"
SUBTITLE = "dengan ODIN Turbo Pascal"
EMAIL = "syamsuddin.ideris@gmail.com"
YEAR = 2026

# (numeral, title, description, first and last chapter, color)
PARTS = [
    ("I", "Fondasi", "Mengenal Pascal dan Odin Turbo Pascal, struktur program, tipe data, masukan dan keluaran, serta operator.", (1, 5), "#1d4ed8"),
    ("II", "Alur Kendali", "Membuat program yang mengambil keputusan dan mengulang perintah, lalu memakainya untuk algoritma klasik.", (6, 8), "#0f8f84"),
    ("III", "Prosedur, Fungsi, dan Rekursi", "Memecah program menjadi bagian kecil yang bisa dipakai ulang, termasuk bagian yang memanggil dirinya sendiri.", (9, 10), "#e2680b"),
    ("IV", "Struktur Data", "Menyimpan dan mengolah banyak data dengan array, string, record, enumerasi, subrange, dan set.", (11, 14), "#7c3aed"),
    ("V", "Pencarian dan Pengurutan", "Algoritma klasik untuk menemukan dan menyusun data, lengkap dengan perbandingan efisiensinya.", (15, 16), "#d0266e"),
    ("VI", "File, Pointer, Unit, dan Proyek Akhir", "Menyimpan data ke disk, memakai memori dinamis, membuat unit sendiri, dan merangkai semuanya dalam proyek.", (17, 20), "#3f3cbb"),
]
CHAPTERS = {
    1: "Mengenal Pascal dan Odin Turbo Pascal", 2: "Struktur Program Pascal", 3: "Tipe Data, Variabel, dan Konstanta",
    4: "Masukan dan Keluaran", 5: "Operator dan Ekspresi", 6: "Percabangan", 7: "Perulangan",
    8: "Berlatih Algoritma dengan Perulangan", 9: "Prosedur dan Fungsi", 10: "Rekursi", 11: "Array",
    12: "Mengolah String", 13: "Record", 14: "Enumerasi, Subrange, dan Set", 15: "Pencarian Data",
    16: "Pengurutan Data", 17: "Bekerja dengan File", 18: "Pointer dan Linked List", 19: "Unit dan Layar Crt",
    20: "Proyek Akhir",
}
# Input the book types where the tests' EXAMPLE_RUNS input is not the best demonstration. A callable
# answers the program's output so far (the guessing game is played with a binary search).
BOOK_INPUTS = {
    "bab08_06_tebak_angka": "tebak",
    "bab19_02_unit_crt": {"keys": "x"},
}
# Where the IDE lives on a reader's Mac once Install.command has copied it (shown in status bars).
APP_EXAMPLES = "~/Applications/Odin Turbo Pascal.app/Contents/Resources/examples"
QUIET = 0.35          # seconds without output before a sleeping program counts as waiting for input
KEY_BYTES = {"Enter": b"\r", "Esc": b"\x1b", "Up": b"\x1b[A", "Down": b"\x1b[B", "Right": b"\x1b[C",
             "Left": b"\x1b[D", "Space": b" ", "Tab": b"\t", "Backspace": b"\x7f", "Home": b"\x1b[H",
             "End": b"\x1b[F", "F1": b"\x1bOP", "F2": b"\x1bOQ", "F10": b"\x1b[21~"}
KEY_LABELS = {"Enter": "↵ Enter", "Esc": "Esc", "Up": "↑", "Down": "↓", "Right": "→", "Left": "←", "Space": "Spasi"}

esc = html.escape


# ---------------------------------------------------------------- facts read from the IDE sources

def module_constants(path: Path) -> dict:
    """Top-level NAME = literal assignments of a module; names inside tuples are resolved in order."""
    values = {}
    for node in ast.parse(path.read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            try:
                values[node.targets[0].id] = ast.literal_eval(node.value)
            except ValueError:
                if isinstance(node.value, ast.Tuple) and all(isinstance(e, ast.Name) for e in node.value.elts):
                    values[node.targets[0].id] = tuple(values.get(e.id) for e in node.value.elts)
    return values


WINDOWS = module_constants(ROOT / "odin" / "windows.py")
BLUE, CYAN, GRAY, WHITE, BLACK = (WINDOWS[k] for k in ("BLUE", "CYAN", "GRAY", "WHITE", "BLACK"))
# The editor palette shown with Syntax colors on (the IDE default): the one tuple besides CLASSIC.
EDITOR = next(v for k, v in WINDOWS.items() if isinstance(v, tuple) and len(v) == 5 and k != "CLASSIC")
SYNTAX_COLORS = WINDOWS["SYNTAX_COLORS"]
SYNTAX_FONTS = WINDOWS.get("SYNTAX_FONTS", {})


def ide_menus():
    """[(menu, [(label, shortcut) or None for a separator])] in menu bar order, from App.create_menus,
    and the function key bar labels."""
    tree = ast.parse((ROOT / "odin" / "app.py").read_text(encoding="utf-8"))
    menus, keys = [], []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "menu"
                and len(node.args) >= 2 and isinstance(node.args[0], ast.Constant) and isinstance(node.args[1], ast.List)):
            items = []
            for element in node.args[1].elts:
                label, shortcut = element.elts[0].value, element.elts[2].value
                items.append(None if label == "-" else (label, shortcut))
            menus.append((node.lineno, node.args[0].value, items))
        if isinstance(node, ast.For) and isinstance(node.iter, ast.Tuple) and node.iter.elts:
            first = node.iter.elts[0]
            if isinstance(first, ast.Tuple) and isinstance(first.elts[0], ast.Constant) and first.elts[0].value == "F1 Help":
                keys = [e.elts[0].value for e in node.iter.elts]
    return [(name, items) for _, name, items in sorted(menus)], keys


MENUS, FUNCTION_KEYS = ide_menus()


def example_runs():
    """stem -> input of EXAMPLE_RUNS in tests/test_core.py (entries that are not plain literals are skipped)."""
    runs = {}
    for node in ast.parse((ROOT / "tests" / "test_core.py").read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "EXAMPLE_RUNS":
            for key, value in zip(node.value.keys, node.value.values):
                try:
                    runs[key.value] = ast.literal_eval(value.elts[0])
                except ValueError:
                    pass
    return runs


EXAMPLE_RUNS = example_runs()


def example_files():
    return sorted(p for p in EXAMPLES.iterdir() if p.suffix.lower() == ".pas")


def program_number(path: Path) -> str:
    m = re.match(r"bab(\d\d)_(\d\d)_", path.name)
    return f"{int(m.group(1))}.{int(m.group(2))}" if m else ""


def chapter_of(path: Path) -> int:
    m = re.match(r"bab(\d\d)_", path.name)
    return int(m.group(1)) if m else 19          # matematika.pas belongs to Bab 19


def program_title(path: Path) -> str:
    """The title in the header comment: '{ Bab 6.4 - case..of' gives 'case..of'."""
    m = re.search(r"\{ Bab [\d.]+ - ([^\n}]*)", path.read_text(encoding="utf-8"))
    return m.group(1).strip() if m else path.stem


# ---------------------------------------------------------------- colors

def mix(color: str, other: str, amount: float) -> str:
    a = [int(color[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(other[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * amount):02x}" for x, y in zip(a, b))


def part_of(chapter: int):
    return next(p for p in PARTS if p[3][0] <= chapter <= p[3][1])


def color_vars(color: str) -> str:
    return (f"--c:{color};--c-dark:{mix(color, '#000000', .3)};--c-soft:{mix(color, '#ffffff', .9)};"
            f"--c-mid:{mix(color, '#ffffff', .55)};--c-line:{mix(color, '#ffffff', .75)}")


def palette_css() -> str:
    """The editor's syntax colors as CSS, so listings look like the IDE with Syntax colors on."""
    bg, fg, cursor, select_bg, _ = EDITOR
    rules = [f":root{{--ed-bg:{bg};--ed-fg:{fg};--ed-cursor:{cursor};--ed-sel:{select_bg};"
             f"--ide-blue:{BLUE};--ide-cyan:{CYAN};--ide-gray:{GRAY};--ide-yellow:{WHITE};"
             f"--ed-gutter:{mix(bg, '#000000', .25)};--ed-ln:{mix(fg, bg, .55)}}}"]
    for kind, color in SYNTAX_COLORS.items():
        style = SYNTAX_FONTS.get(kind, "")
        extra = ";font-weight:700" if style == "bold" else ";font-style:italic" if style == "italic" else ""
        rules.append(f".t-{kind}{{color:{color}{extra}}}")
    return "\n".join(rules)


# ---------------------------------------------------------------- Pascal highlighting

def highlight(text: str) -> list[str]:
    """HTML for each line of Pascal source, with the token kinds odin.core.syntax_spans gives the editor."""
    pieces, pos = [], 0
    for kind, start, end in syntax_spans(text):
        if start > pos:
            pieces.append((None, text[pos:start]))
        pieces.append((kind, text[start:end]))
        pos = end
    pieces.append((None, text[pos:]))
    lines, current = [], []
    for kind, chunk in pieces:
        for i, part in enumerate(chunk.split("\n")):
            if i:
                lines.append("".join(current))
                current = []
            if part:
                current.append(f'<span class="t-{kind}">{esc(part)}</span>' if kind else esc(part))
    lines.append("".join(current))
    return lines


def code_block(text: str, numbers=True, first=1, marks=None, css="code") -> str:
    """Navy editor-style block; marks maps a line number to an extra row class (error, exec)."""
    marks = marks or {}
    rows = []
    for n, line in enumerate(highlight(text.rstrip("\n")), start=1):
        if n < first:
            continue
        cls = "row " + marks.get(n, "")
        number = f'<span class="ln">{n}</span>' if numbers else ""
        rows.append(f'<div class="{cls.strip()}">{number}<span class="src">{line or " "}</span></div>')
    return f'<div class="{css}">{"".join(rows)}</div>'


# ---------------------------------------------------------------- running programs on a PTY

def sleeping(pid: int) -> bool:
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return state[:1] in ("S", "I")


def snapshot(screen) -> list:
    """The screen as rows of [text, fg, bg] runs."""
    rows = []
    for row in screen.grid:
        runs = []
        for ch, fg, bg in row:
            if runs and runs[-1][1] == fg and runs[-1][2] == bg:
                runs[-1][0] += ch
            else:
                runs.append([ch, fg, bg])
        rows.append(runs)
    return rows


def capture(argv, cwd, feeder, limit=40):
    """Runs argv on an 80x25 PTY with echo off. When the program sleeps without output it is waiting for
    input: feeder(output so far) gives (bytes, shown) to type, or None. Returns segments [["out"|"in", text]],
    screens (one before each input and one at the end) and the exit code."""
    master, slave = os.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 25, 80, 0, 0))
    attrs = termios.tcgetattr(slave)
    attrs[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    env = dict(os.environ, TERM="xterm", COLUMNS="80", LINES="25")
    proc = subprocess.Popen(argv, cwd=cwd, stdin=slave, stdout=slave, stderr=slave, start_new_session=True, env=env)
    os.close(slave)
    screen, decoder = Screen(), codecs.getincrementaldecoder("utf-8")("replace")
    segments, screens, output = [], [], []

    def add(kind, text):
        if segments and segments[-1][0] == kind:
            segments[-1][1] += text
        else:
            segments.append([kind, text])

    start = last = time.monotonic()
    try:
        while True:
            ready, _, _ = select.select([master], [], [], 0.03)
            data = b""
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    data = b""
            if data:
                text = decoder.decode(data)
                add("out", text)
                output.append(text)
                screen.feed(text)
                while screen.replies:
                    os.write(master, screen.replies.pop(0))
                last = time.monotonic()
                continue
            if proc.poll() is not None:
                break
            now = time.monotonic()
            if now - start > limit:
                raise RuntimeError(f"{argv[0]}: lebih dari {limit} detik")
            if now - last > QUIET and sleeping(proc.pid):
                item = feeder("".join(output))
                if item is None:
                    if now - last > 2:
                        raise RuntimeError(f"{Path(argv[0]).name} masih menunggu masukan, tetapi masukannya sudah habis")
                    continue
                screens.append(snapshot(screen))
                typed, shown = item
                add("in", shown)
                os.write(master, typed)
                last = time.monotonic()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        os.close(master)
    screens.append(snapshot(screen))
    return segments, screens, proc.returncode


def line_feeder(text: str):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    pending = [((line + "\n").encode(), line) for line in lines]
    return lambda output: pending.pop(0) if pending else None


def key_feeder(keys: str):
    pending = [(KEY_BYTES.get(k, k.encode()), KEY_LABELS.get(k, k)) for k in keys.split()]
    return lambda output: pending.pop(0) if pending else None


def guessing_feeder():
    """Plays bab08_06 with a binary search, reading the hints the program prints."""
    state = {"low": 1, "high": 100, "guess": None}

    def feed(output):
        if state["guess"] is not None:
            hint = output.rstrip().rsplit("\n", 1)[-1]
            if "kecil" in hint:
                state["low"] = state["guess"] + 1
            elif "besar" in hint:
                state["high"] = state["guess"] - 1
        state["guess"] = (state["low"] + state["high"]) // 2
        return f"{state['guess']}\n".encode(), str(state["guess"])
    return feed


def run_input(stem: str, attrs: dict):
    """(kind, value): what to type for an x-run."""
    if "keys" in attrs:
        return "keys", attrs["keys"]
    if "input" in attrs:
        return "lines", attrs["input"].replace("\\n", "\n")
    preset = BOOK_INPUTS.get(stem)
    if preset == "tebak":
        return "tebak", ""
    if isinstance(preset, dict):
        return "keys", preset["keys"]
    return "lines", EXAMPLE_RUNS.get(stem, "")


def feeder_for(kind, value):
    return {"keys": key_feeder, "lines": line_feeder, "tebak": lambda _: guessing_feeder()}[kind](value)


def toolchain_stamp() -> str:
    toolchain = locate_toolchain()
    if not toolchain:
        raise SystemExit("odinpc tidak ditemukan; bangun dulu toolchain (cargo build --release di toolchain/).")
    stat = Path(toolchain).stat()
    return f"{toolchain}:{stat.st_mtime_ns}:{stat.st_size}"


def compile_source(path: Path, chapter: int):
    # One build cache per chapter: odinpc compiles the RTL units into it, and chapters may build at once.
    return build(path, Settings(CACHE / "settings.json"), cache=CACHE / "bin" / f"bab{chapter:02}")


def capture_chapter(chapter: int, requests: list) -> list:
    """Runs of one chapter, in document order, sharing one working folder; cached as a whole."""
    if not requests:
        return []
    key_data = [toolchain_stamp()] + [[(EXAMPLES / src).read_text(encoding="utf-8"), kind, value]
                                      for src, kind, value in requests]
    key = hashlib.sha256(json.dumps(key_data).encode()).hexdigest()[:20]
    cached = CACHE / "runs" / f"bab{chapter:02}-{key}.json"
    if cached.exists():
        return json.loads(cached.read_text(encoding="utf-8"))
    work = CACHE / "kerja" / f"bab{chapter:02}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    results = []
    for src, kind, value in requests:
        result = compile_source(EXAMPLES / src, chapter)
        if not result.success or not result.executable:
            raise SystemExit(f"{src} gagal dikompilasi:\n{result.output}")
        print(f"  jalankan {src}", flush=True)
        try:
            segments, screens, code = capture([str(result.executable)], work, feeder_for(kind, value))
        except OSError as error:
            raise SystemExit(f"{src}: {error} (PTY perlu tersedia; jalankan di luar sandbox)")
        results.append({"src": src, "segments": segments, "screens": screens, "code": code})
    cached.parent.mkdir(parents=True, exist_ok=True)
    for old in cached.parent.glob(f"bab{chapter:02}-*.json"):
        old.unlink()
    cached.write_text(json.dumps(results), encoding="utf-8")
    return results


def compile_snippet(code: str, name: str, run: bool, typed: str):
    """odinpc's verdict on a program written in the book; with run, also its run."""
    key = hashlib.sha256(json.dumps([toolchain_stamp(), code, name, run, typed]).encode()).hexdigest()[:20]
    cached = CACHE / "salah" / f"{key}.json"
    if cached.exists():
        return json.loads(cached.read_text(encoding="utf-8"))
    folder = CACHE / "salah" / key
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    source = folder / name
    source.write_text(code, encoding="utf-8")
    result = build(source, Settings(CACHE / "settings.json"), cache=folder / "bin")
    data = {"success": result.success,
            "diagnostics": [[Path(d.file).name, d.line, d.column, d.kind, d.message] for d in result.diagnostics],
            "output": result.output.replace(str(folder) + os.sep, "")}
    if run:
        if not result.executable:
            raise SystemExit(f"{name} di buku seharusnya terkompilasi:\n{result.output}")
        segments, screens, exit_code = capture([str(result.executable)], folder, line_feeder(typed))
        data.update(segments=segments, screens=screens, code=exit_code)
    cached.write_text(json.dumps(data), encoding="utf-8")
    return data


# ---------------------------------------------------------------- figures drawn from the IDE

def attributes(text: str) -> dict:
    found = {k: html.unescape(v) for k, v in re.findall(r'([\w-]+)="([^"]*)"', text)}
    for flag in re.findall(r'(?:^|\s)([\w-]+)(?=\s|$)', re.sub(r'[\w-]+="[^"]*"', " ", text)):
        found[flag] = ""
    return found


def mac_bar(title: str) -> str:
    return f'<div class="mac"><i></i><i></i><i></i><span>{esc(title)}</span></div>'


SHOWN_FOLDER = "/Users/rina/Pascal"      # what a reader's folder looks like; the real build folder is never shown


def anonymize(text: str) -> str:
    """Programs that print their working folder (Bab 17, 20) would show the build machine's path."""
    for folder in (CACHE / "kerja", CACHE / "salah", ROOT, Path.home()):
        text = re.sub(re.escape(str(folder)) + r"(/[^\s\"']*)?", lambda m: SHOWN_FOLDER, text)
    return text


def transcript_html(segments, code) -> str:
    out = []
    for kind, text in segments:
        text = anonymize(text.replace("\r\n", "\n").replace("\r", ""))
        out.append(f'<span class="ketik">{esc(text)}</span>\n' if kind == "in" else esc(text))
    body = "".join(out)
    body += f"\n\n[Process finished, exit code {code}]"
    return body


def screen_html(rows) -> str:
    lines = []
    for runs in rows:
        parts = []
        for text, fg, bg in runs:
            parts.append(f'<span style="color:{PALETTE[fg]};background:{PALETTE[bg]}">{esc(text)}</span>')
        lines.append("".join(parts))
    return "\n".join(lines)


def user_screen(body_html: str, crt=False) -> str:
    buttons = "".join(f'<span class="btn">{b}</span>' for b in ("Copy screen", "Editor", "Stop"))
    return (f'<div class="win userscreen{" crt" if crt else ""}">{mac_bar("Odin • User screen")}'
            f'<div class="us-bar"><span class="us-title">User screen 80×25</span>{buttons}</div>'
            f'<pre class="us-body">{body_html}</pre></div>')


def menu_bar(open_menu=None, mark="") -> str:
    items = []
    for name, _ in MENUS:
        cls = ' class="open"' if name == open_menu else ""
        items.append(f'<span{cls}> <u>{esc(name[0])}</u>{esc(name[1:])} </span>')
    return f'<div class="ide-menubar">{"".join(items)}<span class="dot">◉</span>{mark}</div>'


def dropdown(name: str, pick: str) -> str:
    offset = 0
    for menu_name, items in MENUS:
        if menu_name == name:
            break
        offset += len(menu_name) + 2
    entries = []
    for item in dict(MENUS)[name]:
        if item is None:
            entries.append('<div class="sep"></div>')
        else:
            label, shortcut = item
            cls = ' class="pick"' if label == pick else ""
            entries.append(f'<div{cls}><span>{esc(label)}</span><span>{esc(shortcut)}</span></div>')
    return f'<div class="ide-dropdown" style="left:{offset + .4}ch">{"".join(entries)}</div>'


def plaque() -> str:
    return (f'<div class="plaque"><div class="pl-tag"><b>NATIVE PASCAL IDE</b><b class="ver">{esc(__version_tag__)}</b></div>'
            f'<div class="pl-author">Created by {esc(__author__)}</div><div class="pl-small">{esc(__copyright__)}</div>'
            f'<div class="pl-small">GNU GPL v3 or later</div></div>')


def editor_window(title, text, top, rows, cursor, marks, breakpoints, active=True, number_marks="") -> str:
    lines = highlight(text.rstrip("\n"))
    total = len(lines)
    shown = []
    for n in range(top, top + rows):
        line = lines[n - 1] if n <= total else ""
        cls = marks.get(n, "")
        if cursor and cursor[0] == n:
            raw = text.split("\n")[n - 1] if n <= total else ""
            col = cursor[1]
            # The insert cursor: a bar before column col (1-based).
            line = highlight_with_cursor(raw, col)
        dot = '<i class="bp"></i>' if n in breakpoints else ""
        shown.append(f'<div class="ed-row {cls}"><span class="gut">{dot}</span><span class="src">{line or " "}</span></div>')
    thumb_top = 0 if total <= rows else (top - 1) / total * 100
    thumb_len = 100 if total <= rows else rows / total * 100
    return (f'<div class="ide-win{" active" if active else ""}"><div class="ide-wt"><span>[■]</span>'
            f'<span class="t">{esc(title)}</span><span>[↕]</span>{number_marks}</div>'
            f'<div class="ide-wb"><div class="ed">{"".join(shown)}</div>'
            f'<div class="vs"><i style="top:{thumb_top:.1f}%;height:{max(thumb_len, 8):.1f}%"></i></div></div>'
            f'<div class="hs"></div></div>')


def highlight_with_cursor(raw: str, col: int) -> str:
    """One highlighted line with the editor's insert cursor before column col."""
    raw = raw.ljust(col - 1)
    lines = highlight(raw[:col - 1] + "\x00" + raw[col - 1:])
    return lines[0].replace("\x00", '<b class="cur"></b>')


def list_window(title, rows, style="") -> str:
    body = "".join(f"<div>{esc(r)}</div>" for r in rows)
    return (f'<div class="ide-win list" style="{style}"><div class="ide-wt"><span>[■]</span><span class="t">{esc(title)}</span>'
            f'<span>[↕]</span></div><div class="ide-list">{body}</div></div>')


def dialog_examples(pick: str) -> str:
    names = [p.name for p in example_files()]
    index = names.index(pick) if pick in names else 0
    first = max(0, min(index - 6, len(names) - 13))
    rows = "".join(f'<div{" class=pick" if n == pick else ""}>{esc(n)}</div>' for n in names[first:first + 13])
    return (f'<div class="dlg-wrap"><div class="win dlg">{mac_bar("Examples")}<div class="dlg-body">'
            f'<div class="dlg-title"> Examples </div><div class="dlg-list">{rows}<i class="sb"></i></div>'
            f'<div class="dlg-buttons"><span class="btn">Open</span></div></div></div></div>')


def dialog_messages(name: str, verdict: dict) -> str:
    title = "Compile successful" if verdict["success"] else "Compile failed"
    output = verdict["output"]
    text = f"$ odinpc build {name} …\n\n{output}"
    diags = "".join(f'<div{" class=pick" if i == 0 else ""}>{esc(f"{k}  {f}:{l}:{c}  {m}")}</div>'
                    for i, (f, l, c, k, m) in enumerate(verdict["diagnostics"]))
    buttons = ('<span class="btn">Go to error</span>' if diags else "") + '<span class="btn right">OK</span>'
    return (f'<div class="dlg-wrap"><div class="win dlg wide">{mac_bar(title)}<div class="dlg-body">'
            f'<div class="dlg-title"> {esc(title)} </div><pre class="dlg-text">{esc(text)}</pre>'
            f'{f"<div class=dlg-diags>{diags}</div>" if diags else ""}<div class="dlg-buttons">{buttons}</div></div></div></div>')


MARK_REGIONS = ("menu", "title", "editor", "gutter", "scroll", "keys", "status", "dropdown", "dialog", "logo", "plaque", "watches")


def ide_figure(attrs: dict, inner: str) -> str:
    marks = [m.strip() for m in attrs.get("marks", "").split(",") if m.strip()]
    number = {region: i + 1 for i, region in enumerate(marks)}
    unknown = set(marks) - set(MARK_REGIONS)
    if unknown:
        raise SystemExit(f"x-ide marks tidak dikenal: {', '.join(sorted(unknown))}")

    def mark(region, style=""):
        return f'<b class="mark" style="{style}">{number[region]}</b>' if region in number else ""

    rows = int(attrs.get("rows", 16))
    desk = []
    status = attrs.get("status")
    if "desktop" in attrs:
        desk.append(f'<div class="desk-center"><div class="logo-wrap">{mark("logo", "right:-1.2em;top:1em")}'
                    f'<img src="{(ROOT / "assets" / "odin-logo.png").as_uri()}" alt=""></div>'
                    f'<div class="plaque-wrap">{plaque()}{mark("plaque", "right:-1.2em;top:.4em")}</div></div>')
        if status is None:
            status = f"Odin Turbo Pascal {__version_tag__}   |   Created by {__author__}   |   F1 Help"
    else:
        if "file" in attrs:
            path = EXAMPLES / attrs["file"]
            text = path.read_text(encoding="utf-8")
            full = attrs.get("path", f"{APP_EXAMPLES}/{path.name}")
            title = path.name.upper()
        else:
            text = html.unescape(inner.strip("\n")) + "\n"
            name = attrs.get("name", "NONAME01.PAS")
            full = attrs.get("path", f"~/Pascal/{name.lower()}" if "name" in attrs else "NONAME.PAS")
            title = name.upper()
        if "dirty" in attrs:
            title += " *"
        cursor = tuple(int(v) for v in attrs["cursor"].split(":")) if "cursor" in attrs else None
        top = int(attrs.get("top", 1))
        line_marks = {}
        for key, cls in (("error", "error"), ("exec", "exec")):
            if key in attrs:
                for n in attrs[key].split(","):
                    line_marks[int(n)] = cls
        breakpoints = {int(n) for n in attrs.get("breakpoints", "").split(",") if n.strip()}
        title_marks = mark("title", "left:30%;top:-.2em") + mark("editor", "left:55%;top:5.5em") + \
            mark("gutter", "left:-.5em;top:3.2em") + mark("scroll", "right:-.3em;top:7em")
        desk.append(editor_window(title, text, top, rows, cursor, line_marks, breakpoints, number_marks=title_marks))
        # Debugger windows; rows are separated by ";" (Watches rows read "expression: value").
        for key, label in (("watches", "Watches"), ("locals", "Local variables"), ("stack", "Call stack")):
            if key in attrs:
                desk.append(list_window(label, attrs[key].split(";"), "") + (mark("watches", "left:40%;bottom:3.4em") if key == "watches" else ""))
        if status is None:
            line, col = cursor or (1, 1)
            status = f"{'Insert'}  {line:5}:{col:<4}  {full}  [TP]"
    if "menu" in attrs:
        desk.append(dropdown(attrs["menu"], attrs.get("pick", "")) + mark("dropdown", f"left:{dropdown_left(attrs['menu']) + 20}ch;top:1.5em"))
    dialog = attrs.get("dialog")
    if dialog and desk:
        # The editor stays visible behind the dialog, which sets the height of the desktop.
        desk[0] = desk[0].replace('<div class="ide-win active">', '<div class="ide-win active behind">', 1)
    if dialog == "examples":
        desk.append(dialog_examples(attrs.get("pick", "bab01_01_halo_dunia.pas")) + mark("dialog", "right:22%;top:3em"))
    elif dialog == "messages":
        if "file" in attrs:
            verdict = compile_snippet((EXAMPLES / attrs["file"]).read_text(encoding="utf-8"), attrs["file"], False, "")
            name = attrs["file"]
        else:
            name = attrs.get("name", "NONAME01.PAS").lower()
            verdict = compile_snippet(html.unescape(inner.strip("\n")) + "\n", name, False, "")
        desk.append(dialog_messages(name, verdict) + mark("dialog", "right:12%;top:2.4em"))
    keys = "".join(f"<span>{esc(k)}</span>" for k in FUNCTION_KEYS)
    return (f'<div class="win ide" style="--rows:{rows}">{mac_bar("Odin Turbo Pascal")}'
            f'{menu_bar(attrs.get("menu"), mark("menu", "left:12ch;top:.1em"))}'
            f'<div class="ide-desk{" bare" if "desktop" in attrs else ""}">{"".join(desk)}</div>'
            f'<div class="ide-keys">{keys}{mark("keys", "left:58ch;top:.1em")}</div>'
            f'<div class="ide-status">{esc(" " + status)}{mark("status", "right:2ch;top:.1em")}</div></div>')


def dropdown_left(name: str) -> int:
    offset = 0
    for menu_name, _ in MENUS:
        if menu_name == name:
            return offset
        offset += len(menu_name) + 2
    return 0


# ---------------------------------------------------------------- chapter sources

# Attribute values may hold markup such as <code>, so a quoted value may contain ">".
TAG = re.compile(r'<x-(listing|run|ide|code|error|diag|wordlist|ref)\b((?:[^>"]|"[^"]*")*)>(.*?)</x-\1>', re.S)


class Section:
    """One source file of the book after expansion: chapter, front matter or back matter."""

    def __init__(self, kind, key, title, body, prefix=None, color=None, objectives="", part=None):
        self.kind, self.key, self.title, self.body = kind, key, title, body
        self.prefix, self.color, self.objectives, self.part = prefix, color, objectives, part
        self.headings = []          # (level, id, number, text)


def run_requests(text: str) -> list:
    requests = []
    for name, attr_text, _ in TAG.findall(text):
        if name == "run":
            attrs = attributes(attr_text)
            stem = Path(attrs["src"]).stem
            kind, value = run_input(stem, attrs)
            requests.append((attrs["src"], kind, value))
    return requests


class Expander:
    def __init__(self, prefix, runs, chapter=None):
        self.prefix, self.runs, self.chapter = prefix, list(runs), chapter
        self.listed = set()

    def caption(self, text):
        return f"<figcaption>{text}</figcaption>"

    def __call__(self, match):
        name, attr_text, inner = match.groups()
        attrs = attributes(attr_text)
        ident = f' id="{attrs["id"]}"' if "id" in attrs else ""
        if name == "listing":
            return self.listing(attrs)
        if name == "run":
            run = self.runs.pop(0)
            if run["src"] != attrs["src"]:
                raise SystemExit(f"Urutan x-run kacau: {run['src']} != {attrs['src']}")
            caption = attrs.get("caption") or f"Keluaran <code>{esc(attrs['src'])}</code> di User screen"
            if any("\x1b" in text for kind, text in run["segments"] if kind == "out"):
                shot = int(attrs.get("shot", 1)) - 1
                body = screen_html(run["screens"][shot])
                return f'<figure class="shot"{ident}>{user_screen(body, crt=True)}{self.caption(caption)}</figure>'
            return f'<figure class="shot"{ident}>{user_screen(transcript_html(run["segments"], run["code"]))}{self.caption(caption)}</figure>'
        if name == "ide":
            return f'<figure class="shot"{ident}>{ide_figure(attrs, inner)}{self.caption(attrs.get("caption", ""))}</figure>'
        if name == "code":
            return code_block(html.unescape(inner.strip("\n")), numbers=False, css="code snippet")
        if name == "error":
            return self.error(attrs, html.unescape(inner.strip("\n")) + "\n", ident)
        if name == "wordlist":
            import odin.core as core
            words = sorted(getattr(core, {"reserved": "RESERVED", "type": "TYPES", "constant": "CONSTANTS",
                                          "builtin": "BUILTINS"}[attrs["kind"]]))
            cells = "".join(f"<span>{esc(w)}</span>" for w in words)
            return f'<div class="wordlist t-{attrs["kind"]}">{cells}</div>'
        if name == "diag":
            # Only the message, for tables of compiler errors.
            code = html.unescape(inner.strip("\n")) + "\n"
            verdict = compile_snippet(code, attrs.get("name", "salah.pas"), False, "")
            if verdict["success"]:
                raise SystemExit(f"x-diag {attrs.get('name')}: program ini ternyata terkompilasi tanpa galat")
            f, l, c, k, m = verdict["diagnostics"][0]
            return f'<code class="diag-msg">{esc(f)}({l},{c}) {esc(k)}: {esc(m)}</code>'
        if name == "ref":
            return f'<a class="ref" href="#{attrs["to"]}" data-ref="{attrs["to"]}">??</a>'
        raise AssertionError(name)

    def listing(self, attrs):
        path = EXAMPLES / attrs["src"]
        if not path.exists():
            raise SystemExit(f"x-listing: {path} tidak ada")
        self.listed.add(path.name)
        text = path.read_text(encoding="utf-8")
        number = program_number(path)
        label = f"Program {number}" if number else "Unit"
        first, last = 1, None
        if "lines" in attrs:
            first, last = (int(v) for v in attrs["lines"].split("-"))
            text = "\n".join(text.split("\n")[:last])
            label += f" (baris {first}–{last})"
        anchor = f' id="prog-{path.stem}"' if "lines" not in attrs else ""
        return (f'<figure class="listing"{anchor}><div class="listing-head"><span class="num">{label}</span>'
                f'<span class="file">{esc(path.name)}</span><span class="desc">{esc(program_title(path))}</span>'
                f'<span class="open">File ▸ Examples…</span></div>{code_block(text, first=first)}</figure>')

    def error(self, attrs, code, ident):
        name = attrs.get("name", "salah.pas")
        verdict = compile_snippet(code, name, "run" in attrs, attrs.get("input", "").replace("\\n", "\n"))
        marks = {line: "error" for _, line, _, kind, _ in verdict["diagnostics"] if kind in ("Error", "Fatal")}
        head = f'<div class="listing-head err"><span class="num">{esc(name)}</span><span class="desc">{esc(attrs.get("title", ""))}</span></div>'
        block = code_block(code, marks=marks)
        if "run" in attrs:
            result = user_screen(transcript_html(verdict["segments"], verdict["code"]))
            caption = attrs.get("caption", f"Keluaran <code>{esc(name)}</code>")
            return f'<figure class="listing error-demo"{ident}>{head}{block}</figure><figure class="shot">{result}{self.caption(caption)}</figure>'
        if verdict["success"]:
            raise SystemExit(f"x-error {name}: program ini ternyata terkompilasi tanpa galat")
        messages = "".join(f'<div><b>{esc(f)}({l},{c})</b> {esc(k)}: {esc(m)}</div>' for f, l, c, k, m in verdict["diagnostics"])
        caption = attrs.get("caption", "")
        return (f'<figure class="listing error-demo"{ident}>{head}{block}'
                f'<div class="diag"><span class="diag-label">Pesan kompiler</span>{messages}</div>'
                f'{self.caption(caption) if caption else ""}</figure>')


def number_figures(body: str, prefix, numbers: dict) -> str:
    """Numbers figcaptions (Gambar) and table captions (Tabel); records id -> label for x-ref."""
    counters = {"Gambar": 0, "Tabel": 0}
    pieces = re.split(r"(<figure\b[^>]*>|<table\b[^>]*>|<figcaption>|<caption>)", body)
    current_id, out = None, []
    for piece in pieces:
        if piece.startswith("<figure") or piece.startswith("<table"):
            m = re.search(r'\bid="([^"]+)"', piece)
            current_id = m.group(1) if m else None
            out.append(piece)
        elif piece in ("<figcaption>", "<caption>"):
            kind = "Gambar" if piece == "<figcaption>" else "Tabel"
            counters[kind] += 1
            label = f"{kind} {prefix}.{counters[kind]}" if prefix else kind
            if current_id:
                numbers[current_id] = label
            out.append(f'{piece}<b class="caption-label">{label}</b> ')
        else:
            out.append(piece)
    return "".join(out)


def number_headings(section: Section) -> str:
    counter = [0, 0]

    def heading(match):
        level, attrs, text = int(match.group(1)), match.group(2), match.group(3)
        m = re.search(r'\bid="([^"]+)"', attrs)
        if level == 2:
            counter[0] += 1
            counter[1] = 0
            number = f"{section.prefix}.{counter[0]}" if section.prefix else ""
        else:
            counter[1] += 1
            number = f"{section.prefix}.{counter[0]}.{counter[1]}" if section.prefix else ""
        ident = m.group(1) if m else f"{section.key}-{counter[0]}" + (f"-{counter[1]}" if level == 3 else "")
        attrs = re.sub(r'\s*\bid="[^"]*"', "", attrs)
        section.headings.append((level, ident, number, re.sub(r"<[^>]+>", "", text)))
        label = f'<span class="hn">{number}</span>' if number else ""
        return f'<h{level} id="{ident}"{attrs}>{label}{text}</h{level}>'

    return re.sub(r"<h([23])\b([^>]*)>(.*?)</h\1>", heading, section.body, flags=re.S)


def load_chapter(n: int, numbers: dict) -> Section:
    path = BOOK / f"bab{n:02}.html"
    text = path.read_text(encoding="utf-8")
    m = re.search(r'<ul class="tujuan">.*?</ul>', text, re.S)
    objectives = m.group(0) if m else ""
    if m:
        text = text.replace(objectives, "")
    requests = run_requests(text)
    runs = capture_chapter(n, requests)
    expander = Expander(str(n), runs, n)
    text = TAG.sub(expander, text)
    expected = {p.name for p in example_files() if chapter_of(p) == n}
    missing = expected - expander.listed
    if missing:
        raise SystemExit(f"bab{n:02}.html belum memuat listing: {', '.join(sorted(missing))}")
    part = part_of(n)
    section = Section("bab", f"bab-{n:02}", CHAPTERS[n], text, prefix=str(n), color=part[4], objectives=objectives, part=part)
    section.body = number_figures(number_headings(section), str(n), numbers)
    return section


def load_matter(name: str, kind: str, numbers: dict) -> list[Section]:
    """depan.html, penutup.html or lampiran.html: <section data-key data-title [data-prefix]> blocks."""
    text = re.sub(r"<!--.*?-->", "", (BOOK / name).read_text(encoding="utf-8"), flags=re.S)
    sections = []
    for attrs, body in re.findall(r"<section\b([^>]*)>(.*?)</section>", text, re.S):
        a = attributes(attrs)
        prefix = a.get("data-prefix")
        requests = run_requests(body)
        runs = capture_chapter(100 + len(sections) + {"depan.html": 0, "penutup.html": 30, "lampiran.html": 60}[name], requests)
        body = TAG.sub(Expander(prefix, runs), body)
        section = Section(kind, a["data-key"], a["data-title"], body, prefix=prefix, color=a.get("data-color", "#1d4ed8"))
        section.layout = a.get("data-layout", "")
        section.body = number_figures(number_headings(section), prefix, numbers)
        sections.append(section)
    return sections


# ---------------------------------------------------------------- page assembly

def roman(n: int) -> str:
    out = ""
    for value, letters in ((10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")):
        while n >= value:
            out += letters
            n -= value
    return out


def journey(current: int) -> str:
    """The 20-chapter track on openers and part pages; current is highlighted."""
    stops = []
    for numeral, _, _, (first, last), color in PARTS:
        for n in range(first, last + 1):
            cls = "now" if n == current else "done" if n < current else ""
            stops.append(f'<span class="{cls}" style="--p:{color}">{n}</span>')
    return f'<div class="journey">{"".join(stops)}</div>'


def chapter_programs(n: int) -> str:
    rows = []
    for path in example_files():
        if chapter_of(path) == n:
            number = program_number(path) or "Unit"
            rows.append(f'<li><a href="#prog-{path.stem}"><b>{number}</b><code>{esc(path.name)}</code>'
                        f'<span>{esc(program_title(path))}</span></a></li>')
    return f'<ul class="programs">{"".join(rows)}</ul>'


def opener(section: Section) -> str:
    n = int(section.prefix)
    numeral, part_title = section.part[0], section.part[1]
    return (f'<div class="opener" id="{section.key}" style="{color_vars(section.color)}">'
            f'<div class="op-top"><div class="op-grid"></div><div class="op-part">Bagian {numeral} · {esc(part_title)}</div>'
            f'<div class="op-num"><span>BAB</span>{n:02}</div><h1>{esc(section.title)}</h1>{journey(n)}</div>'
            f'<div class="op-bottom"><div class="op-col"><h4>Tujuan Pembelajaran</h4>{section.objectives}</div>'
            f'<div class="op-col"><h4>Program dalam Bab Ini</h4>{chapter_programs(n)}</div></div></div>')


def part_page(index: int) -> str:
    numeral, title, description, (first, last), color = PARTS[index]
    chapters = "".join(f'<li><a href="#bab-{n:02}"><b>{n:02}</b>{esc(CHAPTERS[n])}</a></li>' for n in range(first, last + 1))
    return (f'<div class="part-page" id="bagian-{index + 1}" style="{color_vars(color)}"><div class="pp-roman">{numeral}</div>'
            f'<div class="pp-label">BAGIAN {numeral}</div><h1>{esc(title)}</h1><p>{esc(description)}</p>'
            f'<ol class="pp-chapters">{chapters}</ol>{journey(first - 1 if first > 1 else 0)}</div>')


def toc_html(front, parts, back, pages) -> str:
    def entry(cls, ident, number, text):
        page = pages.get(ident, "000")
        num = f'<span class="tn">{number}</span>' if number else ""
        return f'<a class="toc-{cls}" href="#{ident}">{num}<span class="tt">{text}</span><span class="dots"></span><span class="tp">{page}</span></a>'

    out = []
    for s in front:
        if s.key not in ("judul", "hak-cipta"):
            out.append(entry("front", s.key, "", esc(s.title)))
    for i, (numeral, title, _, _, color) in enumerate(PARTS):
        out.append(f'<div style="{color_vars(color)}">' + entry("part", f"bagian-{i + 1}", f"Bagian {numeral}", esc(title)))
        for s in parts[i]:
            out.append(entry("chapter", s.key, f"Bab {s.prefix}", esc(s.title)))
            for level, ident, number, text in s.headings:
                if level == 2:
                    out.append(entry("sec", ident, number, esc(text)))
        out.append("</div>")
    for s in back:
        out.append(entry("back", s.key, f"Lampiran {s.prefix}" if s.prefix and s.kind == "lampiran" else "", esc(s.title)))
    return f'<div class="toc">{"".join(out)}</div>'


def program_index(pages) -> str:
    rows = []
    for path in example_files():
        number = program_number(path) or "Unit"
        rows.append(f'<a href="#prog-{path.stem}"><b>{number}</b><code>{esc(path.name)}</code>'
                    f'<span class="tt">{esc(program_title(path))}</span><span class="tp">{pages.get("prog-" + path.stem, "000")}</span></a>')
    return f'<div class="program-index">{"".join(rows)}</div>'


def cover() -> str:
    logo = (ROOT / "assets" / "odin.png").as_uri()
    code = ("program HaloDunia;\n\nbegin\n  WriteLn('Halo, Dunia!');\n  WriteLn('Selamat datang di Odin Turbo Pascal.');\nend.\n")
    lines = "".join(f'<div><span class="ln">{i}</span>{line or " "}</div>' for i, line in enumerate(highlight(code.rstrip()), 1))
    return f'''<div class="cover" id="sampul">
  <div class="cv-pattern"></div><div class="cv-glow"></div>
  <div class="cv-top"><span>BUKU TUTORIAL</span><span>Edisi Odin Turbo Pascal {esc(__version_tag__)}</span></div>
  <div class="cv-title"><h1>Belajar<br>Pemrograman<br><em>Bahasa Pascal</em></h1>
    <div class="cv-sub">{esc(SUBTITLE.replace("ODIN", "<ODIN>"))}</div></div>
  <div class="cv-art">
    <div class="cv-window"><div class="cv-wbar"><span>[■]</span><span>HALO.PAS</span><span>[↕]</span></div><div class="cv-code">{lines}</div></div>
    <div class="cv-screen"><div>Halo, Dunia!</div><div>Selamat datang di Odin Turbo Pascal.</div><div class="cv-cursor">_</div></div>
    <img class="cv-logo" src="{logo}" alt="">
  </div>
  <div class="cv-chips"><span>20 Bab</span><span>89 Program Contoh</span><span>Infografik &amp; Latihan</span><span>Proyek Akhir</span></div>
  <div class="cv-author"><b>{esc(__author__)}</b><span>{EMAIL}</span></div>
  <div class="cv-band"><span>ODIN TURBO PASCAL</span><span>Native Pascal IDE · macOS · Windows · Linux</span></div>
</div>'''.replace("&lt;ODIN&gt;", "<b>ODIN</b>")


def back_cover() -> str:
    logo = (ROOT / "assets" / "odin.png").as_uri()
    items = ["Memasang dan memakai IDE Odin Turbo Pascal", "Tipe data, operator, percabangan, dan perulangan",
             "Prosedur, fungsi, dan rekursi", "Array, string, record, enumerasi, dan set",
             "Algoritma pencarian dan pengurutan", "File, pointer, linked list, dan unit", "Tiga proyek akhir yang utuh"]
    checks = "".join(f"<li>{esc(i)}</li>" for i in items)
    return f'''<div class="backcover" id="sampul-belakang">
  <div class="cv-pattern"></div>
  <div class="bc-body">
    <h2>Belajar Pascal dengan cara yang menyenangkan: ketik, jalankan, pahami.</h2>
    <p>Buku ini mengajak Anda belajar pemrograman dari nol dengan bahasa Pascal, bahasa yang dirancang khusus untuk
    mengajarkan cara berpikir terstruktur. Setiap konsep dijelaskan dengan bahasa sederhana, infografik berwarna,
    dan program lengkap yang bisa langsung dibuka dan dijalankan di Odin Turbo Pascal, IDE bergaya klasik yang
    berjalan di macOS, Windows, dan Linux.</p>
    <h3>Yang akan Anda kuasai</h3><ul>{checks}</ul>
    <p>Semua 89 program contoh tersedia di menu <b>File ▸ Examples</b>, dan semua keluaran di buku ini adalah hasil
    menjalankan program tersebut dengan kompiler Odin.</p>
  </div>
  <div class="bc-foot"><img src="{logo}" alt=""><div><b>{esc(__author__)}</b><span>{EMAIL}</span>
    <span>Odin Turbo Pascal {esc(__version_tag__)} · GNU GPL v3 atau yang lebih baru</span></div></div>
</div>'''


def title_page() -> str:
    logo = (ROOT / "assets" / "odin-logo.png").as_uri()
    return f'''<div class="title-page" id="judul"><img src="{logo}" alt="">
  <h1>{esc(TITLE)}</h1><div class="tp-sub">{esc(SUBTITLE)}</div><div class="tp-rule"></div>
  <div class="tp-author">{esc(__author__)}</div><div class="tp-mail">{EMAIL}</div>
  <div class="tp-edition">Edisi Odin Turbo Pascal {esc(__version_tag__)} · {YEAR}</div></div>'''


def assemble(front, parts, back, pages, preview=False) -> str:
    body = ['<svg width="0" height="0" style="position:absolute"><defs>'
            '<marker id="panah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            '<path d="M0 0L10 5L0 10z" fill="context-stroke"/></marker></defs></svg>']
    if not preview:
        body.append(cover())
        body.append(title_page())
    for s in front:
        if s.key == "judul":
            continue
        content = s.body.replace("[[DAFTAR-ISI]]", toc_html(front, parts, back, pages))
        body.append(f'<section class="matter {s.kind} {s.layout}" id="{s.key}" style="{color_vars(s.color)}">'
                    f'{"" if s.layout == "plain" else f"<h1>{esc(s.title)}</h1>"}{content}</section>')
    for i, chapters in enumerate(parts):
        if not chapters:
            continue
        body.append(part_page(i))
        for s in chapters:
            body.append(opener(s))
            body.append(f'<section class="bab" style="{color_vars(s.color)}">{s.body}</section>')
    for s in back:
        content = s.body.replace("[[DAFTAR-PROGRAM]]", program_index(pages))
        label = f'<span class="lamp">Lampiran {s.prefix}</span>' if s.kind == "lampiran" and s.prefix else ""
        body.append(f'<section class="matter {s.kind} {s.layout}" id="{s.key}" style="{color_vars(s.color)}">'
                    f'<h1>{label}{esc(s.title)}</h1>{content}</section>')
    if not preview:
        body.append(back_cover())
    css = (BOOK / "buku.css").read_text(encoding="utf-8")
    return (f'<!doctype html><html lang="id"><head><meta charset="utf-8"><title>{esc(TITLE)}</title>'
            f'<style>{palette_css()}\n{css}</style></head><body>{"".join(body)}</body></html>')


def resolve_refs(text: str, numbers: dict) -> str:
    def ref(match):
        target = match.group(1)
        if target not in numbers:
            raise SystemExit(f"x-ref: id {target!r} tidak ditemukan")
        return f'<a class="ref" href="#{target}">{numbers[target]}</a>'
    return re.sub(r'<a class="ref" href="#[^"]*" data-ref="([^"]+)">\?\?</a>', ref, text)


def find_chrome() -> str:
    for candidate in (os.environ.get("CHROME", ""), "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                      "/Applications/Chromium.app/Contents/MacOS/Chromium", shutil.which("google-chrome") or "",
                      shutil.which("chromium") or "", shutil.which("chromium-browser") or ""):
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit("Google Chrome/Chromium tidak ditemukan (atur $CHROME).")


def print_pdf(html_text: str, pdf: Path) -> None:
    source = pdf.with_suffix(".html")
    source.write_text(html_text, encoding="utf-8")
    with tempfile.TemporaryDirectory() as profile:
        result = subprocess.run([find_chrome(), "--headless", "--disable-gpu", "--no-pdf-header-footer",
                                 f"--user-data-dir={profile}", "--run-all-compositor-stages-before-draw",
                                 f"--print-to-pdf={pdf}", source.as_uri()], capture_output=True, text=True, timeout=900)
    if not pdf.exists():
        raise SystemExit(f"Chrome gagal mencetak PDF:\n{result.stderr[-2000:]}")


BODY_SIZE = 10.3     # pt, body text in buku.css


def check_scale(doc) -> None:
    """Chrome shrinks the whole book when any element is wider than the page; the body text then
    prints smaller than buku.css says."""
    sizes = {}
    for page in doc:
        for block in page.get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                for span in line["spans"]:
                    if "Charter" in span["font"]:
                        sizes[round(span["size"], 1)] = sizes.get(round(span["size"], 1), 0) + len(span["text"])
    if sizes:
        size = max(sizes, key=sizes.get)
        if size < BODY_SIZE - .2:
            raise SystemExit(f"Ada elemen yang lebih lebar dari halaman, sehingga Chrome mengecilkan seluruh buku "
                             f"(huruf isi {size}pt, seharusnya {BODY_SIZE}pt). Cari figure, tabel, atau baris pre yang terlalu lebar.")


def anchor_pages(pdf: Path) -> tuple[dict, int]:
    import fitz
    doc = fitz.open(pdf)
    check_scale(doc)
    pages = {}
    for page in doc:
        for link in page.get_links():
            if link.get("nameddest") and link.get("page", -1) >= 0:
                pages.setdefault(link["nameddest"], link["page"])
    return pages, doc.page_count


# ---------------------------------------------------------------- running heads, page numbers, outline

def page_plan(front, parts, back, index: dict, count: int, preview: bool):
    """For every page: (label, head or None, color, thumb). head is None on full-page designs."""
    starts = []   # (page, kind, section)
    for s in front:
        if s.key in index:
            starts.append((index[s.key], "front", s))
    for i, chapters in enumerate(parts):
        if f"bagian-{i + 1}" in index:
            starts.append((index[f"bagian-{i + 1}"], "part", i))
        for s in chapters:
            if s.key in index:
                starts.append((index[s.key], "bab", s))
    for s in back:
        if s.key in index:
            starts.append((index[s.key], "back", s))
    starts.sort(key=lambda item: item[0])
    body_start = next((p for p, kind, _ in starts if kind in ("part", "bab")), count)
    plan = []
    for page in range(count):
        current = None
        for start in starts:
            if start[0] <= page:
                current = start
        if page >= body_start:
            label = str(page - body_start + 1)
        elif preview or page >= 1:
            label = roman(page if not preview else page + 1)
        else:
            label = ""
        kind = current[1] if current else "cover"
        if not preview and (page == 0 or page == count - 1):
            plan.append(("Sampul" if page == 0 else "Sampul belakang", None, None, None))
            continue
        if not preview and page == 1:
            plan.append((label, None, None, None))
            continue
        if kind == "part" or (current and page == current[0] and kind == "bab"):
            plan.append((label, None, None, None))
            continue
        if kind == "bab":
            s = current[2]
            plan.append((label, (f"Bagian {s.part[0]} · {s.part[1]}", f"Bab {s.prefix} · {s.title}"), s.color, s.prefix))
        elif kind in ("front", "back"):
            s = current[2]
            appendix = s.kind == "lampiran" and s.prefix
            left = "Lampiran" if appendix else TITLE
            right = f"Lampiran {s.prefix} · {s.title}" if appendix else s.title
            plan.append((label, (left, right), s.color or "#1d4ed8", "L" if appendix else None))
        else:
            plan.append((label, None, None, None))
    return plan, body_start


def overlay_html(plan) -> str:
    pages = []
    for label, head, color, thumb in plan:
        if head is None:
            pages.append('<div class="pg"></div>')
            continue
        tab = ""
        if thumb:
            slot = 21 if thumb == "L" else int(thumb)
            tab = f'<div class="thumb" style="top:{30 + (slot - 1) * 11.5}mm">{thumb}</div>'
        pages.append(f'<div class="pg" style="{color_vars(color)}"><div class="head"><span>{esc(head[0])}</span>'
                     f'<span>{esc(head[1])}</span></div>{tab}<div class="foot"><span>{esc(TITLE)} · {esc(__author__)}</span>'
                     f'<b>{esc(label)}</b></div></div>')
    css = """@page{size:A4;margin:0}*{margin:0;padding:0;box-sizing:border-box}
body{font-family:"Avenir Next","Helvetica Neue",sans-serif}
.pg{width:210mm;height:297mm;position:relative;break-after:page;overflow:hidden}
.head{position:absolute;left:20mm;right:20mm;top:9mm;display:flex;justify-content:space-between;align-items:flex-end;
 font-size:7.6pt;letter-spacing:.06em;text-transform:uppercase;color:var(--c-dark);padding-bottom:1.6mm;border-bottom:.5pt solid var(--c-line)}
.head span:first-child{font-weight:600;color:var(--c)}
.head span:last-child{font-weight:500;color:#555;text-transform:none;letter-spacing:.01em;font-size:8pt}
.foot{position:absolute;left:20mm;right:20mm;bottom:8.5mm;display:flex;justify-content:space-between;align-items:center;font-size:7.4pt;color:#888}
.foot b{display:inline-block;min-width:9mm;text-align:center;background:var(--c);color:#fff;border-radius:3mm;padding:.9mm 2.4mm;font-size:8.4pt;font-weight:700}
.thumb{position:absolute;right:0;width:7mm;height:10.5mm;background:var(--c);color:#fff;font-weight:800;font-size:8.5pt;
 display:flex;align-items:center;justify-content:center;border-radius:2mm 0 0 2mm}"""
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>{"".join(pages)}</body></html>'


def outline(front, parts, back, index) -> list:
    """PDF bookmarks. Every page comes from index (a link destination); a section with no page is
    skipped, and levels never jump (PyMuPDF requires level n+1 to follow level n)."""
    toc = []

    def add(level, title, key):
        page = index.get(key)
        if page is None:
            return
        safe = min(level, (toc[-1][0] + 1) if toc else 1)
        toc.append([safe, title, page + 1])

    for s in front:
        add(1, s.title, s.key)
    for i, chapters in enumerate(parts):
        numeral, title = PARTS[i][0], PARTS[i][1]
        if chapters:
            key = f"bagian-{i + 1}" if f"bagian-{i + 1}" in index else chapters[0].key
            add(1, f"Bagian {numeral}: {title}", key)
        for s in chapters:
            add(2, f"Bab {s.prefix}. {s.title}", s.key)
            for level, ident, number, text in s.headings:
                if level == 2:
                    add(3, f"{number} {text}", ident)
    for s in back:
        title = f"Lampiran {s.prefix}. {s.title}" if s.kind == "lampiran" and s.prefix else s.title
        add(1, title, s.key)
    return toc


def examples_digest() -> str:
    digest = hashlib.sha256()
    for path in example_files():
        digest.update(path.name.encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()[:16]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--chapters", help="hanya bab tertentu, mis. 6,7 (pratinjau tanpa sampul)")
    parser.add_argument("--out", type=Path, help=f"berkas PDF (bawaan {OUTPUT.relative_to(ROOT)})")
    parser.add_argument("--skip-missing", action="store_true", help="lewati bab yang berkasnya belum ada (untuk pratinjau sebagian)")
    args = parser.parse_args()
    try:
        import fitz
    except ImportError:
        raise SystemExit("PyMuPDF belum terpasang (pip install pymupdf).")
    preview = bool(args.chapters)
    wanted = [int(n) for n in args.chapters.split(",")] if preview else list(CHAPTERS)
    out = args.out or (CACHE / "pratinjau.pdf" if preview else OUTPUT)
    CACHE.mkdir(parents=True, exist_ok=True)
    numbers = {}
    front = [] if preview else load_matter("depan.html", "depan", numbers)
    parts = [[] for _ in PARTS]
    for n in wanted:
        if args.skip_missing and not (BOOK / f"bab{n:02}.html").exists():
            print(f"Bab {n}: (dilewati, belum ada)", flush=True)
            continue
        print(f"Bab {n}", flush=True)
        section = load_chapter(n, numbers)
        parts[PARTS.index(section.part)].append(section)
    back = [] if preview else load_matter("penutup.html", "penutup", numbers) + load_matter("lampiran.html", "lampiran", numbers)

    # Pass 1 finds the page of every linked anchor; pass 2 prints the page labels into the contents.
    work = Path(tempfile.mkdtemp(prefix="cetak-", dir=CACHE))
    draft = work / "draf.pdf"
    labels, index = {}, {}
    for attempt in range(3):
        text = resolve_refs(assemble(front, parts, back, labels, preview), numbers)
        draft.unlink(missing_ok=True)
        print(f"Cetak (putaran {attempt + 1})", flush=True)
        print_pdf(text, draft)
        index, count = anchor_pages(draft)
        plan, _ = page_plan(front, parts, back, index, count, preview)
        new_labels = {ident: plan[page][0] for ident, page in index.items()}
        if new_labels == labels:
            break
        labels = new_labels
    doc = fitz.open(draft)
    overlay_pdf = work / "lapisan.pdf"
    overlay_pdf.unlink(missing_ok=True)
    print_pdf(overlay_html(plan), overlay_pdf)
    overlay = fitz.open(overlay_pdf)
    if overlay.page_count != doc.page_count:
        raise SystemExit("Jumlah halaman lapisan tidak sama dengan buku")
    for page, (label, head, _, _) in zip(doc, plan):
        if head is not None:
            page.show_pdf_page(page.rect, overlay, page.number)
    _, body_start = page_plan(front, parts, back, index, doc.page_count, preview)
    if not preview:
        doc.set_page_labels([{"startpage": 0, "prefix": "Sampul", "style": "", "firstpagenum": 1},
                             {"startpage": 1, "prefix": "", "style": "r", "firstpagenum": 1},
                             {"startpage": body_start, "prefix": "", "style": "D", "firstpagenum": 1},
                             {"startpage": doc.page_count - 1, "prefix": "Sampul belakang", "style": "", "firstpagenum": 1}])
    doc.set_toc(outline(front, parts, back, index))
    doc.set_metadata({"title": f"{TITLE} {SUBTITLE}", "author": f"{__author__} <{EMAIL}>",
                      "subject": f"Buku tutorial Pascal untuk Odin Turbo Pascal {__version_tag__}",
                      "keywords": f"Pascal, Turbo Pascal, Odin Turbo Pascal, odin-version={__version__}, examples-sha256={examples_digest()}",
                      "creator": "scripts/build_book.py (Odin Turbo Pascal)", "producer": "Google Chrome + PyMuPDF"})
    out.parent.mkdir(parents=True, exist_ok=True)
    temp = out.with_suffix(".tmp.pdf")
    doc.save(temp, garbage=4, deflate=True, deflate_fonts=True, clean=True, use_objstms=1)
    os.replace(temp, out)
    shutil.rmtree(work, ignore_errors=True)
    print(f"{out} ({doc.page_count} halaman, {out.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
