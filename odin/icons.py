# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Toolbar icons, drawn from simple shapes on a 16x16 grid and encoded as PNG. No Tk and no image files: render()
returns PNG bytes that tk.PhotoImage(data=...) takes after base64."""
from __future__ import annotations

import math
import struct
import zlib

# Colors used by the icons.
INK, PAPER, BLUE, GREEN, RED, AMBER, GRAY = "#3b4552", "#ffffff", "#2b6cc4", "#2e9d4a", "#d93a2b", "#e8a93a", "#8a94a3"


def rect(x0, y0, x1, y1, color):
    return ("poly", [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], color)


def line(points, width, color):
    return ("line", points, width, color)


def arc(cx, cy, r, start, end, steps=12):
    """Points along a circle from angle start to end (degrees, 0 = east, counter-clockwise on screen)."""
    return [(cx + r * math.cos(math.radians(start + (end - start) * i / steps)),
             cy - r * math.sin(math.radians(start + (end - start) * i / steps))) for i in range(steps + 1)]


def gear(cx, cy, outer, inner, teeth, color):
    """A gear outline as one polygon: teeth alternate between the outer and the inner radius."""
    points = []
    for i in range(teeth * 4):
        angle = 2 * math.pi * i / (teeth * 4)
        radius = outer if i % 4 in (1, 2) else inner
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return ("poly", points, color)


def page(color=PAPER):
    """A sheet of paper with a folded corner."""
    return [("poly", [(3, 1), (10, 1), (14, 5), (14, 15), (3, 15)], INK),
            ("poly", [(4, 2), (9.5, 2), (13, 5.5), (13, 14), (4, 14)], color),
            ("poly", [(9.5, 1.5), (9.5, 5.5), (13.5, 5.5)], INK)]


ICONS = {
    "new": [*page(), rect(6, 8, 11, 9, GRAY), rect(6, 10.5, 11, 11.5, GRAY)],
    "open": [("poly", [(1, 3), (6, 3), (7.5, 4.5), (14, 4.5), (14, 14), (1, 14)], "#c08a1e"),
             ("poly", [(1.5, 14), (3.5, 7), (15.5, 7), (13.5, 14)], AMBER)],
    "save": [("poly", [(1.5, 1.5), (12.5, 1.5), (14.5, 3.5), (14.5, 14.5), (1.5, 14.5)], BLUE),
             rect(4, 1.5, 11.5, 6.5, PAPER), rect(9, 2.5, 10.5, 5.5, BLUE), rect(4, 9, 12, 14.5, "#dce7f5")],
    "compile": [gear(8, 8, 7.2, 5.4, 8, INK), ("circle", 8, 8, 2.3, PAPER)],
    "run": [("poly", [(4, 2), (14, 8), (4, 14)], GREEN)],
    "stop": [("round", 2.5, 2.5, 13.5, 13.5, 2, RED)],
    "debug": [line([(5, 6), (2, 4)], 1.2, INK), line([(11, 6), (14, 4)], 1.2, INK), line([(4.5, 9.5), (1.5, 9.5)], 1.2, INK),
              line([(11.5, 9.5), (14.5, 9.5)], 1.2, INK), line([(5, 12.5), (2, 14.5)], 1.2, INK),
              line([(11, 12.5), (14, 14.5)], 1.2, INK), ("ellipse", 8, 10, 4, 5, GREEN), ("circle", 8, 4.2, 2.4, INK),
              line([(8, 6), (8, 14.5)], 1, INK)],
    "into": [rect(2, 2, 14, 3.5, GRAY), line([(8, 4.5), (8, 12)], 2, BLUE), ("poly", [(4, 10), (12, 10), (8, 15)], BLUE)],
    "over": [line(arc(8, 9, 5.5, 180, 15), 2, BLUE), ("poly", [(10.5, 7.5), (15.5, 7.5), (14.5, 12.5)], BLUE),
             ("circle", 3, 13.5, 1.6, INK)],
    "breakpoint": [("circle", 8, 8, 6.5, "#a82315"), ("circle", 8, 8, 5.5, RED), ("circle", 6.2, 6.2, 1.6, "#f08a7f")],
    "tile": [("round", 1, 1, 7.5, 7.5, 1, BLUE), ("round", 8.5, 1, 15, 7.5, 1, BLUE), ("round", 1, 8.5, 7.5, 15, 1, BLUE),
             ("round", 8.5, 8.5, 15, 15, 1, BLUE), rect(2, 3, 6.5, 6.5, PAPER), rect(9.5, 3, 14, 6.5, PAPER),
             rect(2, 10.5, 6.5, 14, PAPER), rect(9.5, 10.5, 14, 14, PAPER)],
    "cascade": [("round", 1, 1, 10, 9, 1, GRAY), ("round", 3.5, 3.5, 12.5, 11.5, 1, GRAY),
                ("round", 6, 6, 15, 14.5, 1, BLUE), rect(7, 8, 14, 13.5, PAPER)],
}


def _inside_polygon(points, x, y):
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _near_polyline(points, half, x, y):
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        dx, dy = x1 - x0, y1 - y0
        t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy or 1)))
        if (x - x0 - t * dx) ** 2 + (y - y0 - t * dy) ** 2 <= half * half:
            return True
    return False


def _covers(shape, x, y):
    kind = shape[0]
    if kind == "poly":
        return _inside_polygon(shape[1], x, y)
    if kind == "circle":
        _, cx, cy, r, _ = shape
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    if kind == "ellipse":
        _, cx, cy, rx, ry, _ = shape
        return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1
    if kind == "round":
        _, x0, y0, x1, y1, r, _ = shape
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return False
        nx, ny = min(max(x, x0 + r), x1 - r), min(max(y, y0 + r), y1 - r)
        return (x - nx) ** 2 + (y - ny) ** 2 <= r * r
    if kind == "line":
        return _near_polyline(shape[1], shape[2] / 2, x, y)
    raise ValueError(kind)


def _bounds(shape):
    if shape[0] in ("poly", "line"):
        pad = shape[2] / 2 if shape[0] == "line" else 0
        xs, ys = [p[0] for p in shape[1]], [p[1] for p in shape[1]]
        return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad
    if shape[0] == "circle":
        return shape[1] - shape[3], shape[2] - shape[3], shape[1] + shape[3], shape[2] + shape[3]
    if shape[0] == "ellipse":
        return shape[1] - shape[3], shape[2] - shape[4], shape[1] + shape[3], shape[2] + shape[4]
    return shape[1], shape[2], shape[3], shape[4]


def rgba(name, size=16, samples=4):
    """The icon as size*size (r, g, b, a) pixels, each pixel averaged over samples*samples points."""
    scale = 16 / size
    pixels = [[0.0, 0.0, 0.0, 0.0] for _ in range(size * size)]
    for shape in ICONS[name]:
        color = shape[-1]
        r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
        x0, y0, x1, y1 = _bounds(shape)
        for py in range(max(0, int(y0 / scale) - 1), min(size, int(y1 / scale) + 2)):
            for px in range(max(0, int(x0 / scale) - 1), min(size, int(x1 / scale) + 2)):
                hits = sum(_covers(shape, (px + (i + .5) / samples) * scale, (py + (j + .5) / samples) * scale)
                           for i in range(samples) for j in range(samples))
                if not hits:
                    continue
                alpha = hits / samples ** 2
                pixel = pixels[py * size + px]
                # "Over" compositing with premultiplied channels.
                for k, value in enumerate((r, g, b)):
                    pixel[k] = value * alpha + pixel[k] * (1 - alpha)
                pixel[3] = alpha + pixel[3] * (1 - alpha)
    return [(*(round(c / p[3]) if p[3] else 0 for c in p[:3]), round(p[3] * 255)) for p in pixels]


def png(name, size=16):
    """The icon as a PNG file (RGBA, 8 bits per channel)."""
    pixels = rgba(name, size)
    raw = b"".join(b"\x00" + bytes(v for p in pixels[y * size:(y + 1) * size] for v in p) for y in range(size))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
