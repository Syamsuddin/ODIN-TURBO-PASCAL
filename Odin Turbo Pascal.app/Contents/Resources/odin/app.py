# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Classic text-inspired desktop interface; all commands are local."""
from __future__ import annotations

import json
import os
import platform
import queue
import re
import shutil
import subprocess
import sys
import threading
import traceback
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox
from tkinter import font as tkfont

from . import __author__, __copyright__, __version_tag__
from .core import (PACKAGE_ROOT, Document, Settings, atomic_write, build, data_dir, join_command, locate_compiler,
                   locate_toolchain, lock_instance, runtime_error_location, split_arguments, unlock_instance)
from .debugger import DebugSession
from .terminal import Process, Screen, TerminalView
from .windows import BLACK, BLUE, CYAN, GRAY, WHITE, Editor, LocalsWindow, StackWindow, WatchWindow

ASSETS = Path(__file__).resolve().parent.parent
# Help > Buku opens this PDF in docs/.
BOOK = "Belajar_Pemrograman_Bahasa_Pascal.pdf"
TEMPLATE = "program Untitled;\n\nbegin\n  WriteLn('Hello, Pascal!');\nend.\n"
# Compile actions that need a debug build and run under the debugger.
DEBUG_ACTIONS = ("debug", "step", "cursor")
# Monospace fonts in order of preference; Courier when none is installed.
FONTS = {"darwin": ("Menlo",), "win32": ("Consolas", "Courier New")}
# The plaque under the desktop logo: a Turbo Vision dialog (gray, white double frame, black shadow).
# Its fonts are fixed, so it keeps its shape whatever the editor font size is.
PLAQUE_GAP, PLAQUE_PAD, PLAQUE_SHADOW = 14, 16, 8
PLAQUE_FRAME, PLAQUE_VERSION = "#ffffff", "#006060"


