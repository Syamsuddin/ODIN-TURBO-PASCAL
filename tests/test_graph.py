# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Unit Graph (BGI) of the Odin RTL.

GraphProgramTests compiles every tests/pascal/graph/NAME.PAS with odinpc, runs it with its output on a
pipe (so Graph draws only into memory) and compares what it printed with NAME.expect. The programs
print the framebuffer through GetPixel, so the expectations pin down every primitive pixel for pixel.
They are not in the corpus of toolchain/crates/odinpc/tests/corpus.rs because a program that uses Graph
also uses Crt, which writes cursor escape sequences to a pipe; those are removed here.

GraphDisplayTests runs programs on a pseudo-terminal and reads the screen model back, to check the
half-block preview: colors, centering, the text layer, and what stays on the screen after the program.

New or changed expectations: `python3 tests/test_graph.py --bless`, then read the diff against what BGI
does. On macOS and Linux the display tests need a PTY (run them outside the Claude Code sandbox)."""
import os
import queue
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from odin.console import Process, Screen  # noqa: E402
from odin.graphics import GraphChannel  # noqa: E402
from odin.core import executable_name, locate_toolchain, odin_supported  # noqa: E402

GRAPH_DIR = ROOT / "tests" / "pascal" / "graph"
EXAMPLES_DIR = ROOT / "examples-graph"
HAS_ODIN = bool(locate_toolchain() and odin_supported())
NEEDS_ODIN = "Needs odinpc (cargo build in toolchain/) on a host it supports (core.ODIN_HOSTS)"
ESCAPES = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def compile_program(source: Path, out: Path):
    """Build with odinpc; returns (ok, message)."""
    command = [locate_toolchain(), "build", str(source), "--out", str(out), "--rtl", str(ROOT / "rtl")]
    result = subprocess.run(command, capture_output=True, text=True)
    return result.returncode == 0, result.stdout + result.stderr


def program_output(source: Path, work: Path) -> str:
    """What the program printed, without Crt's escape sequences and with LF line ends."""
    exe = work / executable_name(source.stem)
    ok, message = compile_program(source, exe)
    if not ok:
        raise AssertionError(f"{source.name} tidak bisa dikompilasi:\n{message}")
    run = subprocess.run([str(exe)], capture_output=True, cwd=work, timeout=60)
    text = run.stdout.decode("utf-8", "replace").replace("\r\n", "\n")
    return ESCAPES.sub("", text)


@unittest.skipUnless(HAS_ODIN, NEEDS_ODIN)
class GraphProgramTests(unittest.TestCase):
    def test_programs_match_expectations(self):
        sources = sorted(GRAPH_DIR.glob("*.PAS"))
        self.assertTrue(sources, "tidak ada program uji Graph")
        with tempfile.TemporaryDirectory(prefix="odin-graph-") as tmp:
            for source in sources:
                with self.subTest(program=source.name):
                    expected = source.with_suffix(".expect").read_text(encoding="utf-8")
                    self.assertEqual(program_output(source, Path(tmp)), expected)


@unittest.skipUnless(HAS_ODIN, NEEDS_ODIN)
class GraphExampleTests(unittest.TestCase):
    """Every program of examples-graph/ compiles and ends by itself when its input ends (the keys they wait
    for are read as end of file)."""

    def test_examples_compile_and_run(self):
        sources = sorted(EXAMPLES_DIR.glob("grafik_*.pas"))
        self.assertEqual(len(sources), 14)
        with tempfile.TemporaryDirectory(prefix="odin-graph-examples-") as tmp:
            for source in sources:
                with self.subTest(example=source.name):
                    exe = Path(tmp) / executable_name(source.stem)
                    ok, message = compile_program(source, exe)
                    self.assertTrue(ok, message)
                    run = subprocess.run([str(exe)], input=b"", capture_output=True, cwd=tmp, timeout=60)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


