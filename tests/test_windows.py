# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""The Windows port where it can be checked on any platform: the x64 layout of the ConPTY
structures, the environment block, the install folder made by scripts/stage_windows.py, the PE
check of scripts/check_windows.py, and the installer scripts themselves."""
import ctypes
import importlib.util
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from odin import conpty
from odin.core import locate_toolchain

ROOT = Path(__file__).resolve().parent.parent


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ConPtyStructureTests(unittest.TestCase):
    @unittest.skipUnless(ctypes.sizeof(ctypes.c_void_p) == 8, "the documented sizes are those of 64-bit Windows")
    def test_x64_layout(self):
        # Sizes and offsets of the Windows SDK structures on x64.
        sizes = {conpty.COORD: 4, conpty.STARTUPINFOW: 104, conpty.STARTUPINFOEXW: 112, conpty.PROCESS_INFORMATION: 24,
                 conpty.JOBOBJECT_BASIC_LIMIT_INFORMATION: 64, conpty.IO_COUNTERS: 48,
                 conpty.JOBOBJECT_EXTENDED_LIMIT_INFORMATION: 144}
        for structure, size in sizes.items():
            with self.subTest(structure=structure.__name__):
                self.assertEqual(ctypes.sizeof(structure), size)
        self.assertEqual(conpty.STARTUPINFOW.dwFlags.offset, 60)
        self.assertEqual(conpty.STARTUPINFOW.hStdInput.offset, 80)
        self.assertEqual(conpty.STARTUPINFOEXW.lpAttributeList.offset, 104)
        self.assertEqual(conpty.PROCESS_INFORMATION.dwProcessId.offset, 16)
        self.assertEqual(conpty.JOBOBJECT_BASIC_LIMIT_INFORMATION.LimitFlags.offset, 16)
        self.assertEqual(conpty.JOBOBJECT_EXTENDED_LIMIT_INFORMATION.ProcessMemoryLimit.offset, 112)

    def test_every_function_has_a_signature(self):
        names = [name for name, _, _ in conpty.SIGNATURES]
        self.assertEqual(len(names), len(set(names)))
        for name, restype, argtypes in conpty.SIGNATURES:
            with self.subTest(name=name):
                self.assertIsInstance(argtypes, tuple)
                self.assertTrue(all(isinstance(t, type) for t in argtypes))
        # COORD is passed by value, HPCON as a handle.
        create = dict((n, a) for n, _, a in conpty.SIGNATURES)["CreatePseudoConsole"]
        self.assertIs(create[0], conpty.COORD)

    def test_environment_block(self):
        block = conpty.environment_block({"b": "2", "PATH": r"C:\Windows", "A": "", "=C:": r"C:\Odin"})
        self.assertEqual(block, "=C:=C:\\Odin\0A=\0b=2\0PATH=C:\\Windows\0\0")
        self.assertEqual(conpty.environment_block({}), "\0\0")
        for bad in ({"": "x"}, {"A=B": "x"}, {"A": "x\0y"}):
            with self.assertRaises(ValueError):
                conpty.environment_block(bad)

    def test_environment_names_ignore_case(self):
        merged = conpty.merge_environment({"PATH": r"C:\Windows", "TEMP": "t"}, {"Path": r"C:\Odin"}, {"TERM": "xterm"})
        self.assertEqual(merged, {"Path": r"C:\Odin", "TEMP": "t", "TERM": "xterm"})

    def test_hresult_errors(self):
        conpty.check_hresult(0, "x")
        with self.assertRaises(OSError) as raised:
            conpty.check_hresult(-2147467259, "CreatePseudoConsole")   # E_FAIL
        self.assertIn("0x80004005", str(raised.exception))


class WindowsInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="odin install ")
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_stage_install_folder(self):
        stage = load_script("stage_windows")
        target = stage.stage(self.root / "Programs" / "OdinTurboPascal")
        for name in ("main.py", "LICENSE", "THIRD_PARTY.txt", "README.txt", "Uninstall.ps1", "Uninstall.cmd",
                     "OdinTurboPascal.pyw", "odin.ico", "odin/app.py", "odin/conpty.py", "examples/bab01_01_halo_dunia.pas", "examples/matematika.pas",
                     "docs/HELP.txt", "assets/odin.png", "assets/odin-logo.png", "rtl"):
            with self.subTest(name=name):
                self.assertTrue((target / name).exists())
        self.assertFalse(list(target.rglob("__pycache__")))
        self.assertFalse((target / "assets" / "odin-logo-master.png").exists())
        self.assertFalse((target / "assets" / "odin.icns").exists())
        self.assertEqual((target / "toolchain" / "odinpc.exe").exists(), any(p.is_file() for p in stage.TOOLCHAIN))
        # The launcher is the one from scripts/.
        self.assertEqual((target / "OdinTurboPascal.pyw").read_bytes(), (ROOT / "scripts" / "launcher_windows.pyw").read_bytes())
        # A second run never writes over an install.
        with self.assertRaises(SystemExit):
            stage.stage(target)

    def test_icon_holds_png_images(self):
        stage = load_script("stage_windows")
        data = stage.ico(stage.icns_pngs((ROOT / "assets" / "odin.icns").read_bytes()))
        reserved, kind, count = struct.unpack("<HHH", data[:6])
        self.assertEqual((reserved, kind), (0, 1))
        sizes = []
        for i in range(count):
            width, height, colors, _, planes, bits, length, offset = struct.unpack("<BBBBHHII", data[6 + 16 * i:22 + 16 * i])
            image = data[offset:offset + length]
            self.assertTrue(image.startswith(b"\x89PNG\r\n\x1a\n"))
            size = struct.unpack(">I", image[16:20])[0]
            self.assertEqual(width, size % 256)
            self.assertEqual((height, planes, bits), (size % 256, 1, 32))
            sizes.append(size)
        self.assertEqual(sizes, sorted(sizes))
        self.assertIn(256, sizes)
        self.assertTrue(all(size <= 256 for size in sizes))

    def test_pe_machine(self):
        check = load_script("check_windows")
        header = bytearray(256)
        header[:2] = b"MZ"
        header[60:64] = struct.pack("<I", 128)
        header[128:132] = b"PE\0\0"
        for machine, name in ((0x8664, "x86_64"), (0x014C, "i386")):
            header[132:134] = struct.pack("<H", machine)
            path = self.root / f"{name}.exe"
            path.write_bytes(bytes(header))
            self.assertEqual(check.pe_machine(path), name)
        (self.root / "script.exe").write_bytes(b"#!/bin/sh\n")
        self.assertIsNone(check.pe_machine(self.root / "script.exe"))

    def test_installer_scripts(self):
        # Windows PowerShell 5.1 reads a script without BOM in the ANSI code page: ASCII only.
        for name in ("Install.ps1", "Uninstall.ps1"):
            with self.subTest(name=name):
                data = (ROOT / name).read_bytes()
                data.decode("ascii")
                self.assertTrue(data.startswith(b"# SPDX-License-Identifier: GPL-3.0-or-later\n# Copyright (c) 2026 Syams Ideris\n"))
        install = (ROOT / "Install.ps1").read_text(encoding="ascii")
        for text in ("Dibuat oleh Syams Ideris", "Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris",
                     "Python.Python.3.13", "scripts\\check_windows.py", "scripts\\stage_windows.py",
                     "python-path", "WScript.Shell", "-X utf8", "OdinTurboPascal.pyw", ".backup-"):
            with self.subTest(text=text):
                self.assertIn(text, install)
        # odinpc.exe is the only compiler: the installer never looks for or installs Free Pascal.
        self.assertNotIn("fpc", install.lower())
        self.assertNotIn("free pascal", install.lower())
        # cmd.exe wrappers keep CRLF line ends (.gitattributes stops Git from converting them).
        for name in ("Install.cmd", "Uninstall.cmd"):
            with self.subTest(name=name):
                data = (ROOT / name).read_bytes()
                data.decode("ascii")
                self.assertEqual(data.count(b"\n"), data.count(b"\r\n"))
                self.assertIn(b"-ExecutionPolicy Bypass -File \"%~dp0" + name.replace(".cmd", ".ps1").encode(), data)

    def test_inno_setup_script(self):
        # Pure ASCII (Inno reads it in the ANSI code page) and wired to the staging folder.
        text = (ROOT / "scripts" / "odin_setup.iss").read_bytes().decode("ascii")
        for needle in ("PrivilegesRequired=lowest", "{localappdata}\\Programs\\OdinTurboPascal", "MinVersion=10.0.17763",
                       "{#Staging}", "python\\pythonw.exe", "-E -X utf8", "check_windows.py", "x64os",
                       "OutputBaseFilename=OdinTurboPascal-{#Version}-Setup-x64"):
            with self.subTest(needle=needle):
                self.assertIn(needle, text)
        self.assertNotIn("fpc", text.lower())
        # AppId is the identity of upgrades: it must stay what the first setup used.
        self.assertIn("AppId={{8BDFFEC5-4A07-4791-ADB8-2CE29C6E1209}", text)

    def test_setup_builder_pins_python(self):
        build = load_script("build_setup_windows")
        self.assertRegex(build.PYTHON_SHA256, r"^[0-9a-f]{64}$")
        self.assertIn(build.PYTHON_VERSION, build.PYTHON_URL)
        self.assertTrue(build.PYTHON_URL.startswith("https://www.python.org/"))
        config = (ROOT / "toolchain" / ".cargo" / "config.toml").read_text()
        self.assertIn("+crt-static", config)

    @unittest.skipUnless(sys.platform == "win32" and locate_toolchain(), "needs odinpc.exe on Windows")
    def test_installer_compile_gate(self):
        result = subprocess.run([sys.executable, str(ROOT / "scripts" / "check_windows.py")],
                                capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OK: odinpc.exe: compile + run native x86_64", result.stdout)

    @unittest.skipUnless(sys.platform == "win32" and shutil.which("powershell"), "needs Windows PowerShell")
    def test_powershell_parses_installer_scripts(self):
        for name in ("Install.ps1", "Uninstall.ps1"):
            with self.subTest(name=name):
                path = str(ROOT / name).replace("'", "''")
                script = ("$errors = $null; $tokens = $null; "
                          f"[void][System.Management.Automation.Language.Parser]::ParseFile('{path}', [ref]$tokens, [ref]$errors); "
                          "$errors | ForEach-Object { $_.ToString() }; exit $errors.Count")
                result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                                        capture_output=True, text=True, timeout=120)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_launcher_compiles(self):
        path = ROOT / "scripts" / "launcher_windows.pyw"
        compile(path.read_text(encoding="utf-8"), str(path), "exec")


if __name__ == "__main__":
    unittest.main()
