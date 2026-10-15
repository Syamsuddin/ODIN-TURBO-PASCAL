# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
import queue
import tempfile
import unittest
from pathlib import Path

from odin.core import Settings, build, locate_toolchain, odin_supported
from odin.debugger import DebugSession
from odin.terminal import Screen

ROOT = Path(__file__).resolve().parent.parent
REKURSI = ROOT / "examples" / "REKURSI.PAS"


@unittest.skipUnless(locate_toolchain() and odin_supported(), "Needs odinpc (cargo build in toolchain/) on Intel macOS")
class DebugSessionTests(unittest.TestCase):
    """The Odin debugger without Tk: odinpc debug on a PTY, driven through DebugSession."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="odin debugger ")
        self.root = Path(self.temp.name)
        self.settings = Settings(self.root / "settings.json")
        self.settings["backend"] = "odin"
        self.events = queue.Queue()
        self.screen = Screen()
        self.session = None

    def tearDown(self):
        if self.session and self.session.alive:
            self.session.terminate()
        self.temp.cleanup()

    def start(self, source):
        r = build(source, self.settings, cache=self.root / "build", debug=True)
        self.assertTrue(r.success, r.output)
        self.assertIsNotNone(r.debug_info)
        self.session = DebugSession(locate_toolchain(), r.executable, r.debug_info, [], self.root,
                                    lambda k, v: self.events.put((k, v)))
        self.wait("ready")
        return self.session

    def wait(self, event, request=None):
        while True:
            kind, value = self.events.get(timeout=15)
            if kind == "output":
                self.screen.feed(value)
            elif kind == "debug":
                self.session.update(value)
                if value.get("event") == "error":
                    self.fail(value.get("message"))
                if value.get("event") == event and (request is None or value.get("id") == request):
                    return value
            elif kind == "exit" and event != "exit":
                self.fail(f"debugger ended while waiting for {event}")
            elif kind == "exit":
                return value

    def stop(self, line, depth=None):
        event = self.wait("stopped")
        self.assertEqual((Path(event["file"]).name, event["line"]), ("REKURSI.PAS", line), event)
        if depth is not None:
            self.assertEqual(event["depth"], depth, event)
        return event

    def value(self, expression, frame=0):
        result = self.wait("result", self.session.evaluate(expression, frame))
        self.assertTrue(result["ok"], result)
        return result["value"]

    def test_breakpoint_steps_evaluate_stack_and_modify(self):
        s = self.start(REKURSI)
        # Line 8 holds no code: the breakpoint moves to line 9.
        moved = self.wait("breakpoints", s.set_breakpoints(REKURSI, {8}))
        self.assertEqual(moved["verified"], [9])
        self.assertEqual(moved["moved"], [[8, 9]])
        s.start()
        # I = 0 and 1 never reach line 9; Faktorial(2) does.
        self.stop(9, depth=2)
        self.assertEqual(self.value("N"), "2")
        self.assertEqual(self.value("I"), "2")
        s.step_into()
        self.stop(6, depth=3)
        self.assertEqual(self.value("N"), "1")
        s.step_over()
        self.stop(7, depth=3)
        # Out of Faktorial(1) and Faktorial(2), which have no statement left:
        # the next statement is the WriteLn of the main loop.
        s.step_out()
        self.stop(15, depth=1)
        self.assertEqual(self.value("I"), "3")
        s.resume()
        self.stop(9, depth=2)
        s.resume()
        self.stop(9, depth=3)
        frames = self.wait("result", s.stack())["frames"]
        self.assertEqual([f["name"] for f in frames], ["Faktorial(2)", "Faktorial(3)", "Rekursi"])
        self.assertEqual([f["line"] for f in frames], [9, 9, 15])
        self.assertEqual(self.value("N", frame=1), "3")
        local = self.wait("result", s.locals(frame=1))["locals"]
        self.assertEqual(local[0], {"name": "N", "value": "3", "type": "Integer"})
        bad = self.wait("result", s.evaluate("Zork"))
        self.assertFalse(bad["ok"])
        self.assertIn("Zork", bad["error"])
        # Faktorial(2) now computes 5 * Faktorial(4): 3! prints as 360.
        changed = self.wait("result", s.modify("N", "5"))
        self.assertEqual(changed["value"], "5")
        self.wait("breakpoints", s.set_breakpoints(REKURSI, set()))
        s.resume()
        self.assertEqual(self.wait("exited")["code"], 0)
        self.wait("exit")
        self.assertIn(" 3! =      360", self.screen.text())
        self.assertIn("10! =  3628800", self.screen.text())

    def test_pause_runtime_error_and_run_to(self):
        source = self.root / "LOOP.PAS"
        source.write_text("program Loop;\nvar\n  Count: LongInt;\n  P: ^Integer;\nbegin\n  Count := 0;\n"
                          "  while Count < 2000000000 do\n    Count := Count + 1;\n  P := nil;\n  WriteLn(P^);\nend.\n")
        s = self.start(source)
        s.start("run_to", source, 6)
        event = self.wait("stopped")
        self.assertEqual(event["line"], 6)
        s.resume()
        s.pause()
        event = self.wait("stopped")
        self.assertEqual(event["reason"], "pause")
        self.assertIn(event["line"], (7, 8))
        self.assertEqual(self.wait("result", s.modify("Count", "2000000000"))["value"], "2000000000")
        s.resume()
        error = self.wait("runtime_error")
        self.assertEqual((error["code"], error["line"]), (216, 10))
        self.assertEqual(self.wait("exited")["code"], 216)
        self.assertEqual(s.runtime_error["line"], 10)


    def test_object_fields_and_self(self):
        source = self.root / "COUNTER.PAS"
        source.write_text("program Counter;\ntype\n  TCounter = object\n    Count, Step: Integer;\n"
                          "    constructor Init(AStep: Integer);\n    procedure Tick; virtual;\n  end;\n"
                          "constructor TCounter.Init(AStep: Integer);\nbegin\n  Count := 0;\n  Step := AStep;\nend;\n"
                          "procedure TCounter.Tick;\nbegin\n  Count := Count + Step;\nend;\n"
                          "var C: TCounter;\nbegin\n  C.Init(3);\n  C.Tick;\n  C.Tick;\n  WriteLn(C.Count);\nend.\n")
        s = self.start(source)
        self.wait("breakpoints", s.set_breakpoints(source, {15}))
        s.start()
        event = self.wait("stopped")
        self.assertEqual((event["line"], event["depth"]), (15, 2))
        self.assertEqual(self.value("Self"), "(Count:0; Step:3)")
        self.assertEqual(self.value("Count + Step"), "3")
        self.assertEqual(self.value("Self.Step"), "3")
        self.assertEqual(self.value("C", frame=1), "(Count:0; Step:3)")
        local = self.wait("result", s.locals())["locals"]
        self.assertEqual(local[0], {"name": "Self", "value": "(Count:0; Step:3)", "type": "TCounter"})
        frames = self.wait("result", s.stack())["frames"]
        self.assertEqual([f["name"] for f in frames], ["TCounter.Tick", "Counter"])
        self.assertEqual(self.wait("result", s.modify("Step", "10"))["value"], "10")
        self.wait("breakpoints", s.set_breakpoints(source, set()))
        s.resume()
        self.assertEqual(self.wait("exited")["code"], 0)
        self.wait("exit")
        self.assertIn("20", self.screen.text())


if __name__ == "__main__":
    unittest.main()