class App:
    def __init__(self, root):
        self.root = root
        self.settings = Settings()
        # windows: every desktop window in creation order; active: any of them; last_editor: most recently active Editor.
        self.windows, self.active, self.last_editor = [], None, None
        self.counter = 0
        self.messages = queue.Queue(maxsize=256)
        self.compiling = False
        self.process = None
        self.debugger = None            # DebugSession while debugging
        self.debug_requests = {}       # request id -> callback(result event)
        self.debug_frame = 0           # call stack frame used by Watches and Local variables
        self.stack_frames = []
        self.watches = []              # watch expressions, shown with their latest values
        self.watch_values = {}
        self.watch_window = self.locals_window = self.stack_window = None
        self.pending_cursor = None     # (path, line) for Go to cursor
        self.restart_debug = None
        self.debug_source_changed = False
        self.last_runtime_error = None # (code, path or None, line or None)
        self.error_report = None       # (debug_info, report file) of the last Run
        self.console_window = None
        self.console = None
        self.last_build = None
        self.search_term = ""
        self.closed = False
        self.pending_action = None
        self.banner = True
        self.notice = None             # kept in the status bar until the next key or click
        self.session = data_dir() / "recovery.json"
        root.title("Odin Turbo Pascal")
        root.geometry(self.settings["geometry"])
        root.minsize(800, 540)
        root.configure(bg=BLUE)
        root.protocol("WM_DELETE_WINDOW", self.quit)
        root.report_callback_exception = self.report_error
        available = {f.lower() for f in tkfont.families(root)}
        family = next((f for f in FONTS.get(sys.platform, ("DejaVu Sans Mono",)) if f.lower() in available), "Courier")
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
        self.status = tk.Label(root, bg=GRAY, fg=BLUE, anchor="w", font=self.font, pady=3)
        self.status.pack(side="bottom", fill="x")
        self.keys = tk.Frame(root, bg=GRAY)
        self.keys.pack(side="bottom", fill="x")
        for label, action in (("F1 Help",self.help), ("F2 Save",self.save), ("F3 Open",self.open_file),
                              ("F6 Next",self.next_editor), ("F9 Make",self.compile), ("^F9 Run",self.run), ("Alt-X Exit",self.quit)):
            tk.Button(self.keys, text=label, command=action, bg=GRAY, fg="#aa0000", activebackground=CYAN,
                      relief="flat", borderwidth=0, padx=10, pady=3, takefocus=False).pack(side="left")
        self.desktop = tk.Frame(root, bg=BLUE)
        self.desktop.pack(fill="both", expand=True)
        if self.logo:
            self.watermark = tk.Label(self.desktop, image=self.logo, bg=BLUE, borderwidth=0)
        else:
            self.watermark = tk.Label(self.desktop, text="ODIN\nTURBO PASCAL", bg=BLUE, fg=CYAN, font=(family, 24, "bold"),
                                      justify="center")
        self.plaque = self.make_plaque(family)
        # The logo and the plaque are centered together on the desktop.
        below = PLAQUE_GAP + int(self.plaque.cget("height"))
        self.watermark.place(relx=.5, rely=.5, y=-below // 2, anchor="center")
        self.plaque.place(in_=self.watermark, relx=.5, rely=1, y=PLAQUE_GAP, anchor="n")
        self.bind_keys()
        self.restore_session()
        if not self.editors:
            example = ASSETS / "examples" / "bab01_01_halo_dunia.pas"
            self.new_document(Document.read(example) if example.exists() else Document(TEMPLATE))
        self.update_status()
        root.after(40, self.poll)
        root.after(10000, self.recover_tick)
        if sys.platform == "darwin":
            root.createcommand("tkAboutDialog", self.about)
            root.createcommand("::tk::mac::Quit", self.quit)
            root.createcommand("::tk::mac::OpenDocument", lambda *paths: [self.open_file(Path(p)) for p in paths])

    def load_image(self, name):
        # The PNGs are rendered from assets/odin-logo-master.png by scripts/render_logo.py; without them the IDE falls back to text.
        try:
            return tk.PhotoImage(master=self.root, file=str(ASSETS / "assets" / name))
        except tk.TclError:
            return None

    def make_plaque(self, family):
        """The desktop plaque under the logo: tagline and release tag, author credit, copyright and
        license. Canvas items carry the tags tagline, version, author, copyright and license."""
        small = tkfont.Font(root=self.root, family=family, size=10)
        fonts = {"tagline": tkfont.Font(root=self.root, family=family, size=12, weight="bold"),
                 "author": tkfont.Font(root=self.root, family=family, size=14, weight="bold"),
                 "copyright": small, "license": small}
        lines = [("tagline", "NATIVE PASCAL IDE"), ("author", f"Created by {__author__}"),
                 ("copyright", __copyright__), ("license", "GNU GPL v3 or later")]
        gap = 5
        version_width = fonts["tagline"].measure(__version_tag__)
        inner = max(fonts["tagline"].measure(lines[0][1]) + 3 * gap + version_width,
                    *(fonts[tag].measure(text) for tag, text in lines[1:]))
        width = inner + 2 * PLAQUE_PAD
        height = sum(fonts[tag].metrics("linespace") for tag, _ in lines) + (len(lines) - 1) * gap + 2 * PLAQUE_PAD
        canvas = tk.Canvas(self.desktop, width=width + PLAQUE_SHADOW, height=height + PLAQUE_SHADOW, bg=BLUE,
                           highlightthickness=0, borderwidth=0)
        canvas.create_rectangle(PLAQUE_SHADOW, PLAQUE_SHADOW, width + PLAQUE_SHADOW, height + PLAQUE_SHADOW, fill=BLACK, width=0)
        canvas.create_rectangle(0, 0, width, height, fill=GRAY, width=0)
        # Double frame, as on an active Turbo Vision dialog.
        for inset in (5, 9):
            canvas.create_rectangle(inset, inset, width - inset, height - inset, outline=PLAQUE_FRAME, width=1)
        y = PLAQUE_PAD
        for tag, text in lines:
            canvas.create_text(PLAQUE_PAD, y, text=text, anchor="nw", fill=BLACK, font=fonts[tag], tags=tag)
            if tag == "tagline":
                canvas.create_text(width - PLAQUE_PAD, y, text=__version_tag__, anchor="ne", fill=PLAQUE_VERSION,
                                   font=fonts[tag], tags="version")
            y += fonts[tag].metrics("linespace") + gap
        canvas.fonts = fonts
        return canvas

    def report_error(self, kind, value, tb):
        detail = "".join(traceback.format_exception(kind, value, tb))
        try:
            atomic_write(data_dir()/"last-error.log", detail.encode())
        except OSError:
            pass
        messagebox.showerror("Odin", f"Operasi gagal: {value}\n\nDetail: {data_dir() / 'last-error.log'}", parent=self.root)

    def menu(self, name, items, underline=0):
        button = tk.Menubutton(self.menubar, text=f" {name} ", bg=GRAY, fg=BLACK, activebackground=CYAN,
                               activeforeground=BLACK, relief="flat", underline=underline+1, padx=1, pady=3)
        button.pack(side="left")
        menu = tk.Menu(button, tearoff=False, bg=GRAY, fg=BLACK, activebackground=CYAN,
                       activeforeground=BLACK, borderwidth=2)
        button.configure(menu=menu)
        for label, command, shortcut in items:
            if label == "-": menu.add_separator()
            else: menu.add_command(label=label, command=command, accelerator=shortcut)
        self.menus[name] = (button, menu)
        self.root.bind(f"<Alt-{name[underline].lower()}>", lambda e,b=button,m=menu: self.post_menu(b,m))
        return menu

    def post_menu(self, button, menu):
        menu.post(button.winfo_rootx(), button.winfo_rooty()+button.winfo_height())
        menu.activate(0)
        menu.focus_set()
        return "break"

    def create_menus(self):
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
                            ("Next error",self.next_error,"Alt+F8"),("Find error",self.find_error,"")])
        self.menu("Run", [("Run",self.run,"Ctrl+F9"),("Program reset",self.stop,"Ctrl+F2"),
                         ("Parameters...",self.parameters,""),("User screen",self.show_console,"Alt+F5")])
        self.menu("Compile", [("Compile",self.compile,"Alt+F9"),("Make",self.compile,"F9"),
                             ("Build",lambda:self.compile(rebuild=True),""),("Primary file...",self.primary_file,""),
                             ("Clear primary file",self.clear_primary,""),("Compiler messages",self.show_messages,""),
                             ("Export executable...",self.export_executable,"")])
        self.menu("Debug", [("Start debugging",self.debug,""),("Step over",lambda:self.debug_step("over"),"F8"),
                           ("Trace into",lambda:self.debug_step("into"),"F7"),("Go to cursor",lambda:self.debug_step("cursor"),"F4"),
                           ("Continue",lambda:self.debug_step("continue"),""),("-",None,""),
                           ("Toggle breakpoint",self.breakpoint,"Ctrl+F8"),("Clear breakpoints",self.clear_breakpoints,""),("-",None,""),
                           ("Watch window",self.show_watches,""),("Add watch...",self.add_watch,""),
                           ("Local variables",self.show_locals,""),("Call stack",self.show_stack,""),
                           ("Evaluate/Modify...",self.evaluate,"Ctrl+F7")])
        self.menu("Options", [("Compiler...",self.compiler_options,""),("Directories...",self.directory_options,""),
                             ("Editor...",self.editor_options,""),("Save options",self.settings.save,""),
                             ("Environment information",self.environment,"")])
        self.menu("Window", [("Tile",self.tile,""),("Cascade",self.cascade,""),("Zoom",self.zoom,"F5"),
                            ("Next",self.next_editor,"F6"),("Close",self.close_window,"Alt+F3"),("List...",self.window_list,"")])
        self.menu("Help", [("Contents",self.help,"F1"),("Pascal reference",self.reference,""),
                          ("Keyboard shortcuts",lambda:self.help("SHORTCUTS.txt"),""),("Buku",self.book,""),
                          ("About Odin",self.about,"")])
        tk.Label(self.menubar,text="◉",bg=GRAY,fg=BLUE,font=self.font).pack(side="right",padx=10)

    def bind_keys(self):
        commands = {"<F1>":self.help,"<F2>":self.save,"<F3>":self.open_file,"<F5>":self.zoom,"<F6>":self.next_editor,
                    "<F4>":lambda:self.debug_step("cursor"),
                    "<F7>":lambda:self.debug_step("into"),"<F8>":lambda:self.debug_step("over"),"<F9>":self.compile,
                    "<F10>":lambda:self.post_menu(*self.menus["File"]),"<Control-F9>":self.run,"<Alt-F9>":self.compile,
                    "<Alt-F3>":self.close_window,"<Alt-F5>":self.show_console,"<Control-F2>":self.stop,
                    "<Control-F8>":self.breakpoint,"<Control-F7>":self.evaluate,"<Alt-F8>":self.next_error,
                    "<Alt-x>":self.quit,"<Alt-BackSpace>":lambda:self.edit("undo"),
                    "<Control-n>":self.new,"<Control-o>":self.open_file,"<Control-s>":self.save,
                    "<Control-f>":self.find_dialog,"<Control-h>":lambda:self.find_dialog(True),"<Control-g>":self.find_next,
                    "<Control-j>":self.goto_line,"<Control-l>":self.delete_line,"<Control-y>":lambda:self.edit("redo")}
        for sequence, action in commands.items():
            self.root.bind(sequence, lambda e,a=action: self.shortcut(a))
        for name, action in (("s",self.save),("o",self.open_file),("n",self.new),("f",self.find_dialog),
                             ("r",self.run),("b",self.compile),("w",self.close_window),("q",self.quit)):
            if sys.platform == "darwin":
                self.root.bind(f"<Command-{name}>",lambda e,a=action:self.shortcut(a))

    def shortcut(self, action):
        action()
        return "break"

    @property
    def debugging(self):
        """A debug session is running (the program may be running or stopped)."""
        return bool(self.debugger and self.debugger.alive)

    @property
    def editors(self):
        """Editor windows only: Save all, recovery, breakpoints and Compile use these."""
        return [w for w in self.windows if isinstance(w, Editor)]

    @property
    def active_editor(self):
        """The active window when it is an Editor. Text commands do nothing for other windows."""
        return self.active if isinstance(self.active, Editor) else None

    def add_window(self, window):
        self.windows.append(window)
        n = (len(self.windows)-1) % 5
        window.frame.place(x=8+n*20, y=8+n*22, relwidth=1, relheight=1, width=-28-n*20, height=-26-n*22)
        self.activate(window)
        return window

    def new_document(self, doc):
        self.counter += 1
        return self.add_window(Editor(self, doc, self.counter))

    def new(self):
        return self.new_document(Document(TEMPLATE))

    def activate(self, window, focus=True):
        self.active = window
        if isinstance(window, Editor): self.last_editor = window
        window.frame.lift()
        for item in self.windows: item.set_active(item is window)
        if focus: window.focus()
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

    def close_window(self, window=None):
        window = window or self.active
        if not window: return True
        if isinstance(window, Editor) and window.document.dirty:
            answer = messagebox.askyesnocancel("Save changes", "Simpan perubahan sebelum menutup?", parent=self.root)
            if answer is None or (answer and not self.save(window)): return False
        window.destroy()
        self.windows.remove(window)
        if window is self.last_editor:
            editors = self.editors
            self.last_editor = editors[-1] if editors else None
        self.active = self.windows[-1] if self.windows else None
        if self.active: self.activate(self.active)
        else: self.update_status()
        return True

    def close_editor(self, window=None):
        return self.close_window(window)

    def user_input(self):
        self.banner = False
        self.notice = None
        self.update_status()

    def update_status(self, message=None):
        if not hasattr(self,"status"): return
        if message:
            self.status.configure(text=" " + message)
        elif self.notice:
            self.status.configure(text=" " + self.notice)
        elif self.banner or not self.active_editor:
            # Turbo Pascal style startup banner, kept until the first key or click in an editor.
            self.status.configure(text=f" Odin Turbo Pascal {__version_tag__}   |   Created by {__author__}   |   F1 Help")
        else:
            editor = self.active_editor
            line,col = editor.text.index("insert").split(".")
            name = str(editor.document.path) if editor.document.path else "NONAME.PAS"
            self.status.configure(text=f" {'Overwrite' if editor.overwrite_mode else 'Insert'}  {int(line):5}:{int(col)+1:<4}  {name}  [{self.settings['mode'].upper()}]")

    def next_editor(self):
        if self.windows:
            index = self.windows.index(self.active) if self.active in self.windows else -1
            self.activate(self.windows[(index+1)%len(self.windows)])

    def zoom(self, window=None):
        window = window or self.active
        if window:
            window.frame.place(x=5,y=5,relwidth=1,relheight=1,width=-10,height=-10)
            self.activate(window)

    def cascade(self):
        for n,window in enumerate(self.windows):
            i=n%7
            window.frame.place(x=8+i*22,y=8+i*25,relwidth=1,relheight=1,width=-28-i*22,height=-30-i*25)
            window.frame.lift()
        if self.windows:self.activate(self.windows[-1])

    def tile(self):
        count=len(self.windows)
        if count:
            cols=2 if count>1 else 1
            rows=(count+cols-1)//cols
            for i,window in enumerate(self.windows):
                window.frame.place(relx=(i%cols)/cols,rely=(i//cols)/rows,x=3,y=3,relwidth=1/cols,relheight=1/rows,width=-6,height=-6)

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

    def dialog(self,title,width=640):
        win=tk.Toplevel(self.root,bg=GRAY)
        win.title(title)
        win.transient(self.root)
        win.resizable(False,False)
        frame=tk.Frame(win,bg=GRAY,highlightthickness=2,highlightbackground=BLUE,padx=18,pady=14)
        frame.pack(fill="both",expand=True,padx=5,pady=5)
        tk.Label(frame,text=f" {title} ",bg=GRAY,fg=BLUE,font=self.font).pack(pady=(0,12))
        win.bind("<Escape>",lambda e:win.destroy())
        win.update_idletasks()
        win.geometry(f"+{self.root.winfo_rootx()+80}+{self.root.winfo_rooty()+80}")
        return win,frame

    def field(self,parent,label,value="",width=50):
        tk.Label(parent,text=label,bg=GRAY,fg=BLACK,anchor="w").pack(fill="x",pady=(7,2))
        var=tk.StringVar(value=value)
        entry=tk.Entry(parent,textvariable=var,bg=BLUE,fg=WHITE,insertbackground=WHITE,width=width,relief="sunken")
        entry.pack(fill="x")
        return var,entry

    def button(self,parent,label,command):
        return tk.Button(parent,text=f" {label} ",command=command,bg=CYAN,fg=BLACK,activebackground=BLUE,
                         activeforeground=WHITE,relief="raised",padx=8,pady=3)

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
        box=tk.Frame(body,bg=GRAY)
        box.pack(fill="both",expand=True)
        listing=tk.Listbox(box,width=65,height=min(15,max(4,len(items))),bg=BLUE,fg=WHITE,selectbackground=CYAN,selectforeground=BLACK)
        if len(items)>15:
            # The tutorial alone has 90 examples.
            bar=tk.Scrollbar(box,orient="vertical",command=listing.yview)
            listing.configure(yscrollcommand=bar.set)
            bar.pack(side="right",fill="y")
        listing.pack(side="left",fill="both",expand=True)
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
    def window_list(self):self.choose("Windows",[(w.list_label(),w) for w in self.windows],self.activate)
    def examples(self):self.choose("Examples",[(p.name,p) for p in sorted((ASSETS/"examples").iterdir()) if p.suffix.lower()==".pas"],self.open_file)

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
        tk.Checkbutton(body,text="Case sensitive",variable=sensitive,bg=GRAY,fg=BLACK,selectcolor=GRAY).pack(anchor="w",pady=8)
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
        bar=tk.Frame(body,bg=GRAY)
        bar.pack(pady=10)
        self.button(bar,"Find next",search).pack(side="left",padx=4)
        if replace:
            self.button(bar,"Replace",change).pack(side="left",padx=4)
            self.button(bar,"Replace all",lambda:change(True)).pack(side="left",padx=4)
        entry.focus_set()
        entry.bind("<Return>",lambda e:search())

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
        self.input("Go to line","Line number","1",go)

    def compile(self,rebuild=False,after=None):
        if self.compiling:
            self.update_status("Compiler is already running")
            return
        if self.process and self.process.child.poll() is None:
            messagebox.showinfo("Compile","Hentikan program/debugger melalui Run > Program reset terlebih dahulu.",parent=self.root)
            return
        # Without a primary file, Compile/Run use the most recently active Editor, even from another desktop window.
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
                if value.success:
                    self.update_status("Compile successful" if value.executable else "Unit compiled. No executable.")
                    if action and value.executable:self.start_process(action)
                    elif action:messagebox.showinfo("Run","Berkas ini menghasilkan unit. Pilih berkas program sebagai Primary file.",parent=self.root)
                    else:self.show_messages()
                else:self.show_messages()
            elif kind=="build_error":
                self.compiling=False
                self.pending_action=None
                messagebox.showerror("Compiler",value,parent=self.root)
            elif kind=="output":
                if self.console:
                    self.console.feed(value)
                    render=True
            elif kind=="debug":
                self.debug_event(value)
            elif kind=="exit":
                code=self.process_finished(value)
                if self.console:
                    self.console.feed(f"\r\n\r\n[Process finished, exit code {code}]\r\n")
                    render=True
        if render and self.console:self.console.render()
        self.root.after(40,self.poll)

    def start_process(self,action="run"):
        result=self.last_build
        if not result or not result.executable:return
        try:arguments=split_arguments(self.settings["arguments"])
        except ValueError as error:
            messagebox.showerror("Parameters",str(error),parent=self.root)
            return
        self.show_console()
        self.console.screen=Screen()
        self.console.render()
        emit=lambda k,v:self.messages.put((k,v))
        self.last_runtime_error=None
        self.clear_error_marks()
        try:
            if action in DEBUG_ACTIONS:
                if not result.debug_info:
                    messagebox.showerror("Debug","Build ini tidak berisi info debug.",parent=self.root)
                    return
                self.debug_start_mode=action
                self.debug_requests.clear()
                self.debugger=DebugSession(locate_toolchain(),result.executable,result.debug_info,arguments,result.source.parent,emit)
                self.process=self.debugger.process
                self.update_status("Debugging ...")
            else:
                # The RTL of an Odin build reports a runtime error here; Find error maps it to a line.
                report=data_dir()/"runtime-error.txt"
                report.unlink(missing_ok=True)
                self.error_report=(result.debug_info,report) if result.debug_info else None
                self.process=Process([str(result.executable),*arguments],result.source.parent,emit,
                                     env={"ODIN_ERROR_FILE":str(report)} if result.debug_info else None)
            self.console.focus_set()
        except OSError as error:messagebox.showerror("Run",str(error),parent=self.root)

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
            if self.restart_debug:
                action,self.restart_debug=self.restart_debug,None
                self.root.after(10,lambda:self.compile(after=action))
        elif self.error_report:
            debug_info,report=self.error_report
            self.error_report=None
            try:text=report.read_text()
            except OSError:text=""
            location=runtime_error_location(debug_info,text) if text else None
            if location:self.runtime_error_at(*location)
        if not self.last_runtime_error:self.update_status(f"Program finished. Exit code {code}")
        return code

    def show_console(self):
        if self.console_window and self.console_window.winfo_exists():
            self.console_window.deiconify()
            self.console_window.lift()
            self.console.focus_set()
            return
        win=tk.Toplevel(self.root,bg=BLACK)
        win.title("Odin • User screen")
        win.protocol("WM_DELETE_WINDOW",win.withdraw)
        toolbar=tk.Frame(win,bg=GRAY)
        toolbar.pack(fill="x")
        tk.Label(toolbar,text=" User screen 80×25 ",bg=GRAY,fg=BLUE).pack(side="left")
        self.button(toolbar,"Stop",self.stop).pack(side="right")
        self.button(toolbar,"Editor",lambda:(win.withdraw(),self.active.focus() if self.active else None)).pack(side="right")
        self.button(toolbar,"Copy screen",self.copy_screen).pack(side="right")
        self.console=TerminalView(win,self.font,self.send_input)
        self.console.pack(fill="both",expand=True)
        self.console_window=win
        self.console.bind("<Control-F2>",lambda e:self.shortcut(self.stop))
        self.console.bind("<Alt-F5>",lambda e:self.shortcut(win.withdraw))
        # While the debugger holds the program, F7/F8 step; otherwise they belong to the running
        # program (Crt.ReadKey, Turbo Vision).
        self.console.bind("<F7>",lambda e:self.shortcut(lambda:self.debug_step("into")) if self.debug_stopped else self.console.key(e))
        self.console.bind("<F8>",lambda e:self.shortcut(lambda:self.debug_step("over")) if self.debug_stopped else self.console.key(e))
        self.console.focus_set()

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
            messagebox.showinfo("Find error","Belum ada runtime error. Posisinya dicatat saat program dijalankan dengan backend Odin.",parent=self.root)

    def breakpoints_changed(self,editor):
        if self.debugging and editor.document.path:
            self.debugger.set_breakpoints(editor.document.path,editor.document.breakpoints)

    def source_modified(self,editor):
        if self.debugging:self.debug_source_changed=True

    # Watches, Local variables and Call stack: desktop windows filled when the program stops.
    def debug_window(self,attribute,kind,place=None):
        window=getattr(self,attribute)
        if window is None:
            window=self.add_window(kind(self))
            setattr(self,attribute,window)
            if place:window.frame.place(**place)
        self.activate(window)
        return window

    def debug_window_closed(self,window):
        for attribute in ("watch_window","locals_window","stack_window"):
            if getattr(self,attribute) is window:setattr(self,attribute,None)

    def show_watches(self):
        # Turbo Pascal keeps Watches in a strip along the bottom of the desktop.
        window=self.debug_window("watch_window",WatchWindow,dict(x=5,y=-5,relx=0,rely=.72,relwidth=1,relheight=.28,width=-10))
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
            self.watch_window.set_rows([f"{e}: {self.watch_values.get(i,'')}" for i,e in enumerate(self.watches)])

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
                rows=[f"{v['name']}: {v['value']}" for v in event.get("locals",[])] if event.get("ok") else [event.get("error","")]
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
                self.stack_window.set_rows([f"{f['name']}  ({Path(f['file']).name}:{f['line']})" for f in self.stack_frames])
                if self.stack_frames:
                    self.stack_window.list.selection_clear(0,"end")
                    self.stack_window.list.selection_set(min(self.debug_frame,len(self.stack_frames)-1))
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
        tk.Label(body,text="Result",bg=GRAY,fg=BLACK,anchor="w").pack(fill="x",pady=(7,2))
        tk.Entry(body,textvariable=result,state="readonly",readonlybackground=BLUE,fg=WHITE,width=50,relief="sunken").pack(fill="x")
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
        bar=tk.Frame(body,bg=GRAY)
        bar.pack(pady=(14,0))
        self.button(bar,"Evaluate",lambda:run("evaluate")).pack(side="left",padx=4)
        self.button(bar,"Modify",lambda:run("modify")).pack(side="left",padx=4)
        self.button(bar,"Close",win.destroy).pack(side="left",padx=4)
        entry.bind("<Return>",lambda e:run("evaluate"))
        entry.focus_set()
        entry.select_range(0,"end")
        return win

    def breakpoint(self):
        if self.active_editor:self.active_editor.toggle_breakpoint()
    def clear_breakpoints(self):
        for editor in self.editors:
            editor.set_breakpoints(set())

    def show_messages(self):
        result=self.last_build
        if not result:
            self.update_status("No compiler messages")
            return
        win,body=self.dialog("Compile successful" if result.success else "Compile failed")
        text=tk.Text(body,width=82,height=18,bg=BLUE,fg=WHITE,wrap="word",font=self.font)
        text.pack(fill="both",expand=True)
        text.insert("end", "$ "+join_command(result.command)+"\n\n"+result.output)
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
            try:split_arguments(value)
            except ValueError as error:
                messagebox.showerror("Parameters",str(error),parent=self.root)
                return False
            self.settings["arguments"]=value
            self.settings.save()
        self.input("Program parameters","Arguments, e.g. \"hello world\" 123",self.settings["arguments"],accept)

    def compiler_options(self):
        win,body=self.dialog("Compiler options")
        backend=tk.StringVar(value=self.settings["backend"])
        tk.Label(body,text="Backend",bg=GRAY,fg=BLUE).pack(anchor="w")
        for value,label in (("odin","Odin native (experimental)"),("fpc","Free Pascal")):
            tk.Radiobutton(body,text=label,value=value,variable=backend,bg=GRAY,selectcolor=GRAY).pack(anchor="w")
        compiler,entry=self.field(body,"Free Pascal path (empty = automatic)",self.settings["compiler"])
        mode=tk.StringVar(value=self.settings["mode"])
        for value,label in (("tp","Turbo Pascal 7 compatibility"),("objfpc","Object Pascal"),("delphi","Delphi")):
            tk.Radiobutton(body,text=label,value=value,variable=mode,bg=GRAY,selectcolor=GRAY).pack(anchor="w")
        flags={}
        for key,label in (("range_checks","Range checks"),("overflow_checks","Overflow checks"),("debug_info","Debug information")):
            flags[key]=tk.BooleanVar(value=self.settings[key])
            tk.Checkbutton(body,text=label,variable=flags[key],bg=GRAY,selectcolor=GRAY).pack(anchor="w")
        def save():
            self.settings["backend"]=backend.get()
            self.settings["compiler"]=compiler.get().strip()
            # The Odin backend only implements Turbo Pascal mode.
            self.settings["mode"]="tp" if backend.get()=="odin" else mode.get()
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
            text=tk.Text(body,width=60,height=4,bg=BLUE,fg=WHITE,insertbackground=WHITE)
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
        syntax=tk.BooleanVar(value=self.settings["syntax_colors"])
        tk.Checkbutton(body,text="Syntax colors: Turbo Biru Lembut (off = classic yellow on blue)",variable=syntax,bg=GRAY,selectcolor=GRAY).pack(pady=12)
        def save():
            try:
                font_size,tab_width=int(size.get()),int(tab.get())
                if not 10<=font_size<=30 or not 1<=tab_width<=8:raise ValueError()
            except ValueError:
                messagebox.showerror("Editor","Masukkan ukuran dan tab sesuai rentang.",parent=win)
                return
            self.settings["font_size"]=font_size
            self.settings["tab_width"]=tab_width
            self.settings["syntax_colors"]=syntax.get()
            self.font.configure(size=font_size)
            for editor in self.editors:editor.apply_options()
            self.settings.save()
            win.destroy()
        self.button(body,"OK",save).pack()

    def show_text(self,title,content,image=None):
        win=tk.Toplevel(self.root,bg=BLUE)
        win.title(title)
        win.geometry("900x620")
        text=tk.Text(win,bg=BLUE,fg=WHITE,font=self.font,wrap="word",padx=22,pady=20,relief="flat")
        scroll=tk.Scrollbar(win,command=text.yview)
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

    def help(self,name="HELP.txt"):
        try:content=(ASSETS/"docs"/name).read_text(encoding="utf-8")
        except OSError:content="Dokumentasi tidak ditemukan. Lihat README.txt."
        self.show_text("Odin Help",content)

    def reference(self):self.help("PASCAL.txt")
    def book(self):
        """Help > Buku: the tutorial book, opened in the system's PDF viewer (scripts/build_book.py makes it)."""
        path=ASSETS/"docs"/BOOK
        if not path.is_file():
            messagebox.showerror("Buku",f"Buku tidak ditemukan:\n{path}",parent=self.root)
            return
        try:
            if sys.platform=="win32":os.startfile(path)
            else:subprocess.Popen(["/usr/bin/open" if sys.platform=="darwin" else "xdg-open",str(path)],stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        except OSError as error:
            messagebox.showerror("Buku",f"Buku tidak bisa dibuka: {error}\n{path}",parent=self.root)
            return
        self.update_status(f"Opening {BOOK}")
    def about(self):
        self.show_text("About Odin Turbo Pascal",f"ODIN TURBO PASCAL\nVersion {__version_tag__}\nCreated by {__author__}\n\nIndependent classic Pascal IDE.\nPython / Tk + Odin native toolchain; Free Pascal as alternative backend.\n\nInterface inspired by the DOS-era Turbo Pascal IDE.\nThis software is not Borland Turbo Pascal and is not affiliated with Borland.\nNo Borland binaries, logos, fonts, or help files are included.\n\nNative Pascal compilation for the host CPU.\nIntel x86_64 and Apple Silicon arm64 use the same application sources.\n\n{__copyright__}.\nThis program is free software: you can redistribute it and/or modify it\nunder the terms of the GNU General Public License, version 3 or later.\nIt comes with ABSOLUTELY NO WARRANTY. See LICENSE and THIRD_PARTY.txt.\n",self.logo_small)

    def environment(self):
        self.show_text("Environment",f"Odin {__version_tag__}\n\nOS: {platform.platform()}\nCPU: {platform.machine()}\nPython: {sys.version}\nRuntime: {sys.executable}\nTk: {self.root.tk.call('info','patchlevel')}\nBackend: {self.settings['backend']}\nOdin toolchain: {locate_toolchain() or 'NOT FOUND'}\nCompiler: {locate_compiler(self.settings['compiler']) or 'NOT FOUND'}\nMode: {self.settings['mode']}\nPrimary file: {self.settings['main_file'] or '(active editor)'}\nSettings: {self.settings.path}\n")

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
