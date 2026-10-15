# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Odin Vision snapshot tests: each demo in tests/pascal/vision is built with odinpc, run on a PTY
and driven with keys and SGR mouse clicks; the Screen grid (characters and colors) at every "snap"
step must equal tests/pascal/vision/NAME.snap. Snapshots come from our own implementation, reviewed
by hand; ODIN_UPDATE_SNAPSHOTS=1 rewrites them."""
import os
import queue
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
        ("expect", "ALPHA.PAS"), ("expect", "BETA.PAS"), ("expect", "sub/"), ("expect", "Open a file"),
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


@unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc (cargo build in toolchain/) on Intel macOS")
class VisionSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="odin vision ")
        self.root = Path(self.temp.name)
        self.settings = Settings(self.root / "settings.json")
        self.settings["backend"] = "odin"

    def tearDown(self):
        self.temp.cleanup()

    def run_demo(self, name):
        r = build(VISION / f"{name}.PAS", self.settings, cache=self.root / "build")
        self.assertTrue(r.success, r.output)
        events = queue.Queue()
        screen = Screen()
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
            self.assertEqual(lines[25:], want[25:], f"{name} {snap}: colors")

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
        self.assertRegex(text, r"FILE 800 /.*/BETA\.PAS")
        self.assertRegex(text, r"DIR /.*/sub")


if __name__ == "__main__":
    unittest.main()
