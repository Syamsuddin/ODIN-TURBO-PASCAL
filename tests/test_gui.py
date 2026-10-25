# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Run on macOS desktop, or DISPLAY=localhost:99 on a Linux test display."""
import json
import os
import sys
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path
from tkinter import ttk
from unittest.mock import patch

from odin import __copyright__, __version_tag__
from odin.core import Document, Settings, locate_toolchain, odin_supported
from odin.terminal import ALT_MASKS

ROOT = Path(__file__).resolve().parent.parent
needs_odin = unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
needs_pty = unittest.skipUnless(locate_toolchain() and odin_supported() and sys.platform!="win32","Needs odinpc and a POSIX PTY")


@unittest.skipUnless(os.environ.get("DISPLAY") or sys.platform in ("darwin","win32"), "Needs graphical display")
class GuiTests(unittest.TestCase):
    def setUp(self):
        from odin.app import App
        self.temp=tempfile.TemporaryDirectory()
        self.path=Path(self.temp.name)
        self.settings=Settings(self.path/"settings.json")
        self.patches=[patch("odin.app.Settings",return_value=self.settings),patch("odin.app.data_dir",return_value=self.path)]
        for item in self.patches:item.start()
        self.root=tk.Tk()
        self.root.geometry("1120x740")
        self.app=App(self.root)
        self.errors=[]
        self.root.report_callback_exception=lambda *args:self.errors.append(args)
        self.root.update()

    def tearDown(self):
        self.app.stop()
        self.app.closed=True
        self.app.cancel_callbacks()
        self.root.destroy()
        for item in self.patches:item.stop()
        self.temp.cleanup()
        self.assertEqual(self.errors,[])

    def wait_for(self,condition,seconds=15):
        deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            self.root.update()
            if condition():return True
            time.sleep(.02)
        self.fail("timed out")

    def wait_finished(self,runs=1):
        self.wait_for(lambda:self.app.finished_runs>=runs)
        self.root.update()
        self.assertFalse(self.app.program_running)

    def screen(self):
        return self.app.console.screen.text()

    def widgets(self,parent,kind):
        found=[]
        for child in parent.winfo_children():
            if isinstance(child,kind):found.append(child)
            found+=self.widgets(child,kind)
        return found

    def toplevels(self):
        return [c for c in self.root.winfo_children() if isinstance(c,tk.Toplevel)]

    def labels(self,menu):
        menu=self.app.menus[menu][1]
        return [menu.entrycget(i,"label") for i in range(menu.index("end")+1) if menu.type(i) in ("command","cascade","radiobutton")]

    def chooser_items(self,dialog):
        return [dialog.listing.item(item,"values")[0] for item in dialog.listing.get_children()]

    def test_edit_save_find_and_undo(self):
        editor=self.app.new_document(Document("program p;\nbegin\nend.\n"))
        editor.text.insert("2.0","{ hello }\n")
        self.root.update()
        self.assertTrue(editor.document.dirty)
        self.assertTrue(editor.title.cget("text").endswith("●"))
        target=self.path/"saved file.pas"
        with patch("odin.app.filedialog.asksaveasfilename",return_value=str(target)):
            self.assertTrue(self.app.save())
        self.assertIn("{ hello }",target.read_text())
        self.assertFalse(editor.document.dirty)
        self.assertEqual(editor.title.cget("text"),"saved file.pas")
        self.assertEqual(self.root.title(),"saved file.pas - Odin Turbo Pascal")
        self.app.search_term="hello"
        self.app.find_next()
        self.assertEqual(editor.text.get("sel.first","sel.last"),"hello")
        editor.text.mark_set("insert","2.0")
        editor.text.tag_remove("sel","1.0","end")
        editor.text.edit_separator()
        editor.text.insert("insert","test")
        self.app.edit("undo")
        self.assertNotIn("test",editor.text.get("1.0","end"))

    def test_startup_layout_menu_bar_and_window_chrome(self):
        output,messages,hello=self.app.windows
        self.assertIs(output,self.app.output_window)
        self.assertIs(messages,self.app.messages_window)
        self.assertIs(self.app.active,hello)
        self.assertEqual(hello.document.path.name,"bab01_01_halo_dunia.pas")
        # Child windows live in the workspace of the main window, editor above, Output and Messages below.
        for window in self.app.windows:
            self.assertEqual(window.frame.master,self.app.workspace)
        x,y,w,h=hello.geometry()
        self.assertGreater(w,800)
        self.assertLess(y+h,output.geometry()[1]+10)
        self.assertLess(output.geometry()[0],messages.geometry()[0])
        self.assertEqual(hello.title.cget("bg"),"#2b5797")
        self.assertEqual(output.title.cget("bg"),"#e4e6ea")
        self.assertEqual(set(hello.buttons),{"minimize","maximize","close"})
        # The menu bar is a row of text items in the window, each with its dropdown.
        bar=[b for b,_ in self.app.menus.values() if b]
        self.assertEqual([b.cget("text") for b in bar],"File Edit Search Run Compile Debug Options Window Help".split())
        for button in bar:
            self.assertEqual(button.master,self.app.menubar)
            self.assertEqual(int(button.cget("underline")),0)
        self.assertEqual(self.labels("Examples"),["Tutorial...","AI...","Graph...","OOP..."])
        self.assertIn("Examples",self.labels("File"))
        self.assertIn("Open recent",self.labels("File"))

    def test_window_menu_lists_windows_and_arranges_them(self):
        output,messages,hello=self.app.windows
        editor=self.app.new()
        self.root.update()
        self.app.fill_window_menu()
        labels=self.labels("Window")
        for item in ("Tile","Cascade","Arrange icons","Zoom","Minimize","Next","Close","Close all","Output","Messages"):
            self.assertIn(item,labels)
        self.assertEqual(labels[-4:],["1 Output","2 Messages","3 bab01_01_halo_dunia.pas","4 NONAME2"])
        self.assertEqual(self.app.window_choice.get(),3)
        menu=self.app.menus["Window"][1]
        menu.invoke(next(i for i in range(menu.index("end")+1) if menu.type(i)=="radiobutton" and menu.entrycget(i,"label")=="1 Output"))
        self.assertIs(self.app.active,output)
        self.app.tile()
        self.root.update()
        boxes=[w.geometry() for w in self.app.windows]
        for box in boxes:self.assertGreater(box[2],300)
        self.assertEqual(len({(x,y) for x,y,_,_ in boxes}),4)
        self.app.cascade()
        self.root.update()
        self.assertIs(self.app.active,editor)
        self.assertLess(self.app.windows[0].geometry()[0],editor.geometry()[0])
        visited=[]
        for _ in range(4):
            self.app.next_window()
            visited.append(self.app.active)
        self.assertEqual(visited,[output,messages,hello,editor])

    def test_zoom_minimize_restore_move_and_resize(self):
        output,messages,hello=self.app.windows
        before=hello.geometry()
        self.app.zoom(hello)
        self.root.update()
        self.assertEqual(hello.state,"maximized")
        self.assertEqual(hello.geometry()[2:],(self.app.workspace.winfo_width(),self.app.workspace.winfo_height()))
        self.app.zoom(hello)
        self.root.update()
        self.assertEqual((hello.state,hello.geometry()),("normal",before))
        self.app.minimize(hello)
        self.root.update()
        self.assertEqual(hello.state,"minimized")
        self.assertEqual(hello.geometry()[2],200)
        self.assertIsNot(self.app.active,hello)
        self.assertFalse(hello.body.winfo_ismapped())
        self.app.activate(hello)
        self.root.update()
        self.assertEqual((hello.state,hello.geometry()),("normal",before))
        # Dragging the title bar moves the window; dragging its corner resizes it.
        x,y,w,h=hello.geometry()
        hello.drag_start(type("E",(),{"x_root":100,"y_root":100})())
        hello.drag(type("E",(),{"x_root":140,"y_root":130})())
        self.root.update()
        self.assertEqual(hello.geometry()[:2],(x+40,y+30))
        corner=type("E",(),{"x":w-2,"y":h-2,"x_root":500,"y_root":500})()
        self.assertEqual(hello.edge_at(corner),"se")
        hello.resize_start(corner)
        hello.resize(type("E",(),{"x_root":450,"y_root":480})())
        self.root.update()
        self.assertEqual(hello.geometry()[2:],(w-50,h-20))
        hello.resize(type("E",(),{"x_root":-5000,"y_root":-5000})())
        self.root.update()
        self.assertEqual(hello.geometry()[2:],(220,110))

    def test_cancelled_close_and_closing_windows(self):
        output,messages,hello=self.app.windows
        first=self.app.new()
        with patch("odin.app.messagebox.askyesnocancel",return_value=None):
            self.assertFalse(self.app.close_window(first))
        self.assertIn(first,self.app.editors)
        with patch("odin.app.messagebox.askyesnocancel") as ask:
            self.assertTrue(self.app.close_window(messages))
            self.assertTrue(self.app.close_window(output))
        ask.assert_not_called()
        self.assertIsNone(self.app.output_window)
        self.assertIsNone(self.app.console)
        self.assertIs(self.app.show_output(),self.app.output_window)
        self.assertIs(self.app.active,self.app.output_window)
        with patch("odin.app.messagebox.askyesnocancel",return_value=False):
            self.assertTrue(self.app.close_all())
        self.assertEqual(self.app.windows,[])
        self.assertIsNone(self.app.last_editor)
        self.assertIn("Created by",self.app.status.cget("text"))

    def test_breakpoints_and_recovery_snapshot(self):
        editor=self.app.new()
        editor.toggle_breakpoint(3)
        self.assertIn(3,editor.document.breakpoints)
        self.app.write_session()
        self.assertIn("Hello, Pascal",self.app.session.read_text(encoding="utf-8"))
        self.app.clear_breakpoints()
        self.assertFalse(editor.document.breakpoints)

    def test_examples_dialog_lists_the_tutorial(self):
        self.app.examples()
        self.root.update()
        dialog=self.toplevels()[-1]
        names=self.chooser_items(dialog)
        self.assertEqual(len(names),90)
        self.assertEqual((names[0],names[-1]),("bab01_01_halo_dunia.pas","matematika.pas"))
        # 90 names do not fit the 15 rows of the list.
        self.assertTrue(self.widgets(dialog,ttk.Scrollbar))
        dialog.listing.selection_set("1")
        [b for b in self.widgets(dialog,ttk.Button) if b.cget("text")=="Open"][0].invoke()
        self.assertEqual(self.app.active_editor.document.path.name,names[1])

    def test_examples_graph_dialog_lists_the_graph_samples(self):
        self.app.examples_graph()
        self.root.update()
        items=self.chooser_items(self.toplevels()[-1])
        self.assertEqual(len(items),14)
        self.assertTrue(items[0].startswith("grafik_01_halo_grafik.pas"))
        self.assertIn("Jam analog",items[11])

    def test_examples_oop_dialog_lists_the_class_samples(self):
        self.app.examples_oop()
        self.root.update()
        items=self.chooser_items(self.toplevels()[-1])
        self.assertEqual(len(items),9)
        self.assertTrue(items[0].startswith("oop_01_class_pertama.pas"))
        self.assertIn("Polimorfisme",items[4])

    def test_examples_ai_dialog_lists_the_otp_ai_samples(self):
        self.app.examples_ai()
        self.root.update()
        items=self.chooser_items(self.toplevels()[-1])
        names=[item.split()[0] for item in items]
        self.assertEqual(len(names),20)
        self.assertEqual((names[0],names[-1]),("BASIC.PAS","TREEDEMO.PAS"))
        self.assertNotIn("COMMON.INC",names)
        self.assertIn("K-Means",items[names.index("KMEANS.PAS")])
        # A sample opens as a template: Save becomes Save as (it lives under ASSETS).
        before=len(self.app.editors)
        self.app.open_file(ROOT/"otp-AI"/"EXAMPLES"/"BASIC.PAS")
        self.assertEqual(len(self.app.editors),before+1)

    def test_help_menu_opens_the_book(self):
        self.assertEqual(self.labels("Help"),["Contents","Pascal reference","Keyboard shortcuts","Buku","About Odin"])
        book=ROOT/"docs"/"Belajar_Pemrograman_Bahasa_Pascal.pdf"
        self.assertTrue(book.is_file(),"jalankan python3 scripts/build_book.py")
        self.assertEqual(book.read_bytes()[:5],b"%PDF-")
        with patch("odin.app.subprocess.Popen") as popen,patch("odin.app.os.startfile",create=True) as startfile:
            self.app.book()
        if sys.platform=="win32":startfile.assert_called_once_with(book)
        else:self.assertEqual(popen.call_args.args[0][1],str(book))
        # Without the PDF the user gets a message, not a traceback.
        with patch("odin.app.ASSETS",Path(tempfile.gettempdir())/"tanpa-buku"),patch("odin.app.messagebox.showerror") as error:
            self.app.book()
        error.assert_called_once()

    def test_help_in_browser_opens_the_html_help(self):
        page=ROOT/"docs"/"help.html"
        self.assertTrue(page.is_file(),"jalankan python3 scripts/build_help.py")
        with patch("odin.app.subprocess.Popen") as popen,patch("odin.app.os.startfile",create=True) as startfile:
            self.app.help_html()
        if sys.platform=="win32":startfile.assert_called_once_with(page)
        else:self.assertEqual(popen.call_args.args[0][1],str(page))

    def test_f1_opens_the_html_help_at_the_word_under_the_cursor(self):
        editor=self.app.new()
        editor.text.insert("1.0","ClrScr; Sin(X); NamaSendiri\n")
        urls=[]
        for column,expected in ((2,"#k-clrscr"),(10,"#k-sin"),(22,"#cari=NamaSendiri")):
            editor.text.mark_set("insert",f"1.{column}")
            with patch("odin.app.webbrowser.open",side_effect=lambda url:urls.append(url) or True):
                self.app.help_topic()
            self.assertTrue(urls[-1].endswith(expected),urls[-1])
            self.assertIn("/docs/help.html",urls[-1])

    def test_dialogs_open_and_close(self):
        self.app.settings.add_recent(self.path/"a.pas")
        self.app.fill_recent()
        self.assertEqual(self.app.menus["Open recent"][1].entrycget(0,"label"),str((self.path/"a.pas").resolve()))
        for action in (self.app.compiler_options,self.app.directory_options,self.app.editor_options,
                       self.app.environment_options,self.app.find_dialog,lambda:self.app.find_dialog(True),
                       self.app.examples,self.app.window_list,self.app.parameters,self.app.evaluate,
                       self.app.help,self.app.about,self.app.environment):
            action()
            self.root.update()
            for child in self.toplevels():child.destroy()

    def test_toolbar_icons_and_tooltips(self):
        from odin import icons
        from odin.app import TOOLBAR
        self.assertEqual(sorted(icon for group in TOOLBAR for _,icon,_,_,_ in group),sorted(icons.ICONS))
        tools=self.app.tools
        self.assertEqual(list(tools),["New","Open","Save","Compile","Run","Stop","Debug","into","over","Breakpoint","Tile","Cascade"])
        for key,button in tools.items():
            self.assertEqual(str(button.cget("image")[0]) if button.cget("image") else "",str(self.app.tool_images[key]),key)
            self.assertEqual(self.app.tool_images[key].width(),20)
            self.assertEqual(str(button.cget("compound")),"image")
        self.assertEqual(tools["Run"].tooltip.text,"Run (Ctrl+F9)")
        self.assertEqual(tools["New"].tooltip.text,"New (Cmd+N)" if sys.platform=="darwin" else "New (Ctrl+N)")
        tools["Run"].tooltip.show()
        self.assertEqual(tools["Run"].tooltip.window.winfo_children()[0].cget("text"),"Run (Ctrl+F9)")
        tools["Run"].tooltip.hide()
        self.assertIsNone(tools["Run"].tooltip.window)
        # The buttons call their commands.
        with patch.object(self.app,"tile") as tile:
            tools["Tile"].invoke()
        tile.assert_called_once()

    def test_options_dialog_has_tabs_and_applies_settings(self):
        editor=self.app.active_editor
        win=self.app.options("Editor")
        self.root.update()
        notebook=win.notebook
        self.assertEqual([notebook.tab(t,"text") for t in notebook.tabs()],["Compiler","Directories","Editor","Environment"])
        self.assertEqual(notebook.tab(notebook.select(),"text"),"Editor")
        spinboxes=self.widgets(win,ttk.Spinbox)
        font,tab,console=spinboxes
        apply=[b for b in self.widgets(win,ttk.Button) if b.cget("text")=="Apply"][0]
        # A number out of range is refused and changes nothing.
        font.set("99")
        with patch("odin.app.messagebox.showerror") as error:
            apply.invoke()
        error.assert_called_once()
        self.assertEqual(self.settings["font_size"],14)
        font.set("16")
        console.set("10")
        self.widgets(win,ttk.Combobox)[0].set("Gelap")
        apply.invoke()
        self.assertEqual((self.settings["font_size"],self.settings["console_font_size"],self.settings["theme"]),(16,10,"dark"))
        # Fit Output may make the console text smaller than the Output font size, never larger.
        self.assertEqual(self.app.font.cget("size"),16)
        self.assertLessEqual(self.app.console_font.cget("size"),10)
        self.assertEqual(editor.text.cget("bg"),"#1e1e1e")
        self.assertEqual(json.loads((self.path/"settings.json").read_text())["theme"],"dark")
        [b for b in self.widgets(win,ttk.Button) if b.cget("text")=="OK"][0].invoke()
        self.assertFalse(win.winfo_exists())
        # Each Options menu item opens its tab.
        labels=self.labels("Options")
        self.assertEqual(labels[:5],["Options...","Compiler...","Directories...","Editor...","Environment..."])
        win=self.app.environment_options()
        self.assertEqual(win.notebook.tab(win.notebook.select(),"text"),"Environment")
        win.destroy()

    def test_desktop_is_saved_and_restored(self):
        output,messages,hello=self.app.windows
        source=self.path/"posisi.pas"
        source.write_text("program Posisi;\nbegin\n  WriteLn(1);\n  WriteLn(2);\nend.\n")
        editor=self.app.open_file(source)
        editor.toggle_breakpoint(3)
        editor.text.mark_set("insert","4.2")
        self.app.new()                                  # untitled: not part of the desktop
        self.app.close_window(messages)
        self.app.minimize(output)
        self.app.zoom(hello)
        self.app.show_watches()
        self.app.activate(editor)
        self.root.update()
        before=self.app.window_box(editor)
        state=self.app.desktop_state()
        self.assertEqual([w["kind"] for w in state["windows"]],["output","editor","editor","watches"])
        self.assertEqual(state["active"],2)
        self.assertEqual([w["state"] for w in state["windows"]],["minimized","maximized","normal","normal"])
        self.assertEqual((state["windows"][2]["cursor"],state["windows"][2]["breakpoints"]),("4.2",[3]))
        # The state survives settings.json, and a new session reopens it.
        self.settings["desktop"]=state
        self.settings.save()
        self.assertEqual(Settings(self.path/"settings.json")["desktop"],state)
        with patch("odin.app.messagebox.askyesnocancel",return_value=False):
            self.assertTrue(self.app.close_all())
        self.assertTrue(self.app.restore_desktop())
        self.root.update()
        kinds=[type(w).__name__ for w in self.app.windows]
        self.assertEqual(kinds,["OutputWindow","Editor","Editor","WatchWindow"])
        output,hello,editor,watch=self.app.windows
        self.assertIs(self.app.active,editor)
        self.assertEqual((output.state,hello.state,editor.state),("minimized","maximized","normal"))
        self.assertEqual(editor.document.path,source.resolve())
        self.assertEqual(editor.document.breakpoints,{3})
        self.assertEqual(editor.text.index("insert"),"4.2")
        self.assertEqual([round(v,2) for v in self.app.window_box(editor)],[round(v,2) for v in before])
        self.assertIs(self.app.watch_window,watch)
        # A file that is gone is skipped; a broken entry does not stop the others.
        state["windows"][2]["path"]=str(self.path/"hilang.pas")
        state["windows"].insert(0,{"kind":"editor","box":"rusak"})
        self.settings["desktop"]=state
        with patch("odin.app.messagebox.askyesnocancel",return_value=False):
            self.app.close_all()
        self.assertTrue(self.app.restore_desktop())
        self.assertEqual([type(w).__name__ for w in self.app.windows],["OutputWindow","Editor","WatchWindow"])
        # Quit stores the desktop, or nothing when Save desktop is off.
        self.settings["save_desktop"]=False
        with patch.object(self.app,"cancel_callbacks"),patch.object(self.root,"destroy"):
            self.app.quit()
        self.assertEqual(Settings(self.path/"settings.json")["desktop"],{})
        self.app.closed=False

    def test_menu_accelerators_follow_the_os(self):
        from odin.app import accel
        with patch("odin.app.AQUA",True):
            self.assertEqual([accel(k) for k in ("Mod+S","Ctrl+F9","Alt+F8","Mod+Shift+Z","F9","")],
                             ["Command-S","Control-F9","Option-F8","Command-Shift-Z","F9",""])
        with patch("odin.app.AQUA",False):
            self.assertEqual([accel(k) for k in ("Mod+S","Ctrl+F9","Alt+F8")],["Ctrl+S","Ctrl+F9","Alt+F8"])

    @unittest.skipUnless(sys.platform=="darwin","macOS application menu")
    def test_macos_application_menu_is_named_after_odin(self):
        # Without it the application menu reads "Python" with "Quit Python", as Tk takes CFBundleName of Python.app.
        from odin.app import macos_app_name
        self.assertEqual(macos_app_name("Odin Turbo Pascal"),"Odin Turbo Pascal")

    def test_editor_shortcuts_win_over_text_bindings(self):
        # Ctrl+H deletes a character in Tk's Text class on X11; in the editor it opens Replace and keeps the text.
        editor=self.app.new_document(Document("program p;\n"))
        self.assertEqual(editor.text.bindtags()[1],"OdinKeys")
        editor.text.mark_set("insert","1.5")
        editor.text.focus_force()
        self.root.update()
        editor.text.event_generate("<Control-h>")
        self.root.update()
        self.assertEqual(editor.text.get("1.0","end-1c"),"program p;\n")
        self.assertEqual([t.title() for t in self.toplevels()],["Replace"])

    def test_output_console_mouse_and_keys(self):
        console=self.app.console
        self.assertEqual(console.master,self.app.output_window.body)
        console.feed("\x1b[2J\x1b[3;4HReady")
        console.render()
        self.assertEqual(console.get("3.3","3.8"),"Ready")
        self.root.update()
        # A program that turns on mouse tracking gets SGR reports for clicks; keys with
        # Shift/Alt become xterm sequences (Odin Vision reads Alt+key as Esc + key).
        sent=[]
        console.send=sent.append
        console.feed("\x1b[?1000h\x1b[?1002h\x1b[?1006h")
        console.render()
        self.app.zoom(self.app.output_window)
        self.root.update()
        x,y,w,h=console.bbox("3.4")
        console.event_generate("<ButtonPress-1>",x=x+1,y=y+1)
        console.event_generate("<ButtonRelease-1>",x=x+1,y=y+1)
        self.assertEqual(sent,[b"\x1b[<0;5;3M",b"\x1b[<0;5;3m"])
        self.assertIs(self.app.active,self.app.output_window)
        sent.clear()
        alt=console.alt_mask
        console.key(type("E",(),{"keysym":"Left","state":0x01,"char":""})())
        console.key(type("E",(),{"keysym":"x","state":alt,"char":"x"})())
        console.key(type("E",(),{"keysym":"Tab","state":0x01,"char":"\t"})())
        self.assertEqual(sent,[b"\x1b[1;2D",b"\x1bx",b"\x1b[Z"])
        self.app.copy_screen()
        self.assertIn("Ready",self.root.clipboard_get())

    def test_output_text_fits_the_window(self):
        output=self.app.output_window
        console=output.console
        output.fit()
        self.root.update()
        size=self.app.console_font.cget("size")
        self.assertLess(size,self.settings["console_font_size"])
        self.assertGreaterEqual(size,7)
        # The whole 80x25 screen is visible, unless the smallest font is still too big.
        width=self.app.console_font.measure("0")*80+16
        self.assertTrue(width<=console.winfo_width() or size==7)
        self.app.zoom(output)
        self.root.update()
        output.fit()
        self.assertEqual(self.app.console_font.cget("size"),self.settings["console_font_size"])
        self.app.zoom(output)
        self.root.update()
        self.settings["fit_console"]=False
        output.fit()
        self.assertEqual(self.app.console_font.cget("size"),self.settings["console_font_size"])

    def test_windows_modifier_keys(self):
        # On Windows Tk reports Alt as 0x20000 and Num Lock as Mod1 (0x08); AltGr is Ctrl+Alt and types
        # a character. Checked on every platform by giving the widgets the Windows masks.
        console=self.app.console
        sent=[]
        console.send=sent.append
        console.win32,console.alt_mask=True,ALT_MASKS["win32"]
        key=lambda keysym,state,char:console.key(type("E",(),{"keysym":keysym,"state":state,"char":char})())
        key("x",0x20000,"x")
        key("x",0x08,"x")
        key("at",0x20004,"@")
        key("Left",0x20000,"")
        self.assertEqual(sent,[b"\x1bx",b"x",b"@",b"\x1b[1;3D"])
        editor=self.app.active_editor or self.app.last_editor
        editor.win32=True
        event=lambda state:type("E",(),{"state":state})()
        self.assertEqual([editor.command_key(event(s)) for s in (0,0x08,0x04,0x20000,0x20004)],[False,False,True,True,False])
        editor.win32=False
        self.assertEqual([editor.command_key(event(s)) for s in (0,0x08,0x04,0x0c)],[False,True,True,True])

    def test_workspace_caption_status_bar_and_about(self):
        self.assertIsNotNone(self.app.icon)
        self.assertEqual((self.app.logo.width(),self.app.logo.height()),(280,280))
        plaque=self.app.plaque
        self.assertEqual(plaque.master,self.app.workspace)
        self.assertEqual(plaque.author.cget("text"),"Created by Syams Ideris")
        self.assertEqual(plaque.copyright.cget("text"),__copyright__)
        self.assertEqual(plaque.license.cget("text"),"GNU GPL v3 or later")
        # The release tag on the workspace, the startup status bar, the default page (bab01_01_halo_dunia.pas) and About.
        self.assertIn(__version_tag__,plaque.version.cget("text"))
        self.assertIn(f"Odin Turbo Pascal {__version_tag__}",self.app.status.cget("text"))
        self.assertIn("Created by Syams Ideris",self.app.status.cget("text"))
        editor=self.app.active_editor
        self.assertIn(f"Odin Turbo Pascal {__version_tag__} - program pertama",editor.text.get("1.0","end"))
        self.app.user_input()
        self.assertEqual(self.app.mode_label.cget("text"),"INS")
        self.assertEqual(self.app.position_label.cget("text"),"Ln 1, Col 1")
        self.assertIn("UTF-8",self.app.encoding_label.cget("text"))
        self.assertEqual(self.app.status.cget("text"),str(editor.document.path))
        editor.toggle_insert()
        self.assertEqual(self.app.mode_label.cget("text"),"OVR")
        self.app.about()
        self.root.update()
        about=self.toplevels()[-1]
        text=self.widgets(about,tk.Text)[0]
        self.assertEqual(str(text.image_cget("1.0","image")),str(self.app.logo_small))
        content=text.get("1.0","end")
        self.assertIn(f"Version {__version_tag__}",content)
        self.assertIn("not affiliated with Borland",content)
        self.assertIn("ABSOLUTELY NO WARRANTY",content)
        self.assertIn("LICENSE",content)

    def test_gutter_theme_and_font_zoom(self):
        editor=self.app.new_document(Document("\n".join(f"WriteLn({n});" for n in range(1,31))+"\n"))
        editor.toggle_breakpoint(3)
        editor.show_exec(3)
        self.root.update()
        numbers=[int(editor.gutter.itemcget(i,"text")) for i in editor.gutter.find_all() if editor.gutter.type(i)=="text"]
        # The visible lines, wherever show_exec scrolled to.
        self.assertIn(3,numbers)
        self.assertEqual(numbers,list(range(numbers[0],numbers[0]+len(numbers))))
        self.assertEqual(len([i for i in editor.gutter.find_all() if editor.gutter.type(i)=="oval"]),1)
        self.assertEqual(len([i for i in editor.gutter.find_all() if editor.gutter.type(i)=="polygon"]),1)
        self.assertEqual(editor.text.cget("bg"),"#ffffff")
        self.app.settings["theme"]="dark"
        editor.apply_options()
        self.assertEqual(editor.text.cget("bg"),"#1e1e1e")
        self.assertEqual(editor.text.tag_cget("reserved","foreground"),"#569cd6")
        size=self.app.font.cget("size")
        self.app.zoom_font(1)
        self.assertEqual((self.app.font.cget("size"),self.app.settings["font_size"]),(size+1,size+1))

    def test_text_commands_ignore_other_windows(self):
        editor=self.app.new()
        editor.text.edit_separator()
        editor.text.insert("1.0","{ keep }\n")
        self.root.update()
        before=editor.text.get("1.0","end")
        self.app.activate(self.app.messages_window)
        self.app.user_input()
        self.assertIn("Created by",self.app.status.cget("text"))
        self.assertEqual(self.app.position_label.cget("text"),"")
        self.app.search_term="keep"
        with patch("odin.app.filedialog.asksaveasfilename") as ask:
            for action in ("undo","redo","cut","copy","paste","all"):self.app.edit(action)
            self.app.delete_line()
            self.app.find_next()
            self.app.find_dialog()
            self.app.find_dialog(True)
            self.app.goto_line()
            self.app.breakpoint()
            self.assertFalse(self.app.save())
            self.assertFalse(self.app.save(as_new=True))
            self.root.update()
        ask.assert_not_called()
        self.assertEqual(editor.text.get("1.0","end"),before)
        self.assertFalse(editor.text.tag_ranges("sel"))
        self.assertFalse(editor.document.breakpoints)
        self.assertEqual(self.toplevels(),[])
        self.assertIs(self.app.active,self.app.messages_window)
        self.app.focus_editor()
        self.assertIs(self.app.active,editor)

    def test_compile_from_another_window_uses_last_editor(self):
        source=self.path/"last.pas"
        source.write_text("program Last;\nbegin\nend.\n")
        self.app.open_file(source)
        self.app.activate(self.app.messages_window)
        paths=[]
        def fake_build(path,settings,rebuild):
            paths.append(path)
            raise RuntimeError("stub compiler")
        with patch("odin.app.build",side_effect=fake_build),patch("odin.app.messagebox.showerror") as error:
            self.app.compile()
            self.assertIn("Compiling last.pas",self.app.status.cget("text"))
            self.wait_for(lambda:not self.app.compiling,5)
        self.assertEqual(paths,[source.resolve()])
        error.assert_called_once()
        self.assertIs(self.app.active,self.app.messages_window)

    def test_recovery_ignores_other_windows(self):
        self.app.write_session()
        items=json.loads(self.app.session.read_text(encoding="utf-8"))
        self.assertEqual(len(items),len(self.app.editors))
        self.assertEqual(Path(items[0]["path"]).name,"bab01_01_halo_dunia.pas")

    def test_breakpoints_follow_edits_and_survive_recovery(self):
        editor=self.app.new_document(Document("program p;\nbegin\n  WriteLn(1);\n  WriteLn(2);\nend.\n"))
        editor.toggle_breakpoint(3)
        editor.text.insert("1.0","{ new line above }\n")
        self.root.update()
        self.assertEqual(editor.document.breakpoints,{4})
        # Enter at the start of the line moves the breakpoint down with its code.
        editor.text.insert("4.0","\n")
        self.root.update()
        self.assertEqual(editor.document.breakpoints,{5})
        editor.toggle_breakpoint(6)
        editor.text.delete("5.0","6.0")
        self.root.update()
        self.assertEqual(editor.document.breakpoints,{5})
        self.app.write_session()
        items=json.loads(self.app.session.read_text(encoding="utf-8"))
        self.assertEqual(items[-1]["breakpoints"],[5])
        count=len(self.app.editors)
        with patch("odin.app.messagebox.askyesno",return_value=True):
            self.app.restore_session()
        self.assertEqual(self.app.editors[-1].document.breakpoints,{5})
        # A session written before breakpoints were recorded still restores.
        self.app.session.write_text(json.dumps([{"path":None,"text":"begin\nend.\n"}]))
        with patch("odin.app.messagebox.askyesno",return_value=True):
            self.app.restore_session()
        self.assertEqual(len(self.app.editors),count*2+1)
        self.assertEqual(self.app.editors[-1].document.breakpoints,set())

    def test_debug_windows_and_exec_marker(self):
        hello=self.app.active
        labels=self.labels("Debug")
        self.assertIn("Start debugging",labels)
        self.assertIn("Watches",labels)
        self.assertFalse([l for l in labels if "LLDB" in l])
        watch=self.app.show_watches()
        self.app.watches=["N","I * 2"]
        self.app.refresh_watches()
        self.assertEqual(watch.rows(),["N: ","I * 2: "])
        stack=self.app.show_stack()
        local=self.app.show_locals()
        self.assertEqual(self.app.windows[3:],[watch,stack,local])
        self.assertEqual(self.app.editors,[hello])
        # They stack on the right of the editor area.
        self.root.update()
        self.assertLess(watch.geometry()[1],stack.geometry()[1])
        self.assertGreater(watch.geometry()[0],self.app.workspace.winfo_width()//2)
        hello.show_exec(4)
        self.assertEqual([str(i) for i in hello.text.tag_ranges("exec")],["4.0","5.0"])
        self.app.clear_exec()
        self.assertEqual(hello.text.tag_ranges("exec"),())
        self.app.close_window(watch)
        self.assertIsNone(self.app.watch_window)
        self.assertIs(self.app.show_watches().__class__,watch.__class__)
        with patch("odin.app.messagebox.showinfo") as info:
            self.app.find_error()
        info.assert_called_once()

    @needs_odin
    def test_compile_errors_fill_the_messages_window(self):
        source=self.path/"salah.pas"
        source.write_text("program Salah;\nbegin\n  X := ;\nend.\n")
        editor=self.app.open_file(source)
        self.app.compile()
        self.wait_for(lambda:not self.app.compiling and self.app.last_build is not None)
        self.root.update()
        window=self.app.messages_window
        rows=[window.list.item(i,"values") for i in window.list.get_children()]
        self.assertEqual(rows[0][:2],("Error","salah.pas:3:8"))
        self.assertEqual(rows[-1][2],"Compile failed")
        self.assertIn("odinpc",window.log.get("1.0","end"))
        # The first error is shown at once, as in Turbo Pascal.
        self.assertIs(self.app.active,editor)
        self.assertEqual(editor.text.index("insert"),"3.7")
        self.assertEqual(str(editor.text.tag_ranges("error")[0]),"3.0")

    @needs_odin
    def test_real_gui_compile_and_run_in_the_output_window(self):
        source=self.path/"gui-check.pas"
        source.write_text("program GuiCheck; var N: Integer; begin N := 6 * 7; WriteLn('GUI_RUN_OK ', N); end.")
        self.app.open_file(source)
        # A failure to start the program shows an error dialog; record it instead of blocking.
        with patch("odin.app.messagebox.showerror") as error:
            self.app.run()
            self.wait_finished()
        self.assertEqual(error.call_args_list,[])
        self.assertTrue(self.app.last_build.success,self.app.last_build.output)
        self.assertEqual(self.app.last_build.command[1],"build")
        self.assertIn("GUI_RUN_OK 42",self.screen())
        self.assertIn("Process finished, exit code 0",self.screen())
        self.assertIs(self.app.active,self.app.output_window)
        self.assertEqual(self.app.status.cget("text"),"Program finished. Exit code 0")
        self.assertEqual(self.app.output_window.title.cget("text"),"Output")

    @needs_pty
    def test_interactive_input_and_program_reset(self):
        source=self.path/"tanya.pas"
        source.write_text("program Tanya;\nuses Crt;\nvar S: string;\nbegin\n  Write('Nama: ');\n  ReadLn(S);\n"
                          "  WriteLn('Halo ', S);\n  Delay(60000);\nend.\n")
        self.app.open_file(source)
        self.app.run()
        self.wait_for(lambda:"Nama:" in self.screen())
        self.assertEqual(self.app.output_window.title.cget("text"),"Output - tanya")
        self.assertEqual(self.app.tools["Stop"].state(),())
        self.app.send_input(b"Odin\r")
        self.wait_for(lambda:"Halo Odin" in self.screen())
        self.app.stop()
        self.wait_finished()
        self.assertIn("disabled",self.app.tools["Stop"].state())

    @needs_odin
    def test_vision_example_in_the_output_window(self):
        # tests/pascal/vision/VISION.PAS (Odin Vision) in the Output window: a mouse click opens the Help
        # menu, Esc closes it, Alt+X quits and the screen before the program comes back.
        self.app.open_file(ROOT/"tests"/"pascal"/"vision"/"VISION.PAS")
        self.app.run()

        def wait(text,seconds=10):
            deadline=time.monotonic()+seconds
            while time.monotonic()<deadline:
                self.root.update()
                if self.app.console and text in self.screen():return
                time.sleep(.02)
            self.fail(f"{text!r} not in the Output window:\n{self.screen() if self.app.console else ''}")

        wait("Alt+X Exit")
        self.assertTrue(self.app.last_build.success,self.app.last_build.output)
        self.app.zoom(self.app.output_window)
        console=self.app.console
        console.render()
        self.root.update()
        column=self.screen().split("\n")[0].index("Help")
        x,y,w,h=console.bbox(f"1.{column}")
        console.event_generate("<ButtonPress-1>",x=x+1,y=y+1)
        console.event_generate("<ButtonRelease-1>",x=x+1,y=y+1)
        wait("About...")
        self.app.send_input(b"\x1b")
        self.app.send_input(b"\x1b")
        self.app.send_input(b"\x1bx")
        wait("Process finished")
        self.assertIn("Demo Turbo Vision selesai.",self.screen())
        self.assertNotIn("Alt+X Exit",self.screen())

    @needs_pty
    def test_graph_program_opens_a_window_with_the_real_pixels(self):
        from odin.core import build
        source=self.path/"gwin.pas"
        source.write_text("program GWin;\nuses Crt, Graph;\nvar gd, gm: Integer;\nbegin\n  gd := VGA; gm := VGAHi;\n"
                          "  InitGraph(gd, gm, '');\n  SetFillStyle(SolidFill, Red);\n  Bar(10, 20, 109, 59);\n"
                          "  PutPixel(300, 300, LightGreen);\n  ReadKey;\n  CloseGraph;\nend.\n")
        self.app.last_build=build(source,self.settings,cache=self.path/"build")
        self.assertTrue(self.app.last_build.success,self.app.last_build.diagnostics)
        self.app.start_process()
        self.wait_for(lambda:self.app.graph_window and self.app.graph_window.image)
        window=self.app.graph_window
        self.assertEqual((window.image.width(),window.image.height()),(640,480))
        self.assertEqual(window.image.get(50,40),(170,0,0))       # inside the red bar, DOS red
        self.assertEqual(window.image.get(300,300),(85,255,85))   # the single light green pixel
        self.assertEqual(window.image.get(5,5),(0,0,0))
        self.app.send_input(b"x")                                 # ReadKey, then CloseGraph removes the window
        self.wait_for(lambda:window.state()=="withdrawn")
        self.wait_finished()

    @needs_odin
    def test_real_gui_debug_session(self):
        source=self.path/"REKURSI.PAS"
        source.write_text((ROOT/"tests"/"pascal"/"debug"/"REKURSI.PAS").read_text())
        editor=self.app.open_file(source)
        editor.toggle_breakpoint(9)
        self.app.watches=["N"]
        watch=self.app.show_watches()
        stack=self.app.show_stack()
        self.app.debug()
        self.wait_for(lambda:self.app.debug_stopped)
        self.assertEqual(str(editor.text.tag_ranges("exec")[0]),"9.0")
        self.assertEqual(editor.exec_line,9)
        self.wait_for(lambda:watch.rows()==["N: 2"])
        self.wait_for(lambda:len(stack.rows())==2)
        self.assertEqual(stack.rows(),["Faktorial(2): REKURSI.PAS:9","Rekursi: REKURSI.PAS:15"])
        self.app.select_frame(1)
        # Frame 1 is the main program, where N is unknown.
        self.wait_for(lambda:watch.rows()==["N: Identifier tidak dikenal: N"])
        self.app.debug_step("into")
        self.wait_for(lambda:self.app.debug_stopped and str(editor.text.tag_ranges("exec")[0])=="6.0")
        self.wait_for(lambda:watch.rows()==["N: 1"])
        # Removing the breakpoint during the session takes effect at once.
        editor.toggle_breakpoint(9)
        self.app.debug_step("continue")
        self.wait_finished()
        self.assertIsNone(self.app.debugger)
        self.assertEqual(editor.text.tag_ranges("exec"),())
        self.assertIn("Process finished, exit code 0",self.screen())
        self.assertIn("10! =  3628800",self.screen())

    @needs_odin
    def test_runtime_error_line_after_run(self):
        source=self.path/"crash.pas"
        source.write_text("program Crash;\nvar P: ^Integer;\nbegin\n  P := nil;\n  WriteLn(P^);\nend.\n")
        editor=self.app.open_file(source)
        self.app.run()
        self.wait_finished()
        self.assertEqual(self.app.last_runtime_error,(216,source.resolve(),5))
        self.assertEqual(str(editor.text.tag_ranges("error")[0]),"5.0")
        self.assertIn("Runtime error 216",self.app.status.cget("text"))
        editor.text.tag_remove("error","1.0","end")
        self.app.find_error()
        self.assertEqual(str(editor.text.tag_ranges("error")[0]),"5.0")

    @needs_odin
    def test_ukur_runs_in_the_output_window_and_shows_metrics(self):
        self.assertIn("Ukur",self.labels("Run"))
        source=self.path/"ukur.pas"
        source.write_text("program Ukur;\nvar I, S, Tak: LongInt;\nbegin\n  S := 0;\n  for I := 1 to 100 do\n"
                          "    S := S + I;\n  WriteLn('UKUR_OK ', S);\nend.\n")
        self.app.open_file(source)
        self.app.measure()
        self.wait_for(lambda:self.app.last_metrics is not None)
        report=self.app.last_metrics
        case=report["cases"][0]
        # 1 (S := 0) + 1 + 100 (for) + 100 (body) + 1 (WriteLn)
        self.assertEqual((case["verdict"],case["steps"],case["depth_max"]),("selesai",203,1))
        self.assertIn("UKUR_OK 5050",self.screen())
        self.assertEqual({e["line"]:e["steps"] for e in report["lines"]}[6],100)
        self.assertEqual([n["code"] for n in report["structure"]["notes"]],["unused-var"])
        windows=[w for w in self.toplevels() if "Metrik" in w.title()]
        self.assertEqual(len(windows),1)

    @needs_odin
    def test_periksa_scores_a_problem_package(self):
        package=self.path/"paket"
        (package/"kasus").mkdir(parents=True)
        (package/"aturan.json").write_text(json.dumps({"judul":"Jumlah","syarat":["tanpa_goto"]}))
        for name,given,expected in (("contoh1","3\n","6\n"),("r1","10\n","55\n"),("r2","0\n","1\n")):
            (package/"kasus"/f"{name}.in").write_text(given)
            (package/"kasus"/f"{name}.out").write_text(expected)
        source=self.path/"jumlah.pas"
        source.write_text("program Jumlah;\nvar N, I, S: LongInt;\nbegin\n  ReadLn(N);\n  S := 0;\n"
                          "  for I := 1 to N do\n    S := S + I;\n  WriteLn(S);\nend.\n")
        self.app.open_file(source)
        with patch("odin.app.filedialog.askdirectory",return_value=str(package)):
            self.app.check_package()
        self.wait_for(lambda:self.app.last_metrics is not None)
        report=self.app.last_metrics
        self.assertEqual({c["name"]:c["verdict"] for c in report["cases"]},{"contoh1":"lulus","r1":"lulus","r2":"salah"})
        self.assertEqual((report["score"]["passed"],report["score"]["points"]),(2,66))
        self.assertEqual(report["requirements"],[{"name":"tanpa_goto","label":"tanpa goto","met":True}])

if __name__=="__main__":unittest.main()