@unittest.skipUnless(HAS_ODIN, NEEDS_ODIN)
class GraphChannelTests(unittest.TestCase):
    """The program side of the graphics window (rtl/graph.pas) against odin.graphics.GraphChannel."""

    PROGRAM = """program Kanal;
uses Crt, Graph;
var gd, gm: Integer;
begin
  gd := VGA; gm := VGAHi;
  InitGraph(gd, gm, '');
  SetFillStyle(SolidFill, Red);
  Bar(10, 20, 109, 59);
  SetRGBPalette(9, 63, 0, 0);
  PutPixel(300, 300, LightBlue);
  SetColor(White);
  Line(0, 479, 639, 479);
  ReadKey;
  RestoreCrtMode;
  ReadKey;
  SetGraphMode(GetGraphMode);
  Bar(0, 0, 9, 9);
  ReadKey;
  CloseGraph;
end.
"""

    def test_frames_palette_and_mode_changes_arrive(self):
        with tempfile.TemporaryDirectory(prefix="odin-graph-channel-") as tmp:
            source = Path(tmp) / "kanal.pas"
            source.write_text(self.PROGRAM)
            exe = Path(tmp) / executable_name("kanal")
            ok, message = compile_program(source, exe)
            self.assertTrue(ok, message)
            events = queue.Queue()
            channel = GraphChannel(lambda kind, value: events.put(kind))
            env = dict(os.environ, **channel.env())
            process = subprocess.Popen([str(exe)], env=env, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, cwd=tmp)
            try:
                def wait(condition, timeout=8.0):
                    deadline = time.monotonic() + timeout
                    while time.monotonic() < deadline:
                        if condition():
                            return True
                        time.sleep(0.02)
                    return False

                self.assertTrue(wait(lambda: channel.version >= 3 and channel.pixels[300 * 640 + 300] == 9))
                self.assertEqual((channel.width, channel.height, channel.asp), (640, 480, 10000))
                self.assertEqual(channel.pixels[30 * 640 + 50], 4)          # DOS red in the bar
                self.assertEqual(channel.pixels[479 * 640 + 639], 15)       # the line to the corner
                self.assertEqual(channel.palette[9], (255, 0, 0))           # SetRGBPalette(9, 63, 0, 0)
                self.assertEqual(channel.palette[4], (170, 0, 0))
                self.assertTrue(channel.visible)
                visible, width, height, asp, data = channel.snapshot()
                self.assertTrue(data.startswith(b"\x89PNG"))
                process.stdin.write(b"x")                                   # ReadKey; then RestoreCrtMode
                process.stdin.flush()
                self.assertTrue(wait(lambda: not channel.visible), "RestoreCrtMode menyembunyikan jendela")
                process.stdin.write(b"x")                                   # SetGraphMode shows a blank picture again
                process.stdin.flush()
                self.assertTrue(wait(lambda: channel.visible and channel.pixels[0] == 15))
                self.assertEqual(channel.pixels[300 * 640 + 300], 0)        # the mode change cleared the screen
                process.stdin.write(b"x")                                   # CloseGraph
                process.stdin.flush()
                self.assertTrue(wait(lambda: channel.graphics_closed))
                process.wait(8)
                self.assertTrue(wait(lambda: channel.finished))
            finally:
                if process.poll() is None:
                    process.kill()
                process.stdin.close()
                process.wait()
                channel.close()

    def test_wrong_token_is_ignored(self):
        import socket
        import struct
        channel = GraphChannel(lambda kind, value: None)
        try:
            with socket.create_connection(("127.0.0.1", channel.port)) as connection:
                connection.sendall(struct.pack("<BI", 1, 4) + b"nope")
                connection.sendall(struct.pack("<BI", 2, 8) + struct.pack("<HHHH", 640, 480, 10000, 16))
                time.sleep(0.3)
            self.assertEqual(channel.width, 0)
            self.assertFalse(channel.connected)
        finally:
            channel.close()


