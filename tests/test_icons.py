# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Toolbar icons (odin/icons.py) without Tk: every icon renders to a valid PNG with its shapes inside the grid."""
import struct
import unittest
import zlib

from odin import icons


class IconTests(unittest.TestCase):
    def test_every_icon_is_a_valid_rgba_png(self):
        for name in icons.ICONS:
            for size in (16, 20, 32):
                data = icons.png(name, size)
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                width, height, depth, kind = struct.unpack(">IIBB", data[16:26])
                self.assertEqual((width, height, depth, kind), (size, size, 8, 6), name)
                # One filter byte and four channels per pixel in each row.
                raw = zlib.decompress(data[data.index(b"IDAT") + 4:data.index(b"IEND") - 8])
                self.assertEqual(len(raw), size * (1 + 4 * size))

    def test_icons_are_drawn_and_keep_a_transparent_margin(self):
        for name in icons.ICONS:
            pixels = icons.rgba(name, 16)
            opaque = sum(1 for p in pixels if p[3] > 128)
            self.assertGreater(opaque, 20, name)
            self.assertLess(opaque, 16 * 16, name)
        # The play triangle is green and leaves the left edge of the grid transparent.
        run = icons.rgba("run", 16)
        self.assertEqual(run[8 * 16 + 0][3], 0)
        self.assertEqual(run[8 * 16 + 8][:3], (0x2e, 0x9d, 0x4a))


if __name__ == "__main__":
    unittest.main()
