# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""MDI windows placed on the IDE desktop: shared window chrome and the Pascal editor."""
from __future__ import annotations

import re
import tkinter as tk
from bisect import bisect_right

from .core import syntax_spans

BLUE = "#0000aa"
CYAN = "#00aaaa"
WHITE = "#ffff55"
GRAY = "#aaaaaa"
BLACK = "#000000"

# Editor colors: background, text, cursor, selection background, selection text. CLASSIC is Turbo Pascal's yellow
# on blue, shown with Syntax colors off. TURBO_BIRU_LEMBUT, shown with them on, keeps a Turbo navy (Lazarus'
# "Pascal Classic" background) with softer pastel colors.
CLASSIC = (BLUE, WHITE, WHITE, GRAY, BLUE)
TURBO_BIRU_LEMBUT = ("#000080", "#f3e9a6", "#ffe680", "#3b4cc0", "#ffffff")
# Color for each kind syntax_spans() yields, and the kinds drawn in a bold or italic editor font.
SYNTAX_COLORS = {"reserved": "#ffffff", "identifier": "#f3e9a6", "routine": "#ffc66d", "builtin": "#8fe3ff",
                 "type": "#9ee6a0", "constant": "#f5a8d8", "number": "#f5a8d8", "string": "#7fe0c8",
                 "operator": "#b4c2ff", "comment": "#9aa8dc", "directive": "#ff9e9e"}
SYNTAX_FONTS = {"reserved": "bold", "comment": "italic"}


class DesktopWindow:
    """A frame placed on app.desktop with a [■] title [↕] bar; App manages layout and activation.

    Subclasses fill self.body and bind <FocusIn> on their focusable widgets to app.activate(self, focus=False),
    as Editor does. App.add_window() registers and places the window."""
    def __init__(self, app, title=""):
        self.app = app
        self.frame = tk.Frame(app.desktop, bg=CYAN, borderwidth=0, highlightbackground=GRAY, highlightthickness=2)
        self.titlebar = tk.Frame(self.frame, bg=GRAY)
        self.titlebar.pack(fill="x")
        # Flat Turbo Vision style: a raised square at each end, a bold title between them, a dark rule under the bar.
        button = dict(bg=GRAY, fg=BLACK, font=app.font, relief="raised", borderwidth=1, padx=5, pady=0, cursor="hand2")
        self.close_label = tk.Label(self.titlebar, text="\u25a0", **button)
        self.close_label.pack(side="left", padx=(3, 0), pady=2)
        self.close_label.bind("<Button-1>", lambda e: app.close_window(self))
        self.zoom_label = tk.Label(self.titlebar, text="\u2195", **button)
        self.zoom_label.pack(side="right", padx=(0, 3), pady=2)
        self.zoom_label.bind("<Button-1>", lambda e: app.zoom(self))
        self.title = tk.Label(self.titlebar, bg=GRAY, fg=BLUE, font=(app.font.cget("family"), app.font.cget("size"), "bold"), pady=0)
        self.title.pack(side="left", expand=True, fill="x")
        self.rule = tk.Frame(self.frame, bg=BLACK, height=1)
        self.rule.pack(fill="x")
        self.body = tk.Frame(self.frame, bg=BLUE)
        self.body.pack(fill="both", expand=True, padx=3, pady=(0, 3))
        self.title.bind("<Button-1>", self.drag_start)
        self.title.bind("<B1-Motion>", self.drag)
        self.title.bind("<Double-Button-1>", lambda e: app.zoom(self))
        if title:
            self.set_title(title)

    def set_title(self, text):
        self.title.configure(text=f"\u2550\u2561 {text} \u255e\u2550")

    def list_label(self):
        """Label shown in Window > List."""
        return self.title.cget("text").strip("\u2550\u2561\u255e ")

    def set_active(self, active):
        color = GRAY if active else CYAN
        self.titlebar.configure(bg=color)
        self.title.configure(bg=color, fg=BLUE if active else "#005555")
        for label in (self.close_label, self.zoom_label):
            label.configure(bg=color, fg=BLACK if active else "#005555", relief="raised" if active else "flat")

    def focus(self):
        self.frame.focus_set()

    def destroy(self):
        self.frame.destroy()

    def drag_start(self, e):
        self.app.activate(self)
        self.drag_anchor = (e.x_root, e.y_root, self.frame.winfo_x(), self.frame.winfo_y())

    def drag(self, e):
        x,y,left,top = self.drag_anchor
        self.frame.place_configure(x=max(0, left+e.x_root-x), y=max(0, top+e.y_root-y))