class Screens:
    """Runs a program on a PTY and keeps the screen model up to date."""

    def __init__(self, exe, cols=80, rows=25):
        self.screen = Screen(cols, rows)
        self.code = None
        self.process = Process([str(exe)], str(exe.parent), self.emit, cols=cols, rows=rows)

    def emit(self, kind, value):
        if kind == "output":
            self.screen.feed(value)
            for reply in self.screen.replies:
                self.process.write(reply if isinstance(reply, bytes) else reply.encode())
            self.screen.replies.clear()
        elif kind == "exit":
            self.code = value

    def wait_for(self, condition, timeout=8.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition(self.screen):
                return True
            time.sleep(0.05)
        return False

    def wait_exit(self, timeout=8.0):
        deadline = time.monotonic() + timeout
        while self.code is None and time.monotonic() < deadline:
            time.sleep(0.05)
        time.sleep(0.2)
        return self.code

    def stop(self):
        self.process.stop()


def row_text(screen, y):
    return "".join(cell[0] for cell in screen.grid[y])


# ANSI color index in Screen cells for the DOS colors used below (see Crt SetAttr).
ANSI_RED, ANSI_BRIGHT_BLUE = 1, 12

DISPLAY_PROGRAM = """{ SPDX-License-Identifier: GPL-3.0-or-later }
program GraphLayar;
uses Crt, Graph;
var gd, gm: Integer;
begin
  gd := VGA; gm := VGAHi;
  InitGraph(gd, gm, '');
  SetFillStyle(SolidFill, LightBlue);
  Bar(0, 0, 639, 239);
  SetFillStyle(SolidFill, Red);
  Bar(0, 240, 639, 479);
  SetColor(White);
  OutTextXY(80, 100, 'HELLO WORLD');
  SetColor(Yellow);
  Line(0, 0, 639, 479);
  ReadKey;
  CloseGraph;
  WriteLn('selesai');
end.
"""

EXIT_PROGRAM = """{ SPDX-License-Identifier: GPL-3.0-or-later }
program GraphKeluar;
uses Graph;
var gd, gm: Integer;
begin
  gd := Detect;
  InitGraph(gd, gm, '');
  SetFillStyle(SolidFill, Green);
  Bar(0, 0, 639, 479);
end.
"""

TEXT_MODE_PROGRAM = """{ SPDX-License-Identifier: GPL-3.0-or-later }
program GraphTeks;
uses Crt, Graph;
var gd, gm: Integer;
begin
  gd := Detect;
  InitGraph(gd, gm, '');
  SetFillStyle(SolidFill, Blue);
  Bar(0, 0, 639, 479);
  Delay(300);
  RestoreCrtMode;
  WriteLn('mode teks');
  ReadKey;
  SetGraphMode(GetGraphMode);
  SetFillStyle(SolidFill, Magenta);
  Bar(0, 0, 639, 479);
  ReadKey;
  CloseGraph;
end.
"""


@unittest.skipUnless(HAS_ODIN and sys.platform != "win32", NEEDS_ODIN + "; needs a POSIX PTY")
class GraphDisplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="odin-graph-display-")
        cls.work = Path(cls.tmp.name)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def build(self, name, text):
        source = self.work / f"{name}.pas"
        source.write_text(text, encoding="utf-8")
        exe = self.work / executable_name(name)
        ok, message = compile_program(source, exe)
        self.assertTrue(ok, message)
        return exe

    def test_preview_colors_text_and_position(self):
        run = Screens(self.build("graphlayar", DISPLAY_PROGRAM))
        try:
            # A 640x480 image on 80x25 cells: 66.7 columns wide, centered; every cell holds two
            # subpixels of 9.6 pixels.
            def drawn(screen):
                return "HELLO" in row_text(screen, 5)

            self.assertTrue(run.wait_for(drawn), "gambar tidak muncul:\n" + "\n".join(row_text(run.screen, y) for y in range(25)))
            grid = run.screen.grid
            # Bottom half red: spaces on a red background (the background has only 8 colors).
            self.assertEqual(grid[20][40][0], " ")
            self.assertEqual(grid[20][40][2], ANSI_RED)
            # Top half light blue: a full block in the bright foreground color.
            self.assertEqual(grid[2][60][0], "█")
            self.assertEqual(grid[2][60][1], ANSI_BRIGHT_BLUE)
            # The columns left of the image (6) stay black.
            self.assertEqual(grid[20][2], (" ", 7, 0))
            self.assertEqual(grid[20][74], (" ", 7, 0))
            # The text layer: real characters, white, over the blue bar.
            line = row_text(run.screen, 5)
            self.assertIn("HELLO", line)
            column = line.index("HELLO")
            self.assertEqual(grid[5][column][1], 15)
            self.assertEqual(grid[5][column][2], 4)   # ANSI blue: the bar is DOS light blue, whose background is dark blue
            # The diagonal line shows up as half blocks along the way.
            self.assertTrue(any(c[0] in "▀▄█" for c in grid[12]))
            run.process.write(b"x")
            self.assertEqual(run.wait_exit(), 0)
            # CloseGraph returned to the text screen: cleared, with the message and no blocks.
            self.assertEqual(row_text(run.screen, 0).rstrip(), "selesai")
            self.assertFalse(any(c[0] in "▀▄█" for row in run.screen.grid for c in row))
        finally:
            run.stop()

    def test_picture_stays_when_program_ends_without_closegraph(self):
        run = Screens(self.build("graphkeluar", EXIT_PROGRAM))
        try:
            self.assertEqual(run.wait_exit(), 0)
            grid = run.screen.grid
            # Green is DOS color 2, ANSI index 2.
            self.assertEqual(grid[10][40][2], 2)
            self.assertEqual(grid[10][2][2], 0)
        finally:
            run.stop()

    def test_restore_crt_mode_and_set_graph_mode(self):
        run = Screens(self.build("graphteks", TEXT_MODE_PROGRAM))
        try:
            self.assertTrue(run.wait_for(lambda s: "mode teks" in row_text(s, 0)), "mode teks tidak muncul")
            self.assertFalse(any(c[0] in "▀▄█" for row in run.screen.grid for c in row))
            run.process.write(b"x")
            # Back in graphics mode: magenta (DOS 5, ANSI 5), and the text is gone.
            self.assertTrue(run.wait_for(lambda s: s.grid[10][40][2] == 5), "mode grafis tidak kembali")
            self.assertNotIn("mode teks", row_text(run.screen, 0))
            run.process.write(b"x")
            self.assertEqual(run.wait_exit(), 0)
        finally:
            run.stop()


def bless():
    """Rewrites NAME.expect for every program in tests/pascal/graph."""
    if not HAS_ODIN:
        raise SystemExit(NEEDS_ODIN)
    with tempfile.TemporaryDirectory(prefix="odin-graph-") as tmp:
        for source in sorted(GRAPH_DIR.glob("*.PAS")):
            text = program_output(source, Path(tmp))
            source.with_suffix(".expect").write_text(text, encoding="utf-8", newline="\n")
            print(f"tulis  {source.with_suffix('.expect').name} ({len(text.splitlines())} baris)")


if __name__ == "__main__":
    if "--bless" in sys.argv:
        bless()
    else:
        unittest.main()
