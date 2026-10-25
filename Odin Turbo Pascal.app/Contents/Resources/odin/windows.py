# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Child windows of the IDE's workspace (MDI): the Pascal Editor, the Output console, compiler Messages and the
debugger's Watches, Local variables and Call stack."""
from __future__ import annotations

import re
import tkinter as tk
from bisect import bisect_right
from tkinter import font as tkfont
from tkinter import ttk

from .core import syntax_spans
from .terminal import Screen, TerminalView

# Editor themes: background, text, cursor, selection, current line, gutter background, gutter text, and the color
# of each kind syntax_spans() yields.
THEMES = {
    "light": dict(bg="#ffffff", fg="#1f1f1f", cursor="#000000", select="#add6ff", line="#f3f6fb", gutter="#f5f5f5",
                  number="#9a9a9a", syntax={"reserved": "#0000c8", "identifier": "#1f1f1f", "routine": "#795e26",
                                            "builtin": "#267f99", "type": "#1c7c4c", "constant": "#9a3fb5",
                                            "number": "#098658", "string": "#a31515", "operator": "#3c3c3c",
                                            "comment": "#2f8a2f", "directive": "#af00db"}),
    "dark": dict(bg="#1e1e1e", fg="#d4d4d4", cursor="#aeafad", select="#264f78", line="#2a2d2e", gutter="#1e1e1e",
                 number="#858585", syntax={"reserved": "#569cd6", "identifier": "#d4d4d4", "routine": "#dcdcaa",
                                           "builtin": "#4ec9b0", "type": "#4ec9b0", "constant": "#c586c0",
                                           "number": "#b5cea8", "string": "#ce9178", "operator": "#d4d4d4",
                                           "comment": "#6a9955", "directive": "#c586c0"}),
}
SYNTAX_KINDS = tuple(THEMES["light"]["syntax"])
# Kinds drawn in a bold or italic editor font.
SYNTAX_FONTS = {"reserved": "bold", "comment": "italic"}
# Marks that keep their colors in both themes: compile error, search hit, debugger execution line, breakpoint.
ERROR_BG, FOUND_BG, EXEC_BG, BREAKPOINT = "#f14c4c", "#ffd33d", "#3fb950", "#e51400"
# Appended to the title of an editor with unsaved changes.
DIRTY = " ●"

# Window chrome: the workspace behind the child windows, title bars of the active and the other windows (background,
# text), the frame around a window, and the close button under the mouse.
WORKSPACE = "#c8cdd5"
TITLE_ACTIVE = ("#2b5797", "#ffffff")
TITLE_INACTIVE = ("#e4e6ea", "#5f6368")
FRAME_ACTIVE, FRAME_INACTIVE = "#2b5797", "#9aa0a8"
WINDOW_BG = "#f3f3f3"
CLOSE_HOVER = "#e81123"
# The smallest console font Fit Output uses.
FIT_SMALLEST = 7
# Pixels of frame that resize a window, the smallest window, and the width of a minimized window.
GRIP, MIN_WIDTH, MIN_HEIGHT, ICON_WIDTH = 4, 220, 110, 200
# Cursors over each edge and corner (X11 names, which Tk maps on every platform).
EDGE_CURSORS = {"n": "sb_v_double_arrow", "s": "sb_v_double_arrow", "e": "sb_h_double_arrow", "w": "sb_h_double_arrow",
                "nw": "top_left_corner", "se": "bottom_right_corner", "ne": "top_right_corner",
                "sw": "bottom_left_corner"}


class Tooltip:
    """A small label under widget after the mouse rests on it, as toolbar buttons have."""
    DELAY = 600

    def __init__(self, widget, text):
        self.widget, self.text = widget, text
        self.job = self.window = None
        widget.bind("<Enter>", self.schedule, add="+")
        for sequence in ("<Leave>", "<ButtonPress>"):
            widget.bind(sequence, self.hide, add="+")

    def schedule(self, event=None):
        self.hide()
        self.job = self.widget.after(self.DELAY, self.show)

    def show(self):
        self.job = None
        if not self.widget.winfo_exists():
            return
        self.window = tk.Toplevel(self.widget)
        self.window.wm_overrideredirect(True)
        tk.Label(self.window, text=self.text, bg="#ffffe1", fg="#1f1f1f", relief="solid", borderwidth=1,
                 padx=6, pady=2).pack()
        self.window.geometry(f"+{self.widget.winfo_rootx()}+{self.widget.winfo_rooty() + self.widget.winfo_height() + 4}")

    def hide(self, event=None):
        if self.job:
            self.widget.after_cancel(self.job)
            self.job = None
        if self.window:
            self.window.destroy()
            self.window = None


