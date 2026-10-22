# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""The graphics window channel, without Tk.

A program that uses the Graph unit connects to a TCP port on 127.0.0.1 (environment ODIN_GRAPH_PORT,
authenticated with ODIN_GRAPH_TOKEN) and sends its framebuffer, so the IDE can show the real pixels in
a window instead of the half-block preview in the terminal. Keys go the other way through the normal
User screen input, so there is no reverse channel here.

Messages, little-endian: u8 kind, u32 payload length, payload.
    1 HELLO    the token, ASCII
    2 MODE     u16 width, u16 height, u16 AspX (pixel height : width is 10000 : AspX), u16 colors (<= 256)
    3 PALETTE  u16 count, then count x (r, g, b)
    4 FRAME    u16 rows, then per changed row: u16 y, u16 byte count, run-length data (run 1..255, value)
    5 HIDE     the program went back to text mode
    6 CLOSE    CloseGraph
rtl/graph.pas is the sending side; the two must change together."""
from __future__ import annotations

import base64
import secrets
import socket
import struct
import threading
import zlib

HELLO, MODE, PALETTE, FRAME, HIDE, CLOSE = 1, 2, 3, 4, 5, 6
MAX_MESSAGE = 4 * 1024 * 1024
MAX_PIXELS = 1024 * 768
# The first 16 entries before the program sends a palette: the VGA text colors.
DEFAULT_PALETTE = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0),
                   (170, 170, 170), (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85),
                   (255, 85, 255), (255, 255, 85), (255, 255, 255)]


def png(width, height, pixels, palette):
    """An indexed PNG of the pixels (one palette index per byte, row by row), which Tk reads natively."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    rows = b"".join(b"\x00" + bytes(pixels[y * width:(y + 1) * width]) for y in range(height))
    plte = b"".join(bytes(c) for c in palette)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
            + chunk(b"PLTE", plte) + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b""))


class GraphChannel:
    """Listens for one Graph program and keeps the latest picture. emit("gfx", self) is called when the
    picture changed and nobody has fetched it yet, emit("gfx_closed", self) when the program closed the
    graphics or the connection ended."""

    def __init__(self, emit):
        self.emit = emit
        self.token = secrets.token_hex(8)
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(0.3)
        self.port = self.listener.getsockname()[1]
        self.lock = threading.Lock()
        self.width = self.height = 0
        self.asp = 10000
        self.pixels = bytearray()
        self.palette = list(DEFAULT_PALETTE)
        self.visible = False
        self.connected = False
        self.version = 0          # grows with every change of picture, palette, or mode
        self.fetched = 0
        self.closed = False
        self.finished = False     # the connection ended
        self.graphics_closed = False   # the program called CloseGraph (until its next InitGraph)
        threading.Thread(target=self._serve, daemon=True).start()

    def env(self):
        return {"ODIN_GRAPH_PORT": str(self.port), "ODIN_GRAPH_TOKEN": self.token}

    def close(self):
        self.closed = True
        try:
            self.listener.close()
        except OSError:
            pass

    def snapshot(self):
        """(visible, width, height, asp, png bytes) of the current picture; None before a mode was set or
        after CloseGraph."""
        with self.lock:
            self.fetched = self.version
            if not self.width:
                return None
            return (self.visible, self.width, self.height, self.asp,
                    png(self.width, self.height, self.pixels, self.palette))

    def _changed(self):
        with self.lock:
            idle = self.fetched == self.version
            self.version += 1
        if idle:
            self.emit("gfx", self)

    def _recv(self, connection, count):
        data = bytearray()
        while len(data) < count:
            part = connection.recv(count - len(data))
            if not part:
                raise EOFError
            data += part
        return bytes(data)

    def _serve(self):
        connection = None
        while connection is None and not self.closed:
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
        if connection is None:
            return
        try:
            connection.settimeout(None)
            kind, length = struct.unpack("<BI", self._recv(connection, 5))
            if kind != HELLO or length > 64 or self._recv(connection, length).decode("ascii", "replace") != self.token:
                return
            self.connected = True
            while True:
                kind, length = struct.unpack("<BI", self._recv(connection, 5))
                if length > MAX_MESSAGE:
                    return
                self._handle(kind, self._recv(connection, length))
        except (OSError, EOFError, struct.error):
            pass
        finally:
            self.finished = True
            try:
                connection.close()
            except OSError:
                pass
            self.emit("gfx_closed", self)

    def _handle(self, kind, data):
        if kind == MODE and len(data) == 8:
            width, height, asp, colors = struct.unpack("<HHHH", data)
            if 0 < width * height <= MAX_PIXELS:
                with self.lock:
                    self.width, self.height, self.asp = width, height, max(asp, 1)
                    self.pixels = bytearray(width * height)
                    self.visible = True
                    self.graphics_closed = False
                self._changed()
        elif kind == PALETTE and len(data) >= 2:
            (count,) = struct.unpack_from("<H", data)
            if count <= 256 and len(data) == 2 + 3 * count:
                colors = [tuple(data[2 + 3 * i:5 + 3 * i]) for i in range(count)]
                with self.lock:
                    self.palette = colors + [(0, 0, 0)] * (256 - count)
                self._changed()
        elif kind == FRAME and len(data) >= 2 and self.width:
            (rows,) = struct.unpack_from("<H", data)
            at = 2
            with self.lock:
                for _ in range(rows):
                    if at + 4 > len(data):
                        break
                    y, count = struct.unpack_from("<HH", data, at)
                    at += 4
                    run = data[at:at + count]
                    at += count
                    if y >= self.height:
                        continue
                    row = bytearray()
                    for i in range(0, len(run) - 1, 2):
                        row += bytes((run[i + 1],)) * run[i]
                    row = row[:self.width].ljust(self.width, b"\x00")
                    self.pixels[y * self.width:(y + 1) * self.width] = row
            self._changed()
        elif kind == HIDE:
            with self.lock:
                self.visible = False
            self._changed()
        elif kind == CLOSE:
            with self.lock:
                self.visible = False
                self.width = 0
                self.graphics_closed = True
            self.emit("gfx_closed", self)


def png_base64(data):
    """What tk.PhotoImage(data=...) takes for a PNG."""
    return base64.b64encode(data)
