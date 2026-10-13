# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
import os
import queue
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from odin.core import Document, Settings, build, locate_compiler, parse_diagnostics, syntax_spans
from odin.terminal import KEYS, Process, Screen

ROOT=Path(__file__).resolve().parent.parent
FPC=locate_compiler(os.environ.get("ODIN_FPC",""))


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
            p.write_text('{"font_size":999,"tab_width":0,"syntax":"wrong","mode":"unsafe"}')
            s=Settings(p)
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


@unittest.skipUnless(FPC,"Free Pascal is not installed")
class CompilerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin tests ")
        self.root=Path(self.temp.name)
        self.settings=Settings(self.root/"settings.json")
        self.settings["compiler"]=FPC

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
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            k,v=q.get(timeout=10)
            if k=="output":
                output+=v
                if "Nama Anda:" in output and not sent:
                    p.write(b"Syams\r40\r")
                    sent=True
            else:
                self.assertEqual(v,0)
                break
        else:
            p.stop()
            self.fail("ReadLn hung")
        self.assertIn("41 tahun",output)

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


if __name__=="__main__":unittest.main()
