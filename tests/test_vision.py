# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Odin Vision snapshot tests: each demo in tests/pascal/vision is built with odinpc, run on a PTY
and driven with keys and SGR mouse clicks; the Screen grid (characters and colors) at every "snap"
step must equal tests/pascal/vision/NAME.snap. Snapshots come from our own implementation, reviewed
by hand; ODIN_UPDATE_SNAPSHOTS=1 rewrites them."""
import os
import queue
import re
import shutil
import tempfile
import time
import unittest
from pathlib import Path

from odin.core import Settings, build, locate_toolchain, odin_supported
from odin.terminal import KEYS, Process, Screen

ROOT = Path(__file__).resolve().parent.parent
VISION = ROOT / "tests" / "pascal" / "vision"
UPDATE = os.environ.get("ODIN_UPDATE_SNAPSHOTS") == "1"


def click(x, y):
    """A left click on screen cell (x, y), counted from 1."""
    return f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode()


ALT_X = b"\x1bx"

# Steps: bytes are typed; ("snap", name) compares the screen with the snapshot.
SCENARIOS = {
    "VMENUS": [
        ("snap", "start"),
        KEYS["F10"], KEYS["Down"], ("snap", "file-menu"),
        KEYS["Right"], KEYS["Down"], ("snap", "window-menu"),
        KEYS["Return"], ("snap", "cascade"),
        click(30, 2), ("snap", "click-front"),
        click(4, 1), click(5, 3), ("snap", "mouse-menu"),
        KEYS["Escape"], KEYS["Escape"],
        ALT_X,
    ],
    "VDIALOG": [
        KEYS["F4"], ("snap", "dialog"),
        b"1", b"x", b"y", KEYS["Tab"], b" ", KEYS["Tab"], KEYS["Down"], ("snap", "filled"),
        click(20, 13), ("snap", "mouse-check"),
        KEYS["Return"], ("snap", "message"),
        KEYS["Return"], ALT_X,
    ],
    "VEDITOR": [
        b"Halo dunia", KEYS["Return"], b"\tbaris dua", b"\x1b[1;2D", b"\x1b[1;2D", ("snap", "typed"),
        KEYS["F4"], KEYS["Down"], b"-", ("snap", "outline"),
        ALT_X, ("snap", "save-prompt"),
        b"n",
    ],
}

# Steps can also be ("expect", text) or ("absent", text): the screen must (not) show text then.
CHECKS = {
    "VFILES": [
        ("expect", "ALPHA.PAS"), ("expect", "BETA.PAS"), ("expect", "sub" + os.sep), ("expect", "Open a file"),
        ("absent", "notes.txt"), ("absent", ".hidden"),
        b"BETA", KEYS["Return"],
        ("expect", "Change Directory"), ("expect", "Directory tree"),
        b"sub", KEYS["Return"],
    ],
}

# What the program prints on the normal screen after Done.
OUTPUT = {
    "VMENUS": "VMENUS selesai, jendela 3",
    "VDIALOG": "VDIALOG Xy 7 2",
    "VEDITOR": "VEDITOR selesai",
}


def encode(screen):
    """Text rows between bars, then one row of fg/bg hex digit pairs per screen row."""
    text = ["|" + "".join(c[0] for c in row) + "|" for row in screen.grid]
    colors = ["".join(f"{c[1]:x}{c[2]:x}" for c in row) for row in screen.grid]
    return text + colors


def visible(lines):
    """The color rows with the foreground of blank cells left out: it cannot be seen, and
    ConPTY on Windows does not keep it when it re-renders the screen."""
    text, colors = lines[:25], lines[25:]
    return [
        "".join("." + row[2 * i + 1] if i + 1 < len(chars) - 1 and chars[i + 1] == " " else row[2 * i:2 * i + 2]
                for i in range(len(row) // 2))
        for chars, row in zip(text, colors)
    ]


def differing_cells(lines, want, limit=30):
    """(row, column, character, wanted fg/bg, got fg/bg) for the cells whose colors differ."""
    cells = []
    for y, (got_row, want_row) in enumerate(zip(visible(lines), visible(want))):
        for x in range(min(len(got_row), len(want_row)) // 2):
            if got_row[2 * x:2 * x + 2] != want_row[2 * x:2 * x + 2]:
                cells.append((y, x, want[y][x + 1], want_row[2 * x:2 * x + 2], got_row[2 * x:2 * x + 2]))
    return cells[:limit]


def read_snapshots(path):
    snapshots, name, lines = {}, None, []
    if path.exists():
        for line in path.read_text(encoding="utf-8").split("\n"):
            if line.startswith("# snapshot "):
                if name:
                    snapshots[name] = lines
                name, lines = line[len("# snapshot "):], []
            elif name is not None and line != "":
                lines.append(line)
        if name:
            snapshots[name] = lines
    return snapshots


def write_snapshots(path, snapshots):
    parts = []
    for name, lines in snapshots.items():
        parts.append(f"# snapshot {name}\n" + "\n".join(lines) + "\n")
    path.write_text("\n".join(parts), encoding="utf-8")


@unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc (cargo build in toolchain/) on a host it supports (core.ODIN_HOSTS)")
class VisionSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="odin vision "))
        self.settings = Settings(self.root / "settings.json")
        self.settings["backend"] = "odin"

    def tearDown(self):
        # Windows keeps a program's .exe locked for a moment after it has ended.
        for attempt in range(50):
            try:
                shutil.rmtree(self.root)
                return
            except PermissionError:
                if attempt == 49:
                    raise
                time.sleep(.1)

    def run_demo(self, name):
        r = build(VISION / f"{name}.PAS", self.settings, cache=self.root / "build")
        self.assertTrue(r.success, r.output)
        events = queue.Queue()
        screen = Screen()
        self.raw = []
        process = Process([str(r.executable)], self.root, lambda k, v: events.put((k, v)))
        exit_code = None

        def settle(quiet=.4, limit=10):
            """Feeds output until the program has been quiet for `quiet` seconds."""
            nonlocal exit_code
            deadline = time.monotonic() + limit
            last = time.monotonic()
            while time.monotonic() < deadline and exit_code is None:
                try:
                    kind, value = events.get(timeout=.05)
                except queue.Empty:
                    if time.monotonic() - last >= quiet:
                        return
                    continue
                if kind == "output":
                    screen.feed(value)
                    self.raw.append(value)
                    last = time.monotonic()
                elif kind == "exit":
                    exit_code = value

        taken = {}
        try:
            settle()
            for step in SCENARIOS.get(name) or CHECKS[name]:
                if isinstance(step, tuple) and step[0] == "expect":
                    self.assertIn(step[1], screen.text())
                elif isinstance(step, tuple) and step[0] == "absent":
                    self.assertNotIn(step[1], screen.text())
                elif isinstance(step, tuple):
                    taken[step[1]] = encode(screen)
                else:
                    process.write(step)
                    settle()
            settle(quiet=1)
        finally:
            if exit_code is None:
                process.stop()
        return taken, exit_code, screen

    def check(self, name):
        taken, code, screen = self.run_demo(name)
        self.assertEqual(code, 0, screen.text())
        self.assertIn(OUTPUT[name], screen.text())
        path = VISION / f"{name}.snap"
        if UPDATE:
            write_snapshots(path, taken)
            return
        expected = read_snapshots(path)
        self.assertEqual(list(taken), list(expected), "snapshot names differ")
        for snap, lines in taken.items():
            want = expected[snap]
            self.assertEqual(lines[:25], want[:25], f"{name} {snap}: text")
            if visible(lines) != visible(want):
                # The cells and the color escapes as the terminal (ConPTY on Windows) sent them.
                sgr = sorted(set(re.findall(r"\x1b\[[0-9;]*m", "".join(self.raw))))
                self.fail(f"{name} {snap}: colors (row, column, char, want, got): "
                          f"{differing_cells(lines, want)}; SGR seen: {sgr[:60]}")

    def test_menus_windows_and_mouse(self):
        self.check("VMENUS")

    def test_dialog_controls_and_message_box(self):
        self.check("VDIALOG")

    def test_editor_outline_and_save_prompt(self):
        self.check("VEDITOR")

    def test_file_dialog_and_change_directory(self):
        for name in ("ALPHA.PAS", "BETA.PAS", "notes.txt", ".hidden.PAS"):
            (self.root / name).write_text("program X; begin end.\n")
        (self.root / "sub").mkdir()
        _, code, screen = self.run_demo("VFILES")
        self.assertEqual(code, 0, screen.text())
        # Rows are 80 cells wide: the temporary path wraps.
        text = screen.text().replace("\n", "")
        # A name without extension takes the one of the wildcard.
        # An absolute path: /... on Unix, X:\... on Windows.
        self.assertRegex(text, r"FILE 800 (/|[A-Z]:\\).*[/\\]BETA\.PAS")
        self.assertRegex(text, r"DIR (/|[A-Z]:\\).*[/\\]sub")


if __name__ == "__main__":
    unittest.main()
