# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Run on macOS desktop, or DISPLAY=localhost:99 on a Linux test display."""
import os
import sys
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path
from unittest.mock import patch

from odin.core import BuildResult, Diagnostic, Document, Settings, locate_compiler


@unittest.skipUnless(os.environ.get("DISPLAY") or sys.platform=="darwin", "Needs graphical display")
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
        self.assertIn("Hello, Pascal",self.app.session.read_text())
        self.app.clear_breakpoints()
        self.assertFalse(editor.document.breakpoints)

    def test_menus_dialogs_and_terminal(self):
        self.assertEqual(set(self.app.menus),set("ODIN File Edit Search Run Compile Debug Options Window Help".split()))
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

    def test_logo_on_desktop_and_about(self):
        self.assertIsNotNone(self.app.icon)
        self.assertEqual((self.app.logo.width(),self.app.logo.height()),(280,332))
        self.assertEqual(str(self.app.watermark.cget("image")),str(self.app.logo))
        self.assertEqual(self.app.author.cget("text"),"Created by Syams Ideris")
        self.assertIn("Created by Syams Ideris",self.app.status.cget("text"))
        self.app.user_input()
        self.assertIn("Insert",self.app.status.cget("text"))
        about=self.app.about()
        self.root.update()
        self.assertEqual(str(self.app.about_logo.cget("image")),str(self.app.logo_small))
        self.assertTrue(self.app.about_logo.winfo_ismapped())
        about.destroy()

    def test_v2_layout_title_gutter_and_output_panel(self):
        first=self.app.active
        second=self.app.new()
        self.root.update()
        self.assertIn("[2 / 2]",second.title.cget("text"))
        self.assertIn("[1 / 2]",first.title.cget("text"))
        self.assertTrue(second.box.double)
        self.assertFalse(first.box.double)
        self.assertEqual(self.app.status.cget("bg"),"#00aaaa")
        self.assertIn("ODIN Turbo Pascal",self.app.output.get("1.0","end"))
        second.toggle_breakpoint(2)
        self.root.update()
        texts=[second.gutter.itemcget(i,"text") for i in second.gutter.find_all()]
        self.assertIn("    1",texts)
        self.assertIn("*   2",texts)
        self.assertTrue(second.text.tag_nextrange("breakpoint","1.0"))
        self.app.toggle_output()
        self.root.update()
        self.assertFalse(self.app.output_box.frame.winfo_ismapped())
        self.app.toggle_output()
        self.root.update()
        self.assertTrue(self.app.output_box.frame.winfo_ismapped())
        self.app.close_editor(first)
        self.assertIn("[1 / 1]",second.title.cget("text"))

    def test_failed_build_is_listed_in_output_panel(self):
        source=self.path/"broken.pas"
        source.write_text("program Broken;\nbegin\n  WriteLn(x);\nend.\n")
        editor=self.app.open_file(source)
        diag=Diagnostic(str(source),3,11,"Error","Identifier not found \"x\"")
        self.app.messages.put(("build",BuildResult(False,["fpc",str(source)],"",[diag],None,source)))
        self.app.compiling=True
        self.app.poll()
        self.root.update()
        log=self.app.output.get("1.0","end")
        self.assertIn("Compile failed",log)
        self.assertIn("broken.pas(3,11) Error: Identifier not found",log)
        self.assertEqual(editor.text.index("insert"),"3.10")
        self.assertTrue(editor.text.tag_nextrange("error","1.0"))
        self.assertEqual([c for c in self.root.winfo_children() if isinstance(c,tk.Toplevel)],[])

    @unittest.skipUnless(locate_compiler(os.environ.get("ODIN_FPC", "")), "Needs FPC")
    def test_real_gui_compile_and_run(self):
        self.settings["compiler"]=os.environ.get("ODIN_FPC", "")
        source=self.path/"gui-check.pas"
        source.write_text("program GuiCheck; begin WriteLn('GUI_RUN_OK'); end.")
        self.app.open_file(source)
        self.app.run()
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            self.root.update()
            if self.app.console and "Process finished" in self.app.console.screen.text():break
            time.sleep(.02)
        self.assertIsNotNone(self.app.last_build)
        self.assertTrue(self.app.last_build.success,self.app.last_build.output)
        self.assertIn("GUI_RUN_OK",self.app.console.screen.text())


if __name__=="__main__":unittest.main()