class Editor(DesktopWindow):
    def __init__(self, app, document, number):
        super().__init__(app)
        self.document, self.number = document, number
        content = self.body
        # Colors come from apply_options().
        self.gutter = tk.Canvas(content, width=17, highlightthickness=0)
        self.gutter.pack(side="left", fill="y")
        self.text = tk.Text(content, font=app.font, wrap="none", undo=True, maxundo=500,
                            borderwidth=0, highlightthickness=0, padx=3, pady=3, exportselection=False,
                            insertwidth=2, insertontime=550, insertofftime=350)
        self.scrollbar = scrollbar = tk.Scrollbar(content, command=self.text.yview, bg=CYAN, width=16)
        scrollbar.pack(side="right", fill="y")
        self.text.configure(yscrollcommand=lambda a,b: (scrollbar.set(a,b), self.draw_breakpoints()))
        self.text.pack(fill="both", expand=True)
        horizontal = tk.Scrollbar(self.frame, orient="horizontal", command=self.text.xview, width=12)
        horizontal.pack(fill="x", padx=3)
        self.text.configure(xscrollcommand=horizontal.set)
        self.text.insert("1.0", document.text)
        self.text.edit_reset()
        self.text.edit_modified(False)
        # Configured first, so error, found and exec below take priority over syntax colors.
        for name, color in SYNTAX_COLORS.items():
            self.text.tag_configure(name, foreground=color)
        self.text.tag_configure("error", background="#aa0000", foreground="#ffffff")
        self.text.tag_configure("found", background=CYAN, foreground=BLACK)
        # The debugger's execution bar: the statement that runs next.
        self.text.tag_configure("exec", background="#00aa00", foreground="#ffffff")
        self.breakpoint_count = 0
        self.text.bind("<<Modified>>", self.modified)
        self.text.bind("<FocusIn>", lambda e: app.activate(self, focus=False))
        self.text.bind("<KeyRelease>", lambda e: app.user_input())
        self.text.bind("<ButtonRelease-1>", lambda e: app.user_input())
        self.text.bind("<Return>", self.newline)
        self.text.bind("<Tab>", self.tab)
        self.text.bind("<Shift-Tab>", self.unindent)
        self.text.bind("<ISO_Left_Tab>", self.unindent)
        self.text.bind("<Insert>", self.toggle_insert)
        self.text.bind("<KeyPress>", self.overwrite)
        self.gutter.bind("<Button-1>", self.gutter_click)
        self.text.bind("<Configure>", lambda e: self.draw_breakpoints())
        self.overwrite_mode = False
        self.win32 = self.text.tk.call("tk", "windowingsystem") == "win32"
        self.highlight_job = None
        self.apply_options()
        self.update_title()

    def list_label(self):
        return self.document.path.name if self.document.path else f"NONAME{self.number}"

    def focus(self):
        self.text.focus_set()

    def destroy(self):
        if self.highlight_job:
            self.app.root.after_cancel(self.highlight_job)
        super().destroy()

    def apply_options(self):
        self.text.configure(tabs=(self.app.font.measure(" " * self.app.settings["tab_width"]),))
        bg, fg, cursor, select_bg, select_fg = TURBO_BIRU_LEMBUT if self.app.settings["syntax_colors"] else CLASSIC
        self.text.configure(bg=bg, fg=fg, insertbackground=cursor, selectbackground=select_bg, selectforeground=select_fg)
        self.gutter.configure(bg=bg)
        self.scrollbar.configure(troughcolor=bg)
        # Set here, not once in __init__, so the bold and italic fonts follow Options > Editor font size.
        family, size = self.app.font.cget("family"), self.app.font.cget("size")
        for name, style in SYNTAX_FONTS.items():
            self.text.tag_configure(name, font=(family, size, style))
        self.highlight()

    def update_title(self):
        doc = self.document
        name = doc.path.name if doc.path else f"NONAME{self.number:02d}.PAS"
        self.set_title(f"{name.upper()} {'*' if doc.dirty else ''}")

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
        self.app.update_status()
        if self.sync_breakpoints():
            self.app.breakpoints_changed(self)
        self.draw_breakpoints()
        self.app.source_modified(self)

    def highlight(self):
        self.highlight_job = None
        for name in SYNTAX_COLORS:
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
        self.draw_breakpoints()
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
        self.text.mark_set("insert", f"{line}.0")
        self.text.see(f"{line}.0")

    def clear_exec(self):
        self.text.tag_remove("exec", "1.0", "end")

    def draw_breakpoints(self):
        if not self.gutter.winfo_exists():
            return
        self.gutter.delete("all")
        for line in self.document.breakpoints:
            info = self.text.dlineinfo(f"{line}.0")
            if info:
                y = info[1] + info[3] // 2
                self.gutter.create_oval(4,y-5,14,y+5,fill="#ff5555",outline="")