class ChildWindow:
    """A window inside App.workspace with its own title bar (title, minimize, maximize and close). It moves by its
    title bar, resizes from its frame, and is placed, activated and arranged by App (add_window, activate, tile,
    cascade). Subclasses fill self.body and call self.track(widget) on widgets that take clicks or focus."""
    label = ""

    def __init__(self, app, title=""):
        self.app = app
        self.state = "normal"           # normal, maximized or minimized
        self.restore_place = None       # place() options to come back to from maximized or minimized
        self.active = False
        self.frame = tk.Frame(app.workspace, bg=WINDOW_BG, highlightthickness=1, highlightbackground=FRAME_INACTIVE,
                              highlightcolor=FRAME_INACTIVE, borderwidth=0)
        self.titlebar = tk.Frame(self.frame, bg=TITLE_INACTIVE[0], height=26)
        self.titlebar.pack(fill="x", padx=GRIP - 1, pady=(GRIP - 1, 0))
        self.titlebar.pack_propagate(False)
        self.title = tk.Label(self.titlebar, text=title, anchor="w", bg=TITLE_INACTIVE[0], fg=TITLE_INACTIVE[1],
                              font=app.ui_font(12, "bold"), padx=8)
        self.buttons = {}
        for name, glyph in (("close", "✕"), ("maximize", "□"), ("minimize", "—")):
            button = tk.Label(self.titlebar, text=glyph, width=3, bg=TITLE_INACTIVE[0], fg=TITLE_INACTIVE[1],
                              font=app.ui_font(11))
            button.pack(side="right", fill="y")
            button.bind("<Enter>", lambda e, n=name: self.hover(n, True))
            button.bind("<Leave>", lambda e, n=name: self.hover(n, False))
            self.buttons[name] = button
        self.buttons["close"].bind("<ButtonRelease-1>", lambda e: app.close_window(self))
        self.buttons["maximize"].bind("<ButtonRelease-1>", lambda e: app.zoom(self))
        self.buttons["minimize"].bind("<ButtonRelease-1>", lambda e: app.minimize(self))
        self.title.pack(side="left", fill="both", expand=True)
        for widget in (self.titlebar, self.title):
            widget.bind("<ButtonPress-1>", self.drag_start)
            widget.bind("<B1-Motion>", self.drag)
            widget.bind("<Double-Button-1>", lambda e: app.zoom(self))
        self.body = ttk.Frame(self.frame)
        self.body.pack(fill="both", expand=True, padx=GRIP - 1, pady=(0, GRIP - 1))
        self.frame.bind("<Motion>", self.edge_cursor)
        self.frame.bind("<ButtonPress-1>", self.resize_start)
        self.frame.bind("<B1-Motion>", self.resize)
        self.edge = None

    # ---- title ----------------------------------------------------------------------------

    def set_title(self, text):
        self.title.configure(text=text)

    def list_label(self):
        """Label shown in the Window menu."""
        return self.title.cget("text")

    def track(self, widget):
        """Clicks and focus in widget make this the active window."""
        widget.bind("<FocusIn>", lambda e: self.app.activate(self, focus=False), add="+")
        widget.bind("<ButtonPress-1>", lambda e: self.app.activate(self, focus=False), add="+")

    def set_active(self, active):
        self.active = active
        bg, fg = TITLE_ACTIVE if active else TITLE_INACTIVE
        frame = FRAME_ACTIVE if active else FRAME_INACTIVE
        self.frame.configure(highlightbackground=frame, highlightcolor=frame)
        self.titlebar.configure(bg=bg)
        for widget in (self.title, *self.buttons.values()):
            widget.configure(bg=bg, fg=fg)

    def hover(self, name, inside):
        bg, fg = TITLE_ACTIVE if self.active else TITLE_INACTIVE
        if inside:
            bg, fg = (CLOSE_HOVER, "#ffffff") if name == "close" else ("#3c6cb4" if self.active else "#d0d3d8", fg)
        self.buttons[name].configure(bg=bg, fg=fg)

    def focus(self):
        self.frame.focus_set()

    def destroy(self):
        self.frame.destroy()

    # ---- moving and resizing ---------------------------------------------------------------

    def geometry(self):
        """(x, y, width, height) in the workspace."""
        return self.frame.winfo_x(), self.frame.winfo_y(), self.frame.winfo_width(), self.frame.winfo_height()

    def place_at(self, x, y, width, height):
        self.frame.place_forget()
        self.frame.place(x=x, y=y, width=max(MIN_WIDTH, width), height=max(MIN_HEIGHT, height))

    def set_state(self, state):
        """normal, maximized or minimized; App.zoom, minimize and restore call this."""
        if state == self.state:
            return
        if self.state == "normal":
            self.restore_place = self.frame.place_info()
        if state == "minimized":
            self.body.pack_forget()
        elif self.state == "minimized":
            self.body.pack(fill="both", expand=True, padx=GRIP - 1, pady=(0, GRIP - 1))
        self.frame.place_forget()
        if state == "maximized":
            self.frame.place(x=0, y=0, relwidth=1, relheight=1)
        elif state == "normal" and self.restore_place:
            self.frame.place(**{k: v for k, v in self.restore_place.items() if k != "in"})
        self.buttons["maximize"].configure(text="❐" if state != "normal" else "□")
        self.state = state

    def drag_start(self, e):
        self.app.activate(self)
        x, y, _, _ = self.geometry()
        self.drag_anchor = (e.x_root, e.y_root, x, y)

    def drag(self, e):
        if self.state == "maximized":
            return
        x0, y0, left, top = self.drag_anchor
        _, _, width, height = self.geometry()
        workspace = self.app.workspace
        # Keep the title bar reachable.
        x = min(max(left + e.x_root - x0, 60 - width), workspace.winfo_width() - 60)
        y = min(max(top + e.y_root - y0, 0), max(0, workspace.winfo_height() - 26))
        if self.state == "minimized":
            self.frame.place_configure(x=x, y=y)
        else:
            self.place_at(x, y, width, height)

    def edge_at(self, e):
        if self.state != "normal":
            return None
        width, height = self.frame.winfo_width(), self.frame.winfo_height()
        vertical = "n" if e.y < GRIP + 2 else "s" if e.y >= height - GRIP - 2 else ""
        horizontal = "w" if e.x < GRIP + 2 else "e" if e.x >= width - GRIP - 2 else ""
        return (vertical + horizontal) or None

    def edge_cursor(self, e):
        self.frame.configure(cursor=EDGE_CURSORS.get(self.edge_at(e), ""))

    def resize_start(self, e):
        self.app.activate(self)
        self.edge = self.edge_at(e)
        self.resize_anchor = (e.x_root, e.y_root, *self.geometry())

    def resize(self, e):
        if not self.edge:
            return
        x0, y0, x, y, width, height = self.resize_anchor
        dx, dy = e.x_root - x0, e.y_root - y0
        if "e" in self.edge:
            width += dx
        if "s" in self.edge:
            height += dy
        if "w" in self.edge:
            dx = min(dx, width - MIN_WIDTH)
            x, width = x + dx, width - dx
        if "n" in self.edge:
            dy = min(dy, height - MIN_HEIGHT)
            y, height = y + dy, height - dy
        self.place_at(x, y, width, height)


