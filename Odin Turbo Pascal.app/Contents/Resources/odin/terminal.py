# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Small VT100 screen and PTY process driver for console Pascal programs."""
from __future__ import annotations

import codecs
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import threading
import tkinter as tk

PALETTE = ["#000000", "#aa0000", "#00aa00", "#aa5500", "#0000aa", "#aa00aa", "#00aaaa", "#aaaaaa",
           "#555555", "#ff5555", "#55ff55", "#ffff55", "#5555ff", "#ff55ff", "#55ffff", "#ffffff"]
# DEC Special Graphics, used by Free Vision for frames and the desktop pattern.
DEC_GRAPHICS = dict(zip("`afgjklmnopqrstuvwxyz{|}~", "◆▒°±┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·"))
# xterm sequences; FPC Crt.ReadKey and Free Vision decode them to #0 + scan code.
KEYS = {"Return": b"\r", "BackSpace": b"\x7f", "Tab": b"\t", "Escape": b"\x1b",
        "Up": b"\x1b[A", "Down": b"\x1b[B", "Right": b"\x1b[C", "Left": b"\x1b[D",
        "Home": b"\x1b[H", "End": b"\x1b[F", "Insert": b"\x1b[2~", "Delete": b"\x1b[3~",
        "Prior": b"\x1b[5~", "Next": b"\x1b[6~",
        "F1": b"\x1bOP", "F2": b"\x1bOQ", "F3": b"\x1bOR", "F4": b"\x1bOS",
        "F5": b"\x1b[15~", "F6": b"\x1b[17~", "F7": b"\x1b[18~", "F8": b"\x1b[19~",
        "F9": b"\x1b[20~", "F10": b"\x1b[21~", "F11": b"\x1b[23~", "F12": b"\x1b[24~"}


