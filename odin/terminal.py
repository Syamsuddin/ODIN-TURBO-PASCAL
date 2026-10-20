# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""TerminalView, the Tk widget that shows the User screen.

The screen model and the process driver live in odin/console.py, which needs no Tk; they are
re-exported here so existing imports keep working."""
from __future__ import annotations

import tkinter as tk

from .console import (  # noqa: F401  (re-exported)
    ALT_MASKS, DEC_GRAPHICS, KEYS, MOUSE_MODES, OPTION_CHARS, PALETTE, Process,
    PtyProcess, Screen, color_256, modified_key, mouse_report, nearest_color)


class TerminalView(tk.Text):
    def __init__(self, master, font, send):
        super().__init__(master, bg="#000000", fg="#aaaaaa", insertbackground="#ffffff", font=font,
                         width=80, height=25, wrap="none", borderwidth=0, highlightthickness=0,
                         padx=8, pady=6, cursor="xterm", exportselection=False)
        self.screen = Screen()
        self.send = send
        system = self.tk.call("tk", "windowingsystem")
        self.aqua = system == "aqua"
        self.win32 = system == "win32"
        self.alt_mask = ALT_MASKS.get(system, ALT_MASKS["x11"])
        self.buttons = set()      # xterm button codes held down
        self.last_cell = None
        self.bind("<Key>", self.key)
        self.bind("<<Paste>>", self.paste)
        for n in (1, 2, 3):
            self.bind(f"<ButtonPress-{n}>", lambda e, n=n: self.mouse_button(e, n, False))
            self.bind(f"<ButtonRelease-{n}>", lambda e, n=n: self.mouse_button(e, n, True))
        self.bind("<Motion>", self.mouse_motion)
        self.bind("<MouseWheel>", lambda e: self.mouse_wheel(e, e.delta > 0))
        self.bind("<Button-4>", lambda e: self.mouse_wheel(e, True))
        self.bind("<Button-5>", lambda e: self.mouse_wheel(e, False))
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
        shift = bool(e.state & 0x0001)
        ctrl = bool(e.state & 0x0004)
        alt = bool(e.state & self.alt_mask)
        if e.keysym == "ISO_Left_Tab" or (e.keysym == "Tab" and shift):
            self.send(b"\x1b[Z")
        elif self.win32 and ctrl and alt and e.char and e.char.isprintable():
            # AltGr on Windows arrives as Ctrl+Alt and types a character (@, {, € ...).
            self.send(e.char.encode())
        elif e.keysym in KEYS:
            sequence = KEYS[e.keysym]
            if sequence.startswith(b"\x1b") and len(sequence) > 1 and e.keysym != "Escape":
                sequence = modified_key(sequence, 1 + shift + 2 * alt + 4 * ctrl)
            elif alt:
                sequence = b"\x1b" + sequence
            self.send(sequence)
        elif alt and len(e.keysym) == 1 and e.keysym.isascii() and e.keysym.isalnum():
            self.send(b"\x1b" + e.keysym.lower().encode())
        elif alt and e.char in OPTION_CHARS:
            self.send(b"\x1b" + OPTION_CHARS[e.char].encode())
        elif e.char:
            self.send(e.char.encode())
        return "break"

    def cell(self, e):
        line, column = self.index(f"@{e.x},{e.y}").split(".")
        return (max(0, min(int(column), self.screen.cols - 1)), max(0, min(int(line) - 1, self.screen.rows - 1)))

    def mouse_button(self, e, number, release):
        """Reports a click when the program turned on mouse tracking (Odin Vision, Free Vision)."""
        self.focus_set()
        if not self.screen.mouse:
            return None
        # Tk numbers the right button 2 on macOS and 3 elsewhere.
        code = {1: 0, 2: 2, 3: 1}[number] if self.aqua else {1: 0, 2: 1, 3: 2}[number]
        x, y = self.cell(e)
        if release:
            self.buttons.discard(code)
        else:
            self.buttons.add(code)
        if not release or self.screen.mouse != {9}:
            self.send(mouse_report(code, x, y, release, self.screen.sgr_mouse))
        self.last_cell = (x, y)
        return "break"

    def mouse_motion(self, e):
        modes = self.screen.mouse
        if not modes or not ({1002, 1003} & modes):
            return None
        if not self.buttons and 1003 not in modes:
            return "break"
        x, y = self.cell(e)
        if (x, y) == self.last_cell:
            return "break"
        self.last_cell = (x, y)
        code = (min(self.buttons) if self.buttons else 3) + 32
        self.send(mouse_report(code, x, y, False, self.screen.sgr_mouse))
        return "break"

    def mouse_wheel(self, e, up):
        if not self.screen.mouse:
            return None
        x, y = self.cell(e)
        self.send(mouse_report(64 if up else 65, x, y, False, self.screen.sgr_mouse))
        return "break"

    def feed(self, data):
        self.screen.feed(data)
        while self.screen.replies:
            self.send(self.screen.replies.pop(0))

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