class Editor(ChildWindow):
    def __init__(self, app, document, number):
        super().__init__(app)
        self.document, self.number = document, number
        body = self.body
        body.rowconfigure(0, weight=1)
        body.columnconfigure(1, weight=1)
        # Line numbers, breakpoints and the execution arrow. Colors come from apply_options().
        self.gutter = tk.Canvas(body, width=48, highlightthickness=0, borderwidth=0)
        self.gutter.grid(row=0, column=0, sticky="ns")
        self.text = tk.Text(body, font=app.font, wrap="none", undo=True, maxundo=500, borderwidth=0,
                            highlightthickness=0, padx=6, pady=4, exportselection=False, insertwidth=2,
                            insertontime=550, insertofftime=350, width=20, height=4)
        self.text.grid(row=0, column=1, sticky="nsew")
        self.scrollbar = ttk.Scrollbar(body, orient="vertical", command=self.text.yview)
        self.scrollbar.grid(row=0, column=2, sticky="ns")
        horizontal = ttk.Scrollbar(body, orient="horizontal", command=self.text.xview)
        horizontal.grid(row=1, column=1, sticky="ew")
        self.text.configure(yscrollcommand=lambda a, b: (self.scrollbar.set(a, b), self.draw_gutter()),
                            xscrollcommand=horizontal.set)
        self.text.insert("1.0", document.text)
        self.text.mark_set("insert", "1.0")
        self.text.edit_reset()
        self.text.edit_modified(False)
        # Configured first, so the marks below take priority over syntax colors; "line" (the current line) is
        # lowest of all.
        self.text.tag_configure("line")
        for name in SYNTAX_KINDS:
            self.text.tag_configure(name)
        self.text.tag_configure("error", background=ERROR_BG, foreground="#ffffff")
        self.text.tag_configure("found", background=FOUND_BG, foreground="#000000")
        # The debugger's execution bar: the statement that runs next.
        self.text.tag_configure("exec", background=EXEC_BG, foreground="#ffffff")
        self.text.tag_configure("metric", underline=True)
        self.exec_line = None
        self.breakpoint_count = 0
        # App's shortcuts come before the Text class bindings (Ctrl+H, Ctrl+O and Ctrl+T edit text on X11).
        self.text.bindtags((str(self.text), "OdinKeys", "Text", ".", "all"))
        self.text.bind("<<Modified>>", self.modified)
        self.text.bind("<FocusIn>", lambda e: app.activate(self, focus=False))
        self.text.bind("<KeyRelease>", lambda e: self.cursor_moved())
        self.text.bind("<ButtonRelease-1>", lambda e: self.cursor_moved())
        self.text.bind("<Return>", self.newline)
        self.text.bind("<Tab>", self.tab)
        self.text.bind("<Shift-Tab>", self.unindent)
        self.text.bind("<ISO_Left_Tab>", self.unindent)
        self.text.bind("<Insert>", self.toggle_insert)
        self.text.bind("<KeyPress>", self.overwrite)
        for button in ("<Button-2>", "<Button-3>") if self.text.tk.call("tk", "windowingsystem") == "aqua" else ("<Button-3>",):
            self.text.bind(button, self.context_menu)
        self.gutter.bind("<Button-1>", self.gutter_click)
        self.track(self.gutter)
        self.text.bind("<Configure>", lambda e: self.draw_gutter())
        self.overwrite_mode = False
        self.win32 = self.text.tk.call("tk", "windowingsystem") == "win32"
        self.highlight_job = None
        self.apply_options()
        self.update_title()
        self.cursor_moved(notify=False)

    def caption(self):
        doc = self.document
        name = doc.path.name if doc.path else f"NONAME{self.number:02d}.PAS"
        return name + DIRTY if doc.dirty else name

    def list_label(self):
        return self.document.path.name if self.document.path else f"NONAME{self.number}"

    def focus(self):
        self.text.focus_set()

    def destroy(self):
        if self.highlight_job:
            self.app.root.after_cancel(self.highlight_job)
        super().destroy()

    def theme(self):
        return THEMES.get(self.app.settings["theme"], THEMES["light"])

    def apply_options(self):
        theme = self.theme()
        self.text.configure(tabs=(self.app.font.measure(" " * self.app.settings["tab_width"]),), bg=theme["bg"],
                            fg=theme["fg"], insertbackground=theme["cursor"], selectbackground=theme["select"],
                            selectforeground=theme["fg"], inactiveselectbackground=theme["select"])
        self.text.tag_configure("line", background=theme["line"])
        self.gutter.configure(bg=theme["gutter"])
        # Set here, not once in __init__, so the bold and italic fonts follow the editor font size.
        family, size = self.app.font.cget("family"), self.app.font.cget("size")
        for name, color in theme["syntax"].items():
            self.text.tag_configure(name, foreground=color, font=(family, size, SYNTAX_FONTS[name])
                                    if name in SYNTAX_FONTS else "")
        self.highlight()
        self.draw_gutter()

    def update_title(self):
        self.set_title(self.caption())
        self.app.window_title_changed(self)

    def modified(self, event=None):
        if not self.text.edit_modified():
            return
        self.document.text = self.text.get("1.0", "end-1c")
        self.text.edit_modified(False)
        self.text.tag_remove("error", "1.0", "end")
        self.update_title()
        if self.highlight_job:
            self.app.root.after_cancel(self.highlight_job)
        self.highlight_job = self.app.root.after(180, self.highlight)
        self.cursor_moved()
        if self.sync_breakpoints():
            self.app.breakpoints_changed(self)
        self.draw_gutter()
        self.app.source_modified(self)

    def cursor_moved(self, notify=True):
        """Moves the current-line band to the insert line and updates the status bar."""
        self.text.tag_remove("line", "1.0", "end")
        self.text.tag_add("line", "insert linestart", "insert lineend+1c")
        self.text.tag_lower("line")
        if notify:
            self.app.user_input()

    def highlight(self):
        self.highlight_job = None
        for name in SYNTAX_KINDS:
            self.text.tag_remove(name, "1.0", "end")
        if self.app.settings["syntax_colors"]:
            # One tag_add per kind, with line.column indices: a "1.0+Nc" index makes Tk count from the top each time.
            text = self.text.get("1.0", "end-1c")
            starts = [0] + [match.end() for match in re.finditer("\n", text)]
            def index(offset):
                line = bisect_right(starts, offset)
                return f"{line}.{offset - starts[line - 1]}"
            ranges = {}
            for name, start, end in syntax_spans(text):
                ranges.setdefault(name, []).extend((index(start), index(end)))
            for name, indices in ranges.items():
                self.text.tag_add(name, *indices)
        self.text.tag_raise("sel")

    def newline(self, event=None):
        line = self.text.get("insert linestart", "insert")
        indent = re.match(r"[ \t]*", line).group()
        self.remove_selection()
        self.text.insert("insert", "\n" + indent)
        self.text.see("insert")
        self.cursor_moved()
        return "break"

    def remove_selection(self):
        if self.text.tag_ranges("sel"):
            self.text.delete("sel.first", "sel.last")

    def tab(self, event=None):
        self.remove_selection()
        width = self.app.settings["tab_width"]
        column = int(self.text.index("insert").split(".")[1])
        self.text.insert("insert", " " * (width - column % width))
        return "break"

    def unindent(self, event=None):
        start = self.text.index("insert linestart")
        line = self.text.get(start, "insert lineend")
        spaces = len(line) - len(line.lstrip(" "))
        self.text.delete(start, f"{start}+{min(spaces, self.app.settings['tab_width'])}c")
        return "break"

    def toggle_insert(self, event=None):
        self.overwrite_mode = not self.overwrite_mode
        self.app.update_status()
        return "break"

    def command_key(self, e):
        """Control or Mod1 (Command on macOS, Alt on X11) held: a shortcut, not typing. On Windows
        Mod1 is Num Lock and Alt is Tk's ALT_MASK (0x20000); AltGr arrives as Control+Alt and types."""
        if self.win32:
            held = e.state & 0x20004
            return bool(held) and held != 0x20004
        return bool(e.state & 0x0c)

    def overwrite(self, e):
        if self.overwrite_mode and e.char and e.char.isprintable() and not self.command_key(e) and not self.text.tag_ranges("sel"):
            if self.text.get("insert", "insert+1c") != "\n":
                self.text.delete("insert", "insert+1c")

    def context_menu(self, e):
        if not self.text.tag_ranges("sel"):
            self.text.mark_set("insert", f"@{e.x},{e.y}")
        self.cursor_moved()
        menu = tk.Menu(self.text, tearoff=False)
        for label, action in (("Cut", "cut"), ("Copy", "copy"), ("Paste", "paste")):
            menu.add_command(label=label, command=lambda a=action: self.app.edit(a))
        menu.add_separator()
        menu.add_command(label="Toggle breakpoint", command=self.toggle_breakpoint)
        menu.add_command(label="Add watch...", command=self.app.add_watch)
        menu.add_command(label="Evaluate/Modify...", command=self.app.evaluate)
        menu.add_command(label="Go to cursor", command=lambda: self.app.debug_step("cursor"))
        menu.add_separator()
        menu.add_command(label="Help on word", command=self.app.help_topic)
        menu.tk_popup(e.x_root, e.y_root)
        return "break"

    def gutter_click(self, e):
        line = int(self.text.index(f"@0,{e.y}").split(".")[0])
        self.toggle_breakpoint(line)

    # Breakpoints are Tk marks at the start of their line, so they move with lines inserted or
    # deleted above them; document.breakpoints is recomputed from the marks.
    def breakpoint_marks(self):
        return [m for m in self.text.mark_names() if m.startswith("bp")]

    def add_breakpoint_mark(self, line):
        self.breakpoint_count += 1
        name = f"bp{self.breakpoint_count}"
        self.text.mark_set(name, f"{line}.0")
        # Right gravity: Enter at the start of the line pushes the mark down with the code.
        self.text.mark_gravity(name, "right")

    def sync_breakpoints(self):
        """Updates document.breakpoints from the marks; True when the set of lines changed."""
        lines = {}
        for name in self.breakpoint_marks():
            line = int(self.text.index(name).split(".")[0])
            if line in lines:
                self.text.mark_unset(name)
            else:
                lines[line] = name
                if self.text.index(name) != f"{line}.0":
                    self.text.mark_set(name, f"{line}.0")
        points = self.document.breakpoints
        changed = set(lines) != points
        points.clear()
        points.update(lines)
        return changed

    def set_breakpoints(self, lines, notify=True):
        for name in self.breakpoint_marks():
            self.text.mark_unset(name)
        last = int(self.text.index("end-1c").split(".")[0])
        for line in lines:
            if 1 <= int(line) <= last:
                self.add_breakpoint_mark(int(line))
        self.sync_breakpoints()
        self.draw_gutter()
        if notify:
            self.app.breakpoints_changed(self)

    def toggle_breakpoint(self, line=None):
        line = line or int(self.text.index("insert").split(".")[0])
        self.sync_breakpoints()
        lines = set(self.document.breakpoints)
        lines.symmetric_difference_update({line})
        self.set_breakpoints(lines)

    def show_exec(self, line):
        self.text.tag_remove("exec", "1.0", "end")
        self.text.tag_add("exec", f"{line}.0", f"{line}.0 lineend+1c")
        self.text.tag_raise("exec")
        self.text.tag_raise("sel")
        self.exec_line = line
        self.text.mark_set("insert", f"{line}.0")
        self.text.see(f"{line}.0")
        self.cursor_moved(notify=False)
        self.draw_gutter()

    def clear_exec(self):
        self.text.tag_remove("exec", "1.0", "end")
        self.exec_line = None
        self.draw_gutter()

    def draw_gutter(self):
        """Line numbers of the visible lines, a red dot on breakpoint lines and an arrow on the execution line."""
        if not self.gutter.winfo_exists():
            return
        theme = self.theme()
        last = int(self.text.index("end-1c").split(".")[0])
        width = self.app.font.measure("9" * max(3, len(str(last)))) + 30
        if int(self.gutter.cget("width")) != width:
            self.gutter.configure(width=width)
        self.gutter.delete("all")
        index = self.text.index("@0,0")
        while True:
            info = self.text.dlineinfo(index)
            if info is None:
                break
            line = int(index.split(".")[0])
            y = info[1] + info[3] // 2
            self.gutter.create_text(width - 8, y, anchor="e", text=str(line), font=self.app.font,
                                    fill=theme["fg"] if line == self.exec_line else theme["number"])
            if line in self.document.breakpoints:
                self.gutter.create_oval(5, y - 6, 17, y + 6, fill=BREAKPOINT, outline="")
            if line == self.exec_line:
                self.gutter.create_polygon(8, y - 6, 18, y, 8, y + 6, fill=EXEC_BG, outline="#ffffff")
            following = self.text.index(f"{index}+1line")
            if following == index:
                break
            index = following

    # Kept for callers of the desktop IDE's name.
    draw_breakpoints = draw_gutter


