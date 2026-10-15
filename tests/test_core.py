# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
import importlib.util
import io
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
from pathlib import Path

from odin import __version__, __version_tag__
from odin import core
from odin.core import (Document, Settings, build, data_dir, executable_name, free_vision_dir, join_command, locate_compiler,
                       locate_toolchain, lock_instance, odin_supported, parse_diagnostics, split_arguments, syntax_spans,
                       unlock_instance)
from odin.terminal import ALT_MASKS, KEYS, Process, Screen, color_256, modified_key, mouse_report

ROOT=Path(__file__).resolve().parent.parent
FPC=locate_compiler(os.environ.get("ODIN_FPC",""))


class VersionTests(unittest.TestCase):
    def test_hello_example_carries_release_tag(self):
        # scripts/package_app.py restamps this comment on every build; a stale tag fails here.
        self.assertEqual(__version_tag__,f"v{__version__}")
        self.assertIn(f"{{ Odin Turbo Pascal {__version_tag__} - program pertama }}",(ROOT/"examples"/"HELLO.PAS").read_text(encoding="utf-8"))

    def test_set_version_rewrites_every_copy(self):
        # Runs the real bump on copies of the real files, so a reworded README or doc fails here, not at release time.
        spec=importlib.util.spec_from_file_location("set_version",ROOT/"scripts"/"set_version.py")
        set_version=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(set_version)
        with tempfile.TemporaryDirectory() as temp:
            temp=Path(temp)
            for name in set_version.FILES:
                (temp/name).parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(ROOT/name,temp/name)
            changelog=temp/"CHANGELOG.md"
            changelog.write_bytes(changelog.read_bytes().replace(b"## [Unreleased]\n",b"## [Unreleased]\n\n### Diubah\n\n- Uji.\n",1))
            new="9.8.7-rc.1"
            with redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
                self.assertEqual(set_version.main([new,"--root",str(temp),"--date","2030-01-02"]),0)
                # The same version again is refused and writes nothing.
                self.assertEqual(set_version.main([new,"--root",str(temp)]),1)
            read=lambda name:(temp/name).read_text(encoding="utf-8")
            self.assertIn(f'__version__ = "{new}"',read("odin/__init__.py"))
            self.assertIn(f'version = "{new}"',read("toolchain/Cargo.toml"))
            self.assertNotIn(f'version = "{__version__}"',read("toolchain/Cargo.lock"))
            self.assertIn(f"ODIN TURBO PASCAL {new}\\n",read("Install.command"))
            self.assertTrue(read("README.txt").startswith(f"ODIN TURBO PASCAL {new}\n"))
            self.assertIn(f"Panduan penggunaan {new}\n",read("docs/HELP.txt"))
            self.assertIn(f"KOMPATIBILITAS DAN CAKUPAN VERSI {new}\n",read("docs/COMPATIBILITY.txt"))
            self.assertIn("badge/rilis-9.8.7--rc.1-",read("README.md"))
            self.assertIn(f"Pemasang ini memasang **rilis {new}**",read("README.md"))
            self.assertIn(f"{{ Odin Turbo Pascal v{new} - program pertama }}",read("examples/HELLO.PAS"))
            self.assertIn(f"## [Unreleased]\n\n## [{new}] - 2030-01-02\n\n### Diubah\n\n- Uji.\n",read("CHANGELOG.md"))
            self.assertIn(f"compare/v{__version__}...v{new}",read("CHANGELOG.md"))


