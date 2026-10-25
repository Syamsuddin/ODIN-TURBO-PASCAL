# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""GUI of the IDE (OTP_WIN_PLAN.md): one main window with a text menu bar, a toolbar, a workspace of child windows
(MDI: editors, Output, Messages, debugger windows) and a status bar. All commands are local."""
from __future__ import annotations

import base64
import json
import math
import os
import platform
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
import webbrowser
import tkinter as tk
from pathlib import Path
from urllib.parse import quote
from tkinter import filedialog, messagebox, ttk
from tkinter import font as tkfont

from . import __author__, __copyright__, __version_tag__
from . import metrics as metrics_report
from .core import (PACKAGE_ROOT, BuildResult, Diagnostic, Document, Settings, atomic_write, build, data_dir, join_command,
                   library_unit_paths, locate_toolchain, lock_instance, odin_supported, runtime_error_location,
                   split_arguments, unlock_instance)
from .debugger import DebugSession
from .graphics import GraphChannel
from .graphwindow import GraphWindow
from .icons import png as icon_png
from .terminal import Process, Screen
from .windows import (GRIP, ICON_WIDTH, WORKSPACE, Editor, LocalsWindow, MessagesWindow, OutputWindow, StackWindow,
                      Tooltip, WatchWindow)

ASSETS = Path(__file__).resolve().parent.parent
# File > Examples > Graph: the programs in examples-graph/ and what each one shows.
GRAPH_EXAMPLE_TOPICS = {
    "01": "Program grafik pertama", "02": "Garis, gaya garis, titik kini", "03": "Bentuk dasar", "04": "Warna dan palet",
    "05": "Isian, pola, FloodFill", "06": "Grafik batang", "07": "Diagram pai", "08": "Grafik fungsi matematika",
    "09": "Animasi dua halaman", "10": "GetImage dan PutImage (sprite)", "11": "Himpunan Mandelbrot", "12": "Jam analog",
    "13": "Menggambar dengan tombol panah", "14": "Teks di layar grafik"}
# File > Examples > OOP: the class programs in examples-oop/ and what each one teaches.
OOP_EXAMPLE_TOPICS = {
    "01": "Class pertama", "02": "Constructor dan destructor", "03": "Enkapsulasi dan property", "04": "Pewarisan",
    "05": "Polimorfisme (virtual, abstract)", "06": "Class var, class method, class of", "07": "Daftar objek, is, as",
    "08": "Overload", "09": "Proyek: kasir toko"}
AI_EXAMPLE_TOPICS = {
    "BASIC": "Matematika, matriks, statistik", "DATAPREP": "Praproses data CSV", "REGDEMO": "Regresi linear",
    "REGMULT": "Regresi linear berganda", "KNNDEMO": "K-Nearest Neighbors", "KMEANS": "K-Means clustering",
    "CROSSVAL": "Cross-validation", "LOGDEMO": "Regresi logistik", "PERDEMO": "Perceptron", "NNDEMO": "Jaringan saraf (XOR)",
    "BAYDEMO": "Naive Bayes", "TEXTDEMO": "Klasifikasi teks", "TREEDEMO": "Pohon keputusan", "RULEDEMO": "Sistem aturan",
    "PATHDEMO": "Pencarian jalur (BFS, DFS, A*)", "FUZDEMO": "Logika fuzzy", "QDEMO": "Q-learning",
    "OPTDEMO": "Optimizer gradient descent", "MODELIO": "Simpan dan muat model", "PLOTDEMO": "Grafik SVG"}
# Help > Buku opens this PDF in docs/.
BOOK = "Belajar_Pemrograman_Bahasa_Pascal.pdf"
# Help > Contents opens this page in docs/.
HELP_HTML = "help.html"
TEMPLATE = "program Untitled;\n\nbegin\n  WriteLn('Hello, Pascal!');\nend.\n"
# Compile actions that need a debug build and run under the debugger.
DEBUG_ACTIONS = ("debug", "step", "cursor")
# Monospace fonts in order of preference; Courier when none is installed.
FONTS = {"darwin": ("Menlo",), "win32": ("Consolas", "Courier New")}
# The ttk theme that draws native widgets on each OS.
TTK_THEMES = {"darwin": "aqua", "win32": "vista"}
AQUA = sys.platform == "darwin"
# The command modifier: Command on macOS, Control elsewhere.
MOD = "Command" if AQUA else "Control"
ENCODINGS = {"utf-8": "UTF-8", "utf-8-sig": "UTF-8 BOM", "cp437": "CP437"}
# Menu bar colors: background, text, item under the mouse or open.
MENU_BG, MENU_FG, MENU_HOVER = "#f3f3f3", "#1f1f1f", "#cce0f7"
# Where the standard windows open, as place() options in the workspace: editors fill the upper part (cascaded),
# Output and Messages share the lower part, the debugger's windows stack on the right.
EDITOR_HEIGHT = .58
OUTPUT_PLACE = dict(x=6, rely=EDITOR_HEIGHT, y=2, relwidth=.58, width=-9, relheight=1 - EDITOR_HEIGHT, height=-8)
MESSAGES_PLACE = dict(relx=.58, x=3, rely=EDITOR_HEIGHT, y=2, relwidth=.42, width=-9, relheight=1 - EDITOR_HEIGHT, height=-8)
DEBUG_PLACES = {"watch_window": dict(relx=.62, x=0, y=6, relwidth=.38, width=-6, relheight=EDITOR_HEIGHT / 3, height=-6),
                "locals_window": dict(relx=.62, x=0, rely=EDITOR_HEIGHT / 3, y=2, relwidth=.38, width=-6,
                                      relheight=EDITOR_HEIGHT / 3, height=-6),
                "stack_window": dict(relx=.62, x=0, rely=2 * EDITOR_HEIGHT / 3, y=-2, relwidth=.38, width=-6,
                                     relheight=EDITOR_HEIGHT / 3, height=-4)}
# Height of a minimized window: its title bar and frame.
ICON_HEIGHT = 26 + 2 * GRIP
# Toolbar buttons in groups: key in App.tools, icon in odin/icons.py, tooltip, App method name and its argument.
TOOLBAR = ((("New", "new", "New (Mod+N)", "new", None), ("Open", "open", "Open (F3)", "open_file", None),
            ("Save", "save", "Save (F2)", "save", None)),
           (("Compile", "compile", "Compile (F9)", "compile", None), ("Run", "run", "Run (Ctrl+F9)", "run", None),
            ("Stop", "stop", "Program reset (Ctrl+F2)", "stop", None)),
           (("Debug", "debug", "Start debugging", "debug", None), ("into", "into", "Trace into (F7)", "debug_step", "into"),
            ("over", "over", "Step over (F8)", "debug_step", "over"),
            ("Breakpoint", "breakpoint", "Toggle breakpoint (Ctrl+F8)", "breakpoint", None)),
           (("Tile", "tile", "Tile windows", "tile", None), ("Cascade", "cascade", "Cascade windows", "cascade", None)))
TOOLBAR_ICON = 20
# Kinds of windows the desktop (Options > Environment > Save desktop) remembers, and their App attributes.
DESKTOP_WINDOWS = {"output": "output_window", "messages": "messages_window", "watches": "watch_window",
                   "locals": "locals_window", "stack": "stack_window"}
OPTION_TABS = ("Compiler", "Directories", "Editor", "Environment")


def accel(keys):
    """Menu accelerator text for keys written as Mod+S, Ctrl+F9 or Alt+F8: Tk's Command-S form on macOS, which the
    menus draw as symbols, and Ctrl+S elsewhere."""
    if not keys:
        return ""
    parts = keys.split("+")
    if AQUA:
        names = {"Mod": "Command", "Ctrl": "Control", "Alt": "Option"}
        return "-".join(names.get(part, part) for part in parts)
    return "+".join("Ctrl" if part == "Mod" else part for part in parts)


class App:
    def __init__(self, root):
        self.root = root
        self.settings = Settings()
        # windows: every child window in creation order; active: any of them; last_editor: most recently active Editor.
        self.windows, self.active, self.last_editor = [], None, None
        self.counter = 0
        self.messages = queue.Queue(maxsize=256)
        self.compiling = False
        self.process = None             # console Process of the program (or of odinpc debug) while it runs
        self.finished_runs = 0          # programs that ended, counted when the IDE has handled their end
        self.debugger = None            # DebugSession while debugging
        self.debug_requests = {}        # request id -> callback(result event)
        self.debug_frame = 0            # call stack frame used by Watches and Local variables
        self.stack_frames = []
        self.watches = []               # watch expressions, shown with their latest values
        self.watch_values = {}
        self.watch_window = self.locals_window = self.stack_window = None
        self.output_window = self.messages_window = None
        self.pending_cursor = None      # (path, line) for Go to cursor
        self.restart_debug = None
        self.debug_source_changed = False
        self.last_runtime_error = None  # (code, path or None, line or None)
        self.error_report = None        # (debug_info, report file) of the last Run
        self.measuring = None           # Run > Ukur in progress: what the Metrik window needs when it ends
        self.last_metrics = None        # the report the Metrik window shows last
        self.graph_channel = None       # the Graph window of the running program (odin/graphics.py)
        self.graph_window = None
        self.last_build = None
        self.error_index = -1
        self.search_term = ""
        self.closed = False
        self.pending_action = None
        self.banner = True
        self.notice = None              # kept in the status bar until the next key or click
        self.session = data_dir() / "recovery.json"
        root.title("Odin Turbo Pascal")
        root.geometry(self.settings["geometry"])
        root.minsize(820, 560)
        root.protocol("WM_DELETE_WINDOW", self.quit)
        root.report_callback_exception = self.report_error
        self.style = ttk.Style(root)
        theme = TTK_THEMES.get(sys.platform, "clam")
        if theme in self.style.theme_names():
            self.style.theme_use(theme)
        available = {f.lower() for f in tkfont.families(root)}
        family = next((f for f in FONTS.get(sys.platform, ("DejaVu Sans Mono",)) if f.lower() in available), "Courier")
        self.font = tkfont.Font(root=root, family=family, size=self.settings["font_size"])
        self.console_font = tkfont.Font(root=root, family=family, size=self.settings["console_font_size"])
        self.icon = self.load_image("odin.png")
        if self.icon:
            root.iconphoto(True, self.icon)
        self.logo = self.load_image("odin-logo.png")
        self.logo_small = self.load_image("odin-logo-small.png")
        if AQUA:
            # The macOS menu bar keeps only the application menu (About, Quit); the IDE's menus are in its window.
            system = tk.Menu(root)
            system.add_cascade(menu=tk.Menu(system, name="apple", tearoff=False))
            root.configure(menu=system)
        self.menubar = tk.Frame(root, bg=MENU_BG)
        self.menubar.pack(side="top", fill="x")
        self.menus = {}
        self.create_menus()
        ttk.Separator(root).pack(side="top", fill="x")
        self.toolbar = ttk.Frame(root, padding=(6, 3))
        self.toolbar.pack(side="top", fill="x")
        self.tools = {}
        self.create_toolbar()
        ttk.Separator(root).pack(side="top", fill="x")
        status = ttk.Frame(root)
        status.pack(side="bottom", fill="x")
        ttk.Separator(root).pack(side="bottom", fill="x")
        self.status = ttk.Label(status, anchor="w", padding=(8, 3))
        self.status.pack(side="left", fill="x", expand=True)
        self.encoding_label = ttk.Label(status, padding=(10, 3))
        self.encoding_label.pack(side="right")
        self.mode_label = ttk.Label(status, padding=(10, 3), width=5, anchor="center")
        self.mode_label.pack(side="right")
        self.position_label = ttk.Label(status, padding=(10, 3), width=16)
        self.position_label.pack(side="right")
        self.workspace = tk.Frame(root, bg=WORKSPACE)
        self.workspace.pack(fill="both", expand=True)
        self.plaque = self.make_plaque()
        self.plaque.place(relx=.5, rely=.5, anchor="center")
        self.bind_keys()
        self.restore_session()
        if not (self.settings["save_desktop"] and self.restore_desktop()):
            self.show_output(activate=False)
            self.show_messages_window(activate=False)
        if not self.editors:
            example = ASSETS / "examples" / "bab01_01_halo_dunia.pas"
            self.new_document(Document.read(example) if example.exists() else Document(TEMPLATE))
        self.update_status()
        root.after(40, self.poll)
        root.after(10000, self.recover_tick)
        if AQUA:
            root.createcommand("tkAboutDialog", self.about)
            root.createcommand("::tk::mac::ShowPreferences", self.options)
            root.createcommand("::tk::mac::Quit", self.quit)
            root.createcommand("::tk::mac::OpenDocument", lambda *paths: [self.open_file(Path(p)) for p in paths])

    def load_image(self, name):
        # The PNGs are rendered from assets/odin-logo-master.png by scripts/render_logo.py; without them the IDE falls back to text.
        try:
            return tk.PhotoImage(master=self.root, file=str(ASSETS / "assets" / name))
        except tk.TclError:
            return None

    def ui_font(self, size, weight="normal"):
        """The OS's interface font at another size, for headings."""
        return (tkfont.nametofont("TkDefaultFont", root=self.root).cget("family"), size, weight)

    def make_plaque(self):
        """The caption in the middle of the workspace, behind the windows: logo, name and release tag, author
        credit, copyright and license. Its labels are the attributes tagline, version, author, copyright, license."""
        plaque = tk.Frame(self.workspace, bg=WORKSPACE)
        if self.logo_small:
            tk.Label(plaque, image=self.logo_small, bg=WORKSPACE, borderwidth=0).pack(pady=(0, 12))
        rows = (("tagline", "Odin Turbo Pascal", self.ui_font(20, "bold"), "#26313d"),
                ("version", f"Native Pascal IDE  {__version_tag__}", self.ui_font(13), "#2b5797"),
                ("author", f"Created by {__author__}", self.ui_font(13, "bold"), "#26313d"),
                ("copyright", __copyright__, self.ui_font(11), "#4a5562"),
                ("license", "GNU GPL v3 or later", self.ui_font(11), "#4a5562"))
        for name, text, font, color in rows:
            label = tk.Label(plaque, text=text, font=font, fg=color, bg=WORKSPACE)
            label.pack()
            setattr(plaque, name, label)
        return plaque

    def report_error(self, kind, value, tb):
        detail = "".join(traceback.format_exception(kind, value, tb))
        try:
            atomic_write(data_dir()/"last-error.log", detail.encode())
        except OSError:
            pass
        messagebox.showerror("Odin", f"Operasi gagal: {value}\n\nDetail: {data_dir() / 'last-error.log'}", parent=self.root)

    # ---- menus, toolbar and keys -------------------------------------------------------------

    def menu(self, label, items, parent=None):
        """A menu of (label, command, keys) items: a text item of the menu bar with its dropdown, or a cascade of
        parent. "-" is a separator and a list as command makes a cascade."""
        if parent is None:
            button = tk.Menubutton(self.menubar, text=label, underline=0, relief="flat", borderwidth=0, padx=9, pady=4,
                                   bg=MENU_BG, fg=MENU_FG, activebackground=MENU_HOVER, activeforeground=MENU_FG,
                                   highlightthickness=0, font=self.ui_font(13))
            button.pack(side="left")
            menu = tk.Menu(button, tearoff=False)
            button.configure(menu=menu)
            self.root.bind(f"<Alt-{label[0].lower()}>", lambda e, b=button: self.post_menu(b))
        else:
            button = None
            menu = tk.Menu(parent, tearoff=False)
            parent.add_cascade(label=label, menu=menu)
        for text, command, keys in items:
            if text == "-":
                menu.add_separator()
            elif isinstance(command, list):
                self.menu(text, command, parent=menu)
            else:
                menu.add_command(label=text, command=command, accelerator=accel(keys))
        self.menus[label] = (button, menu)
        return menu

    def post_menu(self, button):
        """Opens a menu of the menu bar from the keyboard (F10, Alt+letter)."""
        try:
            self.root.tk.call("tk::MbPost", str(button))
        except tk.TclError:
            menu = self.root.nametowidget(button.cget("menu"))
            menu.post(button.winfo_rootx(), button.winfo_rooty() + button.winfo_height())
        return "break"

    def create_menus(self):
        examples = [("Tutorial...", self.examples, ""), ("AI...", self.examples_ai, ""),
                    ("Graph...", self.examples_graph, ""), ("OOP...", self.examples_oop, "")]
        file_items = [("New", self.new, "Mod+N"), ("Open...", self.open_file, "Mod+O"), ("Open recent", [], ""),
                      ("Examples", examples, ""), ("-", None, ""), ("Save", self.save, "Mod+S"),
                      ("Save as...", lambda: self.save(as_new=True), "Mod+Shift+S"), ("Save all", self.save_all, ""),
                      ("-", None, ""), ("Change directory...", self.change_directory, ""), ("-", None, ""),
                      ("Exit", self.quit, "Mod+Q" if AQUA else "Alt+X")]
        self.menu("File", file_items)
        self.menus["Open recent"][1].configure(postcommand=self.fill_recent)
        redo = "Mod+Shift+Z" if AQUA else "Ctrl+Y"
        self.menu("Edit", [("Undo", lambda: self.edit("undo"), "Mod+Z"), ("Redo", lambda: self.edit("redo"), redo),
                           ("-", None, ""), ("Cut", lambda: self.edit("cut"), "Mod+X"),
                           ("Copy", lambda: self.edit("copy"), "Mod+C"), ("Paste", lambda: self.edit("paste"), "Mod+V"),
                           ("Select all", lambda: self.edit("all"), "Mod+A"), ("-", None, ""),
                           ("Delete line", self.delete_line, "Ctrl+L")])
        self.menu("Search", [("Find...", self.find_dialog, "Mod+F"), ("Replace...", lambda: self.find_dialog(True), "Ctrl+H"),
                             ("Search again", self.find_next, "Mod+G"), ("Go to line...", self.goto_line, "Ctrl+J"),
                             ("-", None, ""), ("Next error", self.next_error, "Alt+F8"), ("Find error", self.find_error, "")])
        self.menu("Run", [("Run", self.run, "Ctrl+F9"), ("Program reset", self.stop, "Ctrl+F2"),
                          ("Parameters...", self.parameters, ""), ("-", None, ""),
                          ("Ukur", self.measure, "Shift+F9"), ("Periksa...", self.check_package, "")])
        self.menu("Compile", [("Compile", self.compile, "Alt+F9"), ("Make", self.compile, "F9"),
                              ("Build", lambda: self.compile(rebuild=True), ""), ("-", None, ""),
                              ("Primary file...", self.primary_file, ""), ("Clear primary file", self.clear_primary, ""),
                              ("-", None, ""), ("Compiler messages", self.show_messages, ""),
                              ("Export executable...", self.export_executable, "")])
        self.menu("Debug", [("Start debugging", self.debug, ""), ("Step over", lambda: self.debug_step("over"), "F8"),
                            ("Trace into", lambda: self.debug_step("into"), "F7"),
                            ("Go to cursor", lambda: self.debug_step("cursor"), "F4"),
                            ("Continue", lambda: self.debug_step("continue"), ""), ("-", None, ""),
                            ("Toggle breakpoint", self.breakpoint, "Ctrl+F8"), ("Clear breakpoints", self.clear_breakpoints, ""),
                            ("-", None, ""), ("Watches", self.show_watches, ""), ("Add watch...", self.add_watch, ""),
                            ("Local variables", self.show_locals, ""), ("Call stack", self.show_stack, ""),
                            ("Evaluate/Modify...", self.evaluate, "Ctrl+F7")])
        self.menu("Options", [("Options...", self.options, "Mod+," if AQUA else ""), ("-", None, ""),
                              ("Compiler...", self.compiler_options, ""), ("Directories...", self.directory_options, ""),
                              ("Editor...", self.editor_options, ""), ("Environment...", self.environment_options, ""),
                              ("-", None, ""), ("Zoom in", lambda: self.zoom_font(1), "Mod+="),
                              ("Zoom out", lambda: self.zoom_font(-1), "Mod+-"), ("-", None, ""),
                              ("Save options", self.settings.save, ""), ("Environment information", self.environment, "")])
        self.menu("Window", [])
        self.menus["Window"][1].configure(postcommand=self.fill_window_menu)
        self.fill_window_menu()
        self.menu("Help", [("Contents", self.help_html, "F1"), ("Pascal reference", self.reference, ""),
                           ("Keyboard shortcuts", lambda: self.help("SHORTCUTS.txt"), ""), ("Buku", self.book, ""),
                           ("-", None, ""), ("About Odin", self.about, "")])

    def fill_recent(self):
        menu = self.menus["Open recent"][1]
        menu.delete(0, "end")
        for path in self.settings["recent"]:
            menu.add_command(label=path, command=lambda p=path: self.open_file(p))
        if not self.settings["recent"]:
            menu.add_command(label="(empty)", state="disabled")

    def fill_window_menu(self):
        """The Window menu: arrangement commands, then one entry per window with a check at the active one."""
        menu = self.menus["Window"][1]
        menu.delete(0, "end")
        for label, command, keys in (("Tile", self.tile, ""), ("Cascade", self.cascade, ""),
                                     ("Arrange icons", self.arrange_icons, ""), ("-", None, ""),
                                     ("Zoom", self.zoom, "F5"), ("Minimize", self.minimize, ""),
                                     ("Next", self.next_window, "F6"), ("Previous", self.previous_window, "Shift+F6"),
                                     ("Close", self.close_window, "Alt+F3"), ("Close all", self.close_all, ""),
                                     ("-", None, ""), ("Output", self.show_output, "Alt+F5"),
                                     ("Messages", self.show_messages, "")):
            if label == "-":
                menu.add_separator()
            else:
                menu.add_command(label=label, command=command, accelerator=accel(keys))
        if self.windows:
            menu.add_separator()
            self.window_choice = tk.IntVar(master=self.root, value=self.windows.index(self.active) if self.active in self.windows else -1)
            for n, window in enumerate(self.windows):
                menu.add_radiobutton(label=f"{n + 1} {window.list_label()}", variable=self.window_choice, value=n,
                                     command=lambda w=window: self.activate(w))

    def create_toolbar(self):
        """Icon buttons (odin/icons.py) with tooltips; without PNG support in Tk they show their key as text."""
        self.tool_images = {}
        for n, group in enumerate(TOOLBAR):
            if n:
                ttk.Separator(self.toolbar, orient="vertical").pack(side="left", fill="y", padx=6, pady=2)
            for key, icon, tip, method, argument in group:
                command = (lambda m=method, a=argument: getattr(self, m)(a)) if argument else (lambda m=method: getattr(self, m)())
                try:
                    image = self.tool_images[key] = tk.PhotoImage(master=self.root, format="png",
                                                                  data=base64.b64encode(icon_png(icon, TOOLBAR_ICON)))
                except tk.TclError:
                    image = None
                button = ttk.Button(self.toolbar, image=image or "", text=key, compound="image" if image else "text",
                                    command=command, style="Toolbutton", takefocus=False)
                button.pack(side="left", padx=1)
                button.tooltip = Tooltip(button, tip.replace("Mod+", "Cmd+" if AQUA else "Ctrl+"))
                self.tools[key] = button

    def bind_keys(self):
        commands = {"<F1>": self.help_topic, "<F2>": self.save, "<F3>": self.open_file, "<F5>": self.zoom,
                    "<F6>": self.next_window, "<Shift-F6>": self.previous_window,
                    "<F4>": lambda: self.debug_step("cursor"), "<F7>": lambda: self.debug_step("into"),
                    "<F8>": lambda: self.debug_step("over"), "<F9>": self.compile, "<Control-F9>": self.run,
                    "<Alt-F9>": self.compile, "<Shift-F9>": self.measure, "<Alt-F3>": self.close_window,
                    "<Alt-F5>": self.show_output, "<F10>": lambda: self.post_menu(self.menus["File"][0]),
                    "<Control-F2>": self.stop, "<Control-F8>": self.breakpoint, "<Control-F7>": self.evaluate,
                    "<Alt-F8>": self.next_error, "<Alt-BackSpace>": lambda: self.edit("undo"),
                    f"<{MOD}-n>": self.new, f"<{MOD}-o>": self.open_file, f"<{MOD}-s>": self.save,
                    f"<{MOD}-S>": lambda: self.save(as_new=True), f"<{MOD}-w>": self.close_window,
                    f"<{MOD}-f>": self.find_dialog, f"<{MOD}-g>": self.find_next, f"<{MOD}-r>": self.run,
                    f"<{MOD}-b>": self.compile, f"<{MOD}-equal>": lambda: self.zoom_font(1),
                    f"<{MOD}-plus>": lambda: self.zoom_font(1), f"<{MOD}-minus>": lambda: self.zoom_font(-1),
                    "<Control-h>": lambda: self.find_dialog(True), "<Control-j>": self.goto_line,
                    "<Control-l>": self.delete_line, "<Control-Tab>": self.next_window,
                    "<Control-Shift-Tab>": self.previous_window}
        if not AQUA:
            # Ctrl+Y pastes in X11 Text widgets; here it redoes, as on Windows.
            commands.update({"<Alt-x>": self.quit, "<Control-y>": lambda: self.edit("redo")})
        if self.root.tk.call("tk", "windowingsystem") == "x11":
            commands["<Control-ISO_Left_Tab>"] = self.previous_window
        for sequence, action in commands.items():
            handler = lambda e, a=action: self.shortcut(a)
            self.root.bind(sequence, handler)
            # Editors put the OdinKeys tag before Text, so these win over the Text class bindings.
            self.root.bind_class("OdinKeys", sequence, handler)

    def shortcut(self, action):
        action()
        return "break"

    # ---- child windows -------------------------------------------------------------------

    @property
    def debugging(self):
        """A debug session is running (the program may be running or stopped)."""
        return bool(self.debugger and self.debugger.alive)

    @property
    def program_running(self):
        return bool(self.process and self.process.child.poll() is None)

    @property
    def editors(self):
        """Editor windows only: Save all, recovery, breakpoints and Compile use these."""
        return [w for w in self.windows if isinstance(w, Editor)]

    @property
    def active_editor(self):
        """The active window when it is an Editor. Text commands do nothing for other windows."""
        return self.active if isinstance(self.active, Editor) else None

    @property
    def console(self):
        """The TerminalView of the Output window, or None while it is closed."""
        return self.output_window.console if self.output_window else None

    def add_window(self, window, place=None, activate=True):
        self.windows.append(window)
        if place is None:
            # Editors cascade in the upper part of the workspace.
            n = (len(self.editors) - 1) % 6
            place = dict(x=6 + n * 24, y=6 + n * 24, relwidth=1, width=-12 - n * 24, relheight=EDITOR_HEIGHT,
                         height=-6 - n * 24)
        window.frame.place(**place)
        if activate:
            self.activate(window)
        else:
            window.frame.lift()
            window.set_active(False)
            if self.active:
                self.active.frame.lift()
        return window

    def new_document(self, doc):
        self.counter += 1
        return self.add_window(Editor(self, doc, self.counter))

    def new(self):
        return self.new_document(Document(TEMPLATE))

    def activate(self, window, focus=True):
        if window not in self.windows:
            return
        if window.state == "minimized" and focus:
            self.restore(window)
        self.active = window
        if isinstance(window, Editor):
            self.last_editor = window
        window.frame.lift()
        for item in self.windows:
            item.set_active(item is window)
        if focus:
            window.focus()
        self.update_title()
        self.update_status()

    def focus_editor(self):
        if self.last_editor:
            self.activate(self.last_editor)

    def window_title_changed(self, window):
        if window is self.active:
            self.update_title()

    def update_title(self):
        window = self.active
        name = window.caption() if isinstance(window, Editor) else window.list_label() if window else ""
        self.root.title(f"{name} - Odin Turbo Pascal" if name else "Odin Turbo Pascal")

    def close_window(self, window=None):
        window = window or self.active
        if not window: return True
        if isinstance(window, Editor) and window.document.dirty:
            self.activate(window)
            answer = messagebox.askyesnocancel("Save changes", "Simpan perubahan sebelum menutup?", parent=self.root)
            if answer is None or (answer and not self.save(window)): return False
        if window is self.output_window and self.program_running:
            if not messagebox.askyesno("Output", "Program masih berjalan di jendela ini. Hentikan program?", parent=self.root):
                return False
            self.stop()
        window.destroy()
        self.windows.remove(window)
        if window is self.output_window:
            self.output_window = None
        if window is self.messages_window:
            self.messages_window = None
        if window is self.last_editor:
            editors = self.editors
            self.last_editor = editors[-1] if editors else None
        self.active = None
        visible = [w for w in self.windows if w.state != "minimized"]
        if visible:
            self.activate(visible[-1])
        else:
            self.update_title()
            self.update_status()
        if window.state == "minimized":
            self.arrange_icons()
        return True

    # Kept for callers of the earlier name.
    close_editor = close_window

    def close_all(self):
        for window in list(self.windows):
            if not self.close_window(window):
                return False
        return True

    def next_window(self, step=1):
        if self.windows:
            index = self.windows.index(self.active) if self.active in self.windows else -1
            self.activate(self.windows[(index + step) % len(self.windows)])

    def previous_window(self):
        self.next_window(-1)

    # Kept for callers of the desktop IDE's name.
    next_editor = next_window

    def zoom(self, window=None):
        """F5: maximizes the window in the workspace, or restores it."""
        window = window or self.active
        if not window:
            return
        window.set_state("normal" if window.state == "maximized" else "maximized")
        self.arrange_icons()
        self.activate(window)

    def minimize(self, window=None):
        window = window or self.active
        if not window:
            return
        window.set_state("minimized")
        self.arrange_icons()
        window.set_active(False)
        visible = [w for w in self.windows if w.state != "minimized"]
        if visible:
            self.activate(visible[-1])
        else:
            self.active = None
            self.update_status()

    def restore(self, window):
        window.set_state("normal")
        self.arrange_icons()

    def arrange_icons(self):
        """Minimized windows line up along the bottom of the workspace."""
        for n, window in enumerate(w for w in self.windows if w.state == "minimized"):
            window.frame.place_forget()
            window.frame.place(x=4 + n * (ICON_WIDTH + 4), rely=1, y=-4, anchor="sw", width=ICON_WIDTH, height=ICON_HEIGHT)
            window.frame.lift()

    def arranged(self):
        """The windows Tile and Cascade arrange: every window that is not minimized, maximized ones restored."""
        windows = [w for w in self.windows if w.state != "minimized"]
        for window in windows:
            window.set_state("normal")
        bottom = ICON_HEIGHT + 8 if len(windows) < len(self.windows) else 0
        return windows, bottom

    def tile(self):
        windows, bottom = self.arranged()
        if not windows:
            return
        cols = 1 if len(windows) == 1 else 2 if len(windows) <= 4 else 3
        rows = math.ceil(len(windows) / cols)
        for i, window in enumerate(windows):
            window.frame.place_forget()
            window.frame.place(relx=(i % cols) / cols, rely=(i // cols) / rows, x=3, y=3, relwidth=1 / cols,
                               relheight=1 / rows, width=-6, height=-6 - bottom / rows)
        if self.active in windows:
            self.activate(self.active)

    def cascade(self):
        windows, bottom = self.arranged()
        for i, window in enumerate(windows):
            n = i % 8
            window.frame.place_forget()
            window.frame.place(x=6 + n * 26, y=6 + n * 26, relwidth=1, relheight=1, width=-12 - n * 26 - 104,
                               height=-12 - n * 26 - 104 - bottom)
            window.frame.lift()
        if windows:
            self.activate(windows[-1])

    def window_list(self):
        self.choose("Windows", [(w.list_label(), w) for w in self.windows], self.activate)

    def show_output(self, activate=True, place=None):
        window = self.output_window
        if window is None:
            window = self.output_window = self.add_window(OutputWindow(self), place or dict(OUTPUT_PLACE), activate=activate)
        elif activate:
            self.activate(window)
        return window

    def show_messages_window(self, activate=True, place=None):
        window = self.messages_window
        if window is None:
            window = self.messages_window = self.add_window(MessagesWindow(self), place or dict(MESSAGES_PLACE),
                                                            activate=activate)
            self.fill_messages()
        elif activate:
            self.activate(window)
        return window

    # ---- desktop: the windows of the last session -------------------------------------------

    def window_box(self, window):
        """Where window is when it is not maximized or minimized, as fractions (x, y, width, height) of the
        workspace; None before the workspace has a size."""
        width, height = self.workspace.winfo_width(), self.workspace.winfo_height()
        info = window.frame.place_info() if window.state == "normal" else window.restore_place
        if width < 50 or height < 50 or not info:
            return None
        value = lambda key: float(info.get(key) or 0)
        box = (value("relx") * width + value("x"), value("rely") * height + value("y"),
               value("relwidth") * width + value("width"), value("relheight") * height + value("height"))
        return [round(box[0] / width, 4), round(box[1] / height, 4), round(box[2] / width, 4), round(box[3] / height, 4)]

    def desktop_state(self):
        """The open windows for settings["desktop"]: saved editors with cursor and breakpoints, Output, Messages
        and the debugger's windows, each with its place and state, and which one was active."""
        names = {getattr(self, attribute): kind for kind, attribute in DESKTOP_WINDOWS.items()}
        windows = []
        active = None
        for window in self.windows:
            box = self.window_box(window)
            if box is None:
                continue
            if isinstance(window, Editor):
                if not window.document.path:
                    continue
                item = {"kind": "editor", "path": str(window.document.path), "cursor": window.text.index("insert"),
                        "breakpoints": sorted(window.document.breakpoints)}
            elif window in names:
                item = {"kind": names[window]}
            else:
                continue
            item.update(box=box, state=window.state)
            if window is self.active:
                active = len(windows)
            windows.append(item)
        return {"windows": windows, "active": active} if windows else {}

    def restore_desktop(self):
        """Reopens the windows of settings["desktop"]; files that are gone are skipped. Returns True when it
        restored any window."""
        desktop = self.settings["desktop"]
        items = desktop.get("windows") if isinstance(desktop, dict) else None
        if not isinstance(items, list):
            return False
        restored = {}   # index in items -> window
        for index, item in enumerate(items):
            try:
                box = [float(v) for v in item["box"]]
                if len(box) != 4 or not all(-1 <= v <= 2 for v in box) or box[2] <= 0 or box[3] <= 0:
                    continue
                place = dict(relx=box[0], rely=box[1], relwidth=box[2], relheight=box[3])
                kind = item["kind"]
                if kind == "editor":
                    path = Path(item["path"])
                    window = self.editor_for(path)
                    if window:
                        window.frame.place_forget()
                        window.frame.place(**place)
                    elif path.is_file():
                        self.counter += 1
                        window = self.add_window(Editor(self, Document.read(path), self.counter), place, activate=False)
                        window.set_breakpoints([int(l) for l in item.get("breakpoints", [])], notify=False)
                        window.text.mark_set("insert", str(item.get("cursor", "1.0")))
                        window.text.see("insert")
                        window.cursor_moved(notify=False)
                    else:
                        continue
                elif kind == "output":
                    window = self.show_output(activate=False, place=place)
                elif kind == "messages":
                    window = self.show_messages_window(activate=False, place=place)
                elif kind in DESKTOP_WINDOWS:
                    kinds = {"watches": WatchWindow, "locals": LocalsWindow, "stack": StackWindow}
                    window = self.debug_window(DESKTOP_WINDOWS[kind], kinds[kind], place=place, activate=False)
                else:
                    continue
            except (KeyError, TypeError, ValueError, OSError, tk.TclError):
                continue
            if item.get("state") in ("maximized", "minimized"):
                window.set_state(item["state"])
            restored[index] = window
        self.arrange_icons()
        active = restored.get(desktop.get("active"))
        if active is None and restored:
            active = list(restored.values())[-1]
        if active:
            self.activate(active)
        return bool(restored)

    # ---- files ---------------------------------------------------------------------------

    def open_file(self, path=None):
        if path is None:
            path = filedialog.askopenfilename(parent=self.root, title="Open Pascal file", filetypes=[("Pascal files","*.pas *.pp *.inc *.PAS *.PP *.INC"),("All files","*")])
        if not path: return None
        path = Path(path).expanduser().resolve()
        for editor in self.editors:
            if editor.document.path == path:
                self.activate(editor)
                return editor
        try:
            doc = Document.read(path)
            self.settings.add_recent(path)
        except OSError as error:
            messagebox.showerror("Open",str(error),parent=self.root)
            return None
        return self.new_document(doc)

    def save(self, editor=None, as_new=False):
        editor = editor or self.active_editor
        if not editor: return False
        doc = editor.document
        doc.text = editor.text.get("1.0","end-1c")
        target = doc.path
        if target and ASSETS in target.parents and not as_new:
            # Bundled examples are templates; write the user's own copy.
            as_new = True
        if as_new or target is None:
            value = filedialog.asksaveasfilename(parent=self.root,title="Save Pascal file",defaultextension=".pas",
                        initialfile=target.name if target else f"NONAME{editor.number:02d}.PAS",filetypes=[("Pascal source","*.pas"),("All files","*")])
            if not value: return False
            target = Path(value).resolve()
            if any(e is not editor and e.document.path == target for e in self.editors):
                messagebox.showerror("Save","File ini sedang dibuka pada jendela lain.",parent=self.root)
                return False
        elif doc.externally_changed():
            if not messagebox.askyesno("File berubah","File pada disk berubah di luar Odin. Timpa dengan isi editor?",parent=self.root):
                return False
        try:
            doc.save(target)
            self.settings.add_recent(target)
        except UnicodeEncodeError:
            if messagebox.askyesno("Encoding","Karakter tidak tersedia dalam CP437. Simpan sebagai UTF-8?",parent=self.root):
                doc.encoding = "utf-8"
                return self.save(editor,as_new=as_new)
            return False
        except OSError as error:
            messagebox.showerror("Save",str(error),parent=self.root)
            return False
        editor.update_title()
        self.update_status("File saved")
        return True

    def save_all(self):
        for editor in self.editors:
            if editor.document.dirty or not editor.document.path:
                if not self.save(editor): return False
        return True

    def user_input(self):
        self.banner = False
        self.notice = None
        self.update_status()

    def update_status(self, message=None):
        if not hasattr(self,"status"): return
        editor = self.active_editor
        if message:
            text = message
        elif self.notice:
            text = self.notice
        elif self.banner or not editor:
            # Startup banner, kept until the first key or click in an editor.
            text = f"Odin Turbo Pascal {__version_tag__}   |   Created by {__author__}   |   F1 Help"
        else:
            text = str(editor.document.path) if editor.document.path else "Belum disimpan"
        self.status.configure(text=text)
        if editor:
            line, col = editor.text.index("insert").split(".")
            newline = "CRLF" if editor.document.newline == "\r\n" else "LF"
            self.position_label.configure(text=f"Ln {int(line)}, Col {int(col) + 1}")
            self.mode_label.configure(text="OVR" if editor.overwrite_mode else "INS")
            self.encoding_label.configure(text=f"{ENCODINGS.get(editor.document.encoding, editor.document.encoding)}  {newline}")
        else:
            for label in (self.position_label, self.mode_label, self.encoding_label):
                label.configure(text="")
        self.update_actions()

    def update_actions(self):
        """Toolbar buttons that only make sense in some states."""
        if "Stop" in self.tools:
            self.tools["Stop"].state(["!disabled"] if self.program_running else ["disabled"])

    def zoom_font(self, step):
        size = min(30, max(10, self.font.cget("size") + step))
        self.font.configure(size=size)
        self.settings["font_size"] = size
        for editor in self.editors:
            editor.apply_options()

    def edit(self, action):
        if not self.active_editor:return
        text=self.active_editor.text
        try:
            if action=="undo":text.edit_undo()
            elif action=="redo":text.edit_redo()
            elif action=="all":text.tag_add("sel","1.0","end-1c")
            else:text.event_generate({"cut":"<<Cut>>","copy":"<<Copy>>","paste":"<<Paste>>"}[action])
        except tk.TclError:pass
        text.focus_set()

    def delete_line(self):
        if self.active_editor:self.active_editor.text.delete("insert linestart","insert lineend+1c")

    # ---- dialogs ---------------------------------------------------------------------------

    def dialog(self,title,width=640):
        win=tk.Toplevel(self.root)
        win.title(title)
        win.transient(self.root)
        win.resizable(False,False)
        frame=ttk.Frame(win,padding=(18,14))
        frame.pack(fill="both",expand=True)
        win.bind("<Escape>",lambda e:win.destroy())
        win.update_idletasks()
        win.geometry(f"+{self.root.winfo_rootx()+80}+{self.root.winfo_rooty()+80}")
        return win,frame

    def field(self,parent,label,value="",width=50):
        ttk.Label(parent,text=label,anchor="w").pack(fill="x",pady=(7,2))
        var=tk.StringVar(value=value)
        entry=ttk.Entry(parent,textvariable=var,width=width)
        entry.pack(fill="x")
        return var,entry

    def button(self,parent,label,command,default=False):
        return ttk.Button(parent,text=label,command=command,default="active" if default else "normal")

    def buttons(self,parent,*items):
        """A right-aligned row of (label, command) buttons; the first is the default."""
        bar=ttk.Frame(parent)
        bar.pack(fill="x",pady=(14,0))
        for n,(label,command) in enumerate(reversed(items)):
            self.button(bar,label,command,default=n==len(items)-1).pack(side="right",padx=(6,0))
        return bar

    def input(self,title,label,value,callback):
        win,body=self.dialog(title)
        var,entry=self.field(body,label,value)
        def accept():
            if callback(var.get()) is not False:win.destroy()
        self.buttons(body,("OK",accept),("Cancel",win.destroy))
        entry.bind("<Return>",lambda e:accept())
        entry.focus_set()
        entry.select_range(0,"end")
        return win

    def choose(self,title,items,callback):
        win,body=self.dialog(title)
        box=ttk.Frame(body)
        box.pack(fill="both",expand=True)
        listing=ttk.Treeview(box,columns=("label",),show="",height=min(15,max(4,len(items))),selectmode="browse")
        listing.column("label",width=560)
        if len(items)>15:
            # The tutorial alone has 90 examples.
            bar=ttk.Scrollbar(box,orient="vertical",command=listing.yview)
            listing.configure(yscrollcommand=bar.set)
            bar.pack(side="right",fill="y")
        listing.pack(side="left",fill="both",expand=True)
        for n,(label,value) in enumerate(items):listing.insert("","end",iid=str(n),values=(label,))
        def accept(e=None):
            chosen=listing.selection()
            if chosen:
                value=items[int(chosen[0])][1]
                win.destroy()
                callback(value)
        listing.bind("<Double-Button-1>",accept)
        listing.bind("<Return>",accept)
        self.buttons(body,("Open",accept),("Cancel",win.destroy))
        if items:
            listing.selection_set("0")
            listing.focus("0")
        listing.focus_set()
        win.listing=listing
        return win

    def recent(self):self.choose("Recent files",[(p,p) for p in self.settings["recent"]],self.open_file)
    def examples(self):self.choose("Examples",[(p.name,p) for p in sorted((ASSETS/"examples").iterdir()) if p.suffix.lower()==".pas"],self.open_file)
    def examples_ai(self):
        """OTP-AI samples (otp-AI/EXAMPLES), each labelled with its topic; COMMON.INC is only an include file."""
        folder=ASSETS/"otp-AI"/"EXAMPLES"
        items=[(f"{p.name:<14}{AI_EXAMPLE_TOPICS.get(p.stem.upper(),'')}".rstrip(),p) for p in sorted(folder.glob("*.PAS"))] if folder.is_dir() else []
        if not items:
            messagebox.showinfo("Examples - AI","Contoh OTP-AI tidak ditemukan (folder otp-AI/EXAMPLES).",parent=self.root)
            return
        self.choose("Examples - AI",items,self.open_file)

    def examples_graph(self):
        """Graph samples (examples-graph/), each labelled with its topic; they open the graphics window when run."""
        folder=ASSETS/"examples-graph"
        items=[(f"{p.name:<36}{GRAPH_EXAMPLE_TOPICS.get(p.stem.split('_')[1],'')}".rstrip(),p) for p in sorted(folder.glob("grafik_*.pas"))] if folder.is_dir() else []
        if not items:
            messagebox.showinfo("Examples - Graph","Contoh grafik tidak ditemukan (folder examples-graph).",parent=self.root)
            return
        self.choose("Examples - Graph",items,self.open_file)

    def examples_oop(self):
        """Class samples (examples-oop/), each labelled with what it teaches."""
        folder=ASSETS/"examples-oop"
        items=[(f"{p.name:<36}{OOP_EXAMPLE_TOPICS.get(p.stem.split('_')[1],'')}".rstrip(),p) for p in sorted(folder.glob("oop_*.pas"))] if folder.is_dir() else []
        if not items:
            messagebox.showinfo("Examples - OOP","Contoh OOP tidak ditemukan (folder examples-oop).",parent=self.root)
            return
        self.choose("Examples - OOP",items,self.open_file)

    def change_directory(self):
        path=filedialog.askdirectory(parent=self.root,title="Working directory")
        if path:os.chdir(path)

    def find_dialog(self,replace=False):
        if not self.active_editor:return
        win,body=self.dialog("Replace" if replace else "Find")
        find,entry=self.field(body,"Text to find",self.search_term)
        replacement=None
        if replace:replacement,_=self.field(body,"New text")
        sensitive=tk.BooleanVar(value=False)
        ttk.Checkbutton(body,text="Case sensitive",variable=sensitive).pack(anchor="w",pady=(10,0))
        def search():
            self.search_term=find.get()
            self.find_next(case=sensitive.get())
        def change(all_matches=False):
            term=find.get()
            if not term or not self.active_editor:return
            text=self.active_editor.text
            if all_matches:
                content=text.get("1.0","end-1c")
                changed,count=re.subn(re.escape(term),lambda m:replacement.get(),content,flags=0 if sensitive.get() else re.I)
                text.edit_separator()
                text.delete("1.0","end")
                text.insert("1.0",changed)
                text.edit_separator()
                self.update_status(f"{count} replacement(s)")
            else:
                self.search_term=term
                selected=text.get("sel.first","sel.last") if text.tag_ranges("sel") else ""
                match=selected==term if sensitive.get() else selected.lower()==term.lower()
                if match:
                    start=text.index("sel.first")
                    text.delete("sel.first","sel.last")
                    text.insert(start,replacement.get())
                self.find_next(case=sensitive.get())
        items=[("Find next",search)]
        if replace:items+=[("Replace",change),("Replace all",lambda:change(True))]
        self.buttons(body,*items,("Close",win.destroy))
        entry.focus_set()
        entry.bind("<Return>",lambda e:search())
        return win

    def find_next(self,case=False):
        if not self.active_editor:return
        if not self.search_term:return self.find_dialog()
        text=self.active_editor.text
        start=text.index("sel.last") if text.tag_ranges("sel") else text.index("insert")
        match=text.search(self.search_term,start,stopindex="end",nocase=not case,exact=True)
        if not match:match=text.search(self.search_term,"1.0",stopindex=start,nocase=not case,exact=True)
        if match:
            text.tag_remove("sel","1.0","end")
            text.tag_add("sel",match,f"{match}+{len(self.search_term)}c")
            text.mark_set("insert",f"{match}+{len(self.search_term)}c")
            text.see(match)
            self.active_editor.cursor_moved(notify=False)
            self.update_status()
        else:self.update_status("Text not found")

    def goto_line(self):
        if not self.active_editor:return
        def go(value):
            if not value.isdigit() or int(value)<1:return False
            editor=self.active_editor
            if not editor:return
            editor.text.mark_set("insert",f"{int(value)}.0")
            editor.text.see("insert")
            editor.text.focus_set()
            editor.cursor_moved(notify=False)
            self.update_status()
        self.input("Go to line","Line number","1",go)

    # ---- compile and run -------------------------------------------------------------------

    def compile(self,rebuild=False,after=None):
        if self.compiling:
            self.update_status("Compiler is already running")
            return
        if self.program_running:
            messagebox.showinfo("Compile","Hentikan program/debugger melalui Run > Program reset terlebih dahulu.",parent=self.root)
            return
        # Without a primary file, Compile/Run use the most recently active Editor, even from another window.
        if not self.last_editor:return
        if not self.save_all():return
        path=Path(self.settings["main_file"]) if self.settings["main_file"] else self.last_editor.document.path
        if not path or not path.is_file():
            messagebox.showerror("Compile","Primary file tidak ditemukan. Atur Compile > Primary file.",parent=self.root)
            return
        self.compiling=True
        self.pending_action=after
        self.update_status(f"Compiling {path.name} ...")
        # Snapshot settings before the worker starts. The worker never accesses Tk.
        snapshot=Settings(self.settings.path)
        snapshot.values=json.loads(json.dumps(self.settings.values))
        debug=after in DEBUG_ACTIONS
        def worker():
            try:self.messages.put(("build",build(path,snapshot,rebuild,debug=True) if debug else build(path,snapshot,rebuild)))
            except Exception as error:self.messages.put(("build_error",str(error)))
        threading.Thread(target=worker,daemon=True).start()

    def run(self):
        # Ctrl+F9 while stopped in the debugger continues, as in Turbo Pascal.
        if self.debugging:
            self.debug_step("continue")
        else:
            self.compile(after="run")

    def debug(self):
        if self.debugging:
            self.debug_step("continue")
        else:
            self.compile(after="debug")

    def poll(self):
        if self.closed:return
        render=False
        for _ in range(80):
            try:kind,value=self.messages.get_nowait()
            except queue.Empty:break
            if kind=="build":
                self.compiling=False
                self.last_build=value
                self.error_index=-1
                action=self.pending_action
                self.pending_action=None
                self.fill_messages()
                if value.success:
                    self.update_status("Compile successful" if value.executable else "Unit compiled. No executable.")
                    if action and value.executable:self.start_process(action)
                    elif action:messagebox.showinfo("Run","Berkas ini menghasilkan unit. Pilih berkas program sebagai Primary file.",parent=self.root)
                    else:self.show_messages()
                else:
                    self.update_status("Compile failed")
                    self.show_messages()
                    self.next_error()
            elif kind=="build_error":
                self.compiling=False
                self.pending_action=None
                messagebox.showerror("Compiler",value,parent=self.root)
            elif kind=="measure_built":
                self.compiling=False
                self.start_measure(*value)
            elif kind=="checked":
                self.compiling=False
                source,report=value
                if not report["compile"]["success"]:self.show_compile_report(source,report)
                self.show_metrics(source,report)
            elif kind=="output":
                if self.console:
                    self.console.feed(value)
                    render=True
            elif kind=="gfx":
                self.show_graph(value)
            elif kind=="gfx_closed":
                self.graph_closed(value)
            elif kind=="debug":
                self.debug_event(value)
            elif kind=="exit":
                code=self.process_finished(value)
                if self.graph_window and self.graph_window.winfo_exists():self.graph_window.finished()
                if self.console:
                    self.console.feed(f"\r\n\r\n[Process finished, exit code {code}]\r\n")
                    render=True
        if render and self.console:self.console.render()
        self.root.after(40,self.poll)

    def prepare_console(self,title):
        """The Output window, emptied and active, for a program about to start."""
        window=self.show_output()
        window.set_title(f"Output - {title}")
        window.clear()
        window.focus()
        return window

    def start_process(self,action="run"):
        result=self.last_build
        if not result or not result.executable:return
        try:arguments=split_arguments(self.settings["arguments"])
        except ValueError as error:
            messagebox.showerror("Parameters",str(error),parent=self.root)
            return
        self.prepare_console(result.executable.name)
        emit=lambda k,v:self.messages.put((k,v))
        graph_env=self.open_graph_channel(emit)
        self.last_runtime_error=None
        self.clear_error_marks()
        try:
            if action in DEBUG_ACTIONS:
                if not result.debug_info:
                    messagebox.showerror("Debug","Build ini tidak berisi info debug.",parent=self.root)
                    return
                self.debug_start_mode=action
                self.debug_requests.clear()
                self.debugger=DebugSession(locate_toolchain(),result.executable,result.debug_info,arguments,result.source.parent,emit,env=graph_env)
                self.process=self.debugger.process
                self.update_status("Debugging ...")
            else:
                # The RTL of an Odin build reports a runtime error here; Find error maps it to a line.
                report=data_dir()/"runtime-error.txt"
                report.unlink(missing_ok=True)
                self.error_report=(result.debug_info,report) if result.debug_info else None
                self.process=Process([str(result.executable),*arguments],result.source.parent,emit,
                                     env={**graph_env,**({"ODIN_ERROR_FILE":str(report)} if result.debug_info else {})} or None)
                self.update_status("Program berjalan di jendela Output")
        except OSError as error:messagebox.showerror("Run",str(error),parent=self.root)
        self.update_actions()

    def open_graph_channel(self,emit):
        """A new channel for the Graph window of the program about to start; returns the environment that
        tells the program where to connect (empty when the setting graph_window is off)."""
        if self.graph_channel:self.graph_channel.close()
        self.graph_channel=None
        if self.graph_window and self.graph_window.winfo_exists():self.graph_window.destroy()
        self.graph_window=None
        if not self.settings["graph_window"]:return {}
        try:self.graph_channel=GraphChannel(emit)
        except OSError:return {}
        return self.graph_channel.env()

    def show_graph(self,channel):
        if channel is not self.graph_channel:return
        snapshot=channel.snapshot()
        if not snapshot:return
        visible,width,height,asp,data=snapshot
        if not (self.graph_window and self.graph_window.winfo_exists()):
            if not visible:return
            self.graph_window=GraphWindow(self.root,self.send_input)
        self.graph_window.show(visible,width,height,asp,data)

    def graph_closed(self,channel):
        """CloseGraph, or the program ended: the window of a program that ended stays (like Turbo Pascal's last
        picture); CloseGraph removes it."""
        if channel is not self.graph_channel:return
        if not channel.graphics_closed:return
        if self.graph_window and self.graph_window.winfo_exists():self.graph_window.withdraw()

    def process_finished(self,code):
        """The program (or odinpc debug) ended; returns the program's exit code."""
        session=self.debugger
        if session:
            self.notice=None
            if session.exit_code is not None:code=session.exit_code
            session.state="exited"
            session.close()
            self.debugger=None
            self.clear_exec()
            self.refresh_debug_windows()
            if self.restart_debug:
                action,self.restart_debug=self.restart_debug,None
                self.root.after(10,lambda:self.compile(after=action))
        elif self.measuring:
            self.finish_measure(code)
        elif self.error_report:
            debug_info,report=self.error_report
            self.error_report=None
            try:text=report.read_text()
            except OSError:text=""
            location=runtime_error_location(debug_info,text) if text else None
            if location:self.runtime_error_at(*location)
        self.process=None
        self.finished_runs+=1
        if self.output_window:self.output_window.set_title("Output")
        if not self.last_runtime_error:self.update_status(f"Program finished. Exit code {code}")
        self.update_actions()
        return code

    # ---- Ukur and Periksa (metrics reports, odin/metrics.py) ---------------------------------

    def metrics_toolchain(self):
        """odinpc for judge builds, or None (with a message) when this machine has none."""
        odinpc=locate_toolchain()
        if not odinpc or not odin_supported():
            messagebox.showinfo("Metrik","Ukur dan Periksa memerlukan toolchain Odin (odinpc) untuk komputer ini.",parent=self.root)
            return None
        units=[Path(p).expanduser().resolve() for p in self.settings["unit_paths"] if p]+library_unit_paths()
        return metrics_report.Toolchain(odinpc,PACKAGE_ROOT/"rtl",units)

    def metrics_source(self):
        """The file Ukur and Periksa work on (the primary file or the active editor), saved; or None."""
        if self.compiling:
            self.update_status("Compiler is already running")
            return None
        if self.program_running:
            messagebox.showinfo("Metrik","Hentikan program/debugger melalui Run > Program reset terlebih dahulu.",parent=self.root)
            return None
        if not self.last_editor or not self.save_all():return None
        path=Path(self.settings["main_file"]) if self.settings["main_file"] else self.last_editor.document.path
        if not path or not path.is_file():
            messagebox.showerror("Metrik","Primary file tidak ditemukan. Atur Compile > Primary file.",parent=self.root)
            return None
        return path

    def measure(self):
        """Run > Ukur (Shift+F9): a judge build (odinpc --count-steps) runs in the Output window like
        Run; when it ends, the Metrik window shows its steps, heap, call depth, steps per line
        and structure notes."""
        toolchain=self.metrics_toolchain()
        path=self.metrics_source() if toolchain else None
        if not path:return
        self.compiling=True
        self.update_status(f"Building {path.name} for Ukur ...")
        def worker():
            try:
                structure,diagnostics=toolchain.structure(path)
                exe=info=None
                if structure is not None:
                    exe,info,diagnostics=toolchain.build(path,data_dir()/"metrics"/"ukur")
                self.messages.put(("measure_built",(toolchain,path,structure,exe,info,diagnostics)))
            except Exception as error:self.messages.put(("build_error",str(error)))
        threading.Thread(target=worker,daemon=True).start()

    def show_compile_report(self,path,report_or_diagnostics):
        """Compiler messages of a failed judge build, in the Messages window."""
        items=report_or_diagnostics["compile"]["diagnostics"] if isinstance(report_or_diagnostics,dict) else report_or_diagnostics
        diagnostics=[Diagnostic(d.get("file",""),int(d.get("line",0)),int(d.get("column",0)),
                                {"warning":"Warning","note":"Note","hint":"Hint"}.get(d.get("severity"),"Error"),d.get("message",""))
                     for d in items]
        output="\n".join(f"{d.path}({d.line},{d.column}) {d.kind}: {d.message}" for d in diagnostics)
        self.last_build=BuildResult(False,[],output or "Kompilasi gagal.",diagnostics,None,path)
        self.error_index=-1
        self.fill_messages()
        self.show_messages()

    def start_measure(self,toolchain,path,structure,exe,info,diagnostics):
        if exe is None:
            self.update_status("Compile failed")
            self.show_compile_report(path,diagnostics)
            return
        try:arguments=split_arguments(self.settings["arguments"])
        except ValueError as error:
            messagebox.showerror("Parameters",str(error),parent=self.root)
            return
        folder=data_dir()/"metrics"/"ukur"
        stats,report=folder/"ukur.stats",folder/"ukur.error"
        for f in (stats,report):f.unlink(missing_ok=True)
        self.prepare_console(f"Ukur {path.name}")
        self.last_runtime_error=None
        self.clear_error_marks()
        odbg=exe.with_name(exe.name+".odbg")
        self.error_report=(odbg,report) if odbg.is_file() else None
        self.measuring={"toolchain":toolchain,"path":path,"structure":structure,"info":info,"stats":stats,"report":report,
                        "started":time.monotonic()}
        emit=lambda k,v:self.messages.put((k,v))
        try:
            self.process=Process([str(exe),*arguments],path.parent,emit,
                                 env={"ODIN_STATS_FILE":str(stats),"ODIN_ERROR_FILE":str(report)})
            self.update_status("Ukur: program berjalan di jendela Output")
        except OSError as error:
            self.measuring=None
            messagebox.showerror("Ukur",str(error),parent=self.root)
        self.update_actions()

    def finish_measure(self,code):
        m,self.measuring=self.measuring,None
        if self.error_report:
            debug_info,report=self.error_report
            self.error_report=None
            try:text=report.read_text()
            except OSError:text=""
            location=runtime_error_location(debug_info,text) if text else None
            if location:self.runtime_error_at(*location)
        read=lambda p:p.read_text(encoding="utf-8") if p.is_file() else None
        wall=int((time.monotonic()-m["started"])*1000)
        run=metrics_report.Run(code if isinstance(code,int) else -1,b"",wall_ms=wall)
        report=metrics_report.measured(m["path"],m["toolchain"],m["structure"],m["info"],run,read(m["stats"]),read(m["report"]))
        self.show_metrics(m["path"],report)

    def check_package(self):
        """Run > Periksa...: every case of a problem package (a folder with aturan.json and kasus/,
        docs/HELP.txt), run without the Output window; the Metrik window shows verdicts and score."""
        toolchain=self.metrics_toolchain()
        path=self.metrics_source() if toolchain else None
        if not path:return
        folder=filedialog.askdirectory(parent=self.root,title="Pilih folder paket soal",initialdir=str(path.parent))
        if not folder:return
        try:package=metrics_report.load_package(Path(folder))
        except metrics_report.PackageError as error:
            messagebox.showerror("Periksa",f"Paket soal tidak bisa dipakai: {error}",parent=self.root)
            return
        self.compiling=True
        self.update_status(f"Periksa {path.name}: {len(package.cases)} kasus ...")
        def worker():
            try:self.messages.put(("checked",(path,metrics_report.check(path,package,toolchain,data_dir()/"metrics"/"periksa"))))
            except Exception as error:self.messages.put(("build_error",str(error)))
        threading.Thread(target=worker,daemon=True).start()

    def show_metrics(self,path,report):
        """The Metrik window: the report as text; lines with a source line number jump there."""
        self.last_metrics=report
        win=tk.Toplevel(self.root)
        win.title(f"Odin • Metrik • {path.name}")
        win.geometry("820x620")
        toolbar=ttk.Frame(win,padding=(8,6))
        toolbar.pack(fill="x")
        ttk.Label(toolbar,text="Metrik",font=self.ui_font(13,"bold")).pack(side="left")
        self.button(toolbar,"Tutup",win.destroy).pack(side="right",padx=(6,0))
        self.button(toolbar,"Simpan laporan...",lambda:self.save_metrics(report,path)).pack(side="right")
        text=tk.Text(win,font=self.font,wrap="word",padx=22,pady=16,borderwidth=0,highlightthickness=0,cursor="arrow")
        scroll=ttk.Scrollbar(win,command=text.yview)
        scroll.pack(side="right",fill="y")
        text.configure(yscrollcommand=scroll.set)
        text.pack(fill="both",expand=True)
        text.tag_configure("link",foreground="#0b62d6",underline=True)
        for i,(content,line) in enumerate(metrics_report.summary(report)):
            if line:
                tag=f"jump{i}"
                text.insert("end",content,("link",tag))
                text.tag_bind(tag,"<Button-1>",lambda e,l=line:self.show_location(path,l,"metric"))
            else:text.insert("end",content)
            text.insert("end","\n")
        text.configure(state="disabled")
        win.bind("<Escape>",lambda e:win.destroy())
        cases=report.get("cases",[])
        # After process_finished's own "Program finished" status.
        if report.get("score"):status=f"Periksa: skor {report['score']['points']}"
        elif cases:status=f"Ukur: {metrics_report.number(cases[0].get('steps'))} langkah"
        else:status="Metrik: gagal compile"
        self.root.after(1,lambda:self.update_status(status))
        return win

    def save_metrics(self,report,path):
        target=filedialog.asksaveasfilename(parent=self.root,title="Simpan laporan metrik",defaultextension=".json",
                                            initialdir=str(path.parent),initialfile=path.stem+".metrik.json",
                                            filetypes=[("Laporan metrik","*.json")])
        if target:
            atomic_write(Path(target),json.dumps(report,ensure_ascii=False,indent=2).encode("utf-8"))
            self.update_status(f"Laporan disimpan: {Path(target).name}")

    def copy_screen(self):
        if self.console:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.console.screen.text())

    def send_input(self,value):
        if self.process:self.process.write(value)

    def stop(self):
        if self.debugger and self.debugger.alive:self.debugger.terminate()
        elif self.process:self.process.stop()

    # ---- debugger ---------------------------------------------------------------------

    @property
    def debug_stopped(self):
        return bool(self.debugging and self.debugger.stopped)

    def debug_step(self,kind):
        """kind: into, over, out, cursor or continue."""
        editor=self.active_editor or self.last_editor
        if kind=="cursor":
            if not editor or not editor.document.path:return
            self.pending_cursor=(editor.document.path,int(editor.text.index("insert").split(".")[0]))
        if not self.debugging:
            # Turbo Pascal style: F7/F8 start the program and stop at its first statement.
            self.compile(after={"into":"step","over":"step","cursor":"cursor"}.get(kind,"debug"))
            return
        session=self.debugger
        if not session.stopped:
            self.update_status("Program is running")
            return
        if self.debug_source_changed:
            self.debug_source_changed=False
            if messagebox.askyesno("Debug","Sumber berubah. Build ulang?",parent=self.root):
                self.restart_debug="step"
                session.terminate()
                return
        self.clear_exec()
        self.notice=None
        self.update_status("Running ...")
        if kind=="into":session.step_into()
        elif kind=="over":session.step_over()
        elif kind=="out":session.step_out()
        elif kind=="cursor":session.run_to(*self.pending_cursor)
        else:session.resume()

    def debug_request(self,request,callback):
        self.debug_requests[request]=callback

    def debug_event(self,event):
        session=self.debugger
        if not session:return
        session.update(event)
        kind=event.get("event")
        if kind=="ready":
            for editor in self.editors:
                if editor.document.path:session.set_breakpoints(editor.document.path,editor.document.breakpoints)
            mode=self.debug_start_mode
            if mode=="step":session.start("into")
            elif mode=="cursor" and self.pending_cursor:session.start("run_to",*self.pending_cursor)
            else:session.start("run")
        elif kind=="stopped":
            self.debug_frame=0
            self.debug_source_changed=False
            path,line=Path(event["file"]),int(event["line"])
            self.show_location(path,line,"exec")
            self.notice=f"Stopped at {path.name}({line}): {event.get('reason','')}. F7 Trace  F8 Step  Ctrl+F9 Run"
            self.update_status()
            self.refresh_debug_windows()
        elif kind=="result":
            callback=self.debug_requests.pop(event.get("id"),None)
            if callback:callback(event)
        elif kind=="breakpoints":
            moved=dict((a,b) for a,b in event.get("moved",[]))
            editor=self.editor_for(Path(event.get("file","")))
            if editor and moved:
                editor.set_breakpoints({moved.get(l,l) for l in editor.document.breakpoints},notify=False)
        elif kind=="runtime_error":
            self.runtime_error_at(event.get("code"),Path(event["file"]) if event.get("file") else None,event.get("line"))
        elif kind=="exited":
            self.clear_exec()
        elif kind=="error":
            messagebox.showerror("Debug",event.get("message",""),parent=self.root)

    def editor_for(self,path):
        for editor in self.editors:
            if editor.document.path and editor.document.path==path.resolve():return editor
        return None

    def show_location(self,path,line,tag):
        """Opens path at line; tag "exec" marks the execution bar, "error" a runtime error."""
        editor=self.editor_for(path) or (self.open_file(path) if path.is_file() else None)
        if not editor:return None
        self.activate(editor)
        if tag=="exec":
            self.clear_exec()
            editor.show_exec(line)
        else:
            editor.text.tag_remove(tag,"1.0","end")
            editor.text.tag_add(tag,f"{line}.0",f"{line}.0 lineend")
            editor.text.mark_set("insert",f"{line}.0")
            editor.text.see(f"{line}.0")
            editor.cursor_moved(notify=False)
        return editor

    def clear_exec(self):
        for editor in self.editors:editor.clear_exec()

    def clear_error_marks(self):
        for editor in self.editors:editor.text.tag_remove("error","1.0","end")

    def runtime_error_at(self,code,path,line):
        self.last_runtime_error=(code,path,line)
        rtl=(PACKAGE_ROOT/"rtl").resolve()
        if path and line and path.is_file() and rtl not in path.resolve().parents:
            self.notice=f"Runtime error {code} at {path.name}({line})"
            self.show_location(path,line,"error")
        else:
            self.notice=f"Runtime error {code}"
        self.update_status()

    def find_error(self):
        error=self.last_runtime_error
        if error and error[1] and error[2]:
            self.runtime_error_at(*error)
        elif error:
            messagebox.showinfo("Find error",f"Runtime error {error[0]} terjadi di luar kode program (di unit RTL).",parent=self.root)
        else:
            messagebox.showinfo("Find error","Belum ada runtime error. Posisinya dicatat saat program dijalankan.",parent=self.root)

    def breakpoints_changed(self,editor):
        if self.debugging and editor.document.path:
            self.debugger.set_breakpoints(editor.document.path,editor.document.breakpoints)

    def source_modified(self,editor):
        if self.debugging:self.debug_source_changed=True

    # Watches, Local variables and Call stack: child windows filled when the program stops.
    def debug_window(self,attribute,kind,place=None,activate=True):
        window=getattr(self,attribute)
        if window is None:
            window=self.add_window(kind(self),place or dict(DEBUG_PLACES[attribute]),activate=activate)
            setattr(self,attribute,window)
        if activate:self.activate(window)
        return window

    def debug_window_closed(self,window):
        for attribute in ("watch_window","locals_window","stack_window"):
            if getattr(self,attribute) is window:setattr(self,attribute,None)

    def show_watches(self):
        window=self.debug_window("watch_window",WatchWindow)
        self.draw_watches()
        return window

    def show_locals(self):
        window=self.debug_window("locals_window",LocalsWindow)
        self.refresh_locals()
        return window

    def show_stack(self):
        window=self.debug_window("stack_window",StackWindow)
        self.refresh_stack()
        return window

    def draw_watches(self):
        if self.watch_window:
            self.watch_window.set_rows([(e,self.watch_values.get(i,"")) for i,e in enumerate(self.watches)])

    def add_watch(self):
        word=self.word_at_cursor()
        def add(value):
            if not value.strip():return False
            self.watches.append(value.strip())
            self.show_watches()
            self.refresh_watches()
        self.input("Add watch","Watch expression",word,add)

    def delete_watch(self,index):
        if index is None or index>=len(self.watches):return
        del self.watches[index]
        self.watch_values={i:self.watch_values.get(i+(i>=index)) for i in range(len(self.watches))}
        self.draw_watches()

    def edit_watch(self,index):
        if index is None or index>=len(self.watches):return self.add_watch()
        def change(value):
            if not value.strip():return False
            self.watches[index]=value.strip()
            self.refresh_watches()
        self.input("Edit watch","Watch expression",self.watches[index],change)

    def refresh_watches(self):
        if self.debug_stopped:
            for i,expression in enumerate(self.watches):
                def done(event,i=i):
                    self.watch_values[i]=event["value"] if event.get("ok") else event.get("error","")
                    self.draw_watches()
                self.debug_request(self.debugger.evaluate(expression,self.debug_frame),done)
        else:
            for i in range(len(self.watches)):self.watch_values.setdefault(i,"")
        self.draw_watches()

    def refresh_locals(self):
        if not self.locals_window:return
        if not self.debug_stopped:
            self.locals_window.set_rows([])
            return
        def done(event):
            if self.locals_window:
                rows=[(v['name'],v['value']) for v in event.get("locals",[])] if event.get("ok") else [(event.get("error",""),"")]
                self.locals_window.set_rows(rows)
        self.debug_request(self.debugger.locals(self.debug_frame),done)

    def refresh_stack(self):
        if not self.debug_stopped:
            self.stack_frames=[]
            if self.stack_window:self.stack_window.set_rows([])
            return
        def done(event):
            self.stack_frames=event.get("frames",[]) if event.get("ok") else []
            if self.stack_window:
                self.stack_window.set_rows([(f['name'],f"{Path(f['file']).name}:{f['line']}") for f in self.stack_frames])
                if self.stack_frames:
                    self.stack_window.select(min(self.debug_frame,len(self.stack_frames)-1))
        self.debug_request(self.debugger.stack(),done)

    def refresh_debug_windows(self):
        self.refresh_watches()
        self.refresh_locals()
        self.refresh_stack()

    def select_frame(self,index):
        if index is None or index>=len(self.stack_frames):return
        self.debug_frame=index
        frame=self.stack_frames[index]
        editor=self.editor_for(Path(frame["file"]))
        if editor or Path(frame["file"]).is_file():
            editor=editor or self.open_file(Path(frame["file"]))
            if editor:
                editor.text.mark_set("insert",f"{frame['line']}.0")
                editor.text.see(f"{frame['line']}.0")
                editor.cursor_moved(notify=False)
        self.refresh_watches()
        self.refresh_locals()
        if self.stack_window:self.activate(self.stack_window)

    def word_at_cursor(self):
        editor=self.active_editor or self.last_editor
        if not editor:return ""
        text=editor.text
        if text.tag_ranges("sel"):return text.get("sel.first","sel.last").strip()
        return text.get("insert wordstart","insert wordend").strip()

    def evaluate(self):
        win,body=self.dialog("Evaluate and modify")
        expression,entry=self.field(body,"Expression",self.word_at_cursor())
        result=tk.StringVar()
        ttk.Label(body,text="Result",anchor="w").pack(fill="x",pady=(7,2))
        ttk.Entry(body,textvariable=result,state="readonly",width=50).pack(fill="x")
        new_value,_=self.field(body,"New value")
        def show(event):
            if win.winfo_exists():result.set(event["value"] if event.get("ok") else event.get("error",""))
        def run(command):
            if not self.debug_stopped:
                result.set("Program tidak sedang berhenti di debugger (F7/F8 atau breakpoint).")
                return
            if command=="modify":
                def changed(event):
                    show(event)
                    self.refresh_debug_windows()
                self.debug_request(self.debugger.modify(expression.get(),new_value.get(),self.debug_frame),changed)
            else:
                self.debug_request(self.debugger.evaluate(expression.get(),self.debug_frame),show)
        self.buttons(body,("Evaluate",lambda:run("evaluate")),("Modify",lambda:run("modify")),("Close",win.destroy))
        entry.bind("<Return>",lambda e:run("evaluate"))
        entry.focus_set()
        entry.select_range(0,"end")
        return win

    def breakpoint(self):
        if self.active_editor:self.active_editor.toggle_breakpoint()
    def clear_breakpoints(self):
        for editor in self.editors:
            editor.set_breakpoints(set())

    # ---- compiler messages -----------------------------------------------------------------

    def fill_messages(self):
        """The Messages window for the last build: one row per diagnostic, a summary row, then the command and the
        compiler's raw output."""
        window,result=self.messages_window,self.last_build
        if not window:return
        window.list.delete(*window.list.get_children())
        if not result:
            window.set_log("Belum ada kompilasi. F9 Make, Ctrl+F9 Run.")
            return
        for n,diag in enumerate(result.diagnostics):
            window.list.insert("","end",iid=str(n),tags=(diag.kind,),
                               values=(diag.kind,f"{Path(diag.file).name}:{diag.line}:{diag.column}",diag.message))
        summary="Compile successful" if result.success else "Compile failed"
        if result.success and result.executable:summary+=f": {result.executable.name}"
        window.list.insert("","end",iid="summary",values=("Info",result.source.name if result.source else "",summary))
        window.set_log(f"$ {join_command(result.command)}\n{result.output}".rstrip())

    def show_messages(self):
        if not self.last_build:
            self.update_status("No compiler messages")
            return
        window=self.show_messages_window()
        children=window.list.get_children()
        if children:
            window.list.selection_set(children[0])
            window.list.focus(children[0])

    def jump_selected_message(self):
        window=self.messages_window
        chosen=window.list.selection() if window else ()
        if chosen and chosen[0]!="summary" and self.last_build:
            self.error_index=int(chosen[0])
            self.jump_diagnostic(self.last_build.diagnostics[self.error_index])

    def jump_diagnostic(self,diag):
        path=Path(diag.file)
        if not path.is_absolute():path=self.last_build.source.parent/path
        editor=self.open_file(path)
        if editor:
            pos=f"{diag.line}.{max(0,diag.column-1)}"
            editor.text.mark_set("insert",pos)
            editor.text.tag_add("error",f"{diag.line}.0",f"{diag.line}.end")
            editor.text.see(pos)
            editor.cursor_moved(notify=False)
            self.update_status(diag.message)

    def next_error(self):
        if self.last_build and self.last_build.diagnostics:
            self.error_index=(self.error_index+1)%len(self.last_build.diagnostics)
            item=str(self.error_index)
            window=self.messages_window
            if window and window.list.exists(item):
                window.list.selection_set(item)
                window.list.see(item)
            self.jump_diagnostic(self.last_build.diagnostics[self.error_index])

    def primary_file(self):
        path=filedialog.askopenfilename(parent=self.root,title="Primary program",filetypes=[("Pascal","*.pas *.PAS *.pp")])
        if path:
            self.settings["main_file"]=path
            self.settings.save()
            self.update_status("Primary file: "+path)

    def clear_primary(self):
        self.settings["main_file"]=""
        self.settings.save()
        self.update_status("Primary file cleared. Compile uses the active editor.")

    def export_executable(self):
        if not self.last_build or not self.last_build.executable:
            messagebox.showinfo("Export","Kompilasi program terlebih dahulu.",parent=self.root)
            return
        path=filedialog.asksaveasfilename(parent=self.root,title="Export native executable",initialfile=self.last_build.executable.name)
        if path:
            try:
                shutil.copy2(self.last_build.executable,path)
                self.update_status("Executable exported: "+path)
            except OSError as error:messagebox.showerror("Export",str(error),parent=self.root)

    # ---- options -------------------------------------------------------------------------

    def parameters(self):
        def accept(value):
            try:split_arguments(value)
            except ValueError as error:
                messagebox.showerror("Parameters",str(error),parent=self.root)
                return False
            self.settings["arguments"]=value
            self.settings.save()
        self.input("Program parameters","Arguments, e.g. \"hello world\" 123",self.settings["arguments"],accept)

    def options(self,tab="Compiler"):
        """Options: one dialog with the tabs Compiler, Directories, Editor and Environment. OK and Apply check the
        numbers, store the settings and apply them to the open windows."""
        win,body=self.dialog("Options")
        notebook=ttk.Notebook(body)
        notebook.pack(fill="both",expand=True)
        pages={name:ttk.Frame(notebook,padding=(14,12)) for name in OPTION_TABS}
        for name,page in pages.items():notebook.add(page,text=name)
        flags={key:tk.BooleanVar(value=self.settings[key]) for key in
               ("range_checks","overflow_checks","syntax_colors","graph_window","save_desktop","fit_console")}
        page=pages["Compiler"]
        ttk.Label(page,text="Odin native compiler, Turbo Pascal 7 + class").pack(anchor="w",pady=(0,8))
        for key,label in (("range_checks","Range checks ($R+)"),("overflow_checks","Overflow checks ($Q+)")):
            ttk.Checkbutton(page,text=label,variable=flags[key]).pack(anchor="w",pady=2)
        ttk.Label(page,text=f"Primary file: {self.settings['main_file'] or '(active editor)'}").pack(anchor="w",pady=(12,0))
        page=pages["Directories"]
        ttk.Label(page,text="Satu direktori per baris. Path dengan spasi didukung.").pack(anchor="w")
        paths={}
        for key,label in (("unit_paths","Unit search paths"),("include_paths","Include search paths")):
            ttk.Label(page,text=label).pack(anchor="w",pady=(10,2))
            text=tk.Text(page,width=60,height=4,font=self.font,highlightthickness=1)
            text.pack(fill="x")
            text.insert("1.0","\n".join(self.settings[key]))
            paths[key]=text
        page=pages["Editor"]
        numbers={}
        def number(page,key,label,low,high):
            row=ttk.Frame(page)
            row.pack(fill="x",pady=3)
            ttk.Label(row,text=label,width=26).pack(side="left")
            numbers[key]=(tk.StringVar(value=str(self.settings[key])),low,high,label)
            ttk.Spinbox(row,from_=low,to=high,textvariable=numbers[key][0],width=6).pack(side="left")
        number(page,"font_size","Font size (10..30)",10,30)
        number(page,"tab_width","Tab width (1..8)",1,8)
        themes={"Terang":"light","Gelap":"dark"}
        theme=tk.StringVar(value=next(k for k,v in themes.items() if v==self.settings["theme"]))
        row=ttk.Frame(page)
        row.pack(fill="x",pady=3)
        ttk.Label(row,text="Theme",width=26).pack(side="left")
        ttk.Combobox(row,textvariable=theme,values=list(themes),state="readonly",width=12).pack(side="left")
        ttk.Checkbutton(page,text="Syntax colors",variable=flags["syntax_colors"]).pack(anchor="w",pady=(8,0))
        page=pages["Environment"]
        number(page,"console_font_size","Output font size (8..30)",8,30)
        ttk.Checkbutton(page,text="Fit Output: smaller text when 80x25 does not fit the Output window",variable=flags["fit_console"]).pack(anchor="w",pady=(8,2))
        ttk.Checkbutton(page,text="Graph window for programs that use the Graph unit",variable=flags["graph_window"]).pack(anchor="w",pady=(8,2))
        ttk.Checkbutton(page,text="Save desktop: reopen files and windows where they were",variable=flags["save_desktop"]).pack(anchor="w",pady=2)
        def apply():
            values={}
            for key,(var,low,high,label) in numbers.items():
                try:value=int(var.get())
                except ValueError:value=None
                if value is None or not low<=value<=high:
                    messagebox.showerror("Options",f"{label}: masukkan angka dalam rentang.",parent=win)
                    return False
                values[key]=value
            self.settings.values.update(values)
            for key,var in flags.items():self.settings[key]=var.get()
            for key,text in paths.items():
                self.settings[key]=[str(Path(p.strip()).expanduser().resolve()) for p in text.get("1.0","end-1c").splitlines() if p.strip()]
            self.settings["theme"]=themes[theme.get()]
            self.font.configure(size=self.settings["font_size"])
            self.console_font.configure(size=self.settings["console_font_size"])
            for editor in self.editors:editor.apply_options()
            if self.output_window:self.output_window.fit()
            if self.console:self.console.render()
            self.settings.save()
            self.update_status()
        def accept():
            if apply() is not False:win.destroy()
        self.buttons(body,("OK",accept),("Cancel",win.destroy),("Apply",apply))
        notebook.select(pages[tab] if tab in pages else 0)
        win.notebook=notebook
        return win

    def compiler_options(self):return self.options("Compiler")
    def directory_options(self):return self.options("Directories")
    def editor_options(self):return self.options("Editor")
    def environment_options(self):return self.options("Environment")

    # ---- help ------------------------------------------------------------------------------

    def show_text(self,title,content,image=None):
        win=tk.Toplevel(self.root)
        win.title(title)
        win.geometry("900x620")
        text=tk.Text(win,font=self.font,wrap="word",padx=22,pady=20,borderwidth=0,highlightthickness=0)
        scroll=ttk.Scrollbar(win,command=text.yview)
        scroll.pack(side="right",fill="y")
        text.configure(yscrollcommand=scroll.set)
        text.pack(fill="both",expand=True)
        if image:
            text.image_create("end",image=image)
            text.insert("end","\n\n")
            text.tag_configure("logo",justify="center")
            text.tag_add("logo","1.0","1.end")
        text.insert("end",content)
        text.configure(state="disabled")
        win.bind("<Escape>",lambda e:win.destroy())
        return text

    def help(self,name="HELP.txt"):
        try:content=(ASSETS/"docs"/name).read_text(encoding="utf-8")
        except OSError:content="Dokumentasi tidak ditemukan. Lihat README.txt."
        self.show_text("Odin Help",content)

    def help_topic(self):
        """F1: docs/help.html at the topic of the word under the cursor (or the selection) in the editor."""
        editor=self.active_editor
        word=self.word_at_cursor() if editor else ""
        word=word.splitlines()[0].strip() if word else ""
        self.help_html(word if re.fullmatch(r"\w+",word) else "")

    def reference(self):self.help("PASCAL.txt")
    def book(self):
        """Help > Buku: the tutorial book, opened in the system's PDF viewer (scripts/build_book.py makes it)."""
        self.open_document("Buku",ASSETS/"docs"/BOOK)
    def help_html(self,topic=""):
        """Help > Contents: docs/help.html (scripts/build_help.py makes it) in the default browser. With a topic it
        opens at the reference row k-<name> when the page has one, else with the topic typed in the page's search."""
        page=ASSETS/"docs"/HELP_HTML
        if topic and page.is_file():
            try:
                anchor="k-"+re.sub(r"[^a-z0-9]+","-",topic.lower()).strip("-")
                if f'id="{anchor}"' not in page.read_text(encoding="utf-8"):anchor="cari="+quote(topic)
                if webbrowser.open(f"{page.as_uri()}#{anchor}"):
                    self.update_status(f"Help: {topic}")
                    return
            except OSError:pass
        self.open_document("Help",page)

    def open_document(self,title,path):
        """Open a bundled document with the system's default application."""
        if not path.is_file():
            messagebox.showerror(title,f"Berkas tidak ditemukan:\n{path}",parent=self.root)
            return
        try:
            if sys.platform=="win32":os.startfile(path)
            else:subprocess.Popen(["/usr/bin/open" if sys.platform=="darwin" else "xdg-open",str(path)],stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        except OSError as error:
            messagebox.showerror(title,f"Berkas tidak bisa dibuka: {error}\n{path}",parent=self.root)
            return
        self.update_status(f"Opening {path.name}")

    def about(self):
        self.show_text("About Odin Turbo Pascal",f"ODIN TURBO PASCAL\nVersion {__version_tag__}\nCreated by {__author__}\n\nIndependent Pascal IDE with a windowed interface on every OS.\nPython / Tk + Odin native toolchain (compiler, RTL, debugger).\n\nThe Pascal dialect and keyboard shortcuts follow Turbo Pascal 7.\nThis software is not Borland Turbo Pascal and is not affiliated with Borland.\nNo Borland binaries, logos, fonts, or help files are included.\n\nNative Pascal compilation for the host CPU.\nIntel x86_64 and Apple Silicon arm64 use the same application sources.\n\n{__copyright__}.\nThis program is free software: you can redistribute it and/or modify it\nunder the terms of the GNU General Public License, version 3 or later.\nIt comes with ABSOLUTELY NO WARRANTY. See LICENSE and THIRD_PARTY.txt.\n",self.logo_small)

    def environment(self):
        self.show_text("Environment",f"Odin {__version_tag__}\n\nOS: {platform.platform()}\nCPU: {platform.machine()}\nPython: {sys.version}\nRuntime: {sys.executable}\nTk: {self.root.tk.call('info','patchlevel')}\nOdin toolchain: {locate_toolchain() or 'NOT FOUND'}\nPrimary file: {self.settings['main_file'] or '(active editor)'}\nSettings: {self.settings.path}\n")

    # ---- session -------------------------------------------------------------------------

    def recover_tick(self):
        if self.closed:return
        try:self.write_session()
        except OSError:pass
        self.root.after(10000,self.recover_tick)

    def write_session(self):
        items=[{"path":str(e.document.path) if e.document.path else None,"text":e.text.get("1.0","end-1c"),
                "saved_text":e.document.saved_text,"encoding":e.document.encoding,"newline":e.document.newline,
                "disk_hash":e.document.disk_hash,"breakpoints":sorted(e.document.breakpoints)} for e in self.editors]
        atomic_write(self.session,json.dumps(items,ensure_ascii=False).encode())

    def restore_session(self):
        try:
            items=json.loads(self.session.read_text(encoding="utf-8"))
            if not isinstance(items,list) or not items:return
            if not messagebox.askyesno("Recover session","Sesi sebelumnya belum ditutup normal. Pulihkan isi editor?",parent=self.root):
                self.session.unlink(missing_ok=True)
                return
            for item in items:
                doc=Document(item["text"],Path(item["path"]) if item.get("path") else None,
                             item.get("encoding","utf-8"),item.get("newline","\n"),item.get("saved_text",""),item.get("disk_hash",""))
                # Sessions saved before breakpoints were recorded have no "breakpoints" field.
                self.new_document(doc).set_breakpoints(item.get("breakpoints",[]),notify=False)
        except (OSError,ValueError,KeyError,TypeError):pass

    def quit(self):
        if self.compiling:
            messagebox.showinfo("Exit","Tunggu kompilasi selesai sebelum keluar.",parent=self.root)
            return
        if self.program_running:
            if not messagebox.askyesno("Exit","Hentikan program yang masih berjalan dan keluar?",parent=self.root):return
        # Gather decisions first. Cancel must not close any editor.
        for editor in self.editors:
            if editor.document.dirty:
                self.activate(editor)
                answer=messagebox.askyesnocancel("Save changes",f"Simpan {editor.document.path.name if editor.document.path else 'NONAME.PAS'}?",parent=self.root)
                if answer is None or (answer and not self.save(editor)):return
        self.stop()
        self.settings["desktop"]=self.desktop_state() if self.settings["save_desktop"] else {}
        self.settings["geometry"]=self.root.geometry()
        self.settings.save()
        self.session.unlink(missing_ok=True)
        self.closed=True
        self.cancel_callbacks()
        self.root.destroy()

    def cancel_callbacks(self):
        for callback in self.root.tk.call("after", "info"):
            self.root.after_cancel(callback)


def macos_app_name(name):
    """Tk names the application menu and its About, Hide and Quit items after CFBundleName of the main bundle, which
    is Python when the IDE runs on Python.app (from source, and from the .app, whose launcher starts python3). Sets it
    in the bundle's info dictionary through the Objective-C runtime; call before Tk starts. Returns the name the
    bundle reports afterwards, or None where this is not possible."""
    import ctypes
    import ctypes.util
    try:
        objc=ctypes.cdll.LoadLibrary(ctypes.util.find_library("objc"))
        ctypes.cdll.LoadLibrary(ctypes.util.find_library("Foundation"))
    except (OSError,TypeError):
        return None
    objc.objc_getClass.restype=objc.sel_registerName.restype=ctypes.c_void_p
    objc.objc_getClass.argtypes=objc.sel_registerName.argtypes=[ctypes.c_char_p]
    address=ctypes.cast(objc.objc_msgSend,ctypes.c_void_p).value
    # objc_msgSend gets an exact prototype per call: arm64 does not pass variadic arguments like fixed ones.
    send=lambda restype,*argtypes:ctypes.CFUNCTYPE(restype,ctypes.c_void_p,ctypes.c_void_p,*argtypes)(address)
    sel=objc.sel_registerName
    def string(text):
        new=send(ctypes.c_void_p)(objc.objc_getClass(b"NSString"),sel(b"alloc"))
        return send(ctypes.c_void_p,ctypes.c_char_p)(new,sel(b"initWithUTF8String:"),text.encode("utf-8"))
    bundle=send(ctypes.c_void_p)(objc.objc_getClass(b"NSBundle"),sel(b"mainBundle"))
    info=send(ctypes.c_void_p)(bundle,sel(b"infoDictionary")) if bundle else None
    # An immutable dictionary would raise an Objective-C exception, which ends the process: ask first.
    if not info or not send(ctypes.c_bool,ctypes.c_void_p)(info,sel(b"respondsToSelector:"),sel(b"setObject:forKey:")):
        return None
    for key in ("CFBundleName","CFBundleDisplayName"):
        send(None,ctypes.c_void_p,ctypes.c_void_p)(info,sel(b"setObject:forKey:"),string(name),string(key))
    value=send(ctypes.c_void_p,ctypes.c_void_p)(bundle,sel(b"objectForInfoDictionaryKey:"),string("CFBundleName"))
    text=send(ctypes.c_char_p)(value,sel(b"UTF8String")) if value else None
    return text.decode("utf-8") if text else None


def main():
    if AQUA:
        macos_app_name("Odin Turbo Pascal")
    root=tk.Tk(className="OdinTurboPascal")
    lock = lock_instance(data_dir() / "instance.lock")
    if lock is None:
        root.withdraw()
        messagebox.showinfo("Odin Turbo Pascal", "Odin sudah berjalan. Gunakan File > Open pada jendela yang tersedia.", parent=root)
        root.destroy()
        return
    app=App(root)
    for argument in sys.argv[1:]:
        if not argument.startswith("-psn_"):
            app.open_file(Path(argument))
    try:
        root.mainloop()
    finally:
        unlock_instance(lock)


if __name__=="__main__":main()