class Screen:
    def __init__(self, cols=80, rows=25):
        self.cols, self.rows = cols, rows
        self.fg, self.bg, self.bold, self.inverse = 7, 0, False, False
        self.x = self.y = 0
        self.saved = (0, 0)
        self.top, self.bottom = 0, rows - 1
        self.visible = True
        self.state, self.sequence = "normal", ""
        self.charsets, self.shifted = ["B", "B"], False
        self.wrap_pending = False
        self.grid = [[self.blank() for _ in range(cols)] for _ in range(rows)]

    def blank(self):
        return (" ", self.fg, self.bg)

    def scroll(self):
        del self.grid[self.top]
        self.grid.insert(self.bottom, [self.blank() for _ in range(self.cols)])

    def newline(self):
        if self.y == self.bottom:
            self.scroll()
        else:
            self.y = min(self.rows - 1, self.y + 1)

    def feed(self, text):
        for c in text:
            if self.state == "osc":
                if c == "\x07":
                    self.state = "normal"
                elif c == "\x1b":
                    self.state = "osc_end"
                continue
            if self.state == "osc_end":
                self.state = "normal" if c == "\\" else "osc"
                continue
            if self.state == "charset":
                # ESC ( selects G0, ESC ) selects G1; SO/SI switch between them.
                if self.sequence in "()":
                    self.charsets[self.sequence == ")"] = c
                self.state = "normal"
                continue
            if self.state == "escape":
                self.state = "normal"
                if c == "[":
                    self.state, self.sequence = "csi", ""
                elif c == "]":
                    self.state = "osc"
                elif c in "()*+-./%#":
                    self.state, self.sequence = "charset", c
                elif c == "7":
                    self.saved = (self.x, self.y)
                elif c == "8":
                    self.x, self.y = self.saved
                elif c == "D":
                    self.newline()
                elif c == "M":
                    if self.y == self.top:
                        self.grid.insert(self.top, [self.blank() for _ in range(self.cols)])
                        del self.grid[self.bottom + 1]
                    else:
                        self.y = max(0, self.y - 1)
                elif c == "c":
                    self.__init__(self.cols, self.rows)
                continue
            if self.state == "csi":
                if "@" <= c <= "~":
                    self.control(c, self.sequence)
                    self.state = "normal"
                elif len(self.sequence) < 128:
                    self.sequence += c
                else:
                    self.state = "normal"
                continue
            if c == "\x1b":
                self.state = "escape"
            elif c == "\r":
                self.x = 0
                self.wrap_pending = False
            elif c in "\n\v\f":
                self.newline()
                self.wrap_pending = False
            elif c == "\b":
                self.x = max(0, self.x - 1)
                self.wrap_pending = False
            elif c == "\t":
                self.x = min(self.cols - 1, (self.x // 8 + 1) * 8)
            elif c == "\x0e":
                self.shifted = True
            elif c == "\x0f":
                self.shifted = False
            elif ord(c) >= 32:
                if self.wrap_pending:
                    self.x = 0
                    self.newline()
                    self.wrap_pending = False
                if self.charsets[self.shifted] == "0":
                    c = DEC_GRAPHICS.get(c, c)
                fg = self.fg + 8 if self.bold and self.fg < 8 else self.fg
                fg, bg = (self.bg, fg) if self.inverse else (fg, self.bg)
                self.grid[self.y][self.x] = (c, fg, bg)
                if self.x == self.cols - 1:
                    self.wrap_pending = True
                else:
                    self.x += 1

    def control(self, final, raw):
        private = raw.startswith("?")
        try:
            p = [int(v) if v else 0 for v in raw.lstrip("?").split(";")]
        except ValueError:
            return
        n = p[0] or 1
        if final != "m":
            self.wrap_pending = False
        if final in "Hf":
            self.y = min(self.rows - 1, max(0, n - 1))
            self.x = min(self.cols - 1, max(0, (p[1] if len(p) > 1 and p[1] else 1) - 1))
        elif final == "A": self.y = max(self.top, self.y - n)
        elif final == "B": self.y = min(self.bottom, self.y + n)
        elif final == "C": self.x = min(self.cols - 1, self.x + n)
        elif final == "D": self.x = max(0, self.x - n)
        elif final == "G": self.x = min(self.cols - 1, n - 1)
        elif final == "d": self.y = min(self.rows - 1, n - 1)
        elif final == "s": self.saved = (self.x, self.y)
        elif final == "u": self.x, self.y = self.saved
        elif final == "J":
            position = self.y * self.cols + self.x
            for y in range(self.rows):
                for x in range(self.cols):
                    i = y * self.cols + x
                    if p[0] in (2, 3) or (p[0] == 0 and i >= position) or (p[0] == 1 and i <= position):
                        self.grid[y][x] = self.blank()
        elif final == "K":
            for x in range(self.cols):
                if p[0] == 2 or (p[0] == 0 and x >= self.x) or (p[0] == 1 and x <= self.x):
                    self.grid[self.y][x] = self.blank()
        elif final == "m":
            for v in p:
                if v == 0: self.fg, self.bg, self.bold, self.inverse = 7, 0, False, False
                elif v == 1: self.bold = True
                elif v == 22: self.bold = False
                elif v == 7: self.inverse = True
                elif v == 27: self.inverse = False
                elif 30 <= v <= 37: self.fg = v - 30
                elif 40 <= v <= 47: self.bg = v - 40
                elif 90 <= v <= 97: self.fg = v - 90 + 8
                elif 100 <= v <= 107: self.bg = v - 100 + 8
                elif v == 39: self.fg = 7
                elif v == 49: self.bg = 0
        elif final in "hl" and private:
            if 25 in p: self.visible = final == "h"
        elif final == "r":
            top = n - 1
            bottom = (p[1] if len(p) > 1 and p[1] else self.rows) - 1
            if 0 <= top < bottom < self.rows:
                self.top, self.bottom = top, bottom
                self.x, self.y = 0, 0
        elif final == "P":
            n = min(n, self.cols - self.x)
            row = self.grid[self.y]
            self.grid[self.y] = row[:self.x] + row[self.x + n:] + [self.blank()] * n
        elif final == "@":
            n = min(n, self.cols - self.x)
            row = self.grid[self.y]
            self.grid[self.y] = (row[:self.x] + [self.blank()] * n + row[self.x:])[:self.cols]
        elif final == "X":
            for x in range(self.x, min(self.cols, self.x + n)):
                self.grid[self.y][x] = self.blank()
        elif final == "L":
            for _ in range(min(n, self.bottom - self.y + 1)):
                self.grid.insert(self.y, [self.blank()] * self.cols)
                del self.grid[self.bottom + 1]
        elif final == "M":
            for _ in range(min(n, self.bottom - self.y + 1)):
                del self.grid[self.y]
                self.grid.insert(self.bottom, [self.blank()] * self.cols)

    def text(self):
        return "\n".join("".join(c[0] for c in row) for row in self.grid)


class Process:
    def __init__(self, argv, cwd, emit, cols=80, rows=25):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        env = dict(os.environ, TERM="xterm", COLUMNS=str(cols), LINES=str(rows))
        try:
            self.child = subprocess.Popen(argv, cwd=cwd, stdin=slave, stdout=slave, stderr=slave,
                                          env=env, start_new_session=True, close_fds=True)
        except BaseException:
            os.close(self.master)
            raise
        finally:
            os.close(slave)
        self.emit = emit
        self.closed = False
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        try:
            while True:
                readable, _, _ = select.select([self.master], [], [], .15)
                if readable:
                    try:
                        raw = os.read(self.master, 16384)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not raw:
                        break
                    self.emit("output", decoder.decode(raw))
                elif self.child.poll() is not None:
                    break
            tail = decoder.decode(b"", final=True)
            if tail:
                self.emit("output", tail)
        except OSError:
            pass
        finally:
            os.close(self.master)
            self.closed = True
            self.emit("exit", self.child.wait())

    def write(self, value):
        if not self.closed:
            try:
                if value == b"\x03":
                    os.killpg(self.child.pid, signal.SIGINT)
                    return
                os.write(self.master, value)
            except OSError:
                pass

    def stop(self):
        if self.child.poll() is None:
            try:
                os.killpg(self.child.pid, signal.SIGTERM)
            except ProcessLookupError:
                return
            threading.Timer(1, self._kill).start()

    def _kill(self):
        if self.child.poll() is None:
            try:
                os.killpg(self.child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


class TerminalView(tk.Text):
    def __init__(self, master, font, send):
        super().__init__(master, bg="#000000", fg="#aaaaaa", insertbackground="#ffffff", font=font,
                         width=80, height=25, wrap="none", borderwidth=0, highlightthickness=0,
                         padx=8, pady=6, cursor="xterm", exportselection=False)
        self.screen = Screen()
        self.send = send
        self.bind("<Key>", self.key)
        self.bind("<<Paste>>", self.paste)
        self.bind("<Button-1>", lambda e: self.focus_set())
        for f in range(16):
            for b in range(16):
                self.tag_configure(f"c{f}_{b}", foreground=PALETTE[f], background=PALETTE[b])
        self.render()

    def paste(self, event=None):
        try:
            self.send(self.clipboard_get().replace("\r\n", "\n").replace("\n", "\r").encode())
        except tk.TclError:
            pass
        return "break"

    def key(self, e):
        if e.keysym in KEYS:
            self.send(KEYS[e.keysym])
        elif e.char:
            self.send(e.char.encode())
        return "break"

    def feed(self, data):
        self.screen.feed(data)

    def render(self):
        self.delete("1.0", "end")
        for y, row in enumerate(self.screen.grid):
            start, current = 0, row[0][1:]
            for x in range(1, self.screen.cols + 1):
                if x == self.screen.cols or row[x][1:] != current:
                    text = "".join(c[0] for c in row[start:x])
                    self.insert("end", text, f"c{current[0]}_{current[1]}")
                    if x < self.screen.cols:
                        start, current = x, row[x][1:]
            if y < self.screen.rows - 1:
                self.insert("end", "\n")
        self.mark_set("insert", f"{self.screen.y+1}.{self.screen.x}")
        self.configure(insertwidth=2 if self.screen.visible else 0)