class OutputWindow(ChildWindow):
    """The program's console: Run, Debug and Ukur run the program here on a PTY (ConPTY on Windows), so Crt,
    Graph's text preview and Odin Vision work as on a terminal. Keys typed here go to the program."""
    label = "Output"

    def __init__(self, app):
        super().__init__(app, self.label)
        self.console = TerminalView(self.body, app.console_font, app.send_input)
        self.console.configure(width=20, height=4)
        bar = ttk.Scrollbar(self.body, orient="vertical", command=self.console.yview)
        self.console.configure(yscrollcommand=bar.set)
        bar.pack(side="right", fill="y")
        self.console.pack(fill="both", expand=True)
        self.track(self.console)
        self.fit_job = None
        self.console.bind("<Configure>", self.schedule_fit, add="+")
        self.console.bind("<Control-F2>", lambda e: app.shortcut(app.stop))
        self.console.bind("<Alt-F5>", lambda e: app.shortcut(app.focus_editor))
        # While the debugger holds the program, F7/F8 step; otherwise they belong to the running
        # program (Crt.ReadKey, Odin Vision).
        self.console.bind("<F7>", lambda e: app.shortcut(lambda: app.debug_step("into")) if app.debug_stopped else self.console.key(e))
        self.console.bind("<F8>", lambda e: app.shortcut(lambda: app.debug_step("over")) if app.debug_stopped else self.console.key(e))
        menu_button = "<Button-2>" if self.console.aqua else "<Button-3>"
        self.console.unbind(menu_button)
        self.console.bind(menu_button, self.context_menu)

    def focus(self):
        self.console.focus_set()

    def schedule_fit(self, event=None):
        # On the root, like every timer of the IDE: App.cancel_callbacks cancels them there when it quits.
        root = self.app.root
        if self.fit_job:
            try:
                root.after_cancel(self.fit_job)
            except tk.TclError:
                pass
        self.fit_job = root.after(60, self.fit)

    def fit(self):
        """With Options > Environment > Fit Output: the largest console font, up to the Output font size, at which the
        80x25 screen fits in the window, so Crt and Odin Vision programs are not cut off."""
        self.fit_job = None
        if not self.console.winfo_exists():
            return
        largest = self.app.settings["console_font_size"]
        size = largest
        width, height = self.console.winfo_width(), self.console.winfo_height()
        if self.app.settings["fit_console"] and width > 50 and height > 50:
            probe = tkfont.Font(root=self.console, family=self.app.console_font.cget("family"), size=size)
            pad_x, pad_y = 2 * int(self.console.cget("padx")), 2 * int(self.console.cget("pady"))
            while size > FIT_SMALLEST:
                probe.configure(size=size)
                if (probe.measure("0") * self.console.screen.cols + pad_x <= width
                        and probe.metrics("linespace") * self.console.screen.rows + pad_y <= height):
                    break
                size -= 1
        if self.app.console_font.cget("size") != size:
            self.app.console_font.configure(size=size)

    def clear(self):
        self.console.screen = Screen()
        self.console.render()

    def context_menu(self, e):
        if self.console.screen.mouse:
            return self.console.mouse_button(e, 2 if self.console.aqua else 3, False)
        menu = tk.Menu(self.console, tearoff=False)
        menu.add_command(label="Copy screen", command=self.app.copy_screen)
        menu.add_command(label="Clear", command=self.clear)
        menu.add_command(label="Program reset", command=self.app.stop)
        menu.tk_popup(e.x_root, e.y_root)
        return "break"


