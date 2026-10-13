# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Classic text-inspired desktop interface; all commands are local."""
from __future__ import annotations

import json
import os
import platform
import queue
import re
import shlex
import shutil
import subprocess
import sys
import threading
import traceback
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox
from tkinter import font as tkfont

from . import __author__, __copyright__, __version__
from .core import Document, Settings, atomic_write, build, data_dir, locate_compiler, syntax_spans
from .terminal import Process, Screen, TerminalView

BLUE = "#0000aa"
CYAN = "#00aaaa"
YELLOW = "#ffff55"
WHITE = "#ffffff"
GRAY = "#aaaaaa"
BLACK = "#000000"
ASSETS = Path(__file__).resolve().parent.parent
TEMPLATE = "program Untitled;\n\nbegin\n  WriteLn('Hello, Pascal!');\nend.\n"


class Box:
    """Text-mode window: a one-pixel line frame with the title sitting on the top edge (OTP v2.0 style)."""

    def __init__(self, parent, title, fg, bg, font, double=False):
        self.fg, self.bg, self.font, self.double = fg, bg, font, double
        self.frame = tk.Frame(parent, bg=bg, borderwidth=0, highlightthickness=0)
        self.border = tk.Canvas(self.frame, bg=bg, highlightthickness=0, borderwidth=0)
        self.border.place(x=0, y=0, relwidth=1, relheight=1)
        self.inner = tk.Frame(self.frame, bg=bg)
        self.title = tk.Label(self.frame, text=title, bg=bg, fg=fg, font=font, padx=0, pady=0, borderwidth=0)
        self.relayout()
        self.border.bind("<Configure>", lambda e: self.draw())

    def relayout(self):
        self.inner.pack_forget()
        self.inner.pack(fill="both", expand=True, padx=8, pady=(self.font.metrics("linespace") + 1, 7))
        self.title.place(x=self.font.measure("  "), y=0)
        self.draw()

    def configure(self, title=None, fg=None, double=None):
        if title is not None: self.title.configure(text=title)
        if fg is not None:
            self.fg = fg
            self.title.configure(fg=fg)
        if double is not None: self.double = double
        self.draw()

    def draw(self):
        canvas = self.border
        canvas.delete("all")
        w, h = canvas.winfo_width(), canvas.winfo_height()
        top = self.font.metrics("linespace") // 2
        if w < 12 or h < top + 8:
            return
        canvas.create_rectangle(3, top, w - 4, h - 4, outline=self.fg)
        if self.double:
            canvas.create_rectangle(6, top + 3, w - 7, h - 7, outline=self.fg)


class Editor:
    def __init__(self, app, document, number):
        self.app, self.document, self.number = app, document, number
        self.box = Box(app.desktop, "", YELLOW, BLUE, app.font, double=True)
        self.frame = self.box.frame
        self.title = self.box.title
        content = self.box.inner
        self.gutter = tk.Canvas(content, width=app.font.measure(" 99999 "), bg=BLUE, highlightthickness=0, cursor="hand2")
        self.gutter.pack(side="left", fill="y")
        self.text = tk.Text(content, bg=BLUE, fg=YELLOW, insertbackground=WHITE, selectbackground=CYAN,
                            selectforeground=WHITE, inactiveselectbackground=CYAN, font=app.font, wrap="none",
                            undo=True, maxundo=500, borderwidth=0, highlightthickness=0, padx=3, pady=3,
                            exportselection=False, insertwidth=2, insertontime=550, insertofftime=350)
        scrollbar = tk.Scrollbar(content, command=self.text.yview, bg=CYAN, troughcolor=BLUE, width=14,
                                 borderwidth=0, highlightthickness=0)
        scrollbar.pack(side="right", fill="y")
        self.text.configure(yscrollcommand=lambda a,b: (scrollbar.set(a,b), self.draw_breakpoints()))
        horizontal = tk.Scrollbar(content, orient="horizontal", command=self.text.xview, bg=CYAN, troughcolor=BLUE,
                                  width=10, borderwidth=0, highlightthickness=0)
        horizontal.pack(side="bottom", fill="x")
        self.text.pack(fill="both", expand=True)
        self.text.configure(xscrollcommand=horizontal.set)
        self.text.insert("1.0", document.text)
        self.text.edit_reset()
        self.text.edit_modified(False)
        for name, color in (("keyword", WHITE), ("string", "#55ffff"), ("comment", GRAY), ("number", "#55ff55")):
            self.text.tag_configure(name, foreground=color)
        self.text.tag_configure("breakpoint", background="#aa0000")
        self.text.tag_configure("error", background="#aa0000", foreground=WHITE)
        self.text.tag_configure("found", background=CYAN, foreground=BLACK)
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
        for widget in (self.title, self.box.border):
            widget.bind("<Button-1>", self.drag_start)
            widget.bind("<B1-Motion>", self.drag)
            widget.bind("<Double-Button-1>", lambda e: app.zoom(self))
        self.overwrite_mode = False
        self.highlight_job = None
        self.apply_options()
        self.update_title()

    def apply_options(self):
        self.text.configure(tabs=(self.app.font.measure(" " * self.app.settings["tab_width"]),))
        self.gutter.configure(width=self.app.font.measure(" 99999 "))
        self.box.relayout()
        self.highlight()
        self.draw_breakpoints()

    def update_title(self):
        doc = self.document
        name = doc.path.name if doc.path else f"NONAME{self.number:02d}.PAS"
        editors = self.app.editors
        index = editors.index(self) + 1 if self in editors else len(editors) + 1
        self.title.configure(text=f" {name.upper()}{' *' if doc.dirty else ''}  [{index} / {max(len(editors), index)}] ")

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
        self.draw_breakpoints()

    def highlight(self):
        self.highlight_job = None
        for name in ("keyword", "string", "comment", "number"):
            self.text.tag_remove(name, "1.0", "end")
        if self.app.settings["syntax"]:
            for name, start, end in syntax_spans(self.text.get("1.0", "end-1c")):
                self.text.tag_add(name, f"1.0+{start}c", f"1.0+{end}c")
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

    def overwrite(self, e):
        if self.overwrite_mode and e.char and e.char.isprintable() and not (e.state & 0x0c) and not self.text.tag_ranges("sel"):
            if self.text.get("insert", "insert+1c") != "\n":
                self.text.delete("insert", "insert+1c")

    def drag_start(self, e):
        self.app.activate(self)
        self.drag_anchor = (e.x_root, e.y_root, self.frame.winfo_x(), self.frame.winfo_y())

    def drag(self, e):
        x,y,left,top = self.drag_anchor
        self.frame.place_configure(x=max(0, left+e.x_root-x), y=max(0, top+e.y_root-y))

    def gutter_click(self, e):
        line = int(self.text.index(f"@0,{e.y}").split(".")[0])
        self.toggle_breakpoint(line)

    def toggle_breakpoint(self, line=None):
        line = line or int(self.text.index("insert").split(".")[0])
        points = self.document.breakpoints
        if line in points: points.remove(line)
        else: points.add(line)
        self.draw_breakpoints()

    def draw_breakpoints(self):
        # The gutter shows line numbers in cyan; a breakpoint line gets "*" and a red background, as in OTP v2.0.
        if not self.gutter.winfo_exists():
            return
        self.gutter.delete("all")
        self.text.tag_remove("breakpoint", "1.0", "end")
        for line in self.document.breakpoints:
            self.text.tag_add("breakpoint", f"{line}.0", f"{line}.0 lineend+1c")
        first = int(self.text.index("@0,0").split(".")[0])
        last = int(self.text.index(f"@0,{self.text.winfo_height()}").split(".")[0])
        for line in range(first, last + 1):
            info = self.text.dlineinfo(f"{line}.0")
            if info:
                mark = "*" if line in self.document.breakpoints else " "
                self.gutter.create_text(self.gutter.winfo_width() - self.app.font.measure(" "), info[1],
                                        text=f"{mark}{line:>4}", anchor="ne", fill=CYAN, font=self.app.font)


