# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""User screen on Windows: a child process on a ConPTY pseudoconsole (Windows 10 1809 or later),
reached through ctypes so the IDE stays stdlib only.

ConPtyProcess keeps the contract of the POSIX PtyProcess in terminal.py: a reader thread calls
emit("output", text) for everything the program shows and finally emit("exit", code); write(),
resize(), interrupt() and stop() work the same way.

- Two anonymous pipes connect the IDE to the pseudoconsole. ConPTY (conhost) turns the console
  API calls of the program into VT sequences on the output pipe, and the bytes written to the input
  pipe (keys, xterm sequences, 0x03 for Ctrl-C) into console input.
- The child is created suspended, assigned to a job object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
  and then resumed. stop() terminates the job, so the whole process tree ends, as killpg does on
  POSIX; the job also goes when the IDE exits.
- conhost keeps the output pipe open after the program exits. A waiter thread closes the
  pseudoconsole once the program has gone, which breaks the pipe and ends the reader, while the
  reader keeps draining the pipe (ClosePseudoConsole may wait for that before Windows 11 24H2).

The structures use fixed-size types, so tests can check their x64 layout on any platform;
kernel32 is only loaded on Windows, when the first process starts."""
from __future__ import annotations

import codecs
import ctypes
import os
import subprocess
import sys
import threading
import time

DWORD = ctypes.c_uint32
WORD = ctypes.c_uint16
SHORT = ctypes.c_int16
BOOL = ctypes.c_int32
UINT = ctypes.c_uint32
HRESULT = ctypes.c_int32
HANDLE = ctypes.c_void_p      # also HPCON and LPPROC_THREAD_ATTRIBUTE_LIST
LPVOID = ctypes.c_void_p
LPCWSTR = ctypes.c_wchar_p
SIZE_T = ctypes.c_size_t      # also ULONG_PTR and DWORD_PTR
LARGE_INTEGER = ctypes.c_int64
ULONGLONG = ctypes.c_uint64

EXTENDED_STARTUPINFO_PRESENT = 0x00080000
CREATE_UNICODE_ENVIRONMENT = 0x00000400
CREATE_SUSPENDED = 0x00000004
STARTF_USESTDHANDLES = 0x00000100
PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS = 9   # JobObjectExtendedLimitInformation
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000
# No Windows Error Reporting dialog when a program crashes: it ends at once, as on POSIX.
JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION = 0x00000400
INFINITE = 0xFFFFFFFF
WAIT_OBJECT_0 = 0x00000000
WAIT_TIMEOUT = 0x00000102
RESUME_FAILED = 0xFFFFFFFF
FACILITY_WIN32 = 7
# Exit code of a process ended by stop(), like subprocess.Popen.terminate() on Windows.
TERMINATED = 1


class COORD(ctypes.Structure):
    _fields_ = [("X", SHORT), ("Y", SHORT)]


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [("cb", DWORD),
                ("lpReserved", LPVOID),
                ("lpDesktop", LPVOID),
                ("lpTitle", LPVOID),
                ("dwX", DWORD),
                ("dwY", DWORD),
                ("dwXSize", DWORD),
                ("dwYSize", DWORD),
                ("dwXCountChars", DWORD),
                ("dwYCountChars", DWORD),
                ("dwFillAttribute", DWORD),
                ("dwFlags", DWORD),
                ("wShowWindow", WORD),
                ("cbReserved2", WORD),
                ("lpReserved2", LPVOID),
                ("hStdInput", HANDLE),
                ("hStdOutput", HANDLE),
                ("hStdError", HANDLE)]


class STARTUPINFOEXW(ctypes.Structure):
    _fields_ = [("StartupInfo", STARTUPINFOW),
                ("lpAttributeList", LPVOID)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", HANDLE),
                ("hThread", HANDLE),
                ("dwProcessId", DWORD),
                ("dwThreadId", DWORD)]


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [("PerProcessUserTimeLimit", LARGE_INTEGER),
                ("PerJobUserTimeLimit", LARGE_INTEGER),
                ("LimitFlags", DWORD),
                ("MinimumWorkingSetSize", SIZE_T),
                ("MaximumWorkingSetSize", SIZE_T),
                ("ActiveProcessLimit", DWORD),
                ("Affinity", SIZE_T),
                ("PriorityClass", DWORD),
                ("SchedulingClass", DWORD)]


class IO_COUNTERS(ctypes.Structure):
    _fields_ = [("ReadOperationCount", ULONGLONG),
                ("WriteOperationCount", ULONGLONG),
                ("OtherOperationCount", ULONGLONG),
                ("ReadTransferCount", ULONGLONG),
                ("WriteTransferCount", ULONGLONG),
                ("OtherTransferCount", ULONGLONG)]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
                ("IoInfo", IO_COUNTERS),
                ("ProcessMemoryLimit", SIZE_T),
                ("JobMemoryLimit", SIZE_T),
                ("PeakProcessMemoryUsed", SIZE_T),
                ("PeakJobMemoryUsed", SIZE_T)]


# Every kernel32 function used here, with its exact signature: HANDLE results are c_void_p
# (None for NULL), out parameters are pointers, COORD goes by value.
SIGNATURES = (
    ("CreatePipe", BOOL, (ctypes.POINTER(HANDLE), ctypes.POINTER(HANDLE), LPVOID, DWORD)),
    ("CreatePseudoConsole", HRESULT, (COORD, HANDLE, HANDLE, DWORD, ctypes.POINTER(HANDLE))),
    ("ResizePseudoConsole", HRESULT, (HANDLE, COORD)),
    ("ClosePseudoConsole", None, (HANDLE,)),
    ("SetConsoleCtrlHandler", BOOL, (LPVOID, BOOL)),
    ("InitializeProcThreadAttributeList", BOOL, (LPVOID, DWORD, DWORD, ctypes.POINTER(SIZE_T))),
    ("UpdateProcThreadAttribute", BOOL, (LPVOID, DWORD, SIZE_T, LPVOID, SIZE_T, LPVOID, ctypes.POINTER(SIZE_T))),
    ("DeleteProcThreadAttributeList", None, (LPVOID,)),
    ("CreateProcessW", BOOL, (LPCWSTR, LPVOID, LPVOID, LPVOID, BOOL, DWORD, LPVOID, LPCWSTR,
                              ctypes.POINTER(STARTUPINFOEXW), ctypes.POINTER(PROCESS_INFORMATION))),
    ("ResumeThread", DWORD, (HANDLE,)),
    ("CreateJobObjectW", HANDLE, (LPVOID, LPCWSTR)),
    ("SetInformationJobObject", BOOL, (HANDLE, ctypes.c_int, LPVOID, DWORD)),
    ("AssignProcessToJobObject", BOOL, (HANDLE, HANDLE)),
    ("TerminateJobObject", BOOL, (HANDLE, UINT)),
    ("TerminateProcess", BOOL, (HANDLE, UINT)),
    ("WaitForSingleObject", DWORD, (HANDLE, DWORD)),
    ("GetExitCodeProcess", BOOL, (HANDLE, ctypes.POINTER(DWORD))),
    ("ReadFile", BOOL, (HANDLE, LPVOID, DWORD, ctypes.POINTER(DWORD), LPVOID)),
    ("WriteFile", BOOL, (HANDLE, LPVOID, DWORD, ctypes.POINTER(DWORD), LPVOID)),
    ("CloseHandle", BOOL, (HANDLE,)),
)

_kernel32 = None
_kernel32_lock = threading.Lock()


def kernel32():
    """kernel32.dll with the signatures above (a private WinDLL, so nobody else's argtypes leak in)."""
    global _kernel32
    with _kernel32_lock:
        if _kernel32 is None:
            dll = ctypes.WinDLL("kernel32", use_last_error=True)
            for name, restype, argtypes in SIGNATURES:
                try:
                    function = getattr(dll, name)
                except AttributeError:
                    raise OSError("User screen memerlukan ConPTY: Windows 10 versi 1809 atau yang lebih baru.") from None
                function.restype = restype
                function.argtypes = argtypes
            _kernel32 = dll
        return _kernel32


def last_error():
    return ctypes.WinError(ctypes.get_last_error())


def check_hresult(result, what):
    if result < 0:
        code = result & 0xFFFFFFFF
        if (code >> 16) & 0x1FFF == FACILITY_WIN32:
            raise ctypes.WinError(code & 0xFFFF)
        raise OSError(f"{what} gagal (HRESULT 0x{code:08X}).")


def merge_environment(*sources):
    """Like dict(os.environ, **extra) on POSIX, but names compare without regard to case, as
    Windows does: a later Path replaces PATH instead of sitting next to it."""
    merged = {}
    for source in sources:
        for name, value in source.items():
            merged[str(name).upper()] = (str(name), str(value))
    return dict(merged.values())


def environment_block(environment):
    """The Unicode environment block for CreateProcessW: NAME=value strings sorted by name
    without regard to case (as Windows expects), each ending in NUL, plus a final NUL."""
    entries = []
    for name, value in sorted(environment.items(), key=lambda item: item[0].upper()):
        if not name or "=" in name[1:] or "\0" in name or "\0" in value:
            raise ValueError(f"Nama atau nilai variabel lingkungan tidak sah: {name!r}")
        entries.append(f"{name}={value}\0")
    return "".join(entries) + "\0" if entries else "\0\0"


def _close(handle):
    if handle:
        kernel32().CloseHandle(handle)


def _pipe():
    read, write = HANDLE(), HANDLE()
    if not kernel32().CreatePipe(ctypes.byref(read), ctypes.byref(write), None, 0):
        raise last_error()
    return read.value, write.value


def _job():
    """A job that kills its processes when its last handle closes; None if Windows refuses."""
    k = kernel32()
    job = k.CreateJobObjectW(None, None)
    if not job:
        return None
    limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION
    if not k.SetInformationJobObject(job, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS,
                                     ctypes.byref(limits), ctypes.sizeof(limits)):
        _close(job)
        return None
    return job


class Child:
    """What the IDE uses of subprocess.Popen: pid, returncode, poll(), wait() and terminate()."""

    def __init__(self, handle, pid, args):
        self.args = args
        self.pid = pid
        self.returncode = None
        self._handle = handle
        self._lock = threading.Lock()

    def poll(self):
        with self._lock:
            if self.returncode is None and kernel32().WaitForSingleObject(self._handle, 0) == WAIT_OBJECT_0:
                code = DWORD()
                if not kernel32().GetExitCodeProcess(self._handle, ctypes.byref(code)):
                    raise last_error()
                self.returncode = code.value
            return self.returncode

    def wait(self, timeout=None):
        if self.returncode is None:
            milliseconds = INFINITE if timeout is None else max(0, int(timeout * 1000))
            result = kernel32().WaitForSingleObject(self._handle, milliseconds)
            if result == WAIT_TIMEOUT:
                raise subprocess.TimeoutExpired(self.args, timeout)
            if result != WAIT_OBJECT_0:
                raise last_error()
        return self.poll()

    def terminate(self):
        if self.poll() is None:
            kernel32().TerminateProcess(self._handle, TERMINATED)

    def __del__(self):
        # The handle lives as long as the object, so poll() and wait() never see a closed handle.
        handle, self._handle = getattr(self, "_handle", None), None
        if handle and _kernel32:
            _kernel32.CloseHandle(handle)


class ConPtyProcess:
    """A program on a pseudoconsole; same constructor and methods as terminal.PtyProcess."""

    def __init__(self, argv, cwd, emit, cols=80, rows=25, pass_fds=(), env=None):
        if pass_fds:
            # The debugger's channel on Windows is TCP loopback (IMPLEMENTATION_PLAN.md, Tahap 8d).
            raise OSError("Meneruskan file descriptor (pass_fds) tidak didukung di Windows.")
        k = kernel32()
        self.emit = emit
        self.closed = False
        self._lock = threading.Lock()         # console and job handles
        self._input_lock = threading.Lock()   # the input pipe
        self._console = self._input = self._output = self._job = None
        self._last_output = time.monotonic()
        # conhost asked for win32-input-mode (ESC [?9001h): it then reads a
        # bare 0x03 as text, so Ctrl-C has to arrive as a key event.
        self._win32_input = False
        args = [os.fspath(a) for a in argv]
        environment = merge_environment(os.environ, env or {}, {"TERM": "xterm", "COLUMNS": str(cols), "LINES": str(rows)})
        try:
            self._start(k, args, cwd, environment, cols, rows)
        except BaseException:
            self._release()
            raise
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._wait, daemon=True).start()

    def _start(self, k, args, cwd, environment, cols, rows):
        conhost_input, self._input = _pipe()
        try:
            self._output, conhost_output = _pipe()
            try:
                console = HANDLE()
                check_hresult(k.CreatePseudoConsole(COORD(cols, rows), conhost_input, conhost_output, 0,
                                                    ctypes.byref(console)), "CreatePseudoConsole")
                self._console = console.value
            finally:
                # The pseudoconsole has its own duplicates. Without ours, the output pipe breaks
                # when conhost exits: that is the reader's end of file.
                _close(conhost_output)
        finally:
            _close(conhost_input)
        size = SIZE_T(0)
        k.InitializeProcThreadAttributeList(None, 1, 0, ctypes.byref(size))
        if not size.value:
            raise last_error()
        attributes = ctypes.create_string_buffer(size.value)
        if not k.InitializeProcThreadAttributeList(attributes, 1, 0, ctypes.byref(size)):
            raise last_error()
        try:
            # lpValue is the HPCON itself, not a pointer to it.
            if not k.UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, self._console,
                                               ctypes.sizeof(HANDLE), None, None):
                raise last_error()
            startup = STARTUPINFOEXW()
            startup.StartupInfo.cb = ctypes.sizeof(STARTUPINFOEXW)
            # Explicit NULL standard handles: the child takes the pseudoconsole's. Without this a
            # child of an IDE (or test runner) whose own stdout is a pipe writes into that pipe.
            startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES
            startup.lpAttributeList = ctypes.addressof(attributes)
            info = PROCESS_INFORMATION()
            command = ctypes.create_unicode_buffer(subprocess.list2cmdline(args))
            block = ctypes.create_string_buffer(environment_block(environment).encode("utf-16-le"))
            directory = os.path.abspath(os.fspath(cwd)) if cwd else None
            flags = EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED
            # Children inherit "ignore Ctrl-C" (CI runners and some launchers start us that way);
            # clear it so the program reacts to Ctrl-C like in a console window.
            k.SetConsoleCtrlHandler(None, False)
            if not k.CreateProcessW(None, command, None, None, False, flags, block, directory,
                                    ctypes.byref(startup), ctypes.byref(info)):
                raise last_error()
        finally:
            k.DeleteProcThreadAttributeList(attributes)
        self.child = Child(info.hProcess, info.dwProcessId, args)
        try:
            self._job = _job()
            if self._job and not k.AssignProcessToJobObject(self._job, info.hProcess):
                # Without a job stop() still ends the program itself, but not its children.
                _close(self._job)
                self._job = None
            if k.ResumeThread(info.hThread) == RESUME_FAILED:
                error = last_error()
                self.child.terminate()
                raise error
        finally:
            _close(info.hThread)

    def _read(self):
        k = kernel32()
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        buffer = ctypes.create_string_buffer(16384)
        count = DWORD()
        try:
            # ReadFile fails with ERROR_BROKEN_PIPE once conhost has exited.
            while k.ReadFile(self._output, buffer, len(buffer), ctypes.byref(count), None):
                if count.value:
                    self._last_output = time.monotonic()
                    text = decoder.decode(ctypes.string_at(buffer, count.value))
                    if "\x1b[?9001h" in text:
                        self._win32_input = True
                    if "\x1b[?9001l" in text:
                        self._win32_input = False
                    if text:
                        self.emit("output", text)
            tail = decoder.decode(b"", final=True)
            if tail:
                self.emit("output", tail)
        finally:
            with self._input_lock:
                output, self._output = self._output, None
            _close(output)
            self.closed = True
            if self.child.poll() is None:
                # conhost went away under a running program.
                try:
                    self.child.wait(1)
                except subprocess.TimeoutExpired:
                    self._terminate()
            code = self.child.wait()
            self._release()
            self.emit("exit", code)

    def _wait(self):
        try:
            self.child.wait()
            # Give conhost a moment to paint the program's last output; ClosePseudoConsole also
            # sends a final frame, which the reader still drains.
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline and time.monotonic() - self._last_output < .1:
                time.sleep(.02)
        finally:
            self._close_console()

    def _close_console(self):
        with self._lock:
            console, self._console = self._console, None
        if console:
            kernel32().ClosePseudoConsole(console)

    def _release(self):
        """Closes everything still open; closing the job ends whatever the program left running."""
        with self._input_lock:
            handles, self._input, self._output = (self._input, self._output), None, None
        with self._lock:
            job, self._job = self._job, None
        for handle in (*handles, job):
            _close(handle)
        self._close_console()

    def _terminate(self):
        with self._lock:
            if self._job:
                kernel32().TerminateJobObject(self._job, TERMINATED)
                return
        self.child.terminate()

    def write(self, value):
        """Sends bytes to the program; b"\\x03" becomes Ctrl-C (CTRL_C_EVENT) in conhost."""
        if value == b"\x03" and self._ctrl_c_event():
            return
        if value == b"\x03" and self._win32_input:
            value = b"\x1b[67;46;3;1;8;1_\x1b[67;46;3;0;8;1_"
        with self._input_lock:
            if self.closed or not self._input:
                return
            k = kernel32()
            view = memoryview(bytes(value))
            written = DWORD()
            while view:
                chunk = view.tobytes()
                if not k.WriteFile(self._input, chunk, len(chunk), ctypes.byref(written), None) or not written.value:
                    return
                view = view[written.value:]

    def _ctrl_c_event(self):
        """Ctrl-C as a real console might: a helper without a console of its own attaches to the
        program's pseudoconsole and raises CTRL_C_EVENT there. Input bytes are not enough: newer
        conhost asks for win32-input-mode and then reads 0x03 as plain text. True on success."""
        if self.closed or self.child.poll() is not None:
            return False
        code = ("import ctypes,sys;k=ctypes.windll.kernel32;"
                "ok=k.AttachConsole(int(sys.argv[1])) and k.SetConsoleCtrlHandler(None,1) "
                "and k.GenerateConsoleCtrlEvent(0,0);sys.exit(0 if ok else 1)")
        try:
            return subprocess.run([sys.executable, "-c", code, str(self.child.pid)],
                                  creationflags=0x00000008, timeout=10,  # DETACHED_PROCESS
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False

    def interrupt(self):
        # A CTRL_C_EVENT through a helper (see _ctrl_c_event); failing that, Ctrl+C as input,
        # as a win32-input-mode key record when conhost asked for that mode:
        # ESC [ Vk ; Sc ; Uc ; Kd ; Cs ; Rc _ with VK 'C', scan code 46, character 3 and
        # LEFT_CTRL_PRESSED.
        self.write(b"\x03")

    def resize(self, cols, rows):
        with self._lock:
            if self._console:
                kernel32().ResizePseudoConsole(self._console, COORD(cols, rows))

    def stop(self):
        if self.child.poll() is None:
            self._terminate()