class MessagesWindow(ChildWindow):
    """Compiler messages: one row per diagnostic (double click or Enter jumps to it), then the compiler command
    and its raw output."""
    label = "Messages"

    def __init__(self, app):
        super().__init__(app, self.label)
        self.list = ttk.Treeview(self.body, columns=("kind", "location", "message"), show="headings",
                                 selectmode="browse", height=4)
        for key, heading, width in (("kind", "Kind", 80), ("location", "Location", 160), ("message", "Message", 360)):
            self.list.heading(key, text=heading, anchor="w")
            self.list.column(key, width=width, anchor="w", stretch=key == "message")
        self.list.tag_configure("Error", foreground="#c42b1c")
        self.list.tag_configure("Warning", foreground="#9a6700")
        self.log = tk.Text(self.body, height=3, font=app.font, wrap="word", borderwidth=0, highlightthickness=0,
                           padx=6, pady=2, state="disabled", bg="#fafafa", fg="#444444")
        self.log.pack(side="bottom", fill="x")
        ttk.Separator(self.body).pack(side="bottom", fill="x")
        self.list.pack(fill="both", expand=True)
        self.list.bind("<Double-Button-1>", lambda e: app.jump_selected_message())
        self.list.bind("<Return>", lambda e: app.jump_selected_message())
        self.track(self.list)
        self.track(self.log)

    def focus(self):
        self.list.focus_set()

    def set_log(self, text):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.insert("1.0", text)
        self.log.configure(state="disabled")