class App:
    def __init__(self, root):
        self.root = root
        self.settings = Settings()
        self.editors, self.active = [], None
        self.counter = 0
        self.messages = queue.Queue(maxsize=256)
        self.compiling = False
        self.process = None
        self.debugging = False
        self.console_window = None
        self.console = None
        self.last_build = None
        self.search_term = ""
        self.closed = False
        self.pending_action = None
        self.banner = True
        self.session = data_dir() / "recovery.json"
        root.title("Odin Turbo Pascal")
        root.geometry(self.settings["geometry"])
        root.minsize(800, 540)
        root.configure(bg=BLUE)
        root.protocol("WM_DELETE_WINDOW", self.quit)
        root.report_callback_exception = self.report_error
        family = "Menlo" if sys.platform == "darwin" else "DejaVu Sans Mono"
        if family.lower() not in {f.lower() for f in tkfont.families(root)}:
            family = "Courier"
        self.font = tkfont.Font(family=family, size=self.settings["font_size"])
        root.option_add("*Font", self.font)
        self.icon = self.load_image("odin.png")
        if self.icon:
            root.iconphoto(True, self.icon)
        self.logo = self.load_image("odin-logo.png")
        self.logo_small = self.load_image("odin-logo-small.png")
        self.menubar = tk.Frame(root, bg=GRAY, height=30)
        self.menubar.pack(fill="x")
        self.menus = {}
        self.create_menus()
        # Bottom rows follow OTP v2.0: function keys on the last line, the cyan status line above it,
        # and a grey "Program output" panel between the editor desktop and the status line.
        self.keys = tk.Frame(root, bg=GRAY)
        self.keys.pack(side="bottom", fill="x")
        for label, action in (("F1 Help",self.help), ("F2 Save",self.save), ("F3 Open",self.open_file),
                              ("F5 Zoom",self.zoom), ("F6 Next",self.next_editor),
                              ("F9 Make",self.compile), ("^F9 Run",self.run), ("F10 Menu",lambda:self.post_menu(*self.menus["File"])),
                              ("Alt+X Exit",self.quit)):
            key = tk.Label(self.keys, text=label, bg=GRAY, fg=BLACK, padx=5, pady=1, font=self.font)
            key.pack(side="left")
            key.bind("<Button-1>", lambda e,a=action: a())
            key.bind("<Enter>", lambda e: e.widget.configure(bg=BLUE, fg=WHITE))
            key.bind("<Leave>", lambda e: e.widget.configure(bg=GRAY, fg=BLACK))
        self.status = tk.Label(root, bg=CYAN, fg=WHITE, anchor="w", font=self.font, pady=1)
        self.status.pack(side="bottom", fill="x")
        self.output_box = Box(root, " Program output ", BLACK, GRAY, self.font)
        self.output_box.frame.pack(side="bottom", fill="x")
        self.output = tk.Text(self.output_box.inner, height=6, bg=GRAY, fg=BLACK, font=self.font, wrap="none",
                              borderwidth=0, highlightthickness=0, padx=6, pady=0, cursor="arrow",
                              selectbackground=CYAN, selectforeground=WHITE)
        self.output.pack(fill="both", expand=True)
        self.output.tag_configure("diagnostic", foreground="#aa0000")
        self.output.tag_configure("note", foreground=BLUE)
        self.output.tag_bind("diagnostic", "<Enter>", lambda e: self.output.configure(cursor="hand2"))
        self.output.tag_bind("diagnostic", "<Leave>", lambda e: self.output.configure(cursor="arrow"))
        self.output.configure(state="disabled")
        self.output_visible = True
        self.desktop = tk.Frame(root, bg=BLUE)
        self.desktop.pack(fill="both", expand=True)
        if self.logo:
            self.watermark = tk.Label(self.desktop, image=self.logo, text="1.0  •  NATIVE PASCAL IDE", compound="top",
                                      bg=BLUE, fg=CYAN, font=(family, 14, "bold"))
        else:
            self.watermark = tk.Label(self.desktop, text="ODIN\nTURBO PASCAL\n\n1.0  •  NATIVE PASCAL IDE",
                                      bg=BLUE, fg=CYAN, font=(family, 24, "bold"), justify="center")
        self.watermark.place(relx=.5, rely=.5, y=-34, anchor="center")
        self.author = tk.Label(self.desktop, text=f"Created by {__author__}", bg=BLUE, fg=YELLOW, font=(family, 16, "bold"))
        self.author.place(in_=self.watermark, relx=.5, rely=1, y=6, anchor="n")
        self.credit = tk.Label(self.desktop, text=f"GNU GPL v3  •  {__copyright__}", bg=BLUE, fg=CYAN)
        self.credit.place(in_=self.author, relx=.5, rely=1, y=2, anchor="n")
        self.log(f"ODIN Turbo Pascal {__version__} | Created by {__author__} | Free Pascal native")
        self.log("F3 Open  |  F9 Make  |  Ctrl+F9 Run  |  Alt+F5 User screen", "note")
        self.bind_keys()
        self.restore_session()
        if not self.editors:
            example = ASSETS / "examples" / "HELLO.PAS"
            self.new_document(Document.read(example) if example.exists() else Document(TEMPLATE))
        self.update_status()
        root.after(40, self.poll)
        root.after(10000, self.recover_tick)
        if sys.platform == "darwin":
            root.createcommand("tkAboutDialog", self.about)
            root.createcommand("::tk::mac::Quit", self.quit)
            root.createcommand("::tk::mac::OpenDocument", lambda *paths: [self.open_file(Path(p)) for p in paths])

    def load_image(self, name):
        # The PNGs are rendered from assets/*.svg by scripts/render_logo.py; without them the IDE falls back to text.
        try:
            return tk.PhotoImage(master=self.root, file=str(ASSETS / "assets" / name))
        except tk.TclError:
            return None

    def report_error(self, kind, value, tb):
        detail = "".join(traceback.format_exception(kind, value, tb))
        try:
            atomic_write(data_dir()/"last-error.log", detail.encode())
        except OSError:
            pass
        messagebox.showerror("Odin", f"Operasi gagal: {value}\n\nDetail: {data_dir() / 'last-error.log'}", parent=self.root)

    def menu(self, name, items, underline=0):
        button = tk.Menubutton(self.menubar, text=f" {name} ", bg=GRAY, fg=BLACK, activebackground=BLUE,
                               activeforeground=WHITE, relief="flat", underline=-1 if underline is None else underline+1,
                               padx=6, pady=1)
        button.pack(side="left")
        menu = tk.Menu(button, tearoff=False, bg=GRAY, fg=BLACK, activebackground=BLUE,
                       activeforeground=WHITE, borderwidth=1, relief="solid")
        button.configure(menu=menu)
        for label, command, shortcut in items:
            if label == "-": menu.add_separator()
            else: menu.add_command(label=label, command=command, accelerator=shortcut)
        self.menus[name] = (button, menu)
        if underline is not None:
            self.root.bind(f"<Alt-{name[underline].lower()}>", lambda e,b=button,m=menu: self.post_menu(b,m))
        return menu

    def post_menu(self, button, menu):
        menu.post(button.winfo_rootx(), button.winfo_rooty()+button.winfo_height())
        menu.activate(0)
        menu.focus_set()
        return "break"

    def create_menus(self):
        self.menu("ODIN", [("About ODIN Turbo Pascal",self.about,""),("Environment information",self.environment,""),
                          ("-",None,""),("Exit",self.quit,"Alt+X")], underline=None)
        self.menu("File", [("New",self.new,"Ctrl+N"),("Open...",self.open_file,"F3"),("Save",self.save,"F2"),
                          ("Save as...",lambda:self.save(as_new=True),""),("Save all",self.save_all,""),
                          ("-",None,""),("Recent files...",self.recent,""),("Examples...",self.examples,""),
                          ("Change directory...",self.change_directory,""),("-",None,""),("Exit",self.quit,"Alt+X")])
        self.menu("Edit", [("Undo",lambda:self.edit("undo"),"Alt+Backspace"),("Redo",lambda:self.edit("redo"),"Ctrl+Y"),
                          ("-",None,""),("Cut",lambda:self.edit("cut"),"Shift+Del"),("Copy",lambda:self.edit("copy"),"Ctrl+Ins"),
                          ("Paste",lambda:self.edit("paste"),"Shift+Ins"),("Select all",lambda:self.edit("all"),"Ctrl+A"),
                          ("Delete line",self.delete_line,"Ctrl+L")])
        self.menu("Search", [("Find...",self.find_dialog,"Ctrl+F"),("Replace...",lambda:self.find_dialog(True),"Ctrl+H"),
                            ("Search again",self.find_next,"Ctrl+G"),("Go to line...",self.goto_line,"Ctrl+J"),
                            ("Next error",self.next_error,"Alt+F8")])
        self.menu("Run", [("Run",self.run,"Ctrl+F9"),("Program reset",self.stop,"Ctrl+F2"),
                         ("Parameters...",self.parameters,""),("User screen",self.show_console,"Alt+F5")])
        self.menu("Compile", [("Compile",self.compile,"Alt+F9"),("Make",self.compile,"F9"),
                             ("Build",lambda:self.compile(rebuild=True),""),("Primary file...",self.primary_file,""),
                             ("Clear primary file",self.clear_primary,""),("Compiler messages",self.show_messages,""),
                             ("Export executable...",self.export_executable,"")])
        self.menu("Debug", [("Start LLDB",self.debug,""),("Step over",lambda:self.debug_command("next"),"F8"),
                           ("Trace into",lambda:self.debug_command("step"),"F7"),("Continue",lambda:self.debug_command("continue"),""),
                           ("Toggle breakpoint",self.breakpoint,"Ctrl+F8"),("Clear breakpoints",self.clear_breakpoints,""),
                           ("Local variables",lambda:self.debug_command("frame variable"),""),
                           ("Call stack",lambda:self.debug_command("bt"),""),("Evaluate...",self.evaluate,"Ctrl+F7")])
        self.menu("Options", [("Compiler...",self.compiler_options,""),("Directories...",self.directory_options,""),
                             ("Editor...",self.editor_options,""),("Save options",self.settings.save,""),
                             ("Environment information",self.environment,"")])
        self.menu("Window", [("Tile",self.tile,""),("Cascade",self.cascade,""),("Zoom",self.zoom,"F5"),
                            ("Next",self.next_editor,"F6"),("Close",self.close_editor,"Alt+F3"),("List...",self.window_list,""),
                            ("-",None,""),("Output panel",self.toggle_output,"Shift+F5")])
        self.menu("Help", [("Contents",self.help,"F1"),("Pascal reference",self.reference,""),
                          ("Keyboard shortcuts",lambda:self.help("SHORTCUTS.txt"),""),("About Odin",self.about,"")])

    def bind_keys(self):
        commands = {"<F1>":self.help,"<F2>":self.save,"<F3>":self.open_file,"<F5>":self.zoom,"<F6>":self.next_editor,
                    "<F7>":lambda:self.debug_command("step"),"<F8>":lambda:self.debug_command("next"),"<F9>":self.compile,
                    "<F10>":lambda:self.post_menu(*self.menus["File"]),"<Control-F9>":self.run,"<Alt-F9>":self.compile,
                    "<Alt-F3>":self.close_editor,"<Shift-F5>":self.toggle_output,"<Alt-F5>":self.show_console,"<Control-F2>":self.stop,
                    "<Control-F8>":self.breakpoint,"<Control-F7>":self.evaluate,"<Alt-F8>":self.next_error,
                    "<Alt-x>":self.quit,"<Alt-BackSpace>":lambda:self.edit("undo"),
                    "<Control-n>":self.new,"<Control-o>":self.open_file,"<Control-s>":self.save,
                    "<Control-f>":self.find_dialog,"<Control-h>":lambda:self.find_dialog(True),"<Control-g>":self.find_next,
                    "<Control-j>":self.goto_line,"<Control-l>":self.delete_line,"<Control-y>":lambda:self.edit("redo")}
        for sequence, action in commands.items():
            self.root.bind(sequence, lambda e,a=action: self.shortcut(a))
        for name, action in (("s",self.save),("o",self.open_file),("n",self.new),("f",self.find_dialog),
                             ("r",self.run),("b",self.compile),("w",self.close_editor),("q",self.quit)):
            if sys.platform == "darwin":
                self.root.bind(f"<Command-{name}>",lambda e,a=action:self.shortcut(a))

    def shortcut(self, action):
        action()
        return "break"

    def new_document(self, doc):
        self.counter += 1
        editor = Editor(self, doc, self.counter)
        self.editors.append(editor)
        n = (len(self.editors)-1) % 5
        editor.frame.place(x=n*20, y=n*22, relwidth=1, relheight=1, width=-n*20, height=-n*22)
        self.activate(editor)
        return editor

    def new(self):
        return self.new_document(Document(TEMPLATE))

    def activate(self, editor, focus=True):
        self.active = editor
        editor.frame.lift()
        for item in self.editors:
            # Active window: white double frame; others: grey single frame.
            item.box.configure(fg=WHITE if item is editor else GRAY, double=item is editor)
            item.update_title()
        if focus: editor.text.focus_set()
        self.update_status()

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
        editor = editor or self.active
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

    def close_editor(self, editor=None):
        editor = editor or self.active
        if not editor: return True
        if editor.document.dirty:
            answer = messagebox.askyesnocancel("Save changes", "Simpan perubahan sebelum menutup?", parent=self.root)
            if answer is None or (answer and not self.save(editor)): return False
        if editor.highlight_job:
            self.root.after_cancel(editor.highlight_job)
        editor.frame.destroy()
        self.editors.remove(editor)
        for item in self.editors: item.update_title()
        self.active = self.editors[-1] if self.editors else None
        if self.active: self.activate(self.active)
        else: self.update_status()
        return True

    def user_input(self):
        self.banner = False
        self.update_status()

    def update_status(self, message=None):
        if not hasattr(self,"status"): return
        position = ""
        if self.active:
            line,col = self.active.text.index("insert").split(".")
            position = f"{int(line)}:{int(col)+1}"
        if message:
            self.status.configure(text=f" {position:<7} {message}")
        elif self.banner or not self.active:
            # Startup banner, kept until the first key or click in an editor.
            self.status.configure(text=f" {position or '1:1':<7} Ready. Created by {__author__}. F1 Help")
        else:
            editor = self.active
            name = str(editor.document.path) if editor.document.path else "NONAME.PAS"
            self.status.configure(text=f" {position:<7} {'Overwrite' if editor.overwrite_mode else 'Insert'}  {name}  [{self.settings['mode'].upper()}]")

    def log(self, line, tag=None):
        """Append one line to the Program output panel; the panel keeps the last 500 lines."""
        self.output.configure(state="normal")
        self.output.insert("end", ("\n" if self.output.index("end-1c") != "1.0" else "") + line, tag or ())
        excess = int(self.output.index("end-1c").split(".")[0]) - 500
        if excess > 0: self.output.delete("1.0", f"{excess + 1}.0")
        self.output.configure(state="disabled")
        self.output.see("end")
        self.output.xview_moveto(0)

    def toggle_output(self):
        if self.output_visible: self.output_box.frame.pack_forget()
        else: self.output_box.frame.pack(side="bottom", fill="x", before=self.desktop)
        self.output_visible = not self.output_visible

    def next_editor(self):
        if self.editors:
            index = self.editors.index(self.active) if self.active in self.editors else -1
            self.activate(self.editors[(index+1)%len(self.editors)])

    def zoom(self, editor=None):
        editor = editor or self.active
        if editor:
            editor.frame.place(x=0,y=0,relwidth=1,relheight=1,width=0,height=0)
            self.activate(editor)

    def cascade(self):
        for n,editor in enumerate(self.editors):
            i=n%7
            editor.frame.place(x=8+i*22,y=8+i*25,relwidth=1,relheight=1,width=-28-i*22,height=-30-i*25)
            editor.frame.lift()
        if self.editors:self.activate(self.editors[-1])

    def tile(self):
        count=len(self.editors)
        if count:
            cols=2 if count>1 else 1
            rows=(count+cols-1)//cols
            for i,editor in enumerate(self.editors):
                editor.frame.place(relx=(i%cols)/cols,rely=(i//cols)/rows,x=3,y=3,relwidth=1/cols,relheight=1/rows,width=-6,height=-6)

    def edit(self, action):
        if not self.active:return
        text=self.active.text
        try:
            if action=="undo":text.edit_undo()
            elif action=="redo":text.edit_redo()
            elif action=="all":text.tag_add("sel","1.0","end-1c")
            else:text.event_generate({"cut":"<<Cut>>","copy":"<<Copy>>","paste":"<<Paste>>"}[action])
        except tk.TclError:pass
        text.focus_set()

    def delete_line(self):
        if self.active:self.active.text.delete("insert linestart","insert lineend+1c")

    def dialog(self,title,width=640):
        # Grey box with a black line frame and the title on its top edge, as in OTP v2.0.
        win=tk.Toplevel(self.root,bg=GRAY)
        win.title(title)
        win.transient(self.root)
        win.resizable(False,False)
        box=Box(win,f" {title} ",BLACK,GRAY,self.font)
        box.frame.pack(fill="both",expand=True,padx=4,pady=4)
        frame=box.inner
        frame.configure(padx=14,pady=6)
        win.bind("<Escape>",lambda e:win.destroy())
        win.update_idletasks()
        win.geometry(f"+{self.root.winfo_rootx()+80}+{self.root.winfo_rooty()+80}")
        return win,frame

    def field(self,parent,label,value="",width=50):
        tk.Label(parent,text=label,bg=GRAY,fg=BLACK,anchor="w").pack(fill="x",pady=(7,2))
        var=tk.StringVar(value=value)
        entry=tk.Entry(parent,textvariable=var,bg=BLUE,fg=YELLOW,insertbackground=WHITE,width=width,relief="flat",
                       borderwidth=2,highlightthickness=0,selectbackground=CYAN,selectforeground=WHITE)
        entry.pack(fill="x")
        return var,entry

    def button(self,parent,label,command):
        return tk.Button(parent,text=f"[ {label} ]",command=command,bg=GRAY,fg=BLACK,activebackground=BLUE,
                         activeforeground=WHITE,relief="flat",borderwidth=0,highlightthickness=0,padx=6,pady=2)

    def input(self,title,label,value,callback):
        win,body=self.dialog(title)
        var,entry=self.field(body,label,value)
        def accept():
            if callback(var.get()) is not False:win.destroy()
        self.button(body,"OK",accept).pack(pady=(14,0))
        entry.bind("<Return>",lambda e:accept())
        entry.focus_set()
        entry.select_range(0,"end")
        return win

    def choose(self,title,items,callback):
        win,body=self.dialog(title)
        listing=tk.Listbox(body,width=65,height=min(15,max(4,len(items))),bg=BLUE,fg=YELLOW,selectbackground=CYAN,
                         selectforeground=WHITE,borderwidth=0,highlightthickness=0)
        listing.pack(fill="both",expand=True)
        for label,value in items:listing.insert("end",label)
        def accept(e=None):
            indices=listing.curselection()
            if indices:
                value=items[indices[0]][1]
                win.destroy()
                callback(value)
        listing.bind("<Double-Button-1>",accept)
        listing.bind("<Return>",accept)
        self.button(body,"Open",accept).pack(pady=(12,0))
        if items:listing.selection_set(0)
        listing.focus_set()

    def recent(self):self.choose("Recent files",[(p,p) for p in self.settings["recent"]],self.open_file)
    def window_list(self):self.choose("Windows",[(e.document.path.name if e.document.path else f"NONAME{e.number}",e) for e in self.editors],self.activate)
    def examples(self):self.choose("Examples",[(p.name,p) for p in sorted((ASSETS/"examples").glob("*.PAS"))],self.open_file)

    def change_directory(self):
        path=filedialog.askdirectory(parent=self.root,title="Working directory")
        if path:os.chdir(path)

    def find_dialog(self,replace=False):
        if not self.active:return
        win,body=self.dialog("Replace" if replace else "Find")
        find,entry=self.field(body,"Text to find",self.search_term)
        replacement=None
        if replace:replacement,_=self.field(body,"New text")
        sensitive=tk.BooleanVar(value=False)
        tk.Checkbutton(body,text="Case sensitive",variable=sensitive,bg=GRAY,fg=BLACK,selectcolor=GRAY,activebackground=GRAY,highlightthickness=0).pack(anchor="w",pady=8)
        def search():
            self.search_term=find.get()
            self.find_next(case=sensitive.get())
        def change(all_matches=False):
            term=find.get()
            if not term:return
            text=self.active.text
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
        bar=tk.Frame(body,bg=GRAY)
        bar.pack(pady=10)
        self.button(bar,"Find next",search).pack(side="left",padx=4)
        if replace:
            self.button(bar,"Replace",change).pack(side="left",padx=4)
            self.button(bar,"Replace all",lambda:change(True)).pack(side="left",padx=4)
        entry.focus_set()
        entry.bind("<Return>",lambda e:search())

    def find_next(self,case=False):
        if not self.active:return
        if not self.search_term:return self.find_dialog()
        text=self.active.text
        start=text.index("sel.last") if text.tag_ranges("sel") else text.index("insert")
        match=text.search(self.search_term,start,stopindex="end",nocase=not case,exact=True)
        if not match:match=text.search(self.search_term,"1.0",stopindex=start,nocase=not case,exact=True)
        if match:
            text.tag_remove("sel","1.0","end")
            text.tag_add("sel",match,f"{match}+{len(self.search_term)}c")
            text.mark_set("insert",f"{match}+{len(self.search_term)}c")
            text.see(match)
            self.update_status()
        else:self.update_status("Text not found")

    def goto_line(self):
        if not self.active:return
        def go(value):
            if not value.isdigit() or int(value)<1:return False
            self.active.text.mark_set("insert",f"{int(value)}.0")
            self.active.text.see("insert")
            self.active.text.focus_set()
        self.input("Go to line","Line number","1",go)

    def compile(self,rebuild=False,after=None):
        if self.compiling:
            self.update_status("Compiler is already running")
            return
        if self.process and self.process.child.poll() is None:
            messagebox.showinfo("Compile","Hentikan program/debugger melalui Run > Program reset terlebih dahulu.",parent=self.root)
            return
        if not self.active:return
        if not self.save_all():return
        path=Path(self.settings["main_file"]) if self.settings["main_file"] else self.active.document.path
        if not path or not path.is_file():
            messagebox.showerror("Compile","Primary file tidak ditemukan. Atur Compile > Primary file.",parent=self.root)
            return
        self.compiling=True
        self.pending_action=after
        self.output.configure(state="normal")
        self.output.delete("1.0","end")
        self.output.configure(state="disabled")
        self.log(f"Compiling {path.name} ...")
        self.update_status(f"Compiling {path.name} ...")
        # Snapshot settings before the worker starts. The worker never accesses Tk.
        snapshot=Settings(self.settings.path)
        snapshot.values=json.loads(json.dumps(self.settings.values))
        def worker():
            try:self.messages.put(("build",build(path,snapshot,rebuild)))
            except Exception as error:self.messages.put(("build_error",str(error)))
        threading.Thread(target=worker,daemon=True).start()

    def run(self):self.compile(after="run")
    def debug(self):self.compile(after="debug")

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
                self.log_build(value)
                if value.success:
                    self.update_status("Compile successful" if value.executable else "Unit compiled. No executable.")
                    if action and value.executable:self.start_process(debug=action=="debug")
                    elif action:messagebox.showinfo("Run","Berkas ini menghasilkan unit. Pilih berkas program sebagai Primary file.",parent=self.root)
                elif value.diagnostics:self.next_error()
                else:self.show_messages()
            elif kind=="build_error":
                self.compiling=False
                self.pending_action=None
                self.log(f"Compiler error: {value}","diagnostic")
                messagebox.showerror("Compiler",value,parent=self.root)
            elif kind=="output":
                if self.console:
                    self.console.feed(value)
                    render=True
            elif kind=="exit":
                if self.console:
                    self.console.feed(f"\r\n\r\n[Process finished, exit code {value}]\r\n")
                    render=True
                self.debugging=False
                self.log(f"Program finished. Exit code {value}")
                self.update_status(f"Program finished. Exit code {value}")
        if render and self.console:self.console.render()
        self.root.after(40,self.poll)

    def start_process(self,debug=False):
        result=self.last_build
        if not result or not result.executable:return
        try:arguments=shlex.split(self.settings["arguments"])
        except ValueError as error:
            messagebox.showerror("Parameters",str(error),parent=self.root)
            return
        argv=[str(result.executable),*arguments]
        if debug:
            lldb=shutil.which("lldb")
            if not lldb and sys.platform=="darwin":lldb="/usr/bin/lldb"
            if not lldb:
                messagebox.showerror("Debugger","LLDB tidak tersedia. Pasang Xcode Command Line Tools.",parent=self.root)
                return
            argv=[lldb,"--no-lldbinit"]
            count=0
            for editor in self.editors:
                for line in sorted(editor.document.breakpoints):
                    if editor.document.path:
                        argv += ["-o",f"breakpoint set --file {shlex.quote(str(editor.document.path))} --line {line}"]
                        count+=1
            if not count:argv += ["-o","breakpoint set --name PASCALMAIN"]
            if arguments:argv += ["-o","settings set target.run-args " + " ".join(shlex.quote(a) for a in arguments)]
            argv += ["-o","run","--",str(result.executable)]
        self.show_console()
        self.console.screen=Screen()
        self.console.render()
        try:
            self.process=Process(argv,result.source.parent,lambda k,v:self.messages.put((k,v)))
            self.debugging=debug
            self.console.focus_set()
        except OSError as error:messagebox.showerror("Run",str(error),parent=self.root)

    def show_console(self):
        if self.console_window and self.console_window.winfo_exists():
            self.console_window.deiconify()
            self.console_window.lift()
            self.console.focus_set()
            return
        win=tk.Toplevel(self.root,bg=BLACK)
        win.title("Odin • User screen / LLDB")
        win.protocol("WM_DELETE_WINDOW",win.withdraw)
        toolbar=tk.Frame(win,bg=GRAY)
        toolbar.pack(fill="x")
        tk.Label(toolbar,text=" User screen 80×25 ",bg=GRAY,fg=BLUE).pack(side="left")
        self.button(toolbar,"Stop",self.stop).pack(side="right")
        self.button(toolbar,"Editor",lambda:(win.withdraw(),self.active.text.focus_set() if self.active else None)).pack(side="right")
        self.button(toolbar,"Copy screen",self.copy_screen).pack(side="right")
        self.console=TerminalView(win,self.font,self.send_input)
        self.console.pack(fill="both",expand=True)
        self.console_window=win
        self.console.bind("<Control-F2>",lambda e:self.shortcut(self.stop))
        self.console.bind("<Alt-F5>",lambda e:self.shortcut(win.withdraw))
        # Outside LLDB, F7/F8 belong to the running program (Crt.ReadKey, Turbo Vision).
        self.console.bind("<F7>",lambda e:self.shortcut(lambda:self.debug_command("step")) if self.debugging else self.console.key(e))
        self.console.bind("<F8>",lambda e:self.shortcut(lambda:self.debug_command("next")) if self.debugging else self.console.key(e))
        self.console.focus_set()

    def copy_screen(self):
        if self.console:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.console.screen.text())

    def send_input(self,value):
        if self.process:self.process.write(value)

    def stop(self):
        if self.process:self.process.stop()

    def debug_command(self,command):
        if not self.debugging:
            messagebox.showinfo("Debug","Mulai Debug > Start LLDB terlebih dahulu. F7/F8 bekerja saat LLDB berhenti pada breakpoint.",parent=self.root)
            return
        self.show_console()
        self.send_input((command+"\n").encode())

    def evaluate(self):self.input("Evaluate expression","Ekspresi LLDB (dukungan Pascal terbatas)","",lambda v:self.debug_command("expression -- "+v))
    def breakpoint(self):
        if self.active:self.active.toggle_breakpoint()
    def clear_breakpoints(self):
        for editor in self.editors:
            editor.document.breakpoints.clear()
            editor.draw_breakpoints()

    def show_messages(self):
        result=self.last_build
        if not result:
            self.update_status("No compiler messages")
            return
        win,body=self.dialog("Compile successful" if result.success else "Compile failed")
        text=tk.Text(body,width=82,height=18,bg=BLUE,fg=YELLOW,wrap="word",font=self.font)
        text.pack(fill="both",expand=True)
        text.insert("end", "$ "+shlex.join(result.command)+"\n\n"+result.output)
        text.configure(state="disabled")
        if result.diagnostics:
            listing=tk.Listbox(body,width=82,height=min(5,len(result.diagnostics)),bg=GRAY,fg="#aa0000",selectbackground=CYAN)
            listing.pack(fill="x",pady=8)
            for diag in result.diagnostics:listing.insert("end",f"{diag.kind}  {diag.file}:{diag.line}:{diag.column}  {diag.message}")
            def jump(e=None):
                selection=listing.curselection()
                if selection:
                    win.destroy()
                    self.jump_diagnostic(result.diagnostics[selection[0]])
            listing.bind("<Double-Button-1>",jump)
            listing.bind("<Return>",jump)
            self.button(body,"Go to error",jump).pack(side="left",pady=8)
            listing.selection_set(0)
        self.button(body,"OK",win.destroy).pack(side="right",pady=8)

    def log_build(self,result):
        if result.success:
            target=result.executable.name if result.executable else "unit, no executable"
            self.log(f"Compile successful: {target}")
            return
        self.log(f"Compile failed: {len(result.diagnostics)} message(s). Double-click a message to jump; Alt+F8 next.")
        if not result.diagnostics:
            for line in result.output.strip().splitlines()[-6:]:self.log("  "+line)
        for i,diag in enumerate(result.diagnostics):
            tag=f"diagnostic{i}"
            self.log(f"  {Path(diag.file).name}({diag.line},{diag.column}) {diag.kind}: {diag.message}",("diagnostic",tag))
            self.output.tag_bind(tag,"<Double-Button-1>",lambda e,d=diag,i=i:self.jump_from_output(i,d))

    def jump_from_output(self,index,diag):
        self.error_index=index
        self.jump_diagnostic(diag)
        return "break"

    def jump_diagnostic(self,diag):
        path=Path(diag.file)
        if not path.is_absolute():path=self.last_build.source.parent/path
        editor=self.open_file(path)
        if editor:
            pos=f"{diag.line}.{max(0,diag.column-1)}"
            editor.text.mark_set("insert",pos)
            editor.text.tag_add("error",f"{diag.line}.0",f"{diag.line}.end")
            editor.text.see(pos)
            self.update_status(diag.message)

    def next_error(self):
        if self.last_build and self.last_build.diagnostics:
            self.error_index=(getattr(self,"error_index",-1)+1)%len(self.last_build.diagnostics)
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

    def parameters(self):
        def accept(value):
            try:shlex.split(value)
            except ValueError as error:
                messagebox.showerror("Parameters",str(error),parent=self.root)
                return False
            self.settings["arguments"]=value
            self.settings.save()
        self.input("Program parameters","Arguments, e.g. \"hello world\" 123",self.settings["arguments"],accept)

    def compiler_options(self):
        win,body=self.dialog("Compiler options")
        compiler,entry=self.field(body,"Compiler path (empty = automatic)",self.settings["compiler"])
        mode=tk.StringVar(value=self.settings["mode"])
        for value,label in (("tp","Turbo Pascal 7 compatibility"),("objfpc","Object Pascal"),("delphi","Delphi")):
            tk.Radiobutton(body,text=label,value=value,variable=mode,bg=GRAY,selectcolor=GRAY,activebackground=GRAY,highlightthickness=0).pack(anchor="w")
        flags={}
        for key,label in (("range_checks","Range checks"),("overflow_checks","Overflow checks"),("debug_info","Debug information for LLDB")):
            flags[key]=tk.BooleanVar(value=self.settings[key])
            tk.Checkbutton(body,text=label,variable=flags[key],bg=GRAY,selectcolor=GRAY,activebackground=GRAY,highlightthickness=0).pack(anchor="w")
        def save():
            self.settings["compiler"]=compiler.get().strip()
            self.settings["mode"]=mode.get()
            for key,var in flags.items():self.settings[key]=var.get()
            self.settings.save()
            win.destroy()
            self.update_status()
        self.button(body,"OK",save).pack(pady=10)

    def directory_options(self):
        win,body=self.dialog("Directories")
        tk.Label(body,text="Satu direktori per baris. Path dengan spasi didukung.",bg=GRAY).pack()
        fields={}
        for key,label in (("unit_paths","Unit search paths"),("include_paths","Include search paths")):
            tk.Label(body,text=label,bg=GRAY,fg=BLUE).pack(anchor="w",pady=8)
            text=tk.Text(body,width=60,height=4,bg=BLUE,fg=YELLOW,insertbackground=YELLOW)
            text.pack()
            text.insert("1.0","\n".join(self.settings[key]))
            fields[key]=text
        def save():
            for key,text in fields.items():self.settings[key]=[str(Path(p.strip()).expanduser().resolve()) for p in text.get("1.0","end-1c").splitlines() if p.strip()]
            self.settings.save()
            win.destroy()
        self.button(body,"OK",save).pack(pady=12)

    def editor_options(self):
        win,body=self.dialog("Editor options")
        size,_=self.field(body,"Font size (10..30)",str(self.settings["font_size"]))
        tab,_=self.field(body,"Tab width (1..8)",str(self.settings["tab_width"]))
        syntax=tk.BooleanVar(value=self.settings["syntax"])
        tk.Checkbutton(body,text="Syntax colors (off = classic yellow text)",variable=syntax,bg=GRAY,selectcolor=GRAY,activebackground=GRAY,highlightthickness=0).pack(pady=12)
        def save():
            try:
                font_size,tab_width=int(size.get()),int(tab.get())
                if not 10<=font_size<=30 or not 1<=tab_width<=8:raise ValueError()
            except ValueError:
                messagebox.showerror("Editor","Masukkan ukuran dan tab sesuai rentang.",parent=win)
                return
            self.settings["font_size"]=font_size
            self.settings["tab_width"]=tab_width
            self.settings["syntax"]=syntax.get()
            self.font.configure(size=font_size)
            for editor in self.editors:editor.apply_options()
            self.settings.save()
            win.destroy()
        self.button(body,"OK",save).pack()

    def show_text(self,title,content,image=None):
        win=tk.Toplevel(self.root,bg=GRAY)
        win.title(title)
        win.geometry("900x620")
        box=Box(win,f" {title} ",BLACK,GRAY,self.font)
        box.frame.pack(fill="both",expand=True,padx=4,pady=4)
        text=tk.Text(box.inner,bg=GRAY,fg=BLACK,font=self.font,wrap="word",padx=14,pady=8,relief="flat",
                     borderwidth=0,highlightthickness=0,selectbackground=CYAN,selectforeground=WHITE)
        scroll=tk.Scrollbar(box.inner,command=text.yview,bg=CYAN,troughcolor=GRAY,borderwidth=0,highlightthickness=0)
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
        return win

    def help(self,name="HELP.txt"):
        try:content=(ASSETS/"docs"/name).read_text()
        except OSError:content="Dokumentasi tidak ditemukan. Lihat README.txt."
        self.show_text("ODIN Help",content)

    def reference(self):self.help("PASCAL.txt")
    def about(self):
        # Layout follows the OTP v2.0 About box: text on the left, artwork at the bottom right.
        win,body=self.dialog("About ODIN Turbo Pascal")
        lines=(f"ODIN TURBO PASCAL {__version__}",f"Created by {__author__}. GPL-3.0-or-later.","",
               "Reference: Turbo Pascal 7.0 DOS (1992).",
               "Not Borland Turbo Pascal; not affiliated with Borland.",
               "No Borland binaries, logos, fonts or help files.","",
               "Python / Tk IDE + the real Free Pascal compiler.",
               "Native programs: Intel x86_64, Apple Silicon arm64.","",
               f"{__copyright__}.",
               "Free software under the GNU GPL v3 or later,",
               "with ABSOLUTELY NO WARRANTY.",
               "See LICENSE and THIRD_PARTY.txt.","",
               "Enter or Esc closes this window.")
        row=tk.Frame(body,bg=GRAY)
        row.pack(fill="both",expand=True)
        tk.Label(row,text="\n".join(lines),bg=GRAY,fg=BLACK,font=self.font,justify="left",anchor="nw").pack(side="left",fill="y")
        self.about_logo=tk.Label(row,image=self.logo_small,bg=GRAY) if self.logo_small else None
        if self.about_logo:self.about_logo.pack(side="right",anchor="se",padx=(24,0))
        win.bind("<Return>",lambda e:win.destroy())
        win.focus_set()
        return win

    def environment(self):
        self.show_text("Environment",f"Odin {__version__}\n\nOS: {platform.platform()}\nCPU: {platform.machine()}\nPython: {sys.version}\nRuntime: {sys.executable}\nTk: {self.root.tk.call('info','patchlevel')}\nCompiler: {locate_compiler(self.settings['compiler']) or 'NOT FOUND'}\nMode: {self.settings['mode']}\nPrimary file: {self.settings['main_file'] or '(active editor)'}\nSettings: {self.settings.path}\n")

    def recover_tick(self):
        if self.closed:return
        try:self.write_session()
        except OSError:pass
        self.root.after(10000,self.recover_tick)

    def write_session(self):
        items=[{"path":str(e.document.path) if e.document.path else None,"text":e.text.get("1.0","end-1c"),
                "saved_text":e.document.saved_text,"encoding":e.document.encoding,"newline":e.document.newline,
                "disk_hash":e.document.disk_hash} for e in self.editors]
        atomic_write(self.session,json.dumps(items,ensure_ascii=False).encode())

    def restore_session(self):
        try:
            items=json.loads(self.session.read_text())
            if not isinstance(items,list) or not items:return
            if not messagebox.askyesno("Recover session","Sesi sebelumnya belum ditutup normal. Pulihkan isi editor?",parent=self.root):
                self.session.unlink(missing_ok=True)
                return
            for item in items:
                doc=Document(item["text"],Path(item["path"]) if item.get("path") else None,
                             item.get("encoding","utf-8"),item.get("newline","\n"),item.get("saved_text",""),item.get("disk_hash",""))
                self.new_document(doc)
        except (OSError,ValueError,KeyError,TypeError):pass

    def quit(self):
        if self.compiling:
            messagebox.showinfo("Exit","Tunggu kompilasi selesai sebelum keluar.",parent=self.root)
            return
        if self.process and self.process.child.poll() is None:
            if not messagebox.askyesno("Exit","Hentikan program yang masih berjalan dan keluar?",parent=self.root):return
        # Gather decisions first. Cancel must not close any editor.
        for editor in self.editors:
            if editor.document.dirty:
                self.activate(editor)
                answer=messagebox.askyesnocancel("Save changes",f"Simpan {editor.document.path.name if editor.document.path else 'NONAME.PAS'}?",parent=self.root)
                if answer is None or (answer and not self.save(editor)):return
        self.stop()
        self.settings["geometry"]=self.root.geometry()
        self.settings.save()
        self.session.unlink(missing_ok=True)
        self.closed=True
        self.cancel_callbacks()
        self.root.destroy()

    def cancel_callbacks(self):
        for callback in self.root.tk.call("after", "info"):
            self.root.after_cancel(callback)


def main():
    import fcntl
    root=tk.Tk(className="OdinTurboPascal")
    lock = (data_dir() / "instance.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        root.withdraw()
        messagebox.showinfo("Odin Turbo Pascal", "Odin sudah berjalan. Gunakan File > Open pada jendela yang tersedia.", parent=root)
        root.destroy()
        lock.close()
        return
    app=App(root)
    for argument in sys.argv[1:]:
        if not argument.startswith("-psn_"):
            app.open_file(Path(argument))
    try:
        root.mainloop()
    finally:
        lock.close()


if __name__=="__main__":main()