class ListWindow(DesktopWindow):
    """A desktop window showing one list: the debugger's Watches, Local variables and Call stack."""
    label = ""

    def __init__(self, app):
        super().__init__(app, self.label)
        self.list = tk.Listbox(self.body, bg=BLUE, fg=WHITE, selectbackground=CYAN, selectforeground=BLACK,
                               font=app.font, borderwidth=0, highlightthickness=0, activestyle="none",
                               exportselection=False)
        self.list.pack(fill="both", expand=True, padx=2, pady=2)
        self.list.bind("<FocusIn>", lambda e: app.activate(self, focus=False))

    def focus(self):
        self.list.focus_set()

    def rows(self):
        return list(self.list.get(0, "end"))

    def set_rows(self, rows):
        selected = self.selected()
        self.list.delete(0, "end")
        for row in rows:
            self.list.insert("end", row)
        if selected is not None and selected < len(rows):
            self.list.selection_set(selected)
            self.list.activate(selected)

    def selected(self):
        chosen = self.list.curselection()
        return chosen[0] if chosen else None

    def destroy(self):
        self.app.debug_window_closed(self)
        super().destroy()


class WatchWindow(ListWindow):
    """Insert adds a watch, Delete removes the selected one, Enter or a double click edits it."""
    label = "Watches"

    def __init__(self, app):
        super().__init__(app)
        self.list.bind("<Insert>", lambda e: (app.add_watch(), "break")[1])
        self.list.bind("<Delete>", lambda e: (app.delete_watch(self.selected()), "break")[1])
        self.list.bind("<BackSpace>", lambda e: (app.delete_watch(self.selected()), "break")[1])
        self.list.bind("<Return>", lambda e: (app.edit_watch(self.selected()), "break")[1])
        self.list.bind("<Double-Button-1>", lambda e: app.edit_watch(self.selected()))


class LocalsWindow(ListWindow):
    label = "Local variables"


class StackWindow(ListWindow):
    """Enter or a double click shows a frame; Watches and Local variables then use it."""
    label = "Call stack"

    def __init__(self, app):
        super().__init__(app)
        self.list.bind("<Return>", lambda e: (app.select_frame(self.selected()), "break")[1])
        self.list.bind("<Double-Button-1>", lambda e: app.select_frame(self.selected()))