class ListWindow(ChildWindow):
    """A window with one Treeview: the debugger's Watches, Local variables and Call stack.
    rows() and set_rows() work with plain strings joined by ": " so the debugger code stays the same."""
    columns = (("name", "Name", 140), ("value", "Value", 220))

    def __init__(self, app):
        super().__init__(app, self.label)
        self.tree = ttk.Treeview(self.body, columns=[c[0] for c in self.columns], show="headings",
                                 selectmode="browse", height=3)
        for key, heading, width in self.columns:
            self.tree.heading(key, text=heading, anchor="w")
            self.tree.column(key, width=width, anchor="w", stretch=key == self.columns[-1][0])
        bar = ttk.Scrollbar(self.body, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=bar.set)
        bar.pack(side="right", fill="y")
        self.tree.pack(fill="both", expand=True)
        self.track(self.tree)

    def focus(self):
        self.tree.focus_set()

    def rows(self):
        return [": ".join(str(v) for v in self.tree.item(item, "values")) for item in self.tree.get_children()]

    def set_rows(self, rows):
        """rows: tuples of column values, or "name: value" strings."""
        selected = self.selected()
        self.tree.delete(*self.tree.get_children())
        for row in rows:
            values = tuple(row.split(": ", 1)) if isinstance(row, str) else tuple(row)
            self.tree.insert("", "end", iid=str(len(self.tree.get_children())), values=values)
        if selected is not None and selected < len(rows):
            self.select(selected)

    def select(self, index):
        item = str(index)
        if self.tree.exists(item):
            self.tree.selection_set(item)
            self.tree.focus(item)
            self.tree.see(item)

    def selected(self):
        chosen = self.tree.selection()
        return int(chosen[0]) if chosen else None

    def destroy(self):
        self.app.debug_window_closed(self)
        super().destroy()


