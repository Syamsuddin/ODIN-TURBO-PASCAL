# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Debug session: `odinpc debug` runs the program on the user screen PTY; commands and events
travel as JSON lines over two pipes, or over a TCP connection to 127.0.0.1 on Windows, which
cannot pass descriptors to a child (IMPLEMENTATION_PLAN.md section 6.2). No Tk here: the IDE and
tests/test_debugger.py drive the same class."""
from __future__ import annotations

import json
import os
import socket
import sys
import threading
from pathlib import Path

from .console import Process


class DebugSession:
    """emit(kind, value) receives "output"/"exit" from the PTY, like Process, and ("debug", event)
    for every event of the debugger. Call update(event) on the thread that handles events: it
    keeps state ("starting", "running", "stopped", "exited") and the stop location."""

    def __init__(self, toolchain, executable, debug_info, arguments, cwd, emit, env=None):
        common = ["--exe", str(executable), "--odbg", str(debug_info)]
        tail = ["--cwd", str(cwd), "--", *arguments]
        self._socket = None
        if sys.platform == "win32":
            # No descriptors reach a Windows child: odinpc debug connects back to a port here.
            server = socket.create_server(("127.0.0.1", 0))
            try:
                server.settimeout(15)
                port = server.getsockname()[1]
                argv = [str(toolchain), "debug", *common, "--ide", f"127.0.0.1:{port}", *tail]
                self.process = Process(argv, cwd, emit, env=env or None)
                try:
                    self._socket, _ = server.accept()
                except OSError:
                    self.process.stop()
                    raise OSError("odinpc debug tidak terhubung ke IDE.")
            finally:
                server.close()
            self._socket.settimeout(None)
            self._commands = self._socket.makefile("w", encoding="utf-8")
            events = self._socket.makefile("r", encoding="utf-8")
        else:
            command_read, command_write = os.pipe()
            event_read, event_write = os.pipe()
            argv = [str(toolchain), "debug", *common, "--ide-fds", f"{command_read},{event_write}", *tail]
            try:
                self.process = Process(argv, cwd, emit, pass_fds=(command_read, event_write), env=env or None)
            except BaseException:
                for fd in (command_write, event_read):
                    os.close(fd)
                raise
            finally:
                os.close(command_read)
                os.close(event_write)
            self._commands = os.fdopen(command_write, "w", encoding="utf-8")
            events = os.fdopen(event_read, encoding="utf-8")
        self.emit = emit
        self.state = "starting"
        self.location = None     # (Path, line) of the last stop
        self.reason = None
        self.exit_code = None
        self.runtime_error = None  # event dict of the last runtime error
        self._next_id = 0
        self._lock = threading.Lock()
        threading.Thread(target=self._read, args=(events,), daemon=True).start()

    def _read(self, events):
        with events:
            for line in events:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if isinstance(event, dict):
                    self.emit("debug", event)
        # odinpc debug is gone: nobody reads commands any more.
        self.close()
        self.emit("debug", {"event": "closed"})

    def send(self, command, **fields):
        """Sends a command; returns its request id (results carry the same id)."""
        with self._lock:
            self._next_id += 1
            request = self._next_id
            try:
                self._commands.write(json.dumps({"command": command, "id": request, **fields}) + "\n")
                self._commands.flush()
            except (OSError, ValueError):
                pass
        return request

    def update(self, event):
        kind = event.get("event")
        if kind == "ready" and self.state == "starting":
            self.state = "ready"
        elif kind == "stopped":
            self.state = "stopped"
            self.reason = event.get("reason")
            self.location = (Path(event["file"]), int(event["line"])) if event.get("file") else None
        elif kind == "runtime_error":
            self.runtime_error = event
        elif kind == "exited":
            self.state = "exited"
            if isinstance(event.get("code"), int):
                self.exit_code = event["code"]
        elif kind == "closed":
            self.state = "exited"

    @property
    def stopped(self):
        return self.state == "stopped"

    @property
    def alive(self):
        return self.state != "exited"

    def _resume(self, command, **fields):
        self.state = "running"
        self.location = None
        return self.send(command, **fields)

    # Commands; each returns its request id.
    def set_breakpoints(self, path, lines):
        return self.send("set_breakpoints", file=str(path), lines=sorted(lines))

    def start(self, mode="run", path=None, line=None):
        fields = {"file": str(path), "line": line} if path else {}
        return self._resume("start", mode=mode, **fields)

    def resume(self):
        return self._resume("continue")

    def step_into(self):
        return self._resume("step_into")

    def step_over(self):
        return self._resume("step_over")

    def step_out(self):
        return self._resume("step_out")

    def run_to(self, path, line):
        return self._resume("run_to", file=str(path), line=line)

    def pause(self):
        return self.send("pause")

    def evaluate(self, expression, frame=0):
        return self.send("evaluate", expr=expression, frame=frame)

    def modify(self, expression, value, frame=0):
        return self.send("modify", expr=expression, value=value, frame=frame)

    def stack(self):
        return self.send("stack")

    def locals(self, frame=0):
        return self.send("locals", frame=frame)

    def terminate(self):
        self.send("terminate")
        self.process.stop()

    def close(self):
        with self._lock:
            try:
                self._commands.close()
            except OSError:
                pass
            if self._socket is not None:
                try:
                    self._socket.close()
                except OSError:
                    pass
