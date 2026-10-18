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
from unittest.mock import patch

from odin import __copyright__, __version_tag__
from odin.core import Document, Settings, locate_compiler, locate_toolchain, odin_supported
from odin.terminal import ALT_MASKS


@unittest.skipUnless(os.environ.get("DISPLAY") or sys.platform in ("darwin","win32"), "Needs graphical display")
class GuiTests(unittest.TestCase):
    def setUp(self):
        from odin.app import App
        self.temp=tempfile.TemporaryDirectory()
        self.path=Path(self.temp.name)
        self.settings=Settings(self.path/"settings.json")
        self.patch_settings=patch("odin.app.Settings",return_value=self.settings)
        self.patch_dir=patch("odin.app.data_dir",return_value=self.path)
        self.patch_settings.start()
        self.patch_dir.start()
        self.root=tk.Tk()
        self.app=App(self.root)
        self.errors=[]
        self.root.report_callback_exception=lambda *args:self.errors.append(args)
        self.root.update()

    def tearDown(self):
        self.app.closed=True
        self.app.cancel_callbacks()
        self.root.destroy()
        self.patch_settings.stop()
        self.patch_dir.stop()
        self.temp.cleanup()
        self.assertEqual(self.errors,[])

    def test_edit_save_find_and_undo(self):
        editor=self.app.new_document(Document("program p;\nbegin\nend.\n"))
        editor.text.insert("2.0","{ hello }\n")
        self.root.update()
        self.assertTrue(editor.document.dirty)
        target=self.path/"saved file.pas"
        with patch("odin.app.filedialog.asksaveasfilename",return_value=str(target)):
            self.assertTrue(self.app.save())
        self.assertIn("{ hello }",target.read_text())
        self.assertFalse(editor.document.dirty)
        self.app.search_term="hello"
        self.app.find_next()
        self.assertEqual(editor.text.get("sel.first","sel.last"),"hello")
        editor.text.mark_set("insert","2.0")
        editor.text.tag_remove("sel","1.0","end")
        editor.text.edit_separator()
        editor.text.insert("insert","test")
        self.app.edit("undo")
        self.assertNotIn("test",editor.text.get("1.0","end"))

    def test_window_layout_and_cancelled_close(self):
        first=self.app.new()
        second=self.app.new()
        self.root.update()
        self.app.tile()
        self.root.update()
        self.assertGreater(first.frame.winfo_width(),100)
        self.assertGreater(second.frame.winfo_height(),100)
        self.app.cascade()
        self.app.zoom()
        self.app.next_editor()
        with patch("odin.app.messagebox.askyesnocancel",return_value=None):
            self.assertFalse(self.app.close_editor(first))
        self.assertIn(first,self.app.editors)

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
        names=self.widgets(dialog,tk.Listbox)[0].get(0,"end")
        self.assertEqual(len(names),90)
        self.assertEqual((names[0],names[-1]),("bab01_01_halo_dunia.pas","matematika.pas"))
        # 90 names do not fit the 15 rows of the list.
        self.assertTrue(self.widgets(dialog,tk.Scrollbar))
        dialog.destroy()

    def test_help_menu_opens_the_book(self):
        # Help > Buku sits above About and opens docs/Belajar_Pemrograman_Bahasa_Pascal.pdf in the system viewer.
        menu=self.app.menus["Help"][1]
        labels=[menu.entrycget(i,"label") for i in range(menu.index("end")+1) if menu.type(i)=="command"]
        self.assertEqual(labels,["Contents","Pascal reference","Keyboard shortcuts","Buku","About Odin"])
        book=Path(__file__).resolve().parent.parent/"docs"/"Belajar_Pemrograman_Bahasa_Pascal.pdf"
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

    def test_menus_dialogs_and_terminal(self):
        self.assertEqual(set(self.app.menus),set("File Edit Search Run Compile Debug Options Window Help".split()))
        for action in (self.app.compiler_options,self.app.directory_options,self.app.editor_options,
                       self.app.find_dialog,self.app.examples,self.app.window_list,self.app.help,self.app.about):
            action()
            self.root.update()
            for child in self.root.winfo_children():
                if isinstance(child,tk.Toplevel):child.destroy()
        self.app.show_console()
        self.app.console.feed("\x1b[2J\x1b[3;4HReady")
        self.app.console.render()
        self.assertEqual(self.app.console.get("3.3","3.8"),"Ready")
        self.root.update()
        # A program that turns on mouse tracking gets SGR reports for clicks; keys with
        # Shift/Alt become xterm sequences (Odin Vision reads Alt+key as Esc + key).
        sent=[]
        console=self.app.console
        console.send=sent.append
        console.feed("\x1b[?1000h\x1b[?1002h\x1b[?1006h")
        console.render()
        self.root.update()
        x,y,w,h=console.bbox("3.4")
        console.event_generate("<ButtonPress-1>",x=x+1,y=y+1)
        console.event_generate("<ButtonRelease-1>",x=x+1,y=y+1)
        self.assertEqual(sent,[b"\x1b[<0;5;3M",b"\x1b[<0;5;3m"])
        sent.clear()
        alt=console.alt_mask
        console.key(type("E",(),{"keysym":"Left","state":0x01,"char":""})())
        console.key(type("E",(),{"keysym":"x","state":alt,"char":"x"})())
        console.key(type("E",(),{"keysym":"Tab","state":0x01,"char":"\t"})())
        self.assertEqual(sent,[b"\x1b[1;2D",b"\x1bx",b"\x1b[Z"])

    def test_windows_modifier_keys(self):
        # On Windows Tk reports Alt as 0x20000 and Num Lock as Mod1 (0x08); AltGr is Ctrl+Alt and types
        # a character. Checked on every platform by giving the widgets the Windows masks.
        self.app.show_console()
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

    def test_logo_on_desktop_and_about(self):
        self.assertIsNotNone(self.app.icon)
        self.assertEqual((self.app.logo.width(),self.app.logo.height()),(280,280))
        self.assertEqual(str(self.app.watermark.cget("image")),str(self.app.logo))
        plaque=self.app.plaque
        self.assertEqual(plaque.itemcget("author","text"),"Created by Syams Ideris")
        self.assertEqual(plaque.itemcget("tagline","text"),"NATIVE PASCAL IDE")
        self.assertEqual(plaque.itemcget("copyright","text"),__copyright__)
        self.assertEqual(plaque.itemcget("license","text"),"GNU GPL v3 or later")
        # The plaque sits under the logo, as wide as its longest line, whatever the editor font size.
        self.root.update()
        self.assertGreaterEqual(plaque.winfo_y(),self.app.watermark.winfo_y()+self.app.watermark.winfo_height())
        for tag in ("tagline","version","author","copyright","license"):
            x1,y1,x2,y2=plaque.bbox(tag)
            self.assertTrue(0<=x1 and x2<=int(plaque.cget("width")) and 0<=y1 and y2<=int(plaque.cget("height")),tag)
        boxes=[plaque.bbox(tag) for tag in ("tagline","author","copyright","license")]
        self.assertTrue(all(a[3]<=b[1] for a,b in zip(boxes,boxes[1:])),"plaque lines overlap")
        self.assertLess(plaque.bbox("tagline")[2],plaque.bbox("version")[0])
        self.assertIn("Created by Syams Ideris",self.app.status.cget("text"))
        # The release tag on the desktop, the startup status bar, the default page (bab01_01_halo_dunia.pas) and About.
        self.assertEqual(plaque.itemcget("version","text"),__version_tag__)
        self.assertIn(f"Odin Turbo Pascal {__version_tag__}",self.app.status.cget("text"))
        self.assertIn(f"Odin Turbo Pascal {__version_tag__} - program pertama",self.app.active_editor.text.get("1.0","end"))
        self.app.user_input()
        self.assertIn("Insert",self.app.status.cget("text"))
        self.app.about()
        self.root.update()
        about=[c for c in self.root.winfo_children() if isinstance(c,tk.Toplevel)][-1]
        text=[c for c in about.winfo_children() if isinstance(c,tk.Text)][0]
        self.assertEqual(str(text.image_cget("1.0","image")),str(self.app.logo_small))
        self.assertIn(f"Version {__version_tag__}",text.get("1.0","end"))
        about.destroy()

    def add_dummy(self,title="WATCH"):
        # Minimal non-editor desktop window, standing in for the future Watch/Locals/Call stack windows.
        from odin.windows import DesktopWindow
        class Dummy(DesktopWindow):
            def __init__(self,app,title):
                super().__init__(app,title)
                tk.Label(self.body,text="dummy window",bg="#0000aa",fg="#ffff55").pack(fill="both",expand=True)
        return self.app.add_window(Dummy(self.app,title))

    def widgets(self,parent,kind):
        found=[]
        for child in parent.winfo_children():
            if isinstance(child,kind):found.append(child)
            found+=self.widgets(child,kind)
        return found

    def toplevels(self):
        return [c for c in self.root.winfo_children() if isinstance(c,tk.Toplevel)]

    def test_desktop_window_tile_cascade_zoom_next_and_list(self):
        hello=self.app.active
        editor=self.app.new()
        dummy=self.add_dummy()
        self.root.update()
        self.assertEqual(self.app.windows,[hello,editor,dummy])
        self.assertEqual(self.app.editors,[hello,editor])
        self.assertIs(self.app.active,dummy)
        self.assertIs(self.app.last_editor,editor)
        self.assertEqual(dummy.titlebar.cget("bg"),"#aaaaaa")
        self.assertEqual(editor.titlebar.cget("bg"),"#00aaaa")
        self.app.tile()
        self.root.update()
        for window in self.app.windows:self.assertGreater(window.frame.winfo_width(),100)
        self.assertEqual(float(dummy.frame.place_info()["rely"]),.5)
        self.app.activate(hello)
        self.app.cascade()
        self.assertIs(self.app.active,dummy)
        self.app.zoom()
        self.assertEqual(dummy.frame.place_info()["x"],"5")
        visited=[]
        for _ in range(3):
            self.app.next_editor()
            visited.append(self.app.active)
        self.assertEqual(visited,[hello,editor,dummy])
        self.app.activate(hello)
        self.app.window_list()
        self.root.update()
        dialog=self.toplevels()[-1]
        listing=self.widgets(dialog,tk.Listbox)[0]
        self.assertEqual(listing.get(0,"end"),("bab01_01_halo_dunia.pas","NONAME2","WATCH"))
        listing.selection_clear(0,"end")
        listing.selection_set(2)
        [b for b in self.widgets(dialog,tk.Button) if b.cget("text")==" Open "][0].invoke()
        self.assertIs(self.app.active,dummy)
        self.assertEqual(hello.titlebar.cget("bg"),"#00aaaa")

    def test_closing_desktop_window_never_prompts(self):
        hello=self.app.active
        editor=self.app.new()
        self.assertTrue(editor.document.dirty)
        dummy=self.add_dummy()
        other=self.add_dummy("CALL STACK")
        self.root.update()
        with patch("odin.app.messagebox.askyesnocancel") as ask:
            other.close_label.event_generate("<Button-1>")
            self.assertEqual(self.app.windows,[hello,editor,dummy])
            self.assertIs(self.app.active,dummy)
            self.assertTrue(self.app.close_editor())
            self.assertIs(self.app.active,editor)
            self.app.activate(hello)
            locals_window=self.add_dummy("LOCALS")
            self.assertIs(self.app.last_editor,hello)
            self.assertTrue(self.app.close_window(hello))
        ask.assert_not_called()
        self.assertFalse(other.frame.winfo_exists())
        self.assertFalse(dummy.frame.winfo_exists())
        self.assertEqual(self.app.windows,[editor,locals_window])
        self.assertEqual(self.app.editors,[editor])
        self.assertIs(self.app.last_editor,editor)
        self.assertIs(self.app.active,locals_window)

    def test_text_commands_ignore_desktop_window(self):
        editor=self.app.new()
        editor.text.edit_separator()
        editor.text.insert("1.0","{ keep }\n")
        self.root.update()
        before=editor.text.get("1.0","end")
        dummy=self.add_dummy()
        self.app.user_input()
        self.assertIn("Created by",self.app.status.cget("text"))
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
        self.assertIs(self.app.active,dummy)
        self.app.show_console()
        [b for b in self.widgets(self.app.console_window,tk.Button) if b.cget("text")==" Editor "][0].invoke()
        self.root.update()
        self.assertIs(self.app.active,dummy)
        self.app.activate(editor)
        self.assertIn("Insert",self.app.status.cget("text"))

    def test_compile_from_desktop_window_uses_last_editor(self):
        source=self.path/"last.pas"
        source.write_text("program Last;\nbegin\nend.\n")
        self.app.open_file(source)
        dummy=self.add_dummy()
        paths=[]
        def fake_build(path,settings,rebuild):
            paths.append(path)
            raise RuntimeError("stub compiler")
        with patch("odin.app.build",side_effect=fake_build),patch("odin.app.messagebox.showerror") as error:
            self.app.compile()
            self.assertIn("Compiling last.pas",self.app.status.cget("text"))
            deadline=time.monotonic()+5
            while self.app.compiling and time.monotonic()<deadline:
                self.root.update()
                time.sleep(.02)
        self.assertFalse(self.app.compiling)
        self.assertEqual(paths,[source.resolve()])
        error.assert_called_once()
        self.assertIs(self.app.active,dummy)

    def test_recovery_ignores_desktop_windows(self):
        self.add_dummy()
        self.app.write_session()
        items=json.loads(self.app.session.read_text(encoding="utf-8"))
        self.assertEqual(len(items),len(self.app.editors))
        self.assertEqual(Path(items[0]["path"]).name,"bab01_01_halo_dunia.pas")

    @unittest.skipUnless(locate_compiler(os.environ.get("ODIN_FPC", "")), "Needs FPC")
    def test_real_gui_compile_and_run(self):
        self.settings["compiler"]=os.environ.get("ODIN_FPC", "")
        self.settings["backend"]="fpc"
        source=self.path/"gui-check.pas"
        source.write_text("program GuiCheck; begin WriteLn('GUI_RUN_OK'); end.")
        self.app.open_file(source)
        # A failure to start the program shows an error dialog; record it instead of blocking.
        with patch("odin.app.messagebox.showerror") as error:
            self.app.run()
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                self.root.update()
                if self.app.console and "Process finished" in self.app.console.screen.text():break
                time.sleep(.02)
        self.assertEqual(error.call_args_list,[])
        self.assertIsNotNone(self.app.last_build)
        self.assertTrue(self.app.last_build.success,self.app.last_build.output)
        self.assertIn("GUI_RUN_OK",self.app.console.screen.text())


    @unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
    def test_real_gui_compile_and_run_odin(self):
        self.settings["backend"]="odin"
        source=self.path/"gui-check.pas"
        source.write_text("program GuiCheck; var N: Integer; begin N := 6 * 7; WriteLn('GUI_RUN_OK ', N); end.")
        self.app.open_file(source)
        self.app.run()
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            self.root.update()
            if self.app.console and "Process finished" in self.app.console.screen.text():break
            time.sleep(.02)
        self.assertIsNotNone(self.app.last_build)
        self.assertTrue(self.app.last_build.success,self.app.last_build.output)
        self.assertEqual(self.app.last_build.command[1],"build")
        self.assertIn("GUI_RUN_OK 42",self.app.console.screen.text())

    @unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
    def test_vision_example_in_user_screen(self):
        # tests/pascal/vision/VISION.PAS (Odin Vision) in the User screen: a mouse click opens the Help
        # menu, Esc closes it, Alt+X quits and the screen before the program comes back.
        self.settings["backend"]="odin"
        root=Path(__file__).resolve().parent.parent
        self.app.open_file(root/"tests"/"pascal"/"vision"/"VISION.PAS")
        self.app.run()

        def wait(text,seconds=10):
            deadline=time.monotonic()+seconds
            while time.monotonic()<deadline:
                self.root.update()
                if self.app.console and text in self.app.console.screen.text():return
                time.sleep(.02)
            self.fail(f"{text!r} not on the User screen:\n{self.app.console.screen.text() if self.app.console else ''}")

        wait("Alt+X Exit")
        self.assertTrue(self.app.last_build.success,self.app.last_build.output)
        console=self.app.console
        console.render()
        self.root.update()
        column=console.screen.text().split("\n")[0].index("Help")
        x,y,w,h=console.bbox(f"1.{column}")
        console.event_generate("<ButtonPress-1>",x=x+1,y=y+1)
        console.event_generate("<ButtonRelease-1>",x=x+1,y=y+1)
        wait("About...")
        self.app.send_input(b"\x1b")
        self.app.send_input(b"\x1b")
        self.app.send_input(b"\x1bx")
        wait("Process finished")
        self.assertIn("Demo Turbo Vision selesai.",console.screen.text())
        self.assertNotIn("Alt+X Exit",console.screen.text())

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

    def test_debug_windows_tile_and_exec_marker(self):
        hello=self.app.active
        labels=[self.app.menus["Debug"][1].entrycget(i,"label") for i in range(self.app.menus["Debug"][1].index("end")+1)
                if self.app.menus["Debug"][1].type(i)=="command"]
        self.assertIn("Start debugging",labels)
        self.assertIn("Watch window",labels)
        self.assertFalse([l for l in labels if "LLDB" in l])
        watch=self.app.show_watches()
        self.assertEqual(float(watch.frame.place_info()["rely"]),.72)
        self.app.watches=["N","I * 2"]
        self.app.refresh_watches()
        self.assertEqual(watch.rows(),["N: ","I * 2: "])
        stack=self.app.show_stack()
        local=self.app.show_locals()
        self.assertEqual(self.app.windows,[hello,watch,stack,local])
        self.assertEqual(self.app.editors,[hello])
        self.app.tile()
        self.root.update()
        for window in self.app.windows:self.assertGreater(window.frame.winfo_width(),100)
        hello.show_exec(4)
        self.assertEqual([str(i) for i in hello.text.tag_ranges("exec")],["4.0","5.0"])
        self.app.clear_exec()
        self.assertEqual(hello.text.tag_ranges("exec"),())
        self.app.window_list()
        self.root.update()
        listing=self.widgets(self.toplevels()[-1],tk.Listbox)[0]
        self.assertEqual(listing.get(0,"end"),("bab01_01_halo_dunia.pas","Watches","Call stack","Local variables"))
        self.toplevels()[-1].destroy()
        watch.close_label.event_generate("<Button-1>")
        self.assertIsNone(self.app.watch_window)
        self.assertIs(self.app.show_watches().__class__,watch.__class__)
        with patch("odin.app.messagebox.showinfo") as info:
            self.app.find_error()
        info.assert_called_once()

    def wait_for(self,condition,seconds=10):
        deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            self.root.update()
            if condition():return True
            time.sleep(.02)
        self.fail("timed out")

    @unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
    def test_real_gui_debug_session(self):
        self.settings["backend"]="odin"
        source=self.path/"REKURSI.PAS"
        source.write_text((Path(__file__).resolve().parent/"pascal"/"debug"/"REKURSI.PAS").read_text())
        editor=self.app.open_file(source)
        editor.toggle_breakpoint(9)
        self.app.watches=["N"]
        watch=self.app.show_watches()
        stack=self.app.show_stack()
        self.app.debug()
        self.wait_for(lambda:self.app.debug_stopped)
        self.assertEqual(str(editor.text.tag_ranges("exec")[0]),"9.0")
        self.wait_for(lambda:watch.rows()==["N: 2"])
        self.wait_for(lambda:len(stack.rows())==2)
        self.assertEqual(stack.rows(),["Faktorial(2)  (REKURSI.PAS:9)","Rekursi  (REKURSI.PAS:15)"])
        self.app.select_frame(1)
        # Frame 1 is the main program, where N is unknown.
        self.wait_for(lambda:watch.rows()==["N: Identifier tidak dikenal: N"])
        self.app.debug_step("into")
        self.wait_for(lambda:self.app.debug_stopped and str(editor.text.tag_ranges("exec")[0])=="6.0")
        self.wait_for(lambda:watch.rows()==["N: 1"])
        # Removing the breakpoint during the session takes effect at once.
        editor.toggle_breakpoint(9)
        self.app.debug_step("continue")
        self.wait_for(lambda:self.app.console and "Process finished, exit code 0" in self.app.console.screen.text())
        self.assertIsNone(self.app.debugger)
        self.assertEqual(editor.text.tag_ranges("exec"),())
        self.assertIn("10! =  3628800",self.app.console.screen.text())

    @unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
    def test_runtime_error_line_after_run(self):
        self.settings["backend"]="odin"
        source=self.path/"crash.pas"
        source.write_text("program Crash;\nvar P: ^Integer;\nbegin\n  P := nil;\n  WriteLn(P^);\nend.\n")
        editor=self.app.open_file(source)
        self.app.run()
        self.wait_for(lambda:self.app.console and "Process finished" in self.app.console.screen.text())
        self.assertEqual(self.app.last_runtime_error,(216,source.resolve(),5))
        self.assertEqual(str(editor.text.tag_ranges("error")[0]),"5.0")
        self.assertIn("Runtime error 216",self.app.status.cget("text"))
        editor.text.tag_remove("error","1.0","end")
        self.app.find_error()
        self.assertEqual(str(editor.text.tag_ranges("error")[0]),"5.0")

    @unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
    def test_ukur_runs_in_the_user_screen_and_shows_metrics(self):
        self.assertIn("Ukur",[self.app.menus["Run"][1].entrycget(i,"label") for i in range(self.app.menus["Run"][1].index("end")+1)
                              if self.app.menus["Run"][1].type(i)=="command"])
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
        self.assertIn("UKUR_OK 5050",self.app.console.screen.text())
        self.assertEqual({e["line"]:e["steps"] for e in report["lines"]}[6],100)
        self.assertEqual([n["code"] for n in report["structure"]["notes"]],["unused-var"])
        windows=[w for w in self.root.winfo_children() if isinstance(w,tk.Toplevel) and "Metrik" in w.title()]
        self.assertEqual(len(windows),1)

    @unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc on a host it supports (core.ODIN_HOSTS)")
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
