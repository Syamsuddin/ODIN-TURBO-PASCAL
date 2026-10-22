# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""GraphWindow: the window that shows the real pixels of a program that uses the Graph unit (see
odin/graphics.py for how the picture arrives). Keys typed in it go to the program like the User screen."""
from __future__ import annotations

import tkinter as tk

from .console import ALT_MASKS
from .graphics import png_base64
from .terminal import TerminalView


def zoom_factors(width, asp):
    """Integer zoom (x, y) for a mode: small modes are doubled, and the vertical zoom follows the pixel
    aspect (a 640x200 pixel is 2.3 times as tall as it is wide)."""
    zx = 1 if width >= 512 else 2 if width >= 256 else 4
    return zx, max(1, round(zx * 10000 / asp))


class GraphWindow(tk.Toplevel):
    # The same keyboard translation as the User screen; it needs send, win32 and alt_mask.
    key = TerminalView.key

    def __init__(self, master, send, title="Odin • Graph"):
        super().__init__(master, bg="#000000")
        self.send = send
        self.base_title = title
        self.title(title)
        system = self.tk.call("tk", "windowingsystem")
        self.win32 = system == "win32"
        self.alt_mask = ALT_MASKS.get(system, ALT_MASKS["x11"])
        self.label = tk.Label(self, bd=0, bg="#000000", highlightthickness=0, takefocus=True)
        self.label.pack()
        self.image = None
        self.size = (0, 0)
        self.protocol("WM_DELETE_WINDOW", self.withdraw)
        for widget in (self, self.label):
            widget.bind("<Key>", self.key)
        self.label.bind("<Button-1>", lambda e: self.label.focus_set())

    def show(self, visible, width, height, asp, data):
        """Shows the picture (PNG bytes); hides the window when the program is back in text mode."""
        if not visible:
            self.withdraw()
            return
        picture = tk.PhotoImage(master=self, data=png_base64(data), format="png")
        zx, zy = zoom_factors(width, asp)
        if (zx, zy) != (1, 1):
            picture = picture.zoom(zx, zy)
        self.image = picture
        self.label.configure(image=picture)
        if self.size != (width, height) or self.state() == "withdrawn":
            self.size = (width, height)
            self.geometry("")
            self.deiconify()
            self.lift()
            self.label.focus_set()

    def finished(self):
        self.title(f"{self.base_title} (selesai)")
