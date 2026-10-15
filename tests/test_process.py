# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""The User screen process contract, on a POSIX PTY (PtyProcess) and on a Windows ConPTY
(ConPtyProcess): output and exit events, environment and working folder, keyboard input, Ctrl-C,
stop() ending the whole process tree, and resize(). The children are Python programs, so the same
tests run everywhere; WindowsConPtyTests adds what only exists on Windows.

On macOS and Linux these tests need real PTYs (run them outside the Claude Code sandbox)."""
import ctypes
import os
import queue
import re
import sys
import tempfile
import time
import unittest
from pathlib import Path

from odin.terminal import Process, Screen

ROOT = Path(__file__).resolve().parent.parent
PYTHON = sys.executable


def process_gone(pid, timeout):
    """True when process pid has ended within timeout seconds."""
    deadline = time.monotonic() + timeout
    if sys.platform == "win32":
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        open_process = kernel32.OpenProcess
        open_process.argtypes = (ctypes.c_uint32, ctypes.c_int32, ctypes.c_uint32)
        open_process.restype = ctypes.c_void_p
        wait = kernel32.WaitForSingleObject
        wait.argtypes = (ctypes.c_void_p, ctypes.c_uint32)
        wait.restype = ctypes.c_uint32
        close = kernel32.CloseHandle
        close.argtypes = (ctypes.c_void_p,)
        close.restype = ctypes.c_int32
        handle = open_process(0x00100000, False, pid)   # SYNCHRONIZE
        if not handle:
            return True
        try:
            return wait(handle, int(timeout * 1000)) == 0
        finally:
            close(handle)
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(.05)
    return False


class Run:
    """One Process with its events collected; output is checked raw and as a rendered screen,
    because ConPTY may interleave cursor sequences with the text."""

    def __init__(self, code=None, argv=None, cwd=None, env=None):
        self.events = queue.Queue()
        self.output = ""
        self.screen = Screen()
        self.code = None
        self.process = Process(argv or [PYTHON, "-c", code], cwd or ROOT, lambda kind, value: self.events.put((kind, value)), env=env)

    def _take(self, timeout):
        try:
            kind, value = self.events.get(timeout=max(0.01, timeout))
        except queue.Empty:
            return
        if kind == "output":
            self.output += value
            self.screen.feed(value)
        elif kind == "exit":
            if self.code is not None:
                raise AssertionError("second exit event")
            self.code = value
        else:
            raise AssertionError(f"unexpected event {kind!r}")

    def shows(self, pattern):
        for text in (self.output, self.screen.text()):
            match = re.search(pattern, text)
            if match:
                return match
        return None

    def expect(self, pattern, timeout=10):
        """Waits until the program has shown pattern (a regular expression); returns the match."""
        deadline = time.monotonic() + timeout
        while True:
            match = self.shows(pattern)
            if match:
                return match
            if self.code is not None or time.monotonic() > deadline:
                return None
            self._take(deadline - time.monotonic())

    def wait_exit(self, timeout=10):
        deadline = time.monotonic() + timeout
        while self.code is None:
            if time.monotonic() > deadline:
                raise AssertionError(f"program did not exit; output: {self.output!r}")
            self._take(deadline - time.monotonic())
        # The exit event is the last one.
        time.sleep(.2)
        if not self.events.empty():
            raise AssertionError(f"event after exit: {self.events.get()!r}")
        return self.code

    def stop(self):
        if self.code is None and self.process.child.poll() is None:
            self.process.stop()


class ProcessContractTests(unittest.TestCase):
    def setUp(self):
        self.runs = []

    def tearDown(self):
        for run in self.runs:
            run.stop()

    def start(self, code=None, **options):
        run = Run(code, **options)
        self.runs.append(run)
        return run

    def assertShows(self, run, pattern, timeout=10):
        match = run.expect(pattern, timeout)
        self.assertIsNotNone(match, f"{pattern!r} not shown; output: {run.output!r}")
        return match

    def test_output_and_exit_code(self):
        run = self.start("print('hello from the child'); raise SystemExit(3)")
        self.assertShows(run, "hello from the child")
        self.assertEqual(run.wait_exit(), 3)
        self.assertIsNotNone(run.process.child.poll())
        self.assertTrue(run.process.closed)

    def test_environment_and_working_folder(self):
        with tempfile.TemporaryDirectory(prefix="odin-proc-") as folder:
            run = self.start("import os; print('env=%s|term=%s|size=%sx%s|cwd=%s' % (os.environ['ODIN_TEST_VALUE'], os.environ['TERM'],"
                             " os.environ['COLUMNS'], os.environ['LINES'], os.path.basename(os.getcwd())))",
                             cwd=folder, env={"ODIN_TEST_VALUE": "nilai 42"})
            self.assertShows(run, re.escape(f"env=nilai 42|term=xterm|size=80x25|cwd={Path(folder).name}"))
            self.assertEqual(run.wait_exit(), 0)

    def test_keyboard_input(self):
        run = self.start("print('ready', flush=True); line = input(); print('got=' + line[::-1])")
        self.assertShows(run, "ready")
        run.process.write(b"odin\r")
        self.assertShows(run, "got=nido")
        self.assertEqual(run.wait_exit(), 0)

    def test_interrupt_is_ctrl_c(self):
        run = self.start("import time\ntry:\n    print('ready', flush=True)\n    time.sleep(30)\n"
                         "except KeyboardInterrupt:\n    print('interrupted', flush=True)\n    raise SystemExit(5)\n")
        self.assertShows(run, "ready")
        run.process.interrupt()
        self.assertShows(run, "interrupted")
        self.assertEqual(run.wait_exit(), 5)

    def test_stop_ends_the_program_and_its_children(self):
        run = self.start("import subprocess, sys, time\n"
                         "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                         "print('grandchild=%d;' % child.pid, flush=True)\n"
                         "time.sleep(60)\n")
        grandchild = int(self.assertShows(run, r"grandchild=(\d+);").group(1))
        run.process.stop()
        self.assertNotEqual(run.wait_exit(), 0)
        self.assertTrue(process_gone(grandchild, 5), "the program's child survived stop()")

    def test_resize(self):
        run = self.start("import os\n"
                         "show = lambda: print('size=%dx%d' % tuple(os.get_terminal_size()), flush=True)\n"
                         "show()\n"
                         "while input() != 'q':\n    show()\n")
        self.assertShows(run, "size=80x25")
        run.process.resize(100, 30)
        # The new size travels apart from the keyboard input; ask until the program sees it.
        for _ in range(20):
            run.process.write(b"\r")
            if run.expect("size=100x30", timeout=.5):
                break
        self.assertShows(run, "size=100x30", timeout=1)
        run.process.write(b"q\r")
        self.assertEqual(run.wait_exit(), 0)

    def test_missing_program(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(FileNotFoundError):
                Process([str(Path(folder) / "missing-program"), "x"], folder, lambda kind, value: None)

    def test_write_after_exit_is_ignored(self):
        run = self.start("pass")
        self.assertEqual(run.wait_exit(), 0)
        run.process.write(b"late input\r")
        run.process.interrupt()
        run.process.resize(90, 20)
        run.process.stop()


@unittest.skipUnless(sys.platform == "win32", "ConPTY, job objects and cmd.exe exist on Windows only")
class WindowsConPtyTests(unittest.TestCase):
    def test_cmd_builtins_and_exit_code(self):
        run = Run(argv=["cmd", "/c", "echo", "hello", "world"])
        self.assertIsNotNone(run.expect("hello world"), run.output)
        self.assertEqual(run.wait_exit(), 0)
        run = Run(argv=["cmd", "/c", "exit", "7"])
        self.assertEqual(run.wait_exit(), 7)

    def test_child_object_like_popen(self):
        run = Run("import time; print('ready', flush=True); time.sleep(30)")
        try:
            self.assertIsNotNone(run.expect("ready"), run.output)
            child = run.process.child
            self.assertGreater(child.pid, 0)
            self.assertIsNone(child.poll())
            import subprocess
            with self.assertRaises(subprocess.TimeoutExpired):
                child.wait(.1)
        finally:
            run.process.stop()
        self.assertEqual(run.wait_exit(), 1)
        self.assertEqual(run.process.child.wait(), 1)

    def test_descriptors_are_not_passed(self):
        r, w = os.pipe()
        try:
            with self.assertRaises(OSError):
                Process(["cmd", "/c", "exit"], ROOT, lambda kind, value: None, pass_fds=(w,))
        finally:
            os.close(r)
            os.close(w)

    def test_conpty_background_colors_report(self):
        """Diagnostic: how conhost passes background colors on to the User screen. It prints what
        came out for each way of asking for a bright background; it fails only if nothing arrives."""
        code = ("import sys\n"
                "for name, seq in [('10x','\\x1b[107m'),('48;5','\\x1b[48;5;15m'),('rgb','\\x1b[48;2;255;255;255m'),"
                "('blink','\\x1b[37;5m'),('bold4x','\\x1b[1;47m'),('plain','\\x1b[47m')]:\n"
                "    sys.stdout.write('<' + name + '>' + seq + ' X \\x1b[0m|')\n"
                "sys.stdout.write('\\nend\\n'); sys.stdout.flush()\n")
        run = Run(code)
        self.assertIsNotNone(run.expect("end"), run.output)
        sys.stderr.write("\nCONPTY COLORS: " + repr(run.output) + "\n")
        run.wait_exit()

    def test_debugger_without_odinpc_fails_cleanly(self):
        from odin.debugger import DebugSession
        with self.assertRaises(OSError):
            DebugSession(str(ROOT / "no-such-odinpc.exe"), "program.exe", "program.odbg", [], ROOT,
                         lambda kind, value: None)


if __name__ == "__main__":
    unittest.main()