class DocumentTests(unittest.TestCase):
    def test_cp437_crlf_round_trip_and_conflict(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"old.pas"
            raw="{ café }\r\nbegin\r\nend.\r\n".encode("cp437")
            p.write_bytes(raw)
            doc=Document.read(p)
            self.assertEqual(doc.encoding,"cp437")
            self.assertEqual(doc.newline,"\r\n")
            doc.save()
            self.assertEqual(p.read_bytes(),raw)
            p.write_bytes(b"changed")
            self.assertTrue(doc.externally_changed())

    def test_utf8_bom_and_atomic_failure(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"unicode.pas"
            raw=b"\xef\xbb\xbf"+"{ Halo 世界 }\n".encode()
            p.write_bytes(raw)
            doc=Document.read(p)
            self.assertEqual(doc.encoding,"utf-8-sig")
            doc.save()
            self.assertEqual(p.read_bytes(),raw)
            doc.encoding="ascii"
            with self.assertRaises(UnicodeEncodeError):doc.save()
            self.assertEqual(p.read_bytes(),raw)

    def test_settings_invalid_input_is_recoverable(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"settings.json"
            p.write_text('{"font_size":999,"tab_width":0,"syntax":"wrong","mode":"unsafe","backend":"gcc"}')
            s=Settings(p)
            self.assertEqual(s["backend"],"odin")
            self.assertEqual(s["font_size"],30)
            self.assertEqual(s["tab_width"],1)
            self.assertFalse(s["syntax"])
            self.assertEqual(s["mode"],"tp")

    def test_diagnostic_path_with_parentheses(self):
        text="/tmp/my (Pascal)/oops.pas(7,12) Fatal: Syntax error\nfoo.pas(2,1) Warning: Unused"
        diagnostics=parse_diagnostics(text)
        self.assertEqual(diagnostics[0].file,"/tmp/my (Pascal)/oops.pas")
        self.assertEqual((diagnostics[0].line,diagnostics[0].column),(7,12))
        self.assertEqual(len(diagnostics),2)

    def test_lexer_comments_and_escaped_quote(self):
        text="begin { end } WriteLn('it''s a string'); end."
        spans=[(kind,text[a:b]) for kind,a,b in syntax_spans(text)]
        self.assertEqual(spans,[("keyword","begin"),("comment","{ end }"),("string","'it''s a string'"),("keyword","end")])


class TerminalTests(unittest.TestCase):
    def test_clear_position_color_and_fragmented_escape(self):
        s=Screen(20,5)
        s.feed("old\x1b[")
        s.feed("2J\x1b[3;4H\x1b[1;33;44mOdin")
        self.assertEqual(s.grid[2][3],("O",11,4))
        self.assertEqual("".join(c[0] for c in s.grid[0])," "*20)

    def test_status_and_cursor_reports(self):
        s=Screen()
        s.feed("\x1b[3;5Hab\x1b[6n\x1b[5n\x1b[?6n")
        self.assertEqual(s.replies,[b"\x1b[3;7R",b"\x1b[0n"])

    def test_wrap_crlf_and_scroll(self):
        s=Screen(4,2)
        s.feed("1234\r\n5678")
        self.assertEqual(s.text(),"1234\n5678")
        s.feed("9")
        self.assertEqual(s.text(),"5678\n9   ")

    def test_backspace_delete_and_cursor_visibility(self):
        s=Screen(10,2)
        s.feed("abc\bX\x1b[?25l")
        self.assertTrue(s.text().startswith("abX"))
        self.assertFalse(s.visible)
        s.feed("\x1b[1;2H\x1b[P")
        self.assertTrue(s.text().startswith("aX"))

    def test_g1_charset_shift_and_line_drawing(self):
        # Free Vision: G1 = DEC graphics, SO/SI switch; ESC ) 0 alone must not alter text.
        s=Screen(12,2)
        s.feed("\x1b%@\x1b(B\x1b)0File \x0elqk\x0f x\r\n\x1b(0aq\x1b(Bq")
        self.assertEqual(s.text(),"File ┌─┐ x  \n▒─q         ")

    def test_mouse_modes_and_alternate_screen(self):
        # Odin Vision: SGR mouse tracking on the alternate screen; leaving it restores the text.
        s=Screen(10,2)
        s.feed("main\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1006hTV")
        self.assertEqual((s.mouse,s.sgr_mouse),({1000,1002},True))
        # Like xterm, the cursor stays where it was.
        self.assertEqual(s.text().split("\n")[0],"    TV    ")
        s.feed("\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[?1049l")
        self.assertEqual((s.mouse,s.sgr_mouse),(set(),False))
        self.assertTrue(s.text().startswith("main"))

    def test_key_modifiers_and_mouse_reports(self):
        self.assertEqual(modified_key(b"\x1b[D",2),b"\x1b[1;2D")
        self.assertEqual(modified_key(b"\x1b[3~",5),b"\x1b[3;5~")
        self.assertEqual(modified_key(b"\x1bOR",3),b"\x1b[1;3R")
        self.assertEqual(modified_key(b"\x1b[15~",1),b"\x1b[15~")
        self.assertEqual(mouse_report(0,4,2,False,True),b"\x1b[<0;5;3M")
        self.assertEqual(mouse_report(2,4,2,True,True),b"\x1b[<2;5;3m")
        self.assertEqual(mouse_report(0,4,2,True,False),b"\x1b[M#%#")

    def test_extended_colors(self):
        # 256-color and RGB SGR (ConPTY and modern programs) map to the CRT palette and do not
        # leak their parameters as other attributes (the 1 of 38;5;1 is not bold).
        s=Screen(10,1)
        s.feed("\x1b[38;5;1mA\x1b[48;5;12mB\x1b[38;2;255;255;85;48;2;0;0;170mC\x1b[0;38;5;226mD\x1b[38;5;240mE")
        self.assertEqual(s.grid[0][0],("A",1,0))
        self.assertEqual(s.grid[0][1],("B",1,12))
        self.assertEqual(s.grid[0][2],("C",11,4))
        self.assertEqual(s.grid[0][3],("D",11,0))
        self.assertEqual(s.grid[0][4][1],8)
        self.assertFalse(s.bold)
        self.assertEqual([color_256(n) for n in (0,15,16,231,232,255)],[0,15,0,15,0,15])

    def test_alt_masks(self):
        # Alt is Option (Mod2) on macOS, Mod1 on X11 and Tk's ALT_MASK on Windows, where Mod1 is Num Lock.
        self.assertEqual(ALT_MASKS,{"aqua":0x10,"win32":0x20000,"x11":0x08})

    @unittest.skipUnless(os.name=="posix","pass_fds and /bin/sh are POSIX; on Windows the debugger channel will be TCP (Tahap 8d)")
    def test_extra_descriptors_reach_grandchildren(self):
        # Spike S4: the debug channel is a pipe passed through the debugger
        # process to the program, while the program's output stays on the PTY.
        r,w=os.pipe()
        q=queue.Queue()
        p=Process(["/bin/sh","-c",f"/bin/sh -c 'printf hook >&{w}; printf screen'"],"/",lambda k,v:q.put((k,v)),
                  pass_fds=(w,),env={"ODIN_DEBUG_FDS":f"{r},{w}"})
        os.close(w)
        output=""
        while True:
            k,v=q.get(timeout=10)
            if k=="output":output+=v
            else:
                self.assertEqual(v,0)
                break
        self.assertEqual(os.read(r,100),b"hook")
        os.close(r)
        self.assertIn("screen",output)

    def test_process_stop(self):
        import sys
        q=queue.Queue()
        p=Process([sys.executable,"-c","import time; print('ready',flush=True); time.sleep(30)"],ROOT,lambda k,v:q.put((k,v)))
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            k,v=q.get(timeout=5)
            if k=="output" and "ready" in v:break
        p.stop()
        while time.monotonic()<deadline:
            k,v=q.get(timeout=5)
            if k=="exit":
                self.assertNotEqual(v,0)
                break
        else:self.fail("Process did not stop")


class PlatformTests(unittest.TestCase):
    """Platform paths and helpers; Windows behaviour is checked here by patching sys.platform."""

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin platform ")
        self.root=Path(self.temp.name)

    def tearDown(self):self.temp.cleanup()

    def test_data_dir_per_platform(self):
        home=self.root/"home"
        with patch.object(core.Path,"home",return_value=home):
            with patch.object(core.sys,"platform","darwin"):
                self.assertEqual(data_dir(),home/"Library"/"Application Support"/"OdinTurboPascal")
            with patch.object(core.sys,"platform","linux"):
                self.assertEqual(data_dir(),home/".local"/"share"/"OdinTurboPascal")
            with patch.object(core.sys,"platform","win32"):
                with patch.dict(os.environ,{"APPDATA":str(self.root/"Roaming")}):
                    self.assertEqual(data_dir(),self.root/"Roaming"/"OdinTurboPascal")
                with patch.dict(os.environ):
                    os.environ.pop("APPDATA",None)
                    self.assertEqual(data_dir(),home/"AppData"/"Roaming"/"OdinTurboPascal")
        self.assertTrue((self.root/"Roaming"/"OdinTurboPascal").is_dir())

    def test_executable_names_and_arguments(self):
        with patch.object(core.sys,"platform","win32"):
            self.assertEqual(executable_name("HELLO"),"HELLO.exe")
            # Backslashes are path separators on Windows; quotes still group words.
            self.assertEqual(split_arguments(r'C:\Pascal\data.txt "two words" 3'),[r"C:\Pascal\data.txt","two words","3"])
            self.assertEqual(join_command([r"C:\FPC\fpc.exe",r"-oC:\my dir\a.exe"]),r'C:\FPC\fpc.exe "-oC:\my dir\a.exe"')
        with patch.object(core.sys,"platform","darwin"):
            self.assertEqual(executable_name("HELLO"),"HELLO")
            self.assertEqual(split_arguments("\"hello world\" '$(no shell)' a\\ b"),["hello world","$(no shell)","a b"])
            self.assertEqual(join_command(["fpc","my file.pas"]),"fpc 'my file.pas'")

    def test_single_instance_lock(self):
        path=self.root/"instance.lock"
        first=lock_instance(path)
        self.assertIsNotNone(first)
        try:
            # Another open of the same file, as a second IDE would do, is refused.
            self.assertIsNone(lock_instance(path))
        finally:
            unlock_instance(first)
        again=lock_instance(path)
        self.assertIsNotNone(again)
        unlock_instance(again)

    def fake_file(self,path,content=""):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)
        return path

    def test_locate_compiler_in_windows_install_folders(self):
        drive=self.root/"drive"
        self.fake_file(drive/"FPC"/"3.2.0"/"bin"/"x86_64-win64"/"fpc.exe")
        self.fake_file(drive/"FPC"/"3.2.2"/"bin"/"i386-win32"/"fpc.exe")
        native=self.fake_file(drive/"FPC"/"3.2.2"/"bin"/"x86_64-win64"/"fpc.exe")
        choco=self.fake_file(self.root/"tools"/"freepascal"/"bin"/"x86_64-win64"/"fpc.exe")
        with patch.object(core.sys,"platform","win32"),patch("odin.core.shutil.which",return_value=None),\
             patch.dict(os.environ,{"SystemDrive":str(drive),"ChocolateyToolsLocation":str(self.root/"tools")}):
            # Newest version first, a 64-bit compiler before a 32-bit one.
            self.assertEqual(locate_compiler(),str(native))
            shutil.rmtree(drive/"FPC")
            self.assertEqual(locate_compiler(),str(choco))
            self.assertEqual(locate_compiler(str(native.parent)),str(choco))

    @unittest.skipUnless(os.name=="posix","the fake compiler is a shell script")
    def test_free_vision_dir_in_windows_layout(self):
        fpc=self.fake_file(self.root/"FPC"/"3.2.2"/"bin"/"x86_64-win64"/"fpc","#!/bin/sh\necho 3.2.2 x86_64 win64\n")
        units=self.root/"FPC"/"3.2.2"/"units"/"x86_64-win64"/"fv"
        units.mkdir(parents=True)
        free_vision_dir.cache_clear()
        with patch.object(core.sys,"platform","win32"):
            self.assertEqual(free_vision_dir(str(fpc)),str(units))
        free_vision_dir.cache_clear()

    def test_windows_fpc_build_command(self):
        source=self.root/"hello.pas"
        source.write_text("program Hello;\nbegin\nend.\n")
        settings=Settings(self.root/"settings.json")
        settings["backend"]="fpc"
        commands=[]
        def run(command,**options):
            commands.append((command,options))
            return subprocess.CompletedProcess(command,0,stdout="" if options.get("text") else b"")
        free_vision_dir.cache_clear()
        with patch.object(core.sys,"platform","win32"),patch("odin.core.locate_compiler",return_value=r"C:\FPC\fpc.exe"),\
             patch("odin.core.subprocess.run",side_effect=run):
            r=build(source,settings,cache=self.root/"build")
        free_vision_dir.cache_clear()
        command=r.command
        output=[a for a in command if a.startswith("-o")][0]
        self.assertTrue(output.endswith("hello.exe"),output)
        # No macOS-only flags: no -P (CPU) and no -XR (SDK).
        self.assertFalse([a for a in command if a.startswith(("-P","-XR"))])
        self.assertEqual(commands[-1][0],command)
        self.assertEqual(commands[-1][1].get("creationflags"),0x08000000 if os.name=="nt" else None)
        with patch.object(core.sys,"platform","win32"),patch("odin.core.locate_compiler",return_value=None):
            r=build(source,settings,cache=self.root/"build")
        self.assertIn("Install.ps1",r.output)


@unittest.skipUnless(FPC,"Free Pascal is not installed")
@unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc (cargo build in toolchain/) on a host it supports (core.ODIN_HOSTS)")
class OdinBackendTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin backend ")
        self.root=Path(self.temp.name)
        self.settings=Settings(self.root/"settings.json")
        self.settings["backend"]="odin"

    def tearDown(self):self.temp.cleanup()

    def test_default_backend_is_odin_and_falls_back_to_fpc(self):
        self.assertEqual(Settings(self.root/"fresh.json")["backend"],"odin")
        source=self.root/"hello.pas"
        source.write_text("program Hello;\nbegin\n  WriteLn('hi');\nend.\n")
        self.settings["compiler"]=FPC
        with patch("odin.core.locate_toolchain",return_value=None):
            r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        self.assertIn("memakai Free Pascal",r.output)
        self.assertNotEqual(r.command[1],"build")
        with patch("odin.core.odin_supported",return_value=False):
            r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        self.assertIn("belum mendukung",r.output)

    def test_diagnostics_come_back_as_objects(self):
        r=build(ROOT/"tests"/"pascal"/"errors"/"SEMI_STMT.PAS",self.settings,cache=self.root/"build")
        self.assertFalse(r.success)
        self.assertIsNone(r.executable)
        self.assertEqual(r.command[1],"build")
        d=r.diagnostics[0]
        self.assertEqual((d.line,d.column,d.kind),(5,3,"Error"))
        self.assertIn("diharapkan",d.message)
        self.assertIn("SEMI_STMT.PAS(5,3) Error 85",r.output)


class CompilerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin tests ")
        self.root=Path(self.temp.name)
        self.settings=Settings(self.root/"settings.json")
        self.settings["compiler"]=FPC
        self.settings["backend"]="fpc"

    def tearDown(self):self.temp.cleanup()

    def compile_example(self,name):
        r=build(ROOT/"examples"/name,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        return r

    def test_compile_every_example(self):
        for path in (ROOT/"examples").glob("*.PAS"):
            with self.subTest(path=path.name):self.compile_example(path.name)

    def test_actual_output_and_parameters(self):
        for name,input_data,expected,args in [
            ("HELLO.PAS","","Selamat datang",[]),
            ("INPUT.PAS","Syams\n40\n","41 tahun",[]),
            ("KALKULATOR.PAS","12\n4\n4\n","Hasil: 3.00",[]),
            ("KALKULATOR.PAS","12\n0\n4\n","Pembagi tidak boleh nol",[]),
            ("ARRAY.PAS","","75.00",[]),
            ("REKURSI.PAS","","3628800",[]),
            ("UNITDEMO.PAS","","5 kuadrat = 25",[]),
            ("PARAMETER.PAS","","1: hello world",["hello world","$(no shell)"])] :
            with self.subTest(name=name,input=input_data):
                r=self.compile_example(name)
                result=subprocess.run([str(r.executable),*args],input=input_data,capture_output=True,text=True,timeout=5,cwd=self.root)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(expected,result.stdout)

    def test_no_stale_executable_after_failed_build(self):
        source=self.root/"program with spaces.pas"
        source.write_text("program p; begin WriteLn('ok'); end.")
        first=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(first.success,first.output)
        source.write_text("program p; begin not_valid_token; end.")
        second=build(source,self.settings,cache=self.root/"build")
        self.assertFalse(second.success)
        self.assertIsNone(second.executable)
        self.assertFalse(first.executable.exists())
        self.assertTrue(any(d.kind=="Error" for d in second.diagnostics))

    def test_file_io_without_overwriting_existing_file(self):
        r=self.compile_example("BERKAS.PAS")
        output=subprocess.run([str(r.executable)],input="catatan.txt\n",text=True,capture_output=True,cwd=self.root,timeout=5)
        self.assertEqual(output.returncode,0)
        self.assertIn("Belajar Pascal",(self.root/"catatan.txt").read_text())
        second=subprocess.run([str(r.executable)],input="catatan.txt\n",text=True,capture_output=True,cwd=self.root,timeout=5)
        self.assertEqual(second.returncode,1)

    def test_interactive_pty_readln(self):
        r=self.compile_example("INPUT.PAS")
        q=queue.Queue()
        p=Process([str(r.executable)],self.root,lambda k,v:q.put((k,v)))
        output=""
        # ConPTY (Windows) may repaint with cursor moves between words: also check the rendered screen.
        screen=Screen()
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            k,v=q.get(timeout=10)
            if k=="output":
                output+=v
                screen.feed(v)
                if "Nama Anda:" in output+screen.text() and not sent:
                    p.write(b"Syams\r40\r")
                    sent=True
            else:
                self.assertEqual(v,0)
                break
        else:
            p.stop()
            self.fail("ReadLn hung")
        self.assertIn("41 tahun",output+screen.text())

    def test_crt_cursor_and_readkey(self):
        r=self.compile_example("CRTDEMO.PAS")
        q=queue.Queue()
        p=Process([str(r.executable)],self.root,lambda k,v:q.put((k,v)))
        screen=Screen()
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            k,v=q.get(timeout=10)
            if k=="output":
                screen.feed(v)
                if "Tekan sembarang" in screen.text() and not sent:
                    self.assertIn("ODIN TURBO PASCAL",screen.text())
                    self.assertEqual(screen.grid[2][22][0],"O")
                    p.write(b"x")
                    sent=True
            elif k=="exit":
                self.assertEqual(v,0)
                break
        else:
            p.stop()
            self.fail("ReadKey hung")
        self.assertTrue(sent)
        self.assertIn("Demo selesai",screen.text())

    def test_standard_units_and_turbo_vision(self):
        source=self.root/"units.pas"
        source.write_text("program Units;\nuses Crt, Dos, Strings, Printer, Objects;\nbegin\n  WriteLn(StrLen('abc'));\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        if not any(flag.startswith("-Fu") and flag.endswith("fv") for flag in r.command):
            self.skipTest("Free Vision units are not installed")
        source=self.root/"tv.pas"
        source.write_text("program TV;\nuses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, StdDlg;\nvar A: TApplication;\nbegin\n  A.Init;\n  A.Done;\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)

    def test_crt_function_keys(self):
        names=["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","Insert","Up"]
        source=self.root/"keys.pas"
        source.write_text("program Keys;\nuses Crt;\nvar I: Integer; C: Char;\nbegin\n  WriteLn('READY');\n"
                          f"  for I := 1 to {len(names)} do\n  begin\n    C := ReadKey;\n"
                          "    if C = #0 then Write(Ord(ReadKey), ' ') else Write('?', Ord(C), ' ');\n  end;\n  WriteLn('DONE');\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        q=queue.Queue()
        p=Process([str(r.executable)],self.root,lambda k,v:q.put((k,v)))
        screen=Screen()
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            k,v=q.get(timeout=10)
            if k=="output":
                screen.feed(v)
                if "READY" in screen.text() and not sent:
                    for name in names:
                        p.write(KEYS[name])
                        time.sleep(.05)
                    sent=True
            elif k=="exit":
                self.assertEqual(v,0)
                break
        else:
            p.stop()
            self.fail("ReadKey hung")
        # Turbo Pascal scan codes: F1..F10 = 59..68, F11/F12 = 133/134, Insert = 82, Up = 72.
        self.assertIn("59 60 61 62 63 64 65 66 67 68 133 134 82 72 DONE",screen.text())



@unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc (cargo build in toolchain/) on a host it supports (core.ODIN_HOSTS)")
class OdinCompilerTests(CompilerTests):
    """The same compiler tests with the Odin toolchain as backend."""
    __unittest_skip__=False

    def setUp(self):
        super().setUp()
        self.settings["backend"]="odin"

    def test_standard_units_and_turbo_vision(self):
        source=self.root/"units.pas"
        source.write_text("program Units;\nuses Crt, Dos, Strings, Printer, Objects;\nvar C: TStringCollection;\n"
                          "begin\n  C.Init(2, 2);\n  C.Insert(NewStr('b'));\n  C.Insert(NewStr('a'));\n"
                          "  WriteLn(StrLen('abc'), ' ', PString(C.At(0))^, C.Count);\n  C.Done;\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable)],capture_output=True,text=True,timeout=5,cwd=self.root)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("3 a2",result.stdout)
        # Odin Vision: the 1.0 Turbo Vision program builds and runs (without a terminal too).
        source=self.root/"tv.pas"
        source.write_text("program TV;\nuses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, StdDlg;\n"
                          "var A: TApplication;\nbegin\n  A.Init;\n  A.Done;\n  WriteLn('TV ok');\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable)],capture_output=True,text=True,timeout=5,cwd=self.root)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("TV ok",result.stdout)
        # The optional units are not there yet: the error says so.
        source.write_text("program TV;\nuses ColorSel;\nbegin\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertFalse(r.success)
        self.assertIn("belum ada di Odin Vision",r.output)

    def screen_after_run(self,executable):
        """Runs a Crt program on a PTY until it waits in ReadKey, presses a key, returns the screen."""
        q=queue.Queue()
        p=Process([str(executable)],self.root,lambda k,v:q.put((k,v)))
        screen=Screen()
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            try:k,v=q.get(timeout=1)
            except queue.Empty:
                if not sent:
                    p.write(b"x")
                    sent=True
                continue
            if k=="output":
                screen.feed(v)
                # Answer cursor-position requests as TerminalView does (FPC's Crt on Linux asks).
                while screen.replies:p.write(screen.replies.pop(0))
            elif k=="exit":
                self.assertEqual(v,0)
                return screen
        p.stop()
        self.fail("Crt program did not finish")

    @unittest.skipUnless(FPC,"Free Pascal is not installed")
    def test_crt_screen_matches_fpc(self):
        source=ROOT/"tests"/"pascal"/"crt"/"CRT_WINDOW.PAS"
        screens=[]
        for backend in ("fpc","odin"):
            self.settings["backend"]=backend
            r=build(source,self.settings,cache=self.root/f"build-{backend}")
            self.assertTrue(r.success,r.output)
            screens.append(self.screen_after_run(r.executable))
        fpc,odin=screens
        self.assertIn("full width",odin.text())
        for y in range(fpc.rows):
            for x in range(fpc.cols):
                a,b=fpc.grid[y][x],odin.grid[y][x]
                # The foreground of a blank cell cannot be seen.
                same=a[0]==b[0] and a[2]==b[2] and (a[0]==" " or a[1]==b[1])
                self.assertTrue(same,f"cell {x+1},{y+1}: FPC {a} Odin {b}")
        self.assertEqual((fpc.x,fpc.y),(odin.x,odin.y))


if __name__=="__main__":unittest.main()