class WatchWindow(ListWindow):
    """Insert adds a watch, Delete removes the selected one, Enter or a double click edits it."""
    label = "Watches"
    columns = (("name", "Expression", 140), ("value", "Value", 220))

    def __init__(self, app):
        super().__init__(app)
        self.tree.bind("<Insert>", lambda e: (app.add_watch(), "break")[1])
        self.tree.bind("<Delete>", lambda e: (app.delete_watch(self.selected()), "break")[1])
        self.tree.bind("<BackSpace>", lambda e: (app.delete_watch(self.selected()), "break")[1])
        self.tree.bind("<Return>", lambda e: (app.edit_watch(self.selected()), "break")[1])
        self.tree.bind("<Double-Button-1>", lambda e: app.edit_watch(self.selected()))


class LocalsWindow(ListWindow):
    label = "Local variables"


class StackWindow(ListWindow):
    """Enter or a double click shows a frame; Watches and Local variables then use it."""
    label = "Call stack"
    columns = (("name", "Routine", 160), ("value", "Location", 200))

    def __init__(self, app):
        super().__init__(app)
        self.tree.bind("<Return>", lambda e: (app.select_frame(self.selected()), "break")[1])
        self.tree.bind("<Double-Button-1>", lambda e: app.select_frame(self.selected()))
